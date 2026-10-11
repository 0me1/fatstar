import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/data/backup.dart';
import 'package:calorie_diary/data/sync.dart';
import 'package:calorie_diary/domain/records.dart';

Record product({String? id}) => Record(
  id: id ?? const Uuid().v4(),
  kind: 'product',
  data: {
    'name': 'Молоко',
    'brand': 'Ферма',
    'unit': 'milliliter',
    'nutrition': {'kcal': 50, 'protein': 3, 'fat': 2, 'carbs': 5},
    'portions': [],
    'active': true,
  },
);

class FakeRemote implements SyncRemote {
  final Map<String, Record> records = {};
  final Map<String, Json> applied = {};
  bool loseResponse = false, offline = false;
  int writes = 0;
  @override
  Future<Json> apply(Json op) async {
    if (offline) throw StateError('offline');
    final key = op['operation_id'] as String;
    if (applied.containsKey(key)) return applied[key]!;
    final local = Record.fromJson(jsonDecode(op['payload'] as String) as Json);
    final remote = records[local.id];
    if ((remote?.version ?? 0) != op['expected_version']) {
      return {'status': 'conflict', 'record': remote?.toJson() ?? {}};
    }
    final saved = local.copy(version: (remote?.version ?? 0) + 1);
    records[local.id] = saved;
    writes++;
    final result = {'status': 'applied', 'record': saved.toJson()};
    applied[key] = result;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('response lost');
    }
    return result;
  }

  @override
  Future<Json> changes(int cursor) async {
    if (offline) throw StateError('offline');
    return {
      'records': records.values.map((r) => r.toJson()).toList(),
      'cursor': writes,
      'has_more': false,
    };
  }
}

void main() {
  late DiaryDatabase db;
  setUp(() {
    db = DiaryDatabase.memory();
  });
  tearDown(() async {
    await db.close();
  });
  test('local write and outbox are atomic', () async {
    final p = await db.save(product());
    expect((await db.records()).single.id, p.id);
    expect((await db.operations()).single['expected_version'], 0);
  });
  test('stale local edit rejected', () async {
    final p = await db.save(product());
    await db.save(p.copy(data: {...p.data, 'name': 'Новое'}));
    await expectLater(db.save(p), throwsStateError);
  });
  test('soft delete and restore keep identity', () async {
    final p = await db.save(product());
    final deleted = await db.save(p.copy(deleted: true));
    expect(await db.records(), isEmpty);
    final restored = await db.save(deleted.copy(deleted: false));
    expect(restored.id, p.id);
    expect(restored.version, 3);
  });
  test('separate account databases isolate diaries', () async {
    final other = DiaryDatabase.memory();
    try {
      await db.save(product());
      expect(await other.records(), isEmpty);
    } finally {
      await other.close();
    }
  });
  test('backup round trip and repeat import', () async {
    await db.save(product());
    final json = await BackupService(db).export();
    final other = DiaryDatabase.memory();
    try {
      final service = BackupService(other);
      await service.merge(await service.preview(json));
      expect((await other.records()).single.localOnly, true);
      expect(await other.operations(), isEmpty);
      await service.merge(await service.preview(json));
      expect(await other.records(), hasLength(1));
    } finally {
      await other.close();
    }
  });
  test('invalid backup does not alter records', () async {
    await db.save(product());
    await expectLater(
      BackupService(db).preview('{"format":"other"}'),
      throwsFormatException,
    );
    expect(await db.records(), hasLength(1));
  });
  test('backup conflicts preserve existing data', () async {
    final p = await db.save(product());
    final source = jsonEncode({
      'format': 'calorie-diary',
      'version': 1,
      'records': [
        p.copy(data: {...p.data, 'name': 'Другой'}).toJson(),
      ],
    });
    final service = BackupService(db);
    final preview = await service.preview(source);
    expect(preview.conflicts, hasLength(1));
    await service.merge(preview);
    expect((await db.records()).single.data['name'], 'Молоко');
  });
  test('duplicate backup UUID is rejected', () async {
    final p = product();
    await expectLater(
      BackupService(db).preview(
        jsonEncode({
          'format': 'calorie-diary',
          'version': 1,
          'records': [p.toJson(), p.toJson()],
        }),
      ),
      throwsFormatException,
    );
  });
  test('offline queue is preserved then synchronized', () async {
    final remote = FakeRemote()..offline = true;
    final sync = SyncEngine(db, remote, () {});
    try {
      await db.save(product());
      await sync.run();
      expect(await db.operations(), hasLength(1));
      remote.offline = false;
      await sync.run();
      expect(await db.operations(), isEmpty);
      expect(remote.writes, 1);
    } finally {
      await sync.dispose();
    }
  });
  test('lost response retries exactly once on server', () async {
    final remote = FakeRemote()..loseResponse = true;
    final sync = SyncEngine(db, remote, () {});
    try {
      await db.save(product());
      await sync.run();
      expect(await db.operations(), hasLength(1));
      await sync.run();
      expect(await db.operations(), isEmpty);
      expect(remote.writes, 1);
    } finally {
      await sync.dispose();
    }
  });
  test('two users conflict rather than overwrite newer product', () async {
    final remote = FakeRemote();
    final sync = SyncEngine(db, remote, () {});
    try {
      final p = await db.save(product());
      remote.records[p.id] = p.copy(
        data: {...p.data, 'name': 'Чужая новая версия'},
        version: 2,
      );
      remote.writes = 2;
      await sync.run();
      final op = (await db.operations()).single;
      expect(op['status'], 'conflict');
      expect((await db.records()).single.data['name'], 'Молоко');
      await db.resolve(op, keepLocal: true);
      await sync.run();
      expect(remote.records[p.id]!.version, 3);
      expect(remote.records[p.id]!.data['name'], 'Молоко');
    } finally {
      await sync.dispose();
    }
  });
  test('incoming snapshot does not erase pending edit', () async {
    final p = await db.save(product());
    await db.applyPage([
      p.copy(data: {...p.data, 'name': 'Сервер'}, version: 3),
    ], 5);
    expect((await db.records()).single.data['name'], 'Молоко');
    expect(await db.cursor(), 5);
  });
  test('page replay is idempotent', () async {
    final p = product().copy(version: 1);
    await db.applyPage([p], 1);
    await db.applyPage([p], 1);
    expect(await db.records(), hasLength(1));
  });
  test('invalid save has no outbox side effect', () async {
    await expectLater(
      db.save(product().copy(data: {'name': ''})),
      throwsA(anything),
    );
    expect(await db.operations(), isEmpty);
    expect(await db.records(), isEmpty);
  });
}
