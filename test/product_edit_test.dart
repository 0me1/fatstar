import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/main.dart' as app;
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/domain/nutrition.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/presentation/catalog.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'search_widget_test.dart' show ready;

Finder productField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

// The real catalog -> detail sheet -> editor path reproduces the lost-context bug.
Future<void> productEditScenario(WidgetTester tester, DiaryController c) async {
  final p = await c.save('product', {
    'name': 'Шоколад Babyfox',
    'brand': 'Babyfox',
    'unit': 'gram',
    'active': true,
    'nutrition': const Nutrition(520, 7.5, 34, 47).toJson(),
    'portions': [
      {'id': 'small', 'name': 'Штука', 'amount': 40},
      {'id': 'large', 'name': 'Плитка', 'amount': 100},
    ],
  });
  await c.addEntries([entryForProduct(p, 40, 'Штука')], Meal.breakfast);
  final snapshot = c.entries.single.data;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [diaryProvider.overrideWith((ref) => c)],
      child: MaterialApp(
        theme: app.diaryTheme(Brightness.dark),
        home: const CatalogScreen(),
      ),
    ),
  );
  await ready(tester);
  await tester.tap(find.text('Шоколад Babyfox'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Изменить КБЖУ и порции'));
  await tester.pumpAndSettle();
  await tester.enterText(
    productField('Название').first,
    'Шоколад исправленный',
  );
  await tester.ensureVisible(productField('Калории'));
  await tester.enterText(productField('Калории'), '530');
  await tester.ensureVisible(find.byTooltip('Удалить порцию').first);
  await tester.tap(find.byTooltip('Удалить порцию').first);
  await tester.pumpAndSettle();
  // Deleting the first row must leave the second row bound to its own controllers.
  expect(
    tester.widget<TextField>(productField('Размер')).controller!.text,
    '100,0',
  );
  await tester.enterText(productField('Название').last, 'Большая плитка');
  await tester.enterText(productField('Размер'), '120');
  await tester.ensureVisible(find.text('Добавить порцию'));
  await tester.tap(find.text('Добавить порцию'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(productField('Размер').last);
  await tester.enterText(productField('Название').last, 'Половинка');
  await tester.enterText(productField('Размер').last, '60');
  await tester.ensureVisible(find.text('Сохранить'));
  await tester.tap(find.text('Сохранить'));
  await ready(tester);
  final saved = (await c.db!.find('product', p.id))!;
  expect(saved.version, p.version + 1);
  expect(saved.data['name'], 'Шоколад исправленный');
  expect(saved.data['nutrition']['kcal'], 530);
  final portions = saved.data['portions'] as List;
  expect(portions, hasLength(2));
  expect(portions.first, {
    'id': 'large',
    'name': 'Большая плитка',
    'amount': 120.0,
  });
  expect(portions.last['name'], 'Половинка');
  expect(portions.last['amount'], 60);
  expect(c.entries.single.data, snapshot);
  expect(find.text('Шоколад исправленный'), findsOneWidget);
  expect(
    (await c.db!.operations()).where((o) => o['record_id'] == p.id),
    hasLength(2),
  );
  expect(tester.takeException(), isNull);

  // Delete all portions, save, then reopen to verify persistence, not just visual removal.
  await tester.tap(find.text('Шоколад исправленный'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Изменить КБЖУ и порции'));
  await tester.pumpAndSettle();
  for (var i = 0; i < 2; i++) {
    await tester.ensureVisible(find.byTooltip('Удалить порцию').first);
    await tester.tap(find.byTooltip('Удалить порцию').first);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text('Сохранить'));
  await tester.tap(find.text('Сохранить'));
  await ready(tester);
  expect((await c.db!.find('product', p.id))!.data['portions'], isEmpty);
  await tester.tap(find.text('Шоколад исправленный'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Изменить КБЖУ и порции'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Удалить порцию'), findsNothing);
  await tester.enterText(productField('Название'), 'Не сохранять');
  Navigator.of(tester.element(productField('Название'))).pop();
  await tester.pumpAndSettle();
  expect(
    (await c.db!.find('product', p.id))!.data['name'],
    'Шоколад исправленный',
  );
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'catalog edits persist nutrition and portions; deletion and cancel are safe',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = DiaryController()
        ..db = DiaryDatabase.memory()
        ..loading = false;
      await productEditScenario(tester, c);
      // ProviderScope disposes the controller and closes its database.
    },
  );
}
