import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/food_search_repository.dart';
import '../domain/food_search.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';
import 'controller.dart';
import 'forms.dart';
import 'motion.dart';
import 'food_add_button.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, this.meal});
  final Meal? meal;
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final search = TextEditingController();
  final scroll = ScrollController();
  final selected = <Record>[];
  String filter = 'all';
  bool hidden = false, busy = false, pointerDown = false;
  Timer? debounce, settle;
  int generation = 0, observedRevision = -1, visibleCount = 40;
  Object? accountDb;
  FoodSearchRepository? engine;
  List<SearchHit> hits = [];
  List<SearchHit>? pending;
  String? error;

  @override
  void dispose() {
    generation++;
    search.dispose(); scroll.dispose(); debounce?.cancel(); settle?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final c = ref.read(diaryProvider);
    final db = c.db;
    if (db == null) { return; }
    if (accountDb != db) { accountDb = db; engine = FoodSearchRepository(db); }
    final request = ++generation;
    final revision = db.searchRevision;
    setState(() { busy = true; error = null; });
    try {
      final result = await engine!.search(search.text,meal:widget.meal?.name,filter:filter,hidden:hidden,date:c.day);
      if (!mounted || request != generation || ref.read(diaryProvider).db != db) { return; }
      observedRevision = revision;
      setState(() { busy = false; if (pointerDown || (settle?.isActive ?? false)) { pending=result; } else { hits=result; } });
    } catch (_) {
      if (mounted && request == generation) { setState(() { observedRevision=revision; busy=false; error='Не удалось выполнить поиск. Попробуйте еще раз.'; }); }
    }
  }

  void changed() {
    generation++; pending=null; debounce?.cancel();
    debounce=Timer(const Duration(milliseconds:150), () { if(mounted) { unawaited(refresh()); } });
  }

  void releasePointer() {
    pointerDown=false; settle?.cancel();
    settle=Timer(const Duration(milliseconds:220), () {
      if(mounted && !pointerDown && pending!=null) { setState(() { hits=pending!; pending=null; }); }
    });
  }

  Future<bool> add(Json data) async {
    final c = ref.read(diaryProvider);
    if (widget.meal == null) { return false; }
    try {
      final added = await c.addEntries([data],widget.meal!);
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      if (!mounted) { return true; }
      setState(() => selected.addAll(added));
      if (added.isNotEmpty) {
        final entry=added.single;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${entry.data['name']} добавлено'),action:SnackBarAction(label:'Отменить',onPressed:() { unawaited(removeAdded(entry)); })));
      }
      return true;
    } catch(e) { if(mounted) { message(context,e); } return false; }
  }

  Future<void> removeAdded(Record entry) async {
    try {
      await ref.read(diaryProvider).remove(entry);
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      if(mounted) { setState(() => selected.removeWhere((r)=>r.id==entry.id)); }
    } catch(e) { if(mounted) { message(context,e); } }
  }

  Future<bool> choose(Record p, {bool quick=false}) async {
    final last=ref.read(diaryProvider).lastPortion(p.id);
    final requested=SearchQuery(search.text);
    final data=quick ? quickEntryForProduct(p,last) : await selectPortion(context,p,
      initial: requested.unit==p.data['unit'] ? requested.amount : decimal(quickEntryForProduct(p,last)['amount']));
    return data!=null && mounted ? add(data) : false;
  }

  Future<void> create() => editProduct(context,ref.read(diaryProvider),initialName:search.text.trim());
  Future<void> quick() async { final data=await quickFood(context); if(data!=null && mounted) { await add(data); } }

  Widget row(SearchHit hit, {String group='result'}) {
    final p=hit.product, c=ref.read(diaryProvider);
    final n=Nutrition.fromJson(Map<String,dynamic>.from(p.data['nutrition'] as Map));
    final amount=decimal(quickEntryForProduct(p,c.lastPortion(p.id))['amount']);
    final unit=p.data['unit']=='gram'?'г':'мл';
    return ListTile(
      key:ValueKey('$group/${p.id}'),
      title:Text(p.data['name'] as String,maxLines:2),
      subtitle:Text('${p.data['brand'] ?? ''}${p.localOnly?' · локальный':''}\nНа 100 $unit: ${number(n.kcal,0)} ккал · Б ${n.protein == null ? '—' : number(n.protein!)} · Ж ${n.fat == null ? '—' : number(n.fat!)} · У ${n.carbs == null ? '—' : number(n.carbs!)}\n${c.lastPortion(p.id)==null?'Порция':'Последняя порция'}: ${number(amount)} $unit · ${number(n.kcal*amount/100,0)} ккал${p.data['active']==false?' · скрыт':''}${hit.preference!=null && hit.preference!.count>1?' · обычно ${number(hit.preference!.typicalAmount(p.data['unit'] as String))} $unit':''}'),
      onTap:()=>widget.meal==null?productDetails(context,c,p):choose(p),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(tooltip:'Избранное',onPressed:()=>c.favorite(p),icon:Icon(hit.preference?.favorite==true?Icons.star:Icons.star_border,color:hit.preference?.favorite==true?const Color(0xFFFFC857):null)),
        if(widget.meal!=null) FoodAddButton(tooltip:'Добавить ${number(amount)} $unit',onAdd:p.data['active']==false?null:()=>choose(p,quick:true)),
      ]),
    );
  }

  List<Widget> results() {
    if(search.text.trim().isNotEmpty || filter!='all' || hidden) { return [
      if(hits.isNotEmpty && hits.first.correction!=null) ListTile(title:Text('Показаны результаты: ${hits.first.correction}')),
      ...hits.take(visibleCount).map(row),
      if(hits.length>visibleCount) TextButton(onPressed:()=>setState(()=>visibleCount+=40),child:const Text('Показать еще')),
    ]; }
    final groups=<({String name,String filter,List<SearchHit> items})>[
      (name:'Для этого приема пищи',filter:'meal',items:hits.where((h)=>(h.preference?.meals[widget.meal?.name]??0)>0).toList()),
      (name:'Недавние',filter:'recent',items:hits.where((h)=>(h.preference?.count??0)>0).toList()..sort((a,b)=>(b.preference?.last??DateTime(2000)).compareTo(a.preference?.last??DateTime(2000)))),
      (name:'Частые',filter:'frequent',items:hits.where((h)=>(h.preference?.count??0)>0).toList()..sort((a,b)=>(b.preference?.count??0).compareTo(a.preference?.count??0))),
      (name:'Избранное',filter:'favorite',items:hits.where((h)=>h.preference?.favorite==true).toList()),
    ];
    if(groups.every((g)=>g.items.isEmpty)) { return [const ListTile(title:Text('Каталог продуктов')), ...hits.take(visibleCount).map(row),if(hits.length>visibleCount) TextButton(onPressed:()=>setState(()=>visibleCount+=40),child:const Text('Показать еще'))]; }
    return [for(final group in groups.where((g)=>g.items.isNotEmpty)) ...[
      ListTile(title:Text(group.name,style:Theme.of(context).textTheme.titleLarge),trailing:TextButton(onPressed:(){setState(()=>filter=group.filter);unawaited(refresh());},child:const Text('Все'))),
      ...group.items.take(3).map((h)=>row(h,group:group.filter)),
    ]];
  }

  @override
  Widget build(BuildContext context) {
    final c=ref.watch(diaryProvider);
    if(c.db!=null && (accountDb!=c.db || observedRevision!=c.db!.searchRevision) && !busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted && !busy) { unawaited(refresh()); } });
    }
    final parsed=SearchQuery(search.text);
    return Scaffold(
      appBar:AppBar(title:Text(widget.meal?.label??'Продукты'),actions:[
        IconButton(tooltip:hidden?'Скрыть неактивные':'Показать неактивные',onPressed:(){setState(()=>hidden=!hidden);unawaited(refresh());},icon:Icon(hidden?Icons.visibility:Icons.visibility_off_outlined)),
        PopupMenuButton<String>(onSelected:(value){if(value=='create') {unawaited(create());} else {unawaited(quick());}},itemBuilder:(_)=>[
          const PopupMenuItem(value:'create',child:Text('Создать продукт')),
          if(widget.meal!=null) const PopupMenuItem(value:'quick',child:Text('Быстрые КБЖУ')),
        ]),
      ]),
      body:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:TextField(controller:search,autofocus:widget.meal!=null,onChanged:(_){visibleCount=40;changed();},decoration:InputDecoration(hintText:'Название, бренд или порция',prefixIcon:const Icon(Icons.search),suffixIcon:IconButton(tooltip:'Очистить',icon:const Icon(Icons.close),onPressed:(){search.clear();changed();})))),
        if(parsed.amount!=null) Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text('При выборе карточки: ${number(parsed.amount!)} ${parsed.unit=='gram'?'г':'мл'}; проверьте порцию перед добавлением.')),
        SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[for(final pair in [('all','Все'),('frequent','Частые'),('recent','Недавние'),('favorite','Избранное'),if(widget.meal!=null) ('meal','Этот прием')]) Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(pair.$2),selected:filter==pair.$1,onSelected:(_){setState(()=>filter=pair.$1);unawaited(refresh());}))])),
        if(MediaQuery.viewInsetsOf(context).bottom==0) Wrap(spacing:8,children:[TextButton.icon(onPressed:create,icon:const Icon(Icons.add),label:const Text('Создать продукт')),if(widget.meal!=null) TextButton.icon(onPressed:quick,icon:const Icon(Icons.bolt),label:const Text('Быстрые КБЖУ'))]),
        SizedBox(height:2,child:busy?const LinearProgressIndicator():null),
        Expanded(child:error!=null?Center(child:TextButton(onPressed:refresh,child:Text(error!))):hits.isEmpty && !busy?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(search.text.trim().isEmpty?'Здесь пока нет продуктов. Создайте первый или синхронизируйте каталог.':'Ничего не найдено. Попробуйте другое название или создайте продукт.'),TextButton(onPressed:create,child:const Text('Создать продукт'))]))):Listener(onPointerDown:(_){settle?.cancel();pointerDown=true;},onPointerUp:(_)=>releasePointer(),onPointerCancel:(_)=>releasePointer(),child:ListView(controller:scroll,keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,children:results()))),
        if(widget.meal!=null) SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[TextButton(onPressed:selected.isEmpty?null:showSelected,child:Text('${selected.length} добавлено')),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('Готово')))]))),
      ]),
    );
  }

  Future<void> showSelected() async {
    await showModalBottomSheet<void>(context:context,showDragHandle:true,sheetAnimationStyle:sheetMotion(context),isScrollControlled:true,builder:(context)=>StatefulBuilder(builder:(context,update)=>SafeArea(child:SizedBox(height:400,child:ListView(children:[const ListTile(title:Text('Уже добавлено в дневник')),for(final entry in selected.toList()) ListTile(key:ValueKey(entry.id),title:Text(entry.data['name'] as String),trailing:IconButton(tooltip:'Удалить из дневника',icon:const Icon(Icons.close),onPressed:() async {await removeAdded(entry);if(context.mounted){ update((){}); }})),])))));
  }
}

