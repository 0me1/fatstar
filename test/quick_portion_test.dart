import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/domain/nutrition.dart';

Record product(String unit) => Record(id: 'product', kind: 'product', version: 2,
  data: {'name': 'Еда', 'unit': unit, 'portions': [{'id': 'glass', 'name': 'Стакан', 'amount': 200}],
    'nutrition': const Nutrition(50, 3, 2, 5).toJson()});
Record preference(String unit, {String? portionId}) => Record(id: 'preference', kind: 'portion',
  data: {'product_id': 'product', 'unit': unit, 'amount': 200, 'portion_name': 'Стакан', 'portion_id': portionId});

void main() {
  for (final unit in ['gram', 'milliliter']) {
    test('first quick add uses 100 $unit and labeled nutrients', () {
      final entry = quickEntryForProduct(product(unit), null);
      expect(entry['amount'], 100);
      expect(entry['unit'], unit);
      expect(entry['nutrition'], const Nutrition(50, 3, 2, 5).toJson());
      expect(entry['portion_id'], isNull);
    });
  }
  test('later quick add repeats saved quantity and named portion', () {
    final entry = quickEntryForProduct(product('milliliter'), preference('milliliter', portionId: 'glass'));
    expect(entry['amount'], 200);
    expect(entry['portion_id'], 'glass');
    expect(entry['nutrition']['kcal'], 100);
  });
  test('changed base unit does not convert an old weight into volume', () {
    final entry = quickEntryForProduct(product('milliliter'), preference('gram'));
    expect(entry['amount'], 100);
    expect(entry['unit'], 'milliliter');
    expect(entry['nutrition']['kcal'], 50);
  });
  test('deleted named portion falls back to the base 100 amount', () {
    final entry = quickEntryForProduct(product('milliliter'), preference('milliliter', portionId: 'missing'));
    expect(entry['amount'], 100);
    expect(entry['portion_id'], isNull);
  });
}
