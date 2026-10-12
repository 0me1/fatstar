import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/data/food_search_repository.dart';
import 'food_search_test.dart' show food, use;

void main() {
  for (final fts in [true, false]) {
    test(
      'search index ${fts ? 'FTS5' : 'token fallback'}: writes, aliases, delete, restore, pull',
      () async {
        final db = DiaryDatabase.memory(enableFts: fts);
        final engine = FoodSearchRepository(db);
        try {
          var p = await db.save(food(1, 'Молоко 2,5%'));
          expect((await engine.search('vjkjrj')).single.product.id, p.id);
          expect((await engine.search('малако')).single.product.id, p.id);
          p = await db.save(
            p.copy(
              data: {
                ...p.data,
                'name': 'Творог',
                'aliases': ['Белковый сыр'],
              },
            ),
          );
          expect(await engine.search('молоко'), isEmpty);
          expect((await engine.search('белковый')).single.product.id, p.id);
          p = await db.save(p.copy(deleted: true));
          expect(await engine.search('творог'), isEmpty);
          p = await db.save(p.copy(deleted: false));
          expect(await engine.search('твор'), hasLength(1));
          p = await db.save(p.copy(data: {...p.data, 'active': false}));
          expect(await engine.search('твор'), isEmpty);
          expect(await engine.search('твор', hidden: true), hasLength(1));
          final remote = food(2, 'Гречка').copy(version: 7);
          await db.applyPage([remote], 12);
          expect(await engine.search('греча'), hasLength(1));
          expect(await db.cursor(), 12);
          if (!fts) expect(await db.usesFts(), false);
        } finally {
          await db.close();
        }
      },
    );
  }
  test('v2 → v3 rebuilds index and preserves products and diary', () async {
    final dir = Directory.systemTemp.createTempSync('search-migration-');
    final file = File('${dir.path}/db.sqlite');
    var db = DiaryDatabase(file);
    var p = await db.save(food(1, 'Молоко'));
    final entry = use(1, p);
    await db.save(
      entry.copy(
        data: {
          ...entry.data,
          'name': 'Молоко',
          'nutrition': p.data['nutrition'],
        },
      ),
    );
    await db.close();
    final raw = sqlite3.open(file.path);
    for (final table in [
      'food_search_fts',
      'food_search_documents',
      'food_search_tokens',
      'food_search_grams',
    ]) {
      raw.execute('DROP TABLE IF EXISTS $table');
    }
    raw.execute('PRAGMA user_version=2');
    raw.dispose();
    db = DiaryDatabase(file);
    try {
      expect(await FoodSearchRepository(db).search('мол'), hasLength(1));
      expect(await db.records(kind: 'entry'), hasLength(1));
      expect(await db.operations(), hasLength(2));
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'personal caches invalidate on edits/delete; account databases stay separate',
    () async {
      final a = DiaryDatabase.memory(), b = DiaryDatabase.memory();
      try {
        final p = food(1, 'Молоко 2,5%'), q = food(2, 'Молоко 3,2%');
        await a.applyPage([p, q], 1);
        await b.applyPage([p, q], 1);
        final e = use(1, q);
        final saved = await a.save(
          e.copy(
            data: {
              ...e.data,
              'name': 'Молоко',
              'nutrition': q.data['nutrition'],
            },
          ),
        );
        final ar = FoodSearchRepository(a), br = FoodSearchRepository(b);
        expect((await ar.search('молоко')).first.product.id, q.id);
        expect((await br.search('молоко')).first.product.id, p.id);
        await a.save(saved.copy(deleted: true));
        expect((await ar.search('молоко')).first.preference?.count ?? 0, 0);
      } finally {
        await a.close();
        await b.close();
      }
    },
  );
  test(
    'search benchmark indexed catalog 2000 products, cold/warm',
    () async {
      final db = DiaryDatabase.memory();
      try {
        await db.transaction(() async {
          for (var i = 1; i <= 2000; i++) {
            await db.save(
              food(
                i,
                i == 1500 ? 'Молоко 2,5%' : 'Продукт номер $i',
              ).copy(localOnly: true),
            );
          }
        });
        final repo = FoodSearchRepository(db);
        for (final query in ['мол', 'малако', 'vjkjrj', 'номер 1999']) {
          final watch = Stopwatch()..start();
          final hits = await repo.search(query);
          watch.stop();
          expect(hits, isNotEmpty);
          final warm = Stopwatch()..start();
          await repo.search(query);
          warm.stop();
          // This measures the runner, not a physical Android phone.
          // ignore: avoid_print
          print(
            'SEARCH_BENCH products=2000 fts=${await db.usesFts()} query=$query cold_ms=${watch.elapsedMilliseconds} warm_ms=${warm.elapsedMilliseconds} hits=${hits.length}',
          );
        }
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