Future<void> editProduct(
  BuildContext context,
  DiaryController c, {
  Record? product,
  String initialName = '',
}) async {
  final name = TextEditingController(
    text: product?.data['name'] as String? ?? initialName,
  );
  final brand = TextEditingController(
    text: product?.data['brand'] as String? ?? '',
  );
  final aliases = TextEditingController(text: (product?.data['aliases'] as List? ?? []).join('\n'));
  final n = product == null
      ? const Nutrition(0, 0, 0, 0)
      : Nutrition.fromJson(
          Map<String, dynamic>.from(product.data['nutrition'] as Map),
        );
  final values = [n.kcal, n.protein, n.fat, n.carbs]
      .map((v) => TextEditingController(text: product == null ? '' : number(v)))
      .toList();
  var unit = product?.data['unit'] as String? ?? 'gram';
  final portions =
      <
        ({String id, TextEditingController name, TextEditingController amount})
      >[];
  for (final raw in product?.data['portions'] as List? ?? []) {
    final p = Portion.fromJson(Map<String, dynamic>.from(raw as Map));
    portions.add((
      id: p.id,
      name: TextEditingController(text: p.name),
      amount: TextEditingController(text: number(p.amount)),
    ));
  }
  final retired = <TextEditingController>[];
  try {
    final data = await editForm<Json>(
      context,
      product == null ? 'Новый продукт' : 'Редактировать продукт',
      (set) => [
        input('Название', name),
        input('Бренд (необязательно)', brand),
        TextField(controller:aliases,minLines:1,maxLines:4,decoration:const InputDecoration(labelText:'Альтернативные названия (по одному в строке)')),
        DropdownButtonFormField<String>(
          initialValue: unit,
          items: const [
            DropdownMenuItem(value: 'gram', child: Text('На 100 г')),
            DropdownMenuItem(value: 'milliliter', child: Text('На 100 мл')),
          ],
          onChanged: (v) => set(() => unit = v!),
          decoration: const InputDecoration(labelText: 'Базовая единица'),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++)
          input(
            ['Калории', 'Белки', 'Жиры', 'Углеводы'][i],
            values[i],
            numeric: true,
          ),
        const Text('Порции: размер в базовой единице (г или мл)'),
        const SizedBox(height: 12),
        for (var i = 0; i < portions.length; i++)
          Row(
            children: [
              Expanded(child: input('Название', portions[i].name)),
              const SizedBox(width: 8),
              Expanded(
                child: input('Размер', portions[i].amount, numeric: true),
              ),
              IconButton(
                tooltip: 'Удалить порцию',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => set(() {
                  final p = portions.removeAt(i);
                  retired.addAll([p.name, p.amount]);
                }),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () => set(
            () => portions.add((
              id: const Uuid().v4(),
              name: TextEditingController(),
              amount: TextEditingController(),
            )),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Добавить порцию'),
        ),
      ],
      () {
        final nutrition = Nutrition(
          parseNumber(values[0].text),
          parseNumber(values[1].text),
          parseNumber(values[2].text),
          parseNumber(values[3].text),
        );
        final result = {
          'name': name.text.trim(),
          'brand': brand.text.trim(),
          'aliases': aliases.text.split('\n').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toSet().toList(),
          'unit': unit,
          'nutrition': nutrition.toJson(),
          'portions': portions
              .map(
                (p) => Portion(
                  id: p.id,
                  name: p.name.text.trim(),
                  amount: parseNumber(p.amount.text),
                ).toJson(),
              )
              .toList(),
          'active': product?.data['active'] ?? true,
        };
        validateRecord(
          Record(
            id: product?.id ?? const Uuid().v4(),
            kind: 'product',
            data: result,
          ),
        );
        return result;
      },
    );
    if (data == null || !context.mounted) { return; }
    final similar = c
        .of('product')
        .where(
          (p) =>
              p.id != product?.id &&
              (normalizeSearch(
                    p.data['name'] as String,
                  ).contains(normalizeSearch(data['name'] as String)) ||
                  normalizeSearch(
                    data['name'] as String,
                  ).contains(normalizeSearch(p.data['name'] as String))),
        )
        .toList();
    if (similar.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Похожие продукты'),
          content: Text(
            similar
                .take(5)
                .map((p) => '${p.data['name']} ${p.data['brand'] ?? ''}')
                .join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Вернуться к каталогу'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить отдельный'),
            ),
          ],
        ),
      );
      if (confirmed != true) { return; }
    }
    await c.save('product', data, previous: product);
  } catch (e) {
    if (context.mounted) { message(context, e); }
  } finally {
    name.dispose();
    brand.dispose();
    aliases.dispose();
    for (final v in values) {
      v.dispose();
    }
    for (final p in portions) {
      p.name.dispose();
      p.amount.dispose();
    }
    for (final v in retired) {
      v.dispose();
    }
  }
}

