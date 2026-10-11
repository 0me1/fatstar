import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';
import '../domain/records.dart';
import '../domain/repository.dart';

/// Drift custom SQL: the versioned document schema requires no generated code.
class DiaryDatabase extends GeneratedDatabase implements DiaryRepository {
  DiaryDatabase(File file) : super(NativeDatabase.createInBackground(file));
  DiaryDatabase.memory() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE records (
        kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL,
        version INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
        local_only INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(kind,id))''');
      await customStatement('''CREATE TABLE outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT UNIQUE NOT NULL,
        kind TEXT NOT NULL, record_id TEXT NOT NULL, expected_version INTEGER NOT NULL,
        payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        server TEXT, error TEXT)''');
      await customStatement(
        'CREATE INDEX outbox_record ON outbox(kind,record_id,sequence)',
      );
      await customStatement(
        'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<List<Record>> records({String? kind, bool deleted = false}) async {
    final rows = await customSelect(
      'SELECT * FROM records WHERE (? IS NULL OR kind = ?) AND (? = 1 OR deleted = 0)',
      variables: [
        Variable<String>(kind),
        Variable<String>(kind),
        Variable<int>(deleted ? 1 : 0),
      ],
    ).get();
    return rows.map(_record).toList();
  }

  Record _record(QueryRow r) => Record(
    id: r.read<String>('id'),
    kind: r.read<String>('kind'),
    data: jsonDecode(r.read<String>('data')) as Json,
    version: r.read<int>('version'),
    deleted: r.read<int>('deleted') == 1,
    localOnly: r.read<int>('local_only') == 1,
  );

  Future<Record?> find(String kind, String id) async {
    final row = await customSelect(
      'SELECT * FROM records WHERE kind=? AND id=?',
      variables: [Variable(kind), Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : _record(row);
  }

  Future<void> _write(Record record) => customStatement(
    'INSERT OR REPLACE INTO records(kind,id,data,version,deleted,local_only) VALUES(?,?,?,?,?,?)',
    [
      record.kind,
      record.id,
      jsonEncode(record.data),
      record.version,
      record.deleted ? 1 : 0,
      record.localOnly ? 1 : 0,
    ],
  );

  Future<Record> save(Record value) => transaction(() async {
    validateRecord(value);
    final previous = await find(value.kind, value.id);
    if (previous != null && previous.version != value.version) {
      throw StateError('Запись изменена; откройте ее заново');
    }
    final result = value.copy(version: (previous?.version ?? 0) + 1);
    await _write(result);
    if (!result.localOnly) {
      await customStatement(
        'INSERT INTO outbox(operation_id,kind,record_id,expected_version,payload) VALUES(?,?,?,?,?)',
        [
          const Uuid().v4(),
          value.kind,
          value.id,
          previous?.version ?? 0,
          jsonEncode(result.toJson()),
        ],
      );
    }
    return result;
  });

  Future<List<Json>> operations() async => (await customSelect(
    'SELECT * FROM outbox ORDER BY sequence',
  ).get()).map((r) => r.data).toList();

  Future<void> acknowledge(Json operation, Record server) =>
      transaction(() async {
        await cacheHistory(server);
        await customStatement('DELETE FROM outbox WHERE operation_id=?', [
          operation['operation_id'],
        ]);
        final pending = await customSelect(
          'SELECT 1 FROM outbox WHERE kind=? AND record_id=? LIMIT 1',
          variables: [Variable(server.kind), Variable(server.id)],
        ).getSingleOrNull();
        if (pending == null) await _write(server);
      });

  Future<void> conflict(
    Json operation,
    Json server,
    String reason,
  ) => customStatement(
    "UPDATE outbox SET status='conflict',server=?,error=? WHERE operation_id=?",
    [jsonEncode(server), reason, operation['operation_id']],
  );

  Future<void> resolve(Json operation, {required bool keepLocal}) =>
      transaction(() async {
        final local = await find(
          operation['kind'] as String,
          operation['record_id'] as String,
        );
        final remoteJson = jsonDecode(operation['server'] as String) as Json;
        final remote = remoteJson.isEmpty ? null : Record.fromJson(remoteJson);
        await customStatement(
          'DELETE FROM outbox WHERE kind=? AND record_id=?',
          [operation['kind'], operation['record_id']],
        );
        if (remote != null) {
          await _write(remote);
        } else {
          await customStatement('DELETE FROM records WHERE kind=? AND id=?', [
            operation['kind'],
            operation['record_id'],
          ]);
        }
        if (keepLocal && local != null) {
          await save(local.copy(version: remote?.version ?? 0));
        }
      });

  Future<void> applyPage(List<Record> changes, int cursor) =>
      transaction(() async {
        for (final server in changes) {
          await cacheHistory(server);
          final pending = await customSelect(
            'SELECT 1 FROM outbox WHERE kind=? AND record_id=? LIMIT 1',
            variables: [Variable(server.kind), Variable(server.id)],
          ).getSingleOrNull();
          final current = await find(server.kind, server.id);
          if (pending == null &&
              !(current?.localOnly ?? false) &&
              (current == null || current.version <= server.version)) {
            await _write(server);
          }
        }
        await customStatement(
          "INSERT OR REPLACE INTO metadata(key,value) VALUES('cursor',?)",
          ['$cursor'],
        );
      });

  Future<int> cursor() async {
    final row = await customSelect(
      "SELECT value FROM metadata WHERE key='cursor'",
    ).getSingleOrNull();
    return row == null ? 0 : int.parse(row.read<String>('value'));
  }

  Future<void> cacheHistory(Record server) async {
    if (server.kind != 'product') return;
    final key = 'history:${server.id}:${server.version}';
    final value = {
      'version': server.version,
      'actor_id': server.data['updated_by'] ?? server.data['created_by'],
      'created_at': server.data['updated_at'],
      'record': server.toJson(),
    };
    await customStatement(
      'INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)',
      [key, jsonEncode(value)],
    );
  }

  Future<List<Json>> cachedHistory(String productId) async =>
      (await customSelect(
        'SELECT value FROM metadata WHERE key LIKE ?',
        variables: [Variable('history:$productId:%')],
      ).get()).map((r) => jsonDecode(r.read<String>('value')) as Json).toList();
}
