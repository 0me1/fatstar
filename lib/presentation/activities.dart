import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/activity.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';
import 'controller.dart';
import 'forms.dart';
import 'motion.dart';

Future<void> editActivity(
  BuildContext context,
  DiaryController c,
  ActivityType type,
  DateTime day, {
  Record? previous,
}) async {
  final minutes = TextEditingController(
    text: previous == null ? '30' : '${previous.data['minutes']}',
  );
  final initialWeight =
      previous?.data['weight_kg'] as num? ?? activityWeight(c.records, day);
  final weight = TextEditingController(
    text: initialWeight == null ? '' : number(initialWeight),
  );
  final root = context;
  try {
    final data = await editForm<Json>(
      context,
      type.name,
      (update) {
        double? kcal;
        try {
          kcal = type.calories(
            parseNumber(minutes.text),
            type.met == null ? null : parseNumber(weight.text),
          );
        } catch (_) {}
        return [
          TextField(
            key: const ValueKey('activity-minutes'),
            controller: minutes,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Продолжительность, минут',
            ),
            onChanged: (_) => update(() {}),
          ),
          if (type.met != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Вес, кг'),
              onChanged: (_) => update(() {}),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '${number(kcal, 0)} ккал сожжено',
            key: const ValueKey('activity-preview'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            type.met == null
                ? 'Расчет по вашему расходу ккал в минуту.'
                : 'Усредненная оценка: ${type.met} MET, зависит от темпа и нагрузки. Учитывается только дополнительный расход сверх покоя. Если тренировка уже учтена в уровне активности вашей цели, добавление может учитывать ее повторно.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
      },
      () {
        final duration = parseNumber(minutes.text);
        final kg = type.met == null ? null : parseNumber(weight.text);
        final kcal = type.calories(duration, kg);
        return {
          'day': dayKey(day),
          'activity_id': type.id,
          'name': type.name,
          'icon': type.icon,
          'minutes': duration,
          'kcal': kcal,
          'weight_kg': kg,
          'met': type.met,
          'kcal_per_minute': type.kcalPerMinute,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        };
      },
      ownedControllers: [minutes, weight],
    );
    if (data != null) {
      await c.save('activity', data, previous: previous);
      if (root.mounted) message(root, 'Активность сохранена');
    }
  } catch (e) {
    if (root.mounted) message(root, e);
  }
}

class ActivitySearchScreen extends ConsumerStatefulWidget {
  const ActivitySearchScreen({super.key, required this.day});
  final DateTime day;
  @override
  ConsumerState<ActivitySearchScreen> createState() => _ActivitySearchState();
}

class _ActivitySearchState extends ConsumerState<ActivitySearchScreen> {
  String query = '';
  Future<void> create(DiaryController c) async {
    final name = TextEditingController(text: query),
        rate = TextEditingController();
    try {
      final data = await editForm<Json>(
        context,
        'Своя активность',
        (_) => [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Расход, ккал в минуту',
            ),
          ),
          const Text(
            'Укажите дополнительный расход сверх покоя, например по данным тренировки.',
          ),
        ],
        () {
          final result = {
            'name': name.text.trim(),
            'kcal_per_minute': parseNumber(rate.text),
          };
          if (name.text.trim().isEmpty ||
              name.text.trim().length > 200 ||
              (result['kcal_per_minute'] as double) <= 0 ||
              (result['kcal_per_minute'] as double) > 100) {
            throw ArgumentError(
              'Проверьте название и расход (до 100 ккал/мин)',
            );
          }
          return result;
        },
        ownedControllers: [name, rate],
      );
      if (data != null) {
        final saved = await c.save('activity_type', data);
        if (mounted) {
          await editActivity(context, c, activityType(saved), widget.day);
        }
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(diaryProvider);
    final usage = <String, int>{};
    for (final r in c.of('activity')) {
      final id = r.data['activity_id'] as String;
      usage[id] = (usage[id] ?? 0) + 1;
    }
    final types =
        [...builtInActivities, ...c.of('activity_type').map(activityType)]
            .where(
              (t) => normalizeSearch(t.name).contains(normalizeSearch(query)),
            )
            .toList()
          ..sort((a, b) {
            final count = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
            return count != 0 ? count : a.name.compareTo(b.name);
          });
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить активность')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск активности',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final t in types)
                  ListTile(
                    leading: Text(t.icon, style: const TextStyle(fontSize: 30)),
                    title: Text(t.name),
                    onTap: () => editActivity(context, c, t, widget.day),
                  ),
                if (types.isEmpty)
                  const ListTile(title: Text('Ничего не найдено')),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Добавить свою активность'),
                  onTap: () => create(c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActivitySection extends StatelessWidget {
  const ActivitySection({
    super.key,
    required this.controller,
    required this.day,
  });
  final DiaryController controller;
  final DateTime day;
  @override
  Widget build(BuildContext context) {
    final rows = controller
        .of('activity')
        .where((r) => r.data['day'] == dayKey(day))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Активность', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            tile(
              context,
              'Добавить',
              const Icon(Icons.add_circle_outline, size: 32),
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ActivitySearchScreen(day: day),
                ),
              ),
            ),
            for (final r in rows)
              tile(
                context,
                '${number(r.data['kcal'] as num, 0)} ккал',
                Text(
                  r.data['icon'] as String? ?? '✨',
                  style: const TextStyle(fontSize: 32),
                ),
                () => editActivity(
                  context,
                  controller,
                  ActivityType(
                    r.data['activity_id'] as String,
                    r.data['name'] as String,
                    r.data['icon'] as String? ?? '✨',
                    met: (r.data['met'] as num?)?.toDouble(),
                    kcalPerMinute: (r.data['kcal_per_minute'] as num?)
                        ?.toDouble(),
                  ),
                  day,
                  previous: r,
                ),
                record: r,
              ),
          ],
        ),
      ],
    );
  }

  Widget tile(
    BuildContext context,
    String label,
    Widget icon,
    VoidCallback open, {
    Record? record,
  }) => SizedBox(
    width: 100,
    child: Column(
      children: [
        SizedBox(
          height: 100,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              onLongPress: record == null
                  ? null
                  : () async {
                      final remove = await showModalBottomSheet<bool>(
                        context: context,
                        showDragHandle: true,
                        sheetAnimationStyle: sheetMotion(context),
                        builder: (context) => SafeArea(
                          child: ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: const Text('Удалить активность'),
                            onTap: () => Navigator.pop(context, true),
                          ),
                        ),
                      );
                      if (remove == true) {
                        try {
                          await controller.remove(record);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Активность удалена'),
                                action: SnackBarAction(
                                  label: 'Отменить',
                                  onPressed: () async {
                                    try {
                                      await controller.restore(record);
                                    } catch (e) {
                                      if (context.mounted) message(context, e);
                                    }
                                  },
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        }
                      }
                    },
              child: Center(child: icon),
            ),
          ),
        ),
        Text(label, textAlign: TextAlign.center),
        if (record != null)
          Text(
            '${number(record.data['minutes'] as num, 0)} мин',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}