Future<void> productDetails(
  BuildContext context,
  DiaryController c,
  Record p,
) async {
  final nutrition = Nutrition.fromJson(
    Map<String, dynamic>.from(p.data['nutrition'] as Map),
  );
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    sheetAnimationStyle: sheetMotion(context),
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'На 100 ${p.data['unit'] == 'gram' ? 'г' : 'мл'}: ${number(nutrition.kcal, 0)} ккал · Б ${number(nutrition.protein)} · Ж ${number(nutrition.fat)} · У ${number(nutrition.carbs)} г',
        ),
        Text(
          p.data['name'] as String,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('${p.data['brand'] ?? ''} · версия ${p.version}'),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Изменить КБЖУ и порции'),
          onTap: () {
            Navigator.pop(context);
            editProduct(context, c, product: p);
          },
        ),
        ListTile(
          leading: const Icon(Icons.star_border),
          title: const Text('Переключить избранное'),
          onTap: () async {
            await c.favorite(p);
            if (context.mounted) Navigator.pop(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text(
            p.data['active'] == false
                ? 'Восстановить видимость'
                : 'Скрыть продукт',
          ),
          onTap: () async {
            try {
              await c.save('product', {
                ...p.data,
                'active': p.data['active'] == false,
              }, previous: p);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) { message(context, e); }
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('История изменений'),
          onTap: () {
            Navigator.pop(context);
            productHistory(context, c, p);
          },
        ),
        if (p.localOnly)
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Опубликовать в общем каталоге'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Опубликовать продукт?'),
                  content: const Text(
                    'Продукт станет доступен обоим пользователям.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Опубликовать'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                // Publishing uses a fresh shared identity; imported snapshots stay intact.
                await c.save('product', p.data);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ],
    ),
  );
}

