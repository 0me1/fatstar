import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';
import 'controller.dart';
import 'forms.dart';

const goalNames = [
  'Снижение веса',
  'Поддержание веса',
  'Набор веса',
  'Наращивание мышц',
];
const formulaNames = [
  'Миффлина — Сан Жеора',
  'Харриса — Бенедикта (1984)',
  'Кэтча — Макардла',
];
const activityNames = [
  'Минимальная · 1,2',
  'Легкая · 1,375',
  'Умеренная · 1,55',
  'Высокая · 1,725',
  'Очень высокая · 1,9',
];
const activityValues = [1.2, 1.375, 1.55, 1.725, 1.9];

const activityDescriptions = [
  'Сидячий образ жизни, мало ходьбы, без регулярных тренировок.',
  'Немного ходьбы и легкие тренировки 1–3 раза в неделю.',
  'Подвижный день и умеренные тренировки 3–5 раз в неделю.',
  'Много движения или интенсивные тренировки 6–7 раз в неделю.',
  'Тяжелый физический труд и интенсивные тренировки, иногда дважды в день.',
];

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(diaryProvider);
    final g = c.goal;
    final weights = c.of('weight')
      ..sort(
        (a, b) => (b.data['day'] as String).compareTo(a.data['day'] as String),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Мои цели')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (g == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Укажите параметры или задайте норму вручную. Прошлые дни сохраняют действовавшие тогда цели.',
              ),
            ),
          Card(
            child: Column(
              children: [
                row(
                  context,
                  'Цель',
                  g == null
                      ? 'Выбрать'
                      : goalNames[WeightGoal.values
                            .byName(g.data['goal'] as String)
                            .index],
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Исходный вес',
                  g == null ? '—' : '${number(g.data['weight'] as num?)} кг',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Текущий вес',
                  weights.isEmpty
                      ? 'Добавить'
                      : '${number(weights.first.data['kg'] as num)} кг',
                  () => editWeight(context, c),
                ),
                row(
                  context,
                  'Желаемый вес',
                  g == null
                      ? '—'
                      : '${number(g.data['desired_weight'] as num?)} кг',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Изменение в неделю',
                  g == null
                      ? '—'
                      : '${number(g.data['weekly_kg'] as num?, 2)} кг',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Цель по калориям',
                  g == null
                      ? 'Задать'
                      : '${number(Nutrition.fromJson(Map<String, dynamic>.from(g.data['nutrition'] as Map)).kcal, 0)} ккал',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Настройки БЖУ',
                  g?.data['macro_mode'] as String? ?? 'Автоматические',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Активность',
                  g == null ? 'Выбрать' : '${g.data['activity']}',
                  () => editGoal(context, c),
                ),
                row(
                  context,
                  'Формула',
                  g == null
                      ? 'Миффлина — Сан Жеора'
                      : formulaNames[BmrFormula.values
                            .byName(g.data['formula'] as String)
                            .index],
                  () => editGoal(context, c),
                ),
              ],
            ),
          ),
          if (g != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Действует с ${g.data['effective_from']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(g.data['explanation'] as String? ?? ''),
                    const SizedBox(height: 12),
                    const Text(
                      'Это расчетная оценка, а не медицинское измерение. Для беременности, лактации, несовершеннолетних и состояний, влияющих на обмен веществ, норму нужно обсуждать со специалистом.',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => editGoal(context, c),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Настроить цели'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'История веса',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Добавить вес',
                onPressed: () => editWeight(context, c),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (weights.isEmpty) const Text('Измерений пока нет'),
          for (final w in weights)
            ListTile(
              title: Text('${number(w.data['kg'] as num)} кг'),
              subtitle: Text(w.data['day'] as String),
              onTap: () => editWeight(context, c, previous: w),
              trailing: IconButton(
                tooltip: 'Удалить измерение',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await c.remove(w);
                },
              ),
            ),
          const SizedBox(height: 24),
          Text('История целей', style: Theme.of(context).textTheme.titleLarge),
          for (final version
              in c.of('goal')..sort(
                (a, b) => (b.data['effective_from'] as String).compareTo(
                  a.data['effective_from'] as String,
                ),
              ))
            ListTile(
              title: Text(
                'С ${version.data['effective_from']} · ${number(Nutrition.fromJson(Map<String, dynamic>.from(version.data['nutrition'] as Map)).kcal, 0)} ккал',
              ),
              subtitle: Text(version.data['explanation'] as String? ?? ''),
              isThreeLine: false,
            ),
        ],
      ),
    );
  }

  Widget row(
    BuildContext context,
    String label,
    String value,
    VoidCallback tap,
  ) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Expanded(flex: 5, child: Text(label)),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: tap,
      ),
      const Divider(height: 1),
    ],
  );
}

