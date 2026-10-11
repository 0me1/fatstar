import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/domain/nutrition.dart';

void main() {
  group('BMR scientific coefficients', () {
    test('Mifflin male', () => expect(bmr(formula: BmrFormula.mifflin, weight: 70, height: 175, age: 30, sex: BiologicalSex.male), 1648.75));
    test('Mifflin female', () => expect(bmr(formula: BmrFormula.mifflin, weight: 70, height: 175, age: 30, sex: BiologicalSex.female), 1482.75));
    test('Harris 1984 male', () => expect(bmr(formula: BmrFormula.harris, weight: 70, height: 175, age: 30, sex: BiologicalSex.male), closeTo(1695.667, .0001)));
    test('Harris 1984 female', () => expect(bmr(formula: BmrFormula.harris, weight: 70, height: 175, age: 30, sex: BiologicalSex.female), closeTo(1507.133, .0001)));
    test('Katch lean mass', () => expect(bmr(formula: BmrFormula.katch, weight: 70, height: 175, age: 30, sex: BiologicalSex.male, bodyFat: 20), closeTo(1579.6, .0001)));
    test('Katch requires body fat', () => expect(() => bmr(formula: BmrFormula.katch, weight: 70, height: 175, age: 30, sex: BiologicalSex.male), throwsArgumentError));
    test('children cannot receive automatic recommendations', () => expect(() => bmr(formula: BmrFormula.mifflin, weight: 70, height: 175, age: 17, sex: BiologicalSex.male), throwsArgumentError));
    test('nonfinite weight rejected', () => expect(() => bmr(formula: BmrFormula.mifflin, weight: double.nan, height: 175, age: 30, sex: BiologicalSex.male), throwsArgumentError));
  });
  group('TDEE and macros', () {
    test('maintenance uses multiplier', () => expect(energyTarget(basal: 1500, activity: 1.55, goal: WeightGoal.maintain, weeklyKg: 0).kcal, 2325));
    test('loss cannot exceed 20 percent', () { final t = energyTarget(basal: 1500, activity: 1.2, goal: WeightGoal.loss, weeklyKg: 1); expect(t.kcal, 1440); expect(t.limited, true); });
    test('gain cannot exceed 15 percent', () => expect(energyTarget(basal: 1500, activity: 1.2, goal: WeightGoal.gain, weeklyKg: 1).kcal, 2070));
    test('muscle target includes surplus', () => expect(energyTarget(basal: 1500, activity: 1.2, goal: WeightGoal.muscle, weeklyKg: .1).adjustment, closeTo(110, .001)));
    test('unknown activity rejected', () => expect(() => energyTarget(basal: 1500, activity: 9, goal: WeightGoal.loss, weeklyKg: .5), throwsArgumentError));
    test('macro energy adds up', () { final n = macroPercent(2000, 25, 30, 45); expect(n.protein, 125); expect(n.fat, closeTo(66.6667, .001)); expect(n.carbs, 225); expect(n.protein! * 4 + n.fat! * 9 + n.carbs! * 4, closeTo(2000, .001)); });
    test('percent sum checked', () => expect(() => macroPercent(2000, 30, 30, 30), throwsArgumentError));
  });
  group('portions and incomplete values', () {
    const egg = Nutrition(155, 13, 11, 1.1);
    test('two eggs 110 grams', () { final n = portionNutrition(egg, BaseUnit.gram, BaseUnit.gram, 110); expect(n.kcal, closeTo(170.5, .001)); expect(n.protein, closeTo(14.3, .001)); });
    test('milk 300 ml', () => expect(portionNutrition(const Nutrition(50, 3, 2, 5), BaseUnit.milliliter, BaseUnit.milliliter, 300).kcal, 150));
    test('mass volume conversion forbidden', () => expect(() => portionNutrition(egg, BaseUnit.gram, BaseUnit.milliliter, 100), throwsArgumentError));
    test('zero quantity rejected', () => expect(() => egg.scale(0), throwsArgumentError));
    test('only calories preserve null macros', () { final n = const Nutrition(100, null, null, null).scale(2); expect(n.protein, isNull); final t = NutritionTotal([n, egg]); expect(t.kcal, 355); expect(t.protein, 13); expect(t.proteinComplete, false); });
    test('label calories independent from macros', () { expect(egg.toJson()['kcal'], 155); expect(13 * 4 + 11 * 9 + 1.1 * 4, isNot(155)); });
    test('milli precision', () => expect(milli(12.3456), 12346));
    test('Unicode Russian search', () => expect(normalizeSearch(' МОЛОКО Ёж '), 'молоко еж'));
    test('calendar day uses local components', () => expect(dayKey(DateTime(2026, 10, 11)), '2026-10-11'));
  });
}
