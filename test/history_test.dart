import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/domain/nutrition.dart';

Record goal(String id, String date, String time, double kcal) => Record(id: id, kind: 'goal', data: {'effective_from': date, 'recorded_at': time, 'nutrition': Nutrition(kcal, 100, 50, 200).toJson()});
void main() {
  test('new formula does not alter past day targets', () {
    final old = goal('a', '2026-10-01', '2026-10-01T12:00:00Z', 1800);
    final next = goal('b', '2026-10-11', '2026-10-11T12:00:00Z', 2100);
    expect(goalForDay([old, next], DateTime(2026, 10, 10))!.id, 'a');
    expect(goalForDay([old, next], DateTime(2026, 10, 11))!.id, 'b');
  });
  test('same date revision retains original and selects latest deterministically', () {
    final a = goal('a', '2026-10-11', '2026-10-11T12:00:00Z', 1800);
    final b = goal('b', '2026-10-11', '2026-10-11T13:00:00Z', 2000);
    expect(goalForDay([a,b], DateTime(2026, 10, 11))!.id, 'b');
    expect(goalForDay([b,a], DateTime(2026, 10, 11))!.id, 'b');
  });
  test('future and deleted goals not applied', () {
    final next = goal('a', '2026-10-12', '2026-10-11T12:00:00Z', 1800);
    expect(goalForDay([next], DateTime(2026, 10, 11)), isNull);
    expect(goalForDay([next.copy(deleted: true)], DateTime(2026, 10, 12)), isNull);
  });
  test('product changes never mutate diary snapshot', () {
    final p = Record(id: 'a', kind: 'product', version: 1, data: {'name': 'Молоко', 'brand': '', 'unit': 'milliliter', 'nutrition': const Nutrition(50,3,2,5).toJson()});
    final entry = entryForProduct(p, 200, 'Стакан');
    final changed = p.copy(version: 2, data: {...p.data, 'name': 'Новая карточка', 'nutrition': const Nutrition(100,6,4,10).toJson()});
    expect(entry['name'], 'Молоко');
    expect(Nutrition.fromJson(entry['nutrition'] as Json).kcal, 100);
    expect(entryForProduct(changed, 200, 'Стакан')['nutrition']['kcal'], 200);
    expect(entry['product_version'], 1);
  });
}
