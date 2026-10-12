import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:calorie_diary/data/database.dart';

void createLegacy(File file, {bool corrupt = false}) {
  final db = sqlite3.open(file.path);
  db.execute(
    'CREATE TABLE records (kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, version INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, local_only INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(kind,id))',
  );
  db.execute(
    "CREATE TABLE outbox (sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT UNIQUE NOT NULL, kind TEXT NOT NULL, record_id TEXT NOT NULL, expected_version INTEGER NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', server TEXT, error TEXT)",
  );
  db.execute(
    'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );
  db.execute('INSERT INTO records VALUES(?,?,?,?,?,?)', [
    'product',
    '00000000-0000-4000-8000-000000000001',
    corrupt ? 'invalid-json' : jsonEncode({'name': 'Сохраненный продукт'}),
    7,
    0,
    1,
  ]);
  db.execute(
    'INSERT INTO outbox(operation_id,kind,record_id,expected_version,payload) VALUES(?,?,?,?,?)',
    [
      '00000000-0000-4000-8000-000000000002',
      'entry',
      '00000000-0000-4000-8000-000000000003',
      0,
      '{}',
    ],
  );
  db.execute("INSERT INTO metadata VALUES('cursor','17')");
  db.execute('PRAGMA user_version=1');
  db.dispose();
}

void main() {
  test(
    'v1 → v3 preserves values, versions, local products, pending operations and cursor',
    () async {
      final dir = Directory.systemTemp.createTempSync('diary-migration-');
      final file = File('${dir.path}/db.sqlite');
      createLegacy(file);
      final db = DiaryDatabase(file);
      try {
        final p = (await db.records()).single;
        expect(p.data['name'], 'Сохраненный продукт');
        expect(p.version, 7);
        expect(p.localOnly, true);
        expect(await db.operations(), hasLength(1));
        expect(await db.cursor(), 17);
        final physical = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('products','diary_entries','goal_versions')",
            )
            .get();
        expect(physical, hasLength(3));
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
  test('failed migration rolls back without destroying legacy data', () async {
    final dir = Directory.systemTemp.createTempSync('diary-failed-migration-');
    final file = File('${dir.path}/db.sqlite');
    createLegacy(file, corrupt: true);
    final db = DiaryDatabase(file);
    await expectLater(db.records(), throwsA(anything));
    await db.close();
    final raw = sqlite3.open(file.path);
    try {
      expect(
        raw.select('SELECT data FROM records').single['data'],
        'invalid-json',
      );
      expect(raw.select('PRAGMA user_version').single['user_version'], 1);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE name='products'"),
        isEmpty,
      );
    } finally {
      raw.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
