import 'nutrition.dart';
import 'records.dart';

class ActivityType {
  const ActivityType(
    this.id,
    this.name,
    this.icon, {
    this.met,
    this.kcalPerMinute,
  });
  final String id, name, icon;
  final double? met, kcalPerMinute;
  double calories(double minutes, double? weight) {
    if (!minutes.isFinite || minutes <= 0 || minutes > 1440) {
      throw ArgumentError('Продолжительность от 0 до 1440 минут');
    }
    if (kcalPerMinute != null) return kcalPerMinute! * minutes;
    if (weight == null || !weight.isFinite || weight < 20 || weight > 500) {
      throw ArgumentError('Укажите вес от 20 до 500 кг');
    }
    // Net energy above resting expenditure, rather than counting rest twice.
    return (met! - 1) * 3.5 * weight / 200 * minutes;
  }
}

// Moderate defaults: walking at a normal purposeful pace; strength training
// averaged across sets and rest intervals. These are estimates, not measurements.
const builtInActivities = [
  ActivityType('walking', 'Ходьба, обычная', '🚶', met: 3.8),
  ActivityType('running', 'Бег, обычный', '🏃', met: 8.5),
  ActivityType('strength', 'Силовая тренировка', '💪', met: 4.5),
];

ActivityType activityType(Record r) => ActivityType(
  r.id,
  r.data['name'] as String,
  '✨',
  kcalPerMinute: decimal(r.data['kcal_per_minute']),
);

double? activityWeight(Iterable<Record> records, DateTime day) {
  final weights =
      records
          .where(
            (r) =>
                !r.deleted &&
                r.kind == 'weight' &&
                (r.data['day'] as String).compareTo(dayKey(day)) <= 0,
          )
          .toList()
        ..sort(
          (a, b) =>
              (b.data['day'] as String).compareTo(a.data['day'] as String),
        );
  if (weights.isNotEmpty) return decimal(weights.first.data['kg']);
  final v = goalForDay(records, day)?.data['weight'];
  return v is num && v >= 20 && v <= 500 ? v.toDouble() : null;
}

double burnedForDay(Iterable<Record> records, DateTime day) => records
    .where(
      (r) => !r.deleted && r.kind == 'activity' && r.data['day'] == dayKey(day),
    )
    .fold(0, (sum, r) => sum + decimal(r.data['kcal']));
