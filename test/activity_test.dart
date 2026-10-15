import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:calorie_diary/domain/activity.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/data/backup.dart';

void main() {
  test('MET duration, weight, custom rate and invalid values', () {
    expect(builtInActivities.first.calories(30, 70), closeTo(102.9, .001));
    expect(builtInActivities[1].calories(30, 70), closeTo(275.625, .001));
    expect(builtInActivities[2].calories(60, 70), closeTo(257.25, .001));
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
    'moderate estimates scale with weight and duration without a calorie floor',
    () {
      final walking = builtInActivities.first;
      final strength = builtInActivities[2];
      expect(walking.calories(60, 71), closeTo(208.74, .001));
      expect(strength.calories(60, 71), closeTo(260.925, .001));
      expect(strength.calories(60, 50), closeTo(183.75, .001));
      expect(strength.calories(30, 71) * 2, strength.calories(60, 71));
      expect(walking.calories(60, 142), walking.calories(60, 71) * 2);
    },
  );
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
  test('v3 upgrade retains records and queued changes', () async {
    final dir = Directory.systemTemp.createTempSync('activity-migration-');
    final file = File('${dir.path}/db.sqlite');
    final old = DiaryDatabase(file);
    await old.save(
      Record(
        id: const Uuid().v4(),
        kind: 'weight',
        data: {'day': '2026-10-12', 'kg': 70},
      ),
    );
    await old.close();
    final raw = sqlite3.open(file.path);
    raw.execute('DROP VIEW records');
    raw.execute('DROP TABLE activity_entries');
    raw.execute('DROP TABLE activity_types');
    final pairs = DiaryDatabase.tables.entries.where(
      (p) => !p.key.startsWith('activity'),
    );
    raw.execute(
      "CREATE VIEW records AS ${pairs.map((p) => "SELECT '${p.key}' AS kind,id,data,version,deleted,local_only FROM ${p.value}").join(' UNION ALL ')}",
    );
    raw.execute('PRAGMA user_version=3');
    raw.dispose();
    final next = DiaryDatabase(file);
    try {
      expect(await next.records(kind: 'weight'), hasLength(1));
      expect(await next.operations(), hasLength(1));
      expect(await next.records(kind: 'activity'), isEmpty);
      expect(activityWeight(await next.records(), DateTime(2026, 10, 12)), 70);
    } finally {
      await next.close();
      dir.deleteSync(recursive: true);
    }
  });
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
