-- Private activities use the existing owner-based RLS and operation protocol.
begin;
alter table public.private_records drop constraint private_records_kind_check;
alter table public.private_records add constraint private_records_kind_check check(kind in ('entry','goal','weight','favorite','portion','settings','activity','activity_type'));
create or replace function public.valid_record(k text, d jsonb) returns boolean
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
  elsif k='activity' then
    if jsonb_typeof(d->'name') is distinct from 'string' or coalesce(length(trim(d->>'name')),0) not between 1 and 200 or
      jsonb_typeof(d->'minutes') is distinct from 'number' or not ((d->>'minutes')::numeric > 0 and (d->>'minutes')::numeric <= 1440) or
      jsonb_typeof(d->'kcal') is distinct from 'number' or not ((d->>'kcal')::numeric between 0 and 100000) then return false; end if;
    dt := d->>'day';
  elsif k='activity_type' then
    if jsonb_typeof(d->'name') is distinct from 'string' or coalesce(length(trim(d->>'name')),0) not between 1 and 200 or
      jsonb_typeof(d->'kcal_per_minute') is distinct from 'number' or not ((d->>'kcal_per_minute')::numeric > 0 and (d->>'kcal_per_minute')::numeric <= 100) then return false; end if;
  elsif k='settings' then
    if d->>'theme' is null or d->>'theme' not in ('dark','light','system') then return false; end if;
  else return false;
  end if;
  if k in ('entry','goal','weight','activity') then
    if dt is null or dt !~ '^\d{4}-\d{2}-\d{2}$' or to_char(dt::date,'YYYY-MM-DD')<>dt then return false; end if;
  end if;
  return true;
exception when others then return false;
end $$;

commit;
