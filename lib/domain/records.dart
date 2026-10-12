import 'fonts.dart';
import 'nutrition.dart';

typedef Json = Map<String, dynamic>;

class Record {
  const Record({
    required this.id,
    required this.kind,
    required this.data,
    this.version = 0,
    this.deleted = false,
    this.localOnly = false,
  });
  final String id, kind;
  final Json data;
  final int version;
  final bool deleted, localOnly;
  Record copy({Json? data, int? version, bool? deleted, bool? localOnly}) =>
      Record(
        id: id,
        kind: kind,
        data: data ?? this.data,
        version: version ?? this.version,
        deleted: deleted ?? this.deleted,
        localOnly: localOnly ?? this.localOnly,
      );
  Json toJson() => {
    'id': id,
    'kind': kind,
    'data': data,
    'version': version,
    'deleted': deleted,
    'local_only': localOnly,
  };
  factory Record.fromJson(Json j) => Record(
    id: j['id'] as String,
    kind: j['kind'] as String,
    data: Map<String, dynamic>.from(j['data'] as Map),
    version: j['version'] as int? ?? 0,
    deleted: j['deleted'] as bool? ?? false,
    localOnly: j['local_only'] as bool? ?? false,
  );
}

const recordKinds = {
  'product',
  'entry',
  'goal',
  'weight',
  'favorite',
  'portion',
  'settings',
};
final uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void validateRecord(Record record) {
  if (!uuidPattern.hasMatch(record.id) || !recordKinds.contains(record.kind)) {
    throw ArgumentError('Неизвестный тип записи или неверный UUID');
  }
  final d = record.data;
  switch (record.kind) {
    case 'product':
      _name(d['name']);
      if (d['brand'] != null &&
          (d['brand'] is! String || (d['brand'] as String).length > 200)) {
        throw ArgumentError('Бренд должен быть текстом до 200 символов');
      }
      final aliases = d['aliases'];
      if (aliases != null && (aliases is! List || aliases.length > 32 || aliases.any((a)=>a is! String || a.trim().isEmpty || a.length > 200))) {
        throw ArgumentError('Допускается до 32 альтернативных названий по 200 символов');
      }
      if (!['gram', 'milliliter'].contains(d['unit'])) {
        throw ArgumentError('Неверная единица');
      }
      Nutrition.fromJson(
        Map<String, dynamic>.from(d['nutrition'] as Map),
      ).validate(product: true);
      final portions = d['portions'] as List;
      if (portions.length > 128 || d['active'] is! bool) {
        throw ArgumentError('Проверьте статус и список порций');
      }
      final ids = <String>{};
      for (final raw in portions) {
        final p = Portion.fromJson(Map<String, dynamic>.from(raw as Map));
        if (!uuidPattern.hasMatch(p.id) ||
            !ids.add(p.id) ||
            p.name.trim().isEmpty ||
            !p.amount.isFinite ||
            p.amount <= 0 ||
            p.amount > 100000) {
          throw ArgumentError('Проверьте порции');
        }
      }
    case 'entry':
      _date(d['day']);
      if (!Meal.values.any((m) => m.name == d['meal'])) {
        throw ArgumentError('Неверный прием пищи');
      }
      _name(d['name']);
      Nutrition.fromJson(
        Map<String, dynamic>.from(d['nutrition'] as Map),
      ).validate();
      if (decimal(d['amount']) <= 0 ||
          decimal(d['amount']) > 100000 ||
          !decimal(d['amount']).isFinite ||
          !['gram', 'milliliter', 'quick'].contains(d['unit'])) {
        throw ArgumentError('Неверное количество');
      }
      if (d['base'] != null) {
        Nutrition.fromJson(
          Map<String, dynamic>.from(d['base'] as Map),
        ).validate(product: true);
      }
    case 'goal':
      _date(d['effective_from']);
      if (!BmrFormula.values.any((v) => v.name == d['formula']) ||
          !WeightGoal.values.any((v) => v.name == d['goal']) ||
          !['auto', 'manual'].contains(d['mode'])) {
        throw ArgumentError('Неизвестная формула или режим цели');
      }
      final n = Nutrition.fromJson(
        Map<String, dynamic>.from(d['nutrition'] as Map),
      );
      n.validate(product: true);
      if (n.kcal < 500 || n.kcal > 10000) {
        throw ArgumentError('Норма должна быть от 500 до 10000 ккал');
      }
    case 'weight':
      _date(d['day']);
      final v = decimal(d['kg']);
      if (!v.isFinite || v < 20 || v > 500) {
        throw ArgumentError('Вес от 20 до 500 кг');
      }
    case 'favorite':
    case 'portion':
      if (!uuidPattern.hasMatch(d['product_id'] as String)) {
        throw ArgumentError('Неверный продукт');
      }
      if (record.kind == 'portion' &&
          (decimal(d['amount']) <= 0 ||
              decimal(d['amount']) > 100000 ||
              !decimal(d['amount']).isFinite)) {
        throw ArgumentError('Неверная порция');
      }
    case 'settings':
      final accent = d['accent'];
      if (accent != null &&
          (accent is! int || accent < 0xFF000000 || accent > 0xFFFFFFFF)) {
        throw ArgumentError('Неверный акцентный цвет');
      }
      if (d['font'] != null && !diaryFonts.containsKey(d['font'])) {
        throw ArgumentError('Неизвестный шрифт');
      }
      if (!['dark', 'light', 'system'].contains(d['theme'])) {
        throw ArgumentError('Неверная тема');
      }
  }
}

void _name(Object? v) {
  if (v is! String || v.trim().isEmpty || v.length > 200) {
    throw ArgumentError('Название от 1 до 200 символов');
  }
}

void _date(Object? v) {
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
      DateTime.tryParse(v) == null ||
      dayKey(DateTime.parse(v)) != v) {
    throw ArgumentError('Неверная дата');
  }
}

Nutrition entryNutrition(Record entry) => Nutrition.fromJson(
  Map<String, dynamic>.from(entry.data['nutrition'] as Map),
);

Json quickEntryForProduct(Record product, Record? last) {
  final p = product.data;
  final valid =
      last != null &&
      !last.deleted &&
      last.data['product_id'] == product.id &&
      last.data['unit'] == p['unit'] &&
      (last.data['portion_id'] == null ||
          (p['portions'] as List? ?? []).any(
            (raw) => raw['id'] == last.data['portion_id'],
          ));
  return entryForProduct(
    product,
    valid ? decimal(last.data['amount']) : 100,
    valid
        ? (last.data['portion_name'] as String? ?? '')
        : p['unit'] == 'gram'
        ? 'г'
        : 'мл',
    portionId: valid ? last.data['portion_id'] as String? : null,
  );
}

Json entryForProduct(
  Record product,
  double amount,
  String portionName, {
  String? portionId,
}) {
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
    'portion_id': portionId,
  };
}

Record? goalForDay(Iterable<Record> records, DateTime day) {
  final goals = records
      .where(
        (r) =>
            r.kind == 'goal' &&
            !r.deleted &&
            (r.data['effective_from'] as String).compareTo(dayKey(day)) <= 0,
      )
      .toList();
  goals.sort((a, b) {
    final date = (b.data['effective_from'] as String).compareTo(
      a.data['effective_from'] as String,
    );
    if (date != 0) return date;
    final at =
        DateTime.tryParse(a.data['recorded_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bt =
        DateTime.tryParse(b.data['recorded_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final timestamp = bt.compareTo(at);
    return timestamp != 0 ? timestamp : b.id.compareTo(a.id);
  });
  return goals.isEmpty ? null : goals.first;
}
