import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';
import '../domain/records.dart';
import '../domain/food_search.dart';
import '../domain/search_lexicon.dart';
import '../domain/repository.dart';

/// Drift custom SQL: the versioned document schema requires no generated code.
class DiaryDatabase extends GeneratedDatabase implements DiaryRepository {
  static const tables = {
    'product': 'products',
    'entry': 'diary_entries',
    'goal': 'goal_versions',
    'weight': 'weight_entries',
    'favorite': 'favorites',
    'portion': 'portion_preferences',
    'settings': 'user_settings',
  };
  DiaryDatabase(File file)
    : enableFts = true,
      super(NativeDatabase.createInBackground(file));
  DiaryDatabase.memory({this.enableFts = true})
    : super(NativeDatabase.memory());
  final bool enableFts;
  int searchRevision = 0;
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await _createAggregateTables();
      await _createRecordsView();
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
      await _createSearchIndex();
    }),
    onUpgrade: (_, from, to) => transaction(() async {
      if (from == 1 && to == 3) {
        await _createAggregateTables();
        for (final pair in tables.entries) {
          await customStatement(
            'INSERT INTO ${pair.value}(id,data,version,deleted,local_only) SELECT id,data,version,deleted,local_only FROM records WHERE kind=?',
            [pair.key],
          );
        }
        await customStatement('DROP TABLE records');
        await _createRecordsView();
      } else if (from != 2 || to != 3) {
        throw StateError(
          'Неподдерживаемая миграция $from → $to. База не удалена.',
        );
      }
      await _createSearchIndex();
      for (final product in await records(kind: 'product', deleted: true)) {
        await _indexProduct(product);
      }
    }),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      final lexicon = await customSelect(
        "SELECT value FROM metadata WHERE key='food_search_lexicon_version'",
      ).getSingleOrNull();
      if (lexicon?.read<String>('value') != '$foodSearchLexiconVersion') {
        await transaction(() async {
          for (final product in await records(kind: 'product', deleted: true)) {
            await _indexProduct(product);
          }
          await customStatement(
            "INSERT OR REPLACE INTO metadata VALUES('food_search_lexicon_version',?)",
            ['$foodSearchLexiconVersion'],
          );
        });
      }
    },
  );

  Future<void> _createAggregateTables() async {
    for (final table in tables.values) {
      await customStatement(
        'CREATE TABLE $table (id TEXT PRIMARY KEY, data TEXT NOT NULL CHECK(json_valid(data)), version INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)), local_only INTEGER NOT NULL DEFAULT 0 CHECK(local_only IN (0,1)))',
      );
    }
    await customStatement(
      "CREATE INDEX diary_date_meal ON diary_entries(json_extract(data,'\$.day'),json_extract(data,'\$.meal'),deleted)",
    );
    await customStatement(
      "CREATE INDEX goal_effective_date ON goal_versions(json_extract(data,'\$.effective_from'))",
    );
    await customStatement(
      "CREATE INDEX weight_date ON weight_entries(json_extract(data,'\$.day'))",
    );
  }

  Future<void> _createRecordsView() => customStatement(
    'CREATE VIEW records AS ${tables.entries.map((pair) => "SELECT '${pair.key}' AS kind,id,data,version,deleted,local_only FROM ${pair.value}").join(' UNION ALL ')}',
  );

  String _table(String kind) =>
      tables[kind] ?? (throw ArgumentError('Неизвестный тип записи'));

  @override
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

  @override
  Future<Record?> find(String kind, String id) async {
    final row = await customSelect(
      'SELECT * FROM records WHERE kind=? AND id=?',
      variables: [Variable(kind), Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : _record(row);
  }

  Future<void> _write(Record record) async {
    await customStatement(
      'INSERT OR REPLACE INTO ${_table(record.kind)}(id,data,version,deleted,local_only) VALUES(?,?,?,?,?)',
      [
        record.id,
        jsonEncode(record.data),
        record.version,
        record.deleted ? 1 : 0,
        record.localOnly ? 1 : 0,
      ],
    );
    if (record.kind == 'product') {
      await _indexProduct(record);
    }
    searchRevision++;
  }

  Future<void> _createSearchIndex() async {
    await customStatement(
      'CREATE TABLE food_search_documents (product_id TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL, aliases TEXT NOT NULL, hidden INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX food_search_name ON food_search_documents(name)',
    );
    await customStatement(
      'CREATE TABLE food_search_tokens (token TEXT NOT NULL, product_id TEXT NOT NULL, PRIMARY KEY(token,product_id)) WITHOUT ROWID',
    );
    await customStatement(
      'CREATE INDEX food_tokens_product ON food_search_tokens(product_id)',
    );
    await customStatement(
      'CREATE TABLE food_search_grams (gram TEXT NOT NULL, product_id TEXT NOT NULL, PRIMARY KEY(gram,product_id)) WITHOUT ROWID',
    );
    await customStatement(
      'CREATE INDEX food_grams_product ON food_search_grams(product_id)',
    );
    if (enableFts) {
      try {
        await customStatement(
          "CREATE VIRTUAL TABLE food_search_fts USING fts5(product_id UNINDEXED,name,brand,aliases,tokenize='unicode61')",
        );
      } catch (_) {
        // The indexed token and bigram tables remain available without FTS5.
      }
    }
    await customStatement(
      "INSERT OR REPLACE INTO metadata VALUES('food_search_lexicon_version',?)",
      ['$foodSearchLexiconVersion'],
    );
  }

  Future<bool> usesFts() async => (await customSelect(
    "SELECT 1 FROM sqlite_master WHERE name='food_search_fts'",
  ).get()).isNotEmpty;

  Future<void> _removeSearchProduct(String id) async {
    for (final table in [
      'food_search_documents',
      'food_search_tokens',
      'food_search_grams',
    ]) {
      await customStatement('DELETE FROM $table WHERE product_id=?', [id]);
    }
    if (await usesFts()) {
      await customStatement('DELETE FROM food_search_fts WHERE product_id=?', [
        id,
      ]);
    }
  }

  Future<void> _indexProduct(Record product) async {
    await _removeSearchProduct(product.id);
    if (product.deleted) {
      return;
    }
    final name = SearchNormalizer.normalize(
      product.data['name'] as String? ?? '',
    );
    final brand = SearchNormalizer.normalize(
      product.data['brand'] as String? ?? '',
    );
    final aliases = SearchNormalizer.aliases(product);
    await customStatement(
      'INSERT INTO food_search_documents VALUES(?,?,?,?,?)',
      [
        product.id,
        name,
        brand,
        aliases,
        product.data['active'] == false ? 1 : 0,
      ],
    );
    final words = SearchNormalizer.tokens('$name $brand $aliases').toSet();
    final tokens = {
      ...words,
      ...words
          .where((w) => w.length >= 4)
          .map((w) => '~${SearchNormalizer.phonetic(w)}'),
    };
    final grams = tokens.expand(SearchNormalizer.grams).toSet();
    for (final pair in [
      ('food_search_tokens', tokens),
      ('food_search_grams', grams),
    ]) {
      final values = pair.$2.toList();
      for (var i = 0; i < values.length; i += 64) {
        final chunk = values.skip(i).take(64).toList();
        await customStatement(
          'INSERT OR IGNORE INTO ${pair.$1} VALUES ${List.filled(chunk.length, '(?,?)').join(',')}',
          [
            for (final v in chunk) ...[v, product.id],
          ],
        );
      }
    }
    if (await usesFts()) {
      await customStatement(
        'INSERT INTO food_search_fts(product_id,name,brand,aliases) VALUES(?,?,?,?)',
        [product.id, name, brand, aliases],
      );
    }
  }

  Future<List<Record>> searchProductsByIds(
    Iterable<String> ids, {
    bool hidden = false,
  }) async {
    final result = <Record>[];
    final values = ids.toList();
    for (var i = 0; i < values.length; i += 200) {
      final chunk = values.skip(i).take(200).toList();
      final rows = await customSelect(
        "SELECT 'product' AS kind,p.* FROM products p JOIN food_search_documents d ON d.product_id=p.id WHERE p.deleted=0 AND (?=1 OR d.hidden=0) AND p.id IN (${List.filled(chunk.length, '?').join(',')})",
        variables: [Variable(hidden ? 1 : 0), ...chunk.map(Variable.new)],
      ).get();
      result.addAll(rows.map(_record));
    }
    return result;
  }

  Future<List<Record>> searchCandidates(
    SearchQuery query, {
    bool hidden = false,
    int limit = 600,
  }) async {
    if (query.tokens.isEmpty) {
      final rows = await customSelect(
        "SELECT 'product' AS kind,p.* FROM products p JOIN food_search_documents d ON d.product_id=p.id WHERE p.deleted=0 AND (?=1 OR d.hidden=0) ORDER BY d.name,p.id LIMIT ?",
        variables: [Variable(hidden ? 1 : 0), Variable(limit)],
      ).get();
      return rows.map(_record).toList();
    }
    final ids = <String>{};
    final exact = await customSelect(
      'SELECT product_id FROM food_search_documents WHERE name=? LIMIT ?',
      variables: [Variable(query.normalized), Variable(limit)],
    ).get();
    ids.addAll(exact.map((r) => r.read<String>('product_id')));
    final alternatives = [
      query,
      SearchQuery(SearchNormalizer.layout(query.raw)),
    ];
    for (final q in alternatives) {
      if (q.tokens.isEmpty) {
        continue;
      }
      if (await usesFts()) {
        final expression = q.tokens
            .map((t) => '"${t.replaceAll('"', '""')}"*')
            .join(' AND ');
        final rows = await customSelect(
          'SELECT product_id FROM food_search_fts WHERE food_search_fts MATCH ? ORDER BY rank LIMIT ?',
          variables: [Variable(expression), Variable(limit)],
        ).get();
        ids.addAll(rows.map((r) => r.read<String>('product_id')));
      }
      final clauses = <String>[];
      final args = <Variable>[];
      for (final token in q.tokens) {
        clauses.add(
          'SELECT product_id FROM food_search_tokens WHERE token>=? AND token<?',
        );
        args.addAll([Variable(token), Variable('$token\uffff')]);
      }
      final exactWords = await customSelect(
        '${clauses.join(' INTERSECT ')} LIMIT ?',
        variables: [...args, Variable(limit)],
      ).get();
      ids.addAll(exactWords.map((r) => r.read<String>('product_id')));
      for (final token in [
        ...q.tokens,
        ...q.tokens
            .where((w) => w.length >= 4)
            .map((w) => '~${SearchNormalizer.phonetic(w)}'),
      ]) {
        final rows = await customSelect(
          'SELECT DISTINCT product_id FROM food_search_tokens WHERE token>=? AND token<? LIMIT ?',
          variables: [
            Variable(token),
            Variable('$token\uffff'),
            Variable(limit),
          ],
        ).get();
        ids.addAll(rows.map((r) => r.read<String>('product_id')));
      }
    }
    // A bounded indexed overlap shortlist supports substrings and transpositions.
    final grams = query.tokens
        .expand(SearchNormalizer.grams)
        .toSet()
        .take(64)
        .toList();
    if (grams.isNotEmpty) {
      final rows = await customSelect(
        'SELECT product_id,COUNT(*) AS hits FROM food_search_grams WHERE gram IN (${List.filled(grams.length, '?').join(',')}) GROUP BY product_id ORDER BY hits DESC,product_id LIMIT ?',
        variables: [...grams.map(Variable.new), Variable(limit)],
      ).get();
      ids.addAll(rows.map((r) => r.read<String>('product_id')));
    }
    if (ids.isEmpty) return [];
    return searchProductsByIds(ids.take(limit * 3), hidden: hidden);
  }

  @override
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
          if (operation['kind'] == 'product') {
            await _removeSearchProduct(operation['record_id'] as String);
          }
          searchRevision++;
          await customStatement(
            'DELETE FROM ${_table(operation['kind'] as String)} WHERE id=?',
            [operation['record_id']],
          );
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
