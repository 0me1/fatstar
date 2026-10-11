-- All writes go through apply_operation. Audit and author fields are server-owned.
create extension if not exists pgcrypto with schema extensions;

create table public.allowed_users (
  user_id uuid primary key references auth.users(id), active boolean not null default true
);
create table public.products (
  id uuid primary key, data jsonb not null, version bigint not null check(version > 0),
  deleted boolean not null default false, created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.private_records (
  owner_id uuid not null references auth.users(id), kind text not null
    check(kind in ('entry','goal','weight','favorite','portion','settings')),
  id uuid not null, data jsonb not null, version bigint not null check(version > 0),
  deleted boolean not null default false, updated_at timestamptz not null default now(),
  primary key(owner_id,kind,id)
);
create index private_days on public.private_records(owner_id,kind,(data->>'day'));
create index goal_effective_days on public.private_records(owner_id,(data->>'effective_from')) where kind='goal' and not deleted;
create unique index unique_favorite on public.private_records(owner_id,(data->>'product_id')) where kind='favorite' and not deleted;
create unique index unique_portion_preference on public.private_records(owner_id,(data->>'product_id')) where kind='portion' and not deleted;
create unique index unique_settings on public.private_records(owner_id) where kind='settings' and not deleted;
create table public.product_versions (
  product_id uuid not null references public.products(id), version bigint not null,
  actor_id uuid not null references auth.users(id), created_at timestamptz not null default now(),
  previous_record jsonb, record jsonb not null, primary key(product_id,version)
);
create table public.processed_operations (
  actor_id uuid not null references auth.users(id), operation_id uuid not null,
  digest text not null, result jsonb not null, created_at timestamptz not null default now(),
  primary key(actor_id,operation_id)
);
create table public.change_log (
  sequence bigint generated always as identity primary key,
  owner_id uuid references auth.users(id), record jsonb not null,
  created_at timestamptz not null default now()
);
create index changes_owner on public.change_log(owner_id,sequence);

create function public.is_member() returns boolean language sql stable security definer
set search_path = '' as $$
  select exists(select 1 from public.allowed_users where user_id=auth.uid() and active)
$$;

alter table public.allowed_users enable row level security;
alter table public.products enable row level security;
alter table public.private_records enable row level security;
alter table public.product_versions enable row level security;
alter table public.processed_operations enable row level security;
alter table public.change_log enable row level security;

create policy catalog_read on public.products for select to authenticated using (public.is_member());
create policy history_read on public.product_versions for select to authenticated using (public.is_member());
create policy personal_read on public.private_records for select to authenticated
  using (owner_id=auth.uid() and public.is_member());
create policy own_operations_read on public.processed_operations for select to authenticated
  using (actor_id=auth.uid() and public.is_member());
create policy own_changes_read on public.change_log for select to authenticated
  using ((owner_id is null or owner_id=auth.uid()) and public.is_member());
revoke all on public.allowed_users, public.products, public.private_records,
  public.product_versions, public.processed_operations, public.change_log from anon, authenticated;
grant select on public.products, public.private_records, public.product_versions to authenticated;

create function public.valid_nutrition(n jsonb, complete boolean) returns boolean
language plpgsql immutable set search_path = '' as $$
declare k text; v jsonb;
begin
  if jsonb_typeof(n) is distinct from 'object' then return false; end if;
  foreach k in array array['kcal','protein','fat','carbs'] loop
    v := n->k;
    if v is null or v='null'::jsonb then
      if k='kcal' or complete then return false; end if;
    elsif jsonb_typeof(v)<>'number' or (v#>>'{}')::numeric < 0 or (v#>>'{}')::numeric > 100000 then
      return false;
    end if;
  end loop;
  return true;
exception when others then return false;
end $$;

create function public.valid_record(k text, d jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare p jsonb; dt text; ids uuid[] := '{}'; pid uuid;
begin
  if jsonb_typeof(d) is distinct from 'object' or pg_column_size(d)>131072 then return false; end if;
  if k='product' then
    if coalesce(length(trim(d->>'name')),0) not between 1 and 200 or
      d->>'unit' not in ('gram','milliliter') or d->>'unit' is null or
      not public.valid_nutrition(d->'nutrition',true) or
      jsonb_typeof(d->'portions') is distinct from 'array' or
      jsonb_typeof(d->'active') is distinct from 'boolean' or
      (d->'brand' is not null and d->'brand'<>'null'::jsonb and (jsonb_typeof(d->'brand')<>'string' or length(d->>'brand')>200)) or
      jsonb_array_length(d->'portions')>128 then return false; end if;
    for p in select value from jsonb_array_elements(d->'portions') loop
      pid := (p->>'id')::uuid;
      if pid is null or pid=any(ids) or coalesce(length(trim(p->>'name')),0) not between 1 and 100 or
        jsonb_typeof(p->'amount') is distinct from 'number' or
        not ((p->>'amount')::numeric > 0 and (p->>'amount')::numeric <= 100000) then return false; end if;
      ids := array_append(ids,pid);
    end loop;
  elsif k='entry' then
    if coalesce(length(trim(d->>'name')),0) not between 1 and 200 or
      d->>'meal' is null or d->>'meal' not in ('breakfast','lunch','dinner','snack') or
      not public.valid_nutrition(d->'nutrition',false) or
      d->>'unit' is null or d->>'unit' not in ('gram','milliliter','quick') or
      jsonb_typeof(d->'amount') is distinct from 'number' or
      not ((d->>'amount')::numeric > 0 and (d->>'amount')::numeric <= 100000) then return false; end if;
    if d->'base' is not null and d->'base'<>'null'::jsonb and not public.valid_nutrition(d->'base',true) then return false; end if;
    dt := d->>'day';
  elsif k='goal' then
    if not public.valid_nutrition(d->'nutrition',true) or (d->'nutrition'->>'kcal')::numeric not between 500 and 10000 or
      d->>'formula' is null or d->>'formula' not in ('mifflin','harris','katch') or
      d->>'goal' is null or d->>'goal' not in ('loss','maintain','gain','muscle') then return false; end if;
    dt := d->>'effective_from';
  elsif k='weight' then
    if jsonb_typeof(d->'kg') is distinct from 'number' or (d->>'kg')::numeric not between 20 and 500 then return false; end if;
    dt := d->>'day';
  elsif k in ('favorite','portion') then
    if (d->>'product_id')::uuid is null then return false; end if;
    if k='portion' and (jsonb_typeof(d->'amount') is distinct from 'number' or
      not ((d->>'amount')::numeric > 0 and (d->>'amount')::numeric <= 100000)) then return false; end if;
  elsif k='settings' then
    if d->>'theme' is null or d->>'theme' not in ('dark','light','system') then return false; end if;
  else return false;
  end if;
  if k in ('entry','goal','weight') then
    if dt is null or dt !~ '^\d{4}-\d{2}-\d{2}$' or to_char(dt::date,'YYYY-MM-DD')<>dt then return false; end if;
  end if;
  return true;
exception when others then return false;
end $$;

create function public.apply_operation(p_operation_id uuid, p_kind text, p_id uuid,
  p_expected bigint, p_record jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); existing jsonb; next_record jsonb; result jsonb;
  current_version bigint := 0; old_digest text; saved jsonb; digest text; d jsonb;
  removed boolean; creator uuid; created timestamptz; prior jsonb;
begin
  if actor is null or not public.is_member() then raise exception 'Not invited' using errcode='42501'; end if;
  if p_operation_id is null or p_id is null or p_expected is null or p_expected<0 or
    p_record->>'id' is distinct from p_id::text or p_record->>'kind' is distinct from p_kind or
    jsonb_typeof(p_record->'deleted') is distinct from 'boolean' or
    not public.valid_record(p_kind,p_record->'data') then raise exception 'Invalid record' using errcode='22023'; end if;
  -- This lock also covers pull_changes: sequence numbers cannot commit out of order.
  perform pg_advisory_xact_lock(724032184);
  digest := md5(jsonb_build_object('kind',p_kind,'id',p_id,'expected',p_expected,'record',p_record)::text);
  select o.digest,o.result into old_digest,saved from public.processed_operations o where actor_id=actor and operation_id=p_operation_id;
  if found then
    if old_digest<>digest then raise exception 'Idempotency key reused with different payload' using errcode='22023'; end if;
    return saved;
  end if;
  if p_kind='product' then
    select jsonb_build_object('kind','product','id',id,'data',data,'version',version,'deleted',deleted),
      version,created_by,created_at into existing,current_version,creator,created
      from public.products where id=p_id for update;
  else
    select jsonb_build_object('kind',kind,'id',id,'data',data,'version',version,'deleted',deleted),version
      into existing,current_version from public.private_records where owner_id=actor and kind=p_kind and id=p_id for update;
  end if;
  current_version := coalesce(current_version,0);
  if p_expected<>current_version then return jsonb_build_object('status','conflict','record',coalesce(existing,'{}'::jsonb)); end if;
  d := p_record->'data'; removed := (p_record->>'deleted')::boolean;
  if p_kind='product' then
    creator := coalesce(creator,actor); created := coalesce(created,now());
    d := (d - 'created_by' - 'created_at' - 'updated_at' - 'updated_by') || jsonb_build_object('created_by',creator,'created_at',created,'updated_at',now(),'updated_by',actor);
    insert into public.products(id,data,version,deleted,created_by,created_at,updated_at)
      values(p_id,d,current_version+1,removed,creator,created,now())
      on conflict(id) do update set data=excluded.data,version=excluded.version,deleted=excluded.deleted,updated_at=excluded.updated_at;
  else
    -- Client-controlled owner_id is never used to select or write a row.
    d := d - 'owner_id';
    insert into public.private_records(owner_id,kind,id,data,version,deleted)
      values(actor,p_kind,p_id,d,current_version+1,removed)
      on conflict(owner_id,kind,id) do update set data=excluded.data,version=excluded.version,deleted=excluded.deleted,updated_at=now();
  end if;
  next_record := jsonb_build_object('id',p_id,'kind',p_kind,'data',d,'version',current_version+1,'deleted',removed);
  if p_kind='product' then
    insert into public.product_versions(product_id,version,actor_id,previous_record,record)
      values(p_id,current_version+1,actor,existing,next_record);
  end if;
  insert into public.change_log(owner_id,record) values(case when p_kind='product' then null else actor end,next_record);
  result := jsonb_build_object('status','applied','record',next_record);
  insert into public.processed_operations(actor_id,operation_id,digest,result) values(actor,p_operation_id,digest,result);
  return result;
end $$;

create function public.pull_changes(p_cursor bigint default 0, p_limit integer default 200) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); records jsonb; last_sequence bigint; high_water bigint; more boolean;
begin
  if actor is null or not public.is_member() then raise exception 'Not invited' using errcode='42501'; end if;
  if p_cursor<0 or p_limit<1 or p_limit>500 then raise exception 'Invalid cursor or limit'; end if;
  perform pg_advisory_xact_lock(724032184);
  select coalesce(max(sequence),0) into high_water from public.change_log;
  if p_cursor>high_water then raise exception 'Cursor is ahead of server'; end if;
  select coalesce(jsonb_agg(record order by sequence),'[]'::jsonb),coalesce(max(sequence),p_cursor)
    into records,last_sequence from (select sequence,record from public.change_log
      where sequence>p_cursor and (owner_id is null or owner_id=actor) order by sequence limit p_limit) page;
  select exists(select 1 from public.change_log where sequence>last_sequence and (owner_id is null or owner_id=actor)) into more;
  return jsonb_build_object('records',records,'cursor',case when more then last_sequence else high_water end,'has_more',more);
end $$;

revoke execute on function public.valid_record(text,jsonb), public.valid_nutrition(jsonb,boolean),
  public.is_member(), public.apply_operation(uuid,text,uuid,bigint,jsonb), public.pull_changes(bigint,integer) from public, anon;
grant execute on function public.is_member(), public.apply_operation(uuid,text,uuid,bigint,jsonb), public.pull_changes(bigint,integer) to authenticated;
