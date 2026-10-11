import 'dart:math' as math;

/// Fixed precision at storage boundaries. Labels are rounded only by the UI.
int milli(num value) {
  if (!value.isFinite || value < 0 || value > 10000000) {
    throw ArgumentError('Значение вне допустимого диапазона');
  }
  return (value * 1000).round();
}

double decimal(Object? value) => (value as num).toDouble();

enum BaseUnit { gram, milliliter }

enum Meal { breakfast, lunch, dinner, snack }

extension MealLabel on Meal {
  String get label => switch (this) {
    Meal.breakfast => 'Завтрак',
    Meal.lunch => 'Обед',
    Meal.dinner => 'Ужин',
    Meal.snack => 'Перекус',
  };
}

class Nutrition {
  const Nutrition(this.kcal, this.protein, this.fat, this.carbs);
  final double kcal;
  final double? protein;
  final double? fat;
  final double? carbs;

  factory Nutrition.fromJson(Map<String, dynamic> json) => Nutrition(
    decimal(json['kcal']),
    (json['protein'] as num?)?.toDouble(),
    (json['fat'] as num?)?.toDouble(),
    (json['carbs'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'kcal': milli(kcal) / 1000,
    'protein': protein == null ? null : milli(protein!) / 1000,
    'fat': fat == null ? null : milli(fat!) / 1000,
    'carbs': carbs == null ? null : milli(carbs!) / 1000,
  };

  Nutrition scale(double factor) {
    if (!factor.isFinite || factor <= 0) {
      throw ArgumentError('Количество должно быть положительным');
    }
    return Nutrition(
      kcal * factor,
      protein == null ? null : protein! * factor,
      fat == null ? null : fat! * factor,
      carbs == null ? null : carbs! * factor,
    );
  }

  void validate({bool product = false}) {
    for (final value in [kcal, protein, fat, carbs]) {
      if (value != null && (!value.isFinite || value < 0 || value > 100000)) {
        throw ArgumentError('КБЖУ должны быть конечными неотрицательными числами');
      }
    }
    if (product && [protein, fat, carbs].any((v) => v == null)) {
      throw ArgumentError('Для продукта укажите все БЖУ');
    }
  }
}

class NutritionTotal {
  NutritionTotal(Iterable<Nutrition> values) {
    for (final value in values) {
      kcal += value.kcal;
      protein += value.protein ?? 0;
      fat += value.fat ?? 0;
      carbs += value.carbs ?? 0;
      proteinComplete &= value.protein != null;
      fatComplete &= value.fat != null;
      carbsComplete &= value.carbs != null;
    }
  }
  double kcal = 0, protein = 0, fat = 0, carbs = 0;
  bool proteinComplete = true, fatComplete = true, carbsComplete = true;
}

class Portion {
  const Portion({required this.id, required this.name, required this.amount});
  final String id;
  final String name;
  final double amount;
  factory Portion.fromJson(Map<String, dynamic> j) => Portion(
    id: j['id'] as String,
    name: j['name'] as String,
    amount: decimal(j['amount']),
  );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount};
}

Nutrition portionNutrition(
  Nutrition per100,
  BaseUnit productUnit,
  BaseUnit selectedUnit,
  double baseAmount,
) {
  if (productUnit != selectedUnit) {
    throw ArgumentError('Нельзя переводить массу в объем без плотности');
  }
  if (baseAmount > 100000) throw ArgumentError('Слишком большое количество');
  return per100.scale(baseAmount / 100);
}

enum BmrFormula { mifflin, harris, katch }
enum BiologicalSex { male, female }
enum WeightGoal { loss, maintain, gain, muscle }

double bmr({
  required BmrFormula formula,
  required double weight,
  required double height,
  required int age,
  required BiologicalSex sex,
  double? bodyFat,
}) {
  if (!weight.isFinite || weight < 20 || weight > 500 ||
      !height.isFinite || height < 100 || height > 250 || age < 18 || age > 100) {
    throw ArgumentError('Автоматический расчет доступен взрослым 18–100 лет; проверьте рост и вес');
  }
  return switch (formula) {
    BmrFormula.mifflin => 10 * weight + 6.25 * height - 5 * age +
      (sex == BiologicalSex.male ? 5 : -161),
    BmrFormula.harris => sex == BiologicalSex.male
      ? 88.362 + 13.397 * weight + 4.799 * height - 5.677 * age
      : 447.593 + 9.247 * weight + 3.098 * height - 4.330 * age,
    BmrFormula.katch => _katch(weight, bodyFat),
  };
}

double _katch(double weight, double? bodyFat) {
  if (bodyFat == null || !bodyFat.isFinite || bodyFat <= 0 || bodyFat >= 70) {
    throw ArgumentError('Для формулы нужен процент жира от 0 до 70 (не включая границы)');
  }
  return 370 + 21.6 * weight * (1 - bodyFat / 100);
}

class EnergyTarget {
  const EnergyTarget(this.basal, this.tdee, this.adjustment, this.kcal, this.limited);
  final double basal, tdee, adjustment, kcal;
  final bool limited;
}

EnergyTarget energyTarget({
  required double basal,
  required double activity,
  required WeightGoal goal,
  required double weeklyKg,
}) {
  if (!basal.isFinite || basal <= 0 ||
      ![1.2, 1.375, 1.55, 1.725, 1.9].contains(activity) ||
      !weeklyKg.isFinite || weeklyKg < 0 || weeklyKg > 2) {
    throw ArgumentError('Проверьте параметры цели');
  }
  final tdee = basal * activity;
  final desired = weeklyKg * 7700 / 7;
  final bound = tdee * (goal == WeightGoal.loss ? .2 : .15);
  final signed = switch (goal) {
    WeightGoal.loss => -math.min(desired, bound),
    WeightGoal.maintain => 0.0,
    WeightGoal.gain || WeightGoal.muscle => math.min(desired, bound),
  };
  return EnergyTarget(basal, tdee, signed, tdee + signed,
    goal != WeightGoal.maintain && desired > bound);
}

Nutrition macroPercent(double kcal, double protein, double fat, double carbs) {
  if (!kcal.isFinite || kcal <= 0 ||
      [protein, fat, carbs].any((v) => !v.isFinite || v < 0) ||
      (protein + fat + carbs - 100).abs() > .001) {
    throw ArgumentError('Доли БЖУ должны составлять 100%');
  }
  return Nutrition(kcal, kcal * protein / 400,
    kcal * fat / 900, kcal * carbs / 400);
}

String dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
  '${date.month.toString().padLeft(2, '0')}-'
  '${date.day.toString().padLeft(2, '0')}';

String normalizeSearch(String text) => text.toLowerCase().replaceAll('ё', 'е').trim();
