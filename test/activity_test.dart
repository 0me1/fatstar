import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:calorie_diary/domain/activity.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/data/backup.dart';

void main() {
  test('MET duration, weight, custom rate and invalid values', () {
    expect(builtInActivities.first.calories(30, 70), closeTo(91.875, .001));
    expect(builtInActivities[1].calories(30, 70), closeTo(275.625, .001));
    expect(builtInActivities[2].calories(60, 70), closeTo(183.75, .001));
    const custom = ActivityType('custom', 'Test', '✨', kcalPerMinute: 5);
    expect(custom.calories(12, null), 60);
    for (final m in [0.0, -1.0, double.nan, 1441.0]) {
      expect(() => custom.calories(m, null), throwsArgumentError);
    }
    expect(
      () => builtInActivities.first.calories(30, null),
      throwsArgumentError,
    );
  });
  test(
    'activities preserve snapshots, dates, deletion, outbox and backup',
    () async {
      final db = DiaryDatabase.memory(), restored = DiaryDatabase.memory();
      try {
        final original = await db.save(
          Record(
            id: const Uuid().v4(),
            kind: 'activity',
            data: {
              'name': 'Ходьба',
              'day': '2026-10-12',
              'minutes': 30,
              'kcal': 91.875,
              'weight_kg': 70,
              'activity_id': 'walking',
              'met': 3.5,
              'icon': '🚶',
            },
          ),
        );
        expect(
          burnedForDay(await db.records(), DateTime(2026, 10, 12)),
          91.875,
        );
        expect(burnedForDay(await db.records(), DateTime(2026, 10, 11)), 0);
        expect(await db.operations(), hasLength(1));
        final backup = BackupService(db);
        final target = BackupService(restored);
        await target.merge(await target.preview(await backup.export()));
        await target.merge(await target.preview(await backup.export()));
        expect(await restored.records(kind: 'activity'), hasLength(1));
        await db.save(original.copy(deleted: true));
        expect(burnedForDay(await db.records(), DateTime(2026, 10, 12)), 0);
        final latest = await db.find('activity', original.id);
        await db.save(original.copy(version: latest!.version));
        expect(
          burnedForDay(await db.records(), DateTime(2026, 10, 12)),
          91.875,
        );
      } finally {
        await db.close();
        await restored.close();
      }
    },
  );
  test('activity validation rejects malformed minutes and dates', () {
    final r = Record(
      id: const Uuid().v4(),
      kind: 'activity',
      data: {'name': 'Бег', 'day': '2026-10-12', 'minutes': 20, 'kcal': 100},
    );
    validateRecord(r);
    expect(
      () => validateRecord(r.copy(data: {...r.data, 'minutes': -1})),
      throwsArgumentError,
    );
    expect(
      () => validateRecord(r.copy(data: {...r.data, 'day': '2026-02-30'})),
      throwsArgumentError,
    );
  });
}
