import 'dart:io';
import '../test/product_edit_test.dart' show productEditScenario;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:calorie_diary/main.dart' as app;
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/data/food_search_repository.dart';
import 'package:calorie_diary/presentation/catalog.dart';
import 'package:calorie_diary/data/backup.dart';
import 'package:calorie_diary/domain/nutrition.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/presentation/activities.dart';
import 'package:calorie_diary/presentation/app_version.dart';
import 'package:calorie_diary/presentation/goals.dart';
import 'package:calorie_diary/presentation/screens.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: login, diary, shared catalog, account isolation, conflict and cold persistence',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'android-a@example.com',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'Local-only-ci-password-428!',
      );
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(HomeScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      final c = container.read(diaryProvider);
      final p = await c.save('product', {
        'name': 'Тестовое молоко',
        'brand': 'CI',
        'unit': 'milliliter',
        'active': true,
        'portions': [
          {'id': const Uuid().v4(), 'name': 'Стакан', 'amount': 200},
        ],
        'nutrition': const Nutrition(50, 3, 2, 5).toJson(),
      });
      await c.sync!.run();
      await tester.pumpAndSettle();
      final current = (await c.db!.find('product', p.id))!;
      await c.addEntries([
        entryForProduct(current, 200, 'Стакан'),
      ], Meal.breakfast);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Завтрак')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(find.text('Завтрак').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Завтрак'));
      await tester.pumpAndSettle();
      expect(find.text('Тестовое молоко'), findsOneWidget);
      expect(c.entries.single.data['amount'], 200);
      expect(entryNutrition(c.entries.single).kcal, 100);
      await c.sync!.run();

      // Real server conflict between two authenticated users.
      c.sync!.stop();
      final aProduct = (await c.db!.find('product', p.id))!;
      await c.save('product', {
        ...aProduct.data,
        'name': 'Локальная правка A',
      }, previous: aProduct);
      final b = SupabaseClient(app.supabaseUrl, app.supabaseKey);
      await b.auth.signInWithPassword(
        email: 'android-b@example.com',
        password: 'Local-only-ci-password-428!',
      );
      final result =
          await b.rpc(
                'apply_operation',
                params: {
                  'p_operation_id': const Uuid().v4(),
                  'p_kind': 'product',
                  'p_id': p.id,
                  'p_expected': aProduct.version,
                  'p_record': {
                    'id': p.id,
                    'kind': 'product',
                    'deleted': false,
                    'data': {...aProduct.data, 'name': 'Серверная правка B'},
                  },
                },
              )
              as Map;
      expect(result['status'], 'applied');
      c.sync!.start();
      for (
        var i = 0;
        i < 30 && !c.operations.any((o) => o['status'] == 'conflict');
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(c.operations.any((o) => o['status'] == 'conflict'), true);
      final conflict = c.operations.firstWhere(
        (o) => o['status'] == 'conflict',
      );
      await c.db!.resolve(conflict, keepLocal: false);
      await c.reload();
      expect(
        (await c.db!.find('product', p.id))!.data['name'],
        'Серверная правка B',
      );
      // Historical nutrition is a snapshot, unaffected by catalog edits.
      expect(c.entries.single.data['name'], 'Тестовое молоко');

      final backup = await BackupService(c.db!).export();
      final file = File(
        '${Directory.systemTemp.path}/${const Uuid().v4()}.sqlite',
      );
      var cold = DiaryDatabase(file);
      final preview = await BackupService(cold).preview(backup);
      await BackupService(cold).merge(preview);
      await cold.close();
      cold = DiaryDatabase(file);
      expect(await cold.records(kind: 'entry'), hasLength(1));
      expect((await cold.records(kind: 'product')).single.localOnly, true);
      await cold.close();
      await file.delete();

      await c.signOut();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'android-b@example.com',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'Local-only-ci-password-428!',
      );
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(c.entries, isEmpty);
      await c.sync!.run();
      await c.reload();
      expect(c.of('product').any((r) => r.id == p.id), true);
      await b.dispose();
    },
  );
  testWidgets('Android: installed version is available from package manager', (
    tester,
  ) async {
    final version = await readAppVersion();
    expect(version.version, isNotEmpty);
    expect(int.parse(version.build), greaterThanOrEqualTo(12));
  });
  testWidgets(
    'Android: local indexed search and immediate quick add without remote',
    (tester) async {
      final file = File(
        '${Directory.systemTemp.path}/${const Uuid().v4()}.sqlite',
      );
      final db = DiaryDatabase(file);
      final c = DiaryController()
        ..db = db
        ..loading = false
        ..userId = const Uuid().v4();
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await db.save(
            Record(
              id: const Uuid().v4(),
              kind: 'product',
              localOnly: true,
              data: {
                'name': i == 500
                    ? 'Молоко 2,5%'
                    : i == 501
                    ? 'Гречка'
                    : 'Продукт номер $i',
                'brand': 'CI',
                'unit': 'gram',
                'active': true,
                'portions': [],
                'nutrition': const Nutrition(50, 3, 2, 5).toJson(),
              },
            ),
          );
        }
      });
      await c.reload();
      final engine = FoodSearchRepository(db);
      for (final query in ['мол', 'малако', 'vjkjrj']) {
        final watch = Stopwatch()..start();
        final hits = await engine.search(query);
        watch.stop();
        expect(hits.single.product.data['name'], 'Молоко 2,5%');
        // ignore: avoid_print
        print(
          'ANDROID_SEARCH_BENCH products=1000 fts=${await db.usesFts()} query=$query ms=${watch.elapsedMilliseconds}',
        );
      }
      expect(
        (await engine.search('uhtrxrf')).single.product.data['name'],
        'Гречка',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [diaryProvider.overrideWith((ref) => c)],
          child: MaterialApp(
            theme: app.diaryTheme(Brightness.dark),
            home: const CatalogScreen(meal: Meal.breakfast),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      for (
        var i = 0;
        i < 50 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.enterText(find.byType(TextField), 'vjkjrj');
      await tester.pump(const Duration(milliseconds: 200));
      for (
        var i = 0;
        i < 50 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('Молоко 2,5%'), findsOneWidget);
      await tester.tap(find.byTooltip('Добавить 100,0 г'));
      for (var i = 0; i < 50 && c.entries.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(c.entries, hasLength(1));
      expect(c.entries.single.data['amount'], 100);
      expect(c.sync, isNull);
      expect(
        (await db.operations()).where((o) => o['kind'] == 'entry'),
        hasLength(1),
      );
      await tester.tap(find.text('Отменить'));
      for (var i = 0; i < 50 && c.entries.isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(c.entries, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Android: offline activity minutes preview and save', (
    tester,
  ) async {
    final db = DiaryDatabase(
      File('${Directory.systemTemp.path}/${const Uuid().v4()}.sqlite'),
    );
    final c = DiaryController()
      ..db = db
      ..loading = false;
    await c.save('weight', {'day': '2026-10-12', 'kg': 70});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          theme: app.diaryTheme(Brightness.dark),
          home: ActivitySearchScreen(day: DateTime(2026, 10, 12)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ходьба, обычная'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('activity-minutes')),
      '60',
    );
    await tester.pump();
    expect(find.text('206 ккал сожжено'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    for (var i = 0; i < 50 && c.of('activity').isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(c.of('activity').single.data['kcal'], closeTo(205.8, .001));
    expect(
      (await db.operations()).where((o) => o['kind'] == 'activity'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Android: automatic goals save balanced macros and capped protein',
    (tester) async {
      final c = DiaryController()
        ..db = DiaryDatabase(
          File('${Directory.systemTemp.path}/${const Uuid().v4()}.sqlite'),
        )
        ..loading = false;
      await c.save('goal', {
        'effective_from': dayKey(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        'nutrition': const Nutrition(2619, 128, 84, 319).toJson(),
        'mode': 'auto',
        'formula': 'mifflin',
        'sex': 'male',
        'goal': 'muscle',
        'activity': 1.9,
        'weight': 71.0,
        'desired_weight': 73.0,
        'height': 179.0,
        'age': 19,
        'weekly_kg': 0.0,
        'kcal': 2619.0,
        'protein': 128.0,
        'fat': 84.0,
        'carbs': 319.0,
        'macro_mode': 'Граммы',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: app.diaryTheme(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => editGoal(context, c),
                child: const Text('Open goals'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open goals'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('auto-goal-preview')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Белки: 113,6 г'), findsOneWidget);
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      for (var i = 0; i < 50 && c.of('goal').length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      final n = entryNutrition(c.goal!);
      expect(n.protein, 113.6);
      expect(n.protein!, lessThanOrEqualTo(71 * 2.2));
      expect(n.protein! * 4 + n.fat! * 9 + n.carbs! * 4, closeTo(n.kcal, 1e-8));
      expect(c.goal!.data['mode'], 'auto');
      expect(c.goal!.data['macro_mode'], 'Граммы');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
    },
  );
  testWidgets(
    'Android: catalog edit saves nutrition and changes/deletes portions',
    (tester) async {
      final c = DiaryController()
        ..db = DiaryDatabase(
          File('${Directory.systemTemp.path}/${const Uuid().v4()}.sqlite'),
        )
        ..loading = false;
      await productEditScenario(tester, c);
    },
  );
}
