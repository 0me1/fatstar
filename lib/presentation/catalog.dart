import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';
import 'controller.dart';
import 'forms.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, this.meal});
  final Meal? meal;
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final search = TextEditingController();
  final selected = <Json>[];
  String filter = 'all', query = '';
  bool hidden = false, saving = false;
  Timer? debounce;
  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> choose(Record p, {bool quick = false}) async {
    final last = ref.read(diaryProvider).lastPortion(p.id);
    final validLast =
        last != null &&
        last.data['unit'] == p.data['unit'] &&
        (last.data['portion_id'] == null ||
            (p.data['portions'] as List).any(
              (raw) => raw['id'] == last.data['portion_id'],
            ));
    final savedAmount = last == null ? null : decimal(last.data['amount']);
    final data = quick && last != null && validLast
        ? entryForProduct(
            p,
            decimal(last.data['amount']),
            last.data['portion_name'] as String? ?? '',
            portionId: last.data['portion_id'] as String?,
          )
        : await selectPortion(
            context,
            p,
            initial: validLast ? savedAmount : null,
          );
    if (data != null && mounted) setState(() => selected.add(data));
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(diaryProvider);
    final favorites = c.of('favorite').map((r) => r.data['product_id']).toSet();
    final frequency = <String, int>{};
    final recent = <String, String>{};
    for (final e in c.of('entry')) {
      final id = e.data['product_id'] as String?;
      if (id != null) {
        frequency[id] = (frequency[id] ?? 0) + 1;
        final day = e.data['recorded_at'] as String? ?? e.data['day'] as String;
        if ((recent[id] ?? '').compareTo(day) < 0) recent[id] = day;
      }
    }
    final products = c
        .of('product')
        .where(
          (p) =>
              (hidden || p.data['active'] != false) &&
              normalizeSearch(
                '${p.data['name']} ${p.data['brand'] ?? ''}',
              ).contains(query) &&
              (filter != 'favorite' || favorites.contains(p.id)) &&
              (!['recent', 'frequent'].contains(filter) ||
                  frequency.containsKey(p.id)),
        )
        .toList();
    products.sort((a, b) {
      if (query.isNotEmpty) {
        final aName = normalizeSearch(a.data['name'] as String),
            bName = normalizeSearch(b.data['name'] as String);
        final aa = aName == query
            ? 2
            : aName.startsWith(query)
            ? 1
            : 0;
        final bb = bName == query
            ? 2
            : bName.startsWith(query)
            ? 1
            : 0;
        if (aa != bb) return bb.compareTo(aa);
      }
      if (filter == 'recent') {
        return (recent[b.id] ?? '').compareTo(recent[a.id] ?? '');
      }
      final f = (frequency[b.id] ?? 0).compareTo(frequency[a.id] ?? 0);
      return f != 0
          ? f
          : (a.data['name'] as String).compareTo(b.data['name'] as String);
    });
    return PopScope<void>(
      canPop: widget.meal == null || selected.isEmpty || saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Убрать выбранные продукты?'),
            content: const Text(
              'Нажмите «Готово», чтобы сохранить их в дневнике.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Убрать и выйти'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          setState(selected.clear);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.meal?.label ?? 'Продукты'),
          actions: [
            IconButton(
              tooltip: hidden ? 'Скрыть неактивные' : 'Показать неактивные',
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden ? Icons.visibility : Icons.visibility_off_outlined,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    onChanged: (v) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 250), () {
                        if (mounted) setState(() => query = normalizeSearch(v));
                      });
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Что вы ели${widget.meal == null ? '' : ' на ${widget.meal!.label.toLowerCase()}'}?',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          search.clear();
                          setState(() => query = '');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final pair in [
                          ('all', 'Все'),
                          ('frequent', 'Частые'),
                          ('recent', 'Недавние'),
                          ('favorite', 'Избранное'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(pair.$2),
                              selected: filter == pair.$1,
                              onSelected: (_) =>
                                  setState(() => filter = pair.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => editProduct(context, c),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать продукт'),
                      ),
                      if (widget.meal != null)
                        TextButton.icon(
                          onPressed: () async {
                            final d = await quickFood(context);
                            if (d != null && mounted) {
                              setState(() => selected.add(d));
                            }
                          },
                          icon: const Icon(Icons.bolt),
                          label: const Text('Быстрые КБЖУ'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          query.isNotEmpty
                              ? 'Ничего не найдено. Можно создать продукт.'
                              : 'Пока нет продуктов. Создайте первый или дождитесь синхронизации каталога.',
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, _) =>
                          const Divider(indent: 16, endIndent: 16, height: 1),
                      itemBuilder: (context, i) {
                        final p = products[i];
                        final n = Nutrition.fromJson(
                          Map<String, dynamic>.from(p.data['nutrition'] as Map),
                        );
                        final last = c.lastPortion(p.id);
                        final amount = last == null
                            ? 100.0
                            : decimal(last.data['amount']);
                        return ListTile(
                          title: Text(p.data['name'] as String, maxLines: 2),
                          subtitle: Text(
                            '${p.data['brand'] ?? ''}${p.localOnly ? ' · локальный' : ''}\n${number(amount)} ${p.data['unit'] == 'gram' ? 'г' : 'мл'} · ${number(n.kcal * amount / 100, 0)} ккал${p.data['active'] == false ? ' · скрыт' : ''}',
                          ),
                          onTap: () => widget.meal == null
                              ? productDetails(context, c, p)
                              : choose(p),
                          trailing: widget.meal != null
                              ? IconButton(
                                  tooltip: 'Добавить последнюю порцию',
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: Theme.of(context).colorScheme.primary,
                                  onPressed: p.data['active'] == false
                                      ? null
                                      : () => choose(p, quick: true),
                                )
                              : IconButton(
                                  tooltip: 'Избранное',
                                  onPressed: () => c.favorite(p),
                                  icon: Icon(
                                    favorites.contains(p.id)
                                        ? Icons.star
                                        : Icons.star_border,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
            if (widget.meal != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => showSelected(),
                        child: Text('${selected.length} выбрано'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: selected.isEmpty || saving
                              ? null
                              : () async {
                                  setState(() => saving = true);
                                  try {
                                    await c.addEntries(selected, widget.meal!);
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (context.mounted) {
                                      message(context, e);
                                      setState(() => saving = false);
                                    }
                                  }
                                },
                          child: Text(
                            saving
                                ? 'Сохранение…'
                                : 'Готово · ${number(NutritionTotal(selected.map((d) => Nutrition.fromJson(Map<String, dynamic>.from(d['nutrition'] as Map)))).kcal, 0)} ккал',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> showSelected() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: 400,
            child: ListView(
              children: [
                const ListTile(title: Text('Выбранные продукты')),
                for (var i = 0; i < selected.length; i++)
                  ListTile(
                    title: Text(selected[i]['name'] as String),
                    subtitle: Text(
                      '${number(Nutrition.fromJson(Map<String, dynamic>.from(selected[i]['nutrition'] as Map)).kcal, 0)} ккал',
                    ),
                    trailing: IconButton(
                      tooltip: 'Убрать',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        update(() => selected.removeAt(i));
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> editProduct(
  BuildContext context,
  DiaryController c, {
  Record? product,
}) async {
  final name = TextEditingController(
    text: product?.data['name'] as String? ?? '',
  );
  final brand = TextEditingController(
    text: product?.data['brand'] as String? ?? '',
  );
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
    if (data == null || !context.mounted) return;
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
      if (confirmed != true) return;
    }
    await c.save('product', data, previous: product);
  } catch (e) {
    if (context.mounted) message(context, e);
  } finally {
    name.dispose();
    brand.dispose();
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
              if (context.mounted) message(context, e);
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
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
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
                        if (context.mounted) message(context, e);
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