Future<void> productHistory(
  BuildContext context,
  DiaryController c,
  Record p,
) async {
  try {
    List<Json> raw;
    try {
      raw = await c.client
          .from('product_versions')
          .select()
          .eq('product_id', p.id)
          .order('version', ascending: false)
          .timeout(const Duration(seconds: 8));
      for (final version in raw) {
        await c.db!.cacheHistory(
          Record.fromJson(Map<String, dynamic>.from(version['record'] as Map)),
        );
      }
    } catch (_) {
      raw = await c.db!.cachedHistory(p.id);
      raw.sort((a, b) => (b['version'] as int).compareTo(a['version'] as int));
    }
    if (!context.mounted) { return; }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: sheetMotion(context),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'История продукта',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (raw.isEmpty) const Text('История появится после синхронизации'),
            for (final version in raw)
              ListTile(
                title: Text(
                  'Версия ${version['version']} · ${version['created_at']}',
                ),
                subtitle: Text(
                  'Автор ${version['actor_id']}\n${version['record']['data']}',
                ),
                trailing: IconButton(
                  tooltip: 'Восстановить версию',
                  icon: const Icon(Icons.restore),
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Восстановить эту версию?'),
                        content: Text('${version['record']['data']}'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Восстановить'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      try {
                        final latest = await c.db!.find('product', p.id);
                        await c.save(
                          'product',
                          Map<String, dynamic>.from(
                            version['record']['data'] as Map,
                          ),
                          previous: latest,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) { message(context, e); }
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      message(
        context,
        'История недоступна. Проверьте синхронизацию и подключение.',
      );
    }
  }
}