Future<void> editWeight(
  BuildContext context,
  DiaryController c, {
  Record? previous,
}) async {
  final weight = TextEditingController(
    text: previous == null ? '' : number(previous.data['kg'] as num),
  );
  var date = previous == null
      ? DateTime.now()
      : DateTime.parse(previous.data['day'] as String);
  try {
    final data = await editForm<Json>(
      context,
      'Взвешивание',
      (set) => [
        input('Вес, кг', weight, numeric: true),
        ListTile(
          title: const Text('Дата'),
          subtitle: Text(dayKey(date)),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (d != null) set(() => date = d);
          },
        ),
      ],
      () {
        final data = {'kg': parseNumber(weight.text), 'day': dayKey(date)};
        validateRecord(
          Record(
            id: previous?.id ?? '00000000-0000-4000-8000-000000000000',
            kind: 'weight',
            data: data,
          ),
        );
        return data;
      },
    );
    if (data != null) await c.save('weight', data, previous: previous);
  } catch (e) {
    if (context.mounted) message(context, e);
  } finally {
    weight.dispose();
  }
}

Future<void> editGoal(BuildContext context, DiaryController c) async {
  final prior = c.goal?.data;
  var mode = prior?['mode'] as String? ?? 'auto';
  var formula = BmrFormula.values.byName(
    prior?['formula'] as String? ?? 'mifflin',
  );
  var sex = BiologicalSex.values.byName(prior?['sex'] as String? ?? 'female');
  var goal = WeightGoal.values.byName(prior?['goal'] as String? ?? 'maintain');
  var activity = (prior?['activity'] as num?)?.toDouble() ?? 1.2;
  var macros = prior?['macro_mode'] as String? ?? 'Проценты';
  if (!['Проценты', 'Граммы'].contains(macros)) macros = 'Граммы';
  var highProtein =
      prior?['macro_template'] == 'protein' ||
      (prior?['macro_template'] == null &&
          prior?['macro_mode'] == 'Проценты' &&
          prior?['protein'] == 30);
  final fields = <String, TextEditingController>{};
  for (final key in [
    'weight',
    'desired_weight',
    'height',
    'age',
    'body_fat',
    'weekly_kg',
    'kcal',
    'protein',
    'fat',
    'carbs',
  ]) {
    final value = prior?[key];
    fields[key] = TextEditingController(
      text: value is num ? number(value, key == 'age' ? 0 : 1) : '',
    );
  }
  if (prior == null) {
    fields['weekly_kg']!.text = '0';
    fields['protein']!.text = '25';
    fields['fat']!.text = '30';
    fields['carbs']!.text = '45';
  }
  AutomaticGoal calculateAutomatic() {
    final age = parseNumber(fields['age']!.text);
    if (age != age.roundToDouble()) {
      throw ArgumentError('Возраст в полных годах');
    }
    return automaticGoal(
      formula: formula,
      weight: parseNumber(fields['weight']!.text),
      height: parseNumber(fields['height']!.text),
      age: age.toInt(),
      sex: sex,
      activity: activity,
      goal: goal,
      weeklyKg: parseNumber(fields['weekly_kg']!.text),
      bodyFat: formula == BmrFormula.katch
          ? parseNumber(fields['body_fat']!.text)
          : null,
      highProtein: highProtein,
    );
  }

  Widget automaticPreview() {
    try {
      final n = calculateAutomatic().nutrition;
      final weight = parseNumber(fields['weight']!.text);
      return Card(
        key: const ValueKey('auto-goal-preview'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${number(n.kcal, 0)} ккал в сутки',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Белки: ${number(n.protein)} г'),
              Text('Жиры: ${number(n.fat)} г'),
              Text('Углеводы: ${number(n.carbs)} г'),
              const SizedBox(height: 8),
              Text(
                'Белок не выше 2,2 г/кг: ${number(weight * 2.2)} г. Жиры — около 30% калорий, углеводы — оставшаяся энергия.',
              ),
              const SizedBox(height: 8),
              Text(
                '4 × белки + 9 × жиры + 4 × углеводы = ${number(n.kcal, 0)} ккал. Граммы на экране округлены; сохраняется точный расчет.',
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Заполните корректные параметры: калории и БЖУ будут рассчитаны вместе. Для своего распределения выберите ручной режим.',
        ),
      );
    }
  }

  var date = DateTime.now();
  try {
    final data = await editForm<Json>(
      context,
      'Настроить цели',
      (set) => [
        dropdown('Режим', mode, {
          'auto': 'Автоматический',
          'manual': 'Ручной',
        }, (v) => set(() => mode = v)),
        dropdown('Цель', goal.name, {
          for (final v in WeightGoal.values) v.name: goalNames[v.index],
        }, (v) => set(() => goal = WeightGoal.values.byName(v))),
        input(
          'Исходный / расчетный вес, кг',
          fields['weight']!,
          numeric: true,
          onChanged: (_) => set(() {}),
        ),
        input('Желаемый вес, кг', fields['desired_weight']!, numeric: true),
        if (mode == 'auto') ...[
          input(
            'Рост, см',
            fields['height']!,
            numeric: true,
            onChanged: (_) => set(() {}),
          ),
          input(
            'Возраст (полных лет)',
            fields['age']!,
            numeric: true,
            onChanged: (_) => set(() {}),
          ),
          dropdown(
            'Параметр пола для формулы',
            sex.name,
            {'male': 'Мужской', 'female': 'Женский'},
            (v) => set(() => sex = BiologicalSex.values.byName(v)),
          ),
          dropdown(
            'Формула',
            formula.name,
            {for (final v in BmrFormula.values) v.name: formulaNames[v.index]},
            (v) => set(() => formula = BmrFormula.values.byName(v)),
          ),
          if (formula == BmrFormula.katch)
            input(
              'Жир тела, %',
              fields['body_fat']!,
              numeric: true,
              onChanged: (_) => set(() {}),
            ),
          DropdownButtonFormField<double>(
            initialValue: activity,
            isExpanded: true,
            itemHeight: null,
            selectedItemBuilder: (context) => activityNames
                .map(
                  (name) =>
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                )
                .toList(),
            decoration: const InputDecoration(labelText: 'Активность'),
            items: [
              for (var i = 0; i < activityValues.length; i++)
                DropdownMenuItem(
                  value: activityValues[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(activityNames[i]),
                        const SizedBox(height: 4),
                        Text(
                          activityDescriptions[i],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            onChanged: (v) => set(() => activity = v!),
          ),
          const SizedBox(height: 8),
          Text(
            activityDescriptions[activityValues.indexOf(activity)],
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          input(
            'Изменение веса в неделю, кг (положительное число)',
            fields['weekly_kg']!,
            numeric: true,
            onChanged: (_) => set(() {}),
          ),
        ] else
          input('Суточные калории', fields['kcal']!, numeric: true),
        if (mode == 'auto') ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Сбалансированный'),
                selected: !highProtein,
                onSelected: (_) => set(() => highProtein = false),
              ),
              ChoiceChip(
                label: const Text('Больше белка'),
                selected: highProtein,
                onSelected: (_) => set(() => highProtein = true),
              ),
            ],
          ),
          automaticPreview(),
        ] else ...[
          dropdown('Настройка БЖУ', macros, {
            'Проценты': 'В процентах',
            'Граммы': 'В граммах',
          }, (v) => set(() => macros = v)),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => set(() {
                  macros = 'Проценты';
                  fields['protein']!.text = '25';
                  fields['fat']!.text = '30';
                  fields['carbs']!.text = '45';
                }),
                child: const Text('Сбалансированный'),
              ),
              TextButton(
                onPressed: () => set(() {
                  macros = 'Проценты';
                  fields['protein']!.text = '30';
                  fields['fat']!.text = '30';
                  fields['carbs']!.text = '40';
                }),
                child: const Text('Больше белка'),
              ),
            ],
          ),
          for (final key in ['protein', 'fat', 'carbs'])
            input(
              '${{'protein': 'Белки', 'fat': 'Жиры', 'carbs': 'Углеводы'}[key]}, ${macros == 'Проценты' ? '%' : 'г'}',
              fields[key]!,
              numeric: true,
            ),
        ],
        ListTile(
          title: const Text('Применить с даты'),
          subtitle: Text(dayKey(date)),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime(2100),
            );
            if (d != null) set(() => date = d);
          },
        ),
        const Text(
          'Расчет приблизительный. Поправка 7700 ккал/кг не предсказывает точное изменение веса. Автоматический дефицит ограничен 20%, профицит 15% от TDEE.',
        ),
      ],
      () {
        final weight = parseNumber(fields['weight']!.text),
            desired = parseNumber(fields['desired_weight']!.text);
        if (weight < 20 || weight > 500 || desired < 20 || desired > 500) {
          throw ArgumentError('Проверьте вес');
        }
        final weekly = mode == 'auto'
            ? parseNumber(fields['weekly_kg']!.text)
            : 0.0;
        double kcal;
        Nutrition? automaticNutrition;
        String explanation;
        var age = 0;
        var height = 0.0;
        double? bodyFat;
        if (mode == 'auto') {
          final ageValue = parseNumber(fields['age']!.text);
          if (ageValue != ageValue.roundToDouble()) {
            throw ArgumentError('Возраст в полных годах');
          }
          age = ageValue.toInt();
          height = parseNumber(fields['height']!.text);
          bodyFat = formula == BmrFormula.katch
              ? parseNumber(fields['body_fat']!.text)
              : null;
          final calculation = calculateAutomatic();
          final target = calculation.energy;
          automaticNutrition = calculation.nutrition;
          kcal = automaticNutrition.kcal;
          explanation =
              '${formulaNames[formula.index]}: BMR ${number(target.basal, 0)} × $activity = TDEE ${number(target.tdee, 0)}. Поправка ${number(target.adjustment, 0)} ккал. ${target.limited ? 'Применено ограничение.' : ''} '
              'БЖУ рассчитаны вместе с калориями по 4/4/9; белок ограничен 2,2 г/кг расчетного веса. Жиры около 30%, углеводы — остаток.';
        } else {
          kcal = parseNumber(fields['kcal']!.text);
          explanation = 'Ручная норма: ${number(kcal, 0)} ккал.';
        }
        final p =
                automaticNutrition?.protein ??
                parseNumber(fields['protein']!.text),
            f = automaticNutrition?.fat ?? parseNumber(fields['fat']!.text),
            carbs =
                automaticNutrition?.carbs ?? parseNumber(fields['carbs']!.text);
        final n =
            automaticNutrition ??
            (macros == 'Проценты'
                ? macroPercent(kcal, p, f, carbs)
                : Nutrition(kcal, p, f, carbs));
        n.validate(product: true);
        if (mode == 'manual' && macros == 'Граммы') {
          explanation +=
              ' Энергия из БЖУ: ${number(p * 4 + carbs * 4 + f * 9, 0)} ккал (ориентир 4/4/9).';
        }
        final result = {
          'effective_from': dayKey(date),
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
          'nutrition': n.toJson(),
          'mode': mode,
          'formula': formula.name,
          'sex': sex.name,
          'goal': goal.name,
          'activity': activity,
          'weight': weight,
          'desired_weight': desired,
          'height': height,
          'age': age,
          'body_fat': bodyFat,
          'weekly_kg': weekly,
          'kcal': kcal,
          'protein': p,
          'fat': f,
          'carbs': carbs,
          'macro_mode': mode == 'auto' ? 'Автоматически' : macros,
          if (mode == 'auto')
            'macro_template': highProtein ? 'protein' : 'balanced',
          'explanation': explanation,
        };
        validateRecord(
          Record(
            id: '00000000-0000-4000-8000-000000000000',
            kind: 'goal',
            data: result,
          ),
        );
        return result;
      },
      ownedControllers: fields.values.toList(),
    );
    if (data != null && context.mounted) {
      final sameDay = c
          .of('goal')
          .where((r) => r.data['effective_from'] == data['effective_from'])
          .firstOrNull;
      if (sameDay != null) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Новая версия цели на эту дату?'),
            content: const Text(
              'Прежний расчет останется в истории. Для выбранной даты и последующих дней будет действовать новая версия.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Сохранить новую версию'),
              ),
            ],
          ),
        );
        if (accepted != true) return;
      }
      await c.save('goal', data);
    }
  } catch (e) {
    if (context.mounted) message(context, e);
  }
}

Widget dropdown(
  String label,
  String selected,
  Map<String, String> values,
  ValueChanged<String> changed,
) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: DropdownButtonFormField<String>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: (v) => changed(v!),
  ),
);
