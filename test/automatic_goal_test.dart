import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/domain/nutrition.dart';

void main() {
  test('automatic macros preserve exact JSON 4/4/9 energy and protein cap', () {
    for (final weight in [20.0, 53.999, 71.0, 150.0, 500.0]) {
      for (final kcal in [500.0, 1234.567, 2390.78125, 2695.0, 10000.0]) {
        for (final high in [false, true]) {
          final j = automaticMacros(
            kcal: kcal,
            weight: weight,
            highProtein: high,
          ).toJson();
          final energy =
              (j['protein'] as num) * 4 +
              (j['fat'] as num) * 9 +
              (j['carbs'] as num) * 4;
          expect(energy, closeTo(j['kcal'] as num, 1e-8));
          expect(j['protein'] as num, lessThanOrEqualTo(weight * 2.2));
          expect(j['carbs'] as num, greaterThanOrEqualTo(0));
          expect(
            (j['fat'] as num) * 9 / (j['kcal'] as num),
            closeTo(.30, .00005),
          );
        }
      }
    }
  });
  test('all energy formulas, goals and activities recompute linked macros', () {
    for (final formula in BmrFormula.values) {
      for (final goal in WeightGoal.values) {
        for (final activity in [1.2, 1.375, 1.55, 1.725, 1.9]) {
          final c = automaticGoal(
            formula: formula,
            weight: 71,
            height: 179,
            age: 19,
            sex: BiologicalSex.male,
            bodyFat: 18,
            activity: activity,
            goal: goal,
            weeklyKg: .3,
            highProtein: true,
          );
          expect(milli(c.nutrition.kcal), milli(c.energy.kcal));
          expect(c.nutrition.protein!, lessThanOrEqualTo(71 * 2.2));
          expect(
            c.nutrition.protein! * 4 +
                c.nutrition.fat! * 9 +
                c.nutrition.carbs! * 4,
            closeTo(c.nutrition.kcal, 1e-8),
          );
        }
      }
    }
  });
  test('protein follows body weight, independent of normal calorie target', () {
    for (final kcal in [2000.0, 2390.781, 3000.0, 4000.0]) {
      expect(automaticMacros(kcal: kcal, weight: 71).protein, 113.6);
      expect(
        automaticMacros(kcal: kcal, weight: 71, highProtein: true).protein,
        142,
      );
    }
    final low = automaticMacros(kcal: 500, weight: 500, highProtein: true);
    expect(low.carbs, 0);
    expect(low.protein!, lessThan(500 * 2));
    expect(
      low.protein! * 4 + low.fat! * 9 + low.carbs! * 4,
      closeTo(500, 1e-8),
    );
  });
  test('invalid automatic targets are rejected', () {
    for (final value in [0.0, -1.0, double.nan, double.infinity, 10001.0]) {
      expect(
        () => automaticMacros(kcal: value, weight: 71),
        throwsArgumentError,
      );
    }
    expect(() => automaticMacros(kcal: 2000, weight: 19), throwsArgumentError);
    final capped = automaticMacros(kcal: 2695, weight: 71, highProtein: true);
    expect(capped.protein, 142);
    final balanced = automaticMacros(kcal: 2000, weight: 71);
    expect(balanced.protein, 113.6);
  });
}
