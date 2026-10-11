import 'package:flutter/material.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';

String number(num? n, [int digits = 1]) =>
    n == null ? '—' : n.toStringAsFixed(digits).replaceAll('.', ',');
double parseNumber(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite) throw ArgumentError('Введите число');
  return value;
}

void message(BuildContext context, Object text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        text
            .toString()
            .replaceFirst('Invalid argument(s): ', '')
            .replaceFirst('Bad state: ', ''),
      ),
    ),
  );
}

Future<T?> editForm<T>(
  BuildContext context,
  String title,
  List<Widget> Function(StateSetter) content,
  T Function() result,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => StatefulBuilder(
    builder: (context, update) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...content(update),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(context, result());
                } catch (e) {
                  message(context, e);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget input(
  String label,
  TextEditingController controller, {
  bool numeric = false,
  int lines = 1,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextField(
    controller: controller,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
  ),
);

Future<Json?> quickFood(BuildContext context) async {
  final name = TextEditingController();
  final fields = List.generate(4, (_) => TextEditingController());
  try {
    return await editForm(
      context,
      'Быстрые КБЖУ',
      (_) => [
        input('Название (необязательно)', name),
        for (var i = 0; i < 4; i++)
          input(
            [
              'Калории',
              'Белки (необязательно)',
              'Жиры (необязательно)',
              'Углеводы (необязательно)',
            ][i],
            fields[i],
            numeric: true,
          ),
      ],
      () {
        final n = Nutrition(
          parseNumber(fields[0].text),
          fields[1].text.isEmpty ? null : parseNumber(fields[1].text),
          fields[2].text.isEmpty ? null : parseNumber(fields[2].text),
          fields[3].text.isEmpty ? null : parseNumber(fields[3].text),
        );
        n.validate();
        return {
          'name': name.text.trim().isEmpty ? 'Быстрые КБЖУ' : name.text.trim(),
          'nutrition': n.toJson(),
          'amount': 1,
          'unit': 'quick',
          'portion_name': 'запись',
          'product_id': null,
        };
      },
    );
  } finally {
    name.dispose();
    for (final f in fields) {
      f.dispose();
    }
  }
}

Json entryForProduct(Record product, double amount, String portionName) {
  final p = product.data;
  final base = Nutrition.fromJson(
    Map<String, dynamic>.from(p['nutrition'] as Map),
  );
  final unit = BaseUnit.values.byName(p['unit'] as String);
  return {
    'product_id': product.id,
    'product_version': product.version,
    'name': p['name'],
    'brand': p['brand'],
    'base': base.toJson(),
    'nutrition': portionNutrition(base, unit, unit, amount).toJson(),
    'amount': amount,
    'unit': unit.name,
    'portion_name': portionName,
  };
}

Future<Json?> selectPortion(
  BuildContext context,
  Record product, {
  double? initial,
}) async {
  final p = product.data;
  final raw = (p['portions'] as List)
      .map((j) => Portion.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();
  final amount = TextEditingController(text: number(initial ?? 100));
  Portion? selected;
  final baseLabel = p['unit'] == 'gram' ? 'г' : 'мл';
  try {
    return await editForm(
      context,
      p['name'] as String,
      (set) {
        final value = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
        final grams = value * (selected?.amount ?? 1);
        final kcal =
            Nutrition.fromJson(
              Map<String, dynamic>.from(p['nutrition'] as Map),
            ).kcal *
            grams /
            100;
        return [
          Text('${p['brand'] ?? ''} · на 100 $baseLabel'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selected?.id ?? 'base',
            decoration: const InputDecoration(labelText: 'Единица / порция'),
            items: [
              DropdownMenuItem(value: 'base', child: Text(baseLabel)),
              ...raw.map(
                (r) => DropdownMenuItem(
                  value: r.id,
                  child: Text('${r.name} = ${number(r.amount)} $baseLabel'),
                ),
              ),
            ],
            onChanged: (id) => set(() {
              selected = raw.where((r) => r.id == id).firstOrNull;
              amount.text = selected == null ? '100' : '1';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Количество'),
            onChanged: (_) => set(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            '${number(grams)} $baseLabel · ${number(kcal, 0)} ккал',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ];
      },
      () => entryForProduct(
        product,
        parseNumber(amount.text) * (selected?.amount ?? 1),
        selected?.name ?? baseLabel,
      ),
    );
  } finally {
    amount.dispose();
  }
}

Future<Json?> editEntry(BuildContext context, Record entry) async {
  if (entry.data['base'] == null) {
    final n = entryNutrition(entry);
    final fields = [n.kcal, n.protein, n.fat, n.carbs]
        .map((v) => TextEditingController(text: v == null ? '' : number(v)))
        .toList();
    try {
      return await editForm(
        context,
        entry.data['name'] as String,
        (_) => [
          for (var i = 0; i < 4; i++)
            input(
              ['Калории', 'Белки', 'Жиры', 'Углеводы'][i],
              fields[i],
              numeric: true,
            ),
        ],
        () {
          final n = Nutrition(
            parseNumber(fields[0].text),
            fields[1].text.isEmpty ? null : parseNumber(fields[1].text),
            fields[2].text.isEmpty ? null : parseNumber(fields[2].text),
            fields[3].text.isEmpty ? null : parseNumber(fields[3].text),
          );
          n.validate();
          return {...entry.data, 'nutrition': n.toJson()};
        },
      );
    } finally {
      for (final f in fields) {
        f.dispose();
      }
    }
  }
  final amount = TextEditingController(
    text: number(entry.data['amount'] as num),
  );
  try {
    return await editForm(
      context,
      'Изменить количество',
      (_) => [
        input(
          entry.data['unit'] == 'gram' ? 'Граммы' : 'Миллилитры',
          amount,
          numeric: true,
        ),
      ],
      () {
        final value = parseNumber(amount.text);
        final base = Nutrition.fromJson(
          Map<String, dynamic>.from(entry.data['base'] as Map),
        );
        final unit = BaseUnit.values.byName(entry.data['unit'] as String);
        return {
          ...entry.data,
          'amount': value,
          'nutrition': portionNutrition(base, unit, unit, value).toJson(),
        };
      },
    );
  } finally {
    amount.dispose();
  }
}
