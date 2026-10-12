import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/domain/nutrition.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/presentation/catalog.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'food_search_test.dart' show food;

Future<void> ready(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  expect(
    find.byType(LinearProgressIndicator),
    findsNothing,
    reason: 'SQLite and isolate search must finish',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all products form one deduplicated list with filter chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = DiaryController()
      ..db = DiaryDatabase.memory()
      ..loading = false;
    final first = await c.db!.save(food(1, 'Первый продукт'));
    final second = await c.db!.save(food(2, 'Второй продукт'));
    await c.db!.save(food(3, 'Остальной каталог'));
    await c.addEntries([entryForProduct(first, 100, 'г')], Meal.breakfast);
    await c.favorite(first);
    await c.favorite(second);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryProvider.overrideWith((ref) => c)],
        child: const MaterialApp(home: CatalogScreen(meal: Meal.breakfast)),
      ),
    );
    await ready(tester);
    expect(find.text('Для этого приема пищи'), findsNothing);
    expect(find.text('Каталог продуктов'), findsNothing);
    expect(find.text('Первый продукт'), findsOneWidget);
    expect(find.text('Второй продукт'), findsOneWidget);
    expect(find.text('Остальной каталог'), findsOneWidget);
    expect(find.text('Недавние'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Первый продукт')).dy,
      lessThan(tester.getTopLeft(find.text('Второй продукт')).dy),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Избранное'));
    await ready(tester);
    expect(find.text('Первый продукт'), findsOneWidget);
    expect(find.text('Второй продукт'), findsOneWidget);
    expect(find.text('Остальной каталог'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'offline search ${brightness.name}: keyboard, newest query, add/undo and no duplicate on back',
      (tester) async {
        final c = DiaryController()
          ..db = DiaryDatabase.memory()
          ..userId = '00000000-0000-4000-8000-000000000001'
          ..loading = false;
        await c.db!.save(food(1, 'Молоко 2,5%'));
        await c.db!.save(food(2, 'Творог 5%'));
        await c.reload();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [diaryProvider.overrideWith((ref) => c)],
            child: MaterialApp(
              theme: diaryTheme(brightness),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const CatalogScreen(meal: Meal.breakfast),
                      ),
                    ),
                    child: const Text('Открыть поиск'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть поиск'));
        await ready(tester);
        expect(
          tester.widget<TextField>(find.byType(TextField)).autofocus,
          true,
        );
        expect(find.text('Каталог продуктов'), findsNothing);
        await tester.enterText(find.byType(TextField), 'мол');
        await tester.pump(const Duration(milliseconds: 40));
        await tester.enterText(find.byType(TextField), 'тварог');
        await ready(tester);
        expect(find.text('Творог 5%'), findsOneWidget);
        expect(find.text('Молоко 2,5%'), findsNothing);
        final query = tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text;
        final offset = tester
            .widget<ListView>(find.byType(ListView))
            .controller!
            .offset;
        await tester.tap(find.text('Творог 5%'));
        await tester.pumpAndSettle();
        expect(find.text('Единица / порция'), findsOneWidget);
        Navigator.of(tester.element(find.text('Единица / порция'))).pop();
        await ready(tester);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          query,
        );
        expect(
          tester.widget<ListView>(find.byType(ListView)).controller!.offset,
          offset,
        );
        await tester.tap(find.byTooltip('Добавить 100,0 г'));
        await ready(tester);
        expect(c.entries, hasLength(1));
        expect(c.entries.single.data['amount'], 100);
        expect(find.text('Отменить'), findsOneWidget);
        await tester.tap(find.text('Отменить'));
        await ready(tester);
        expect(c.entries, isEmpty);
        await tester.tap(find.byTooltip('Очистить'));
        await ready(tester);
        expect(find.text('Молоко 2,5%'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'несуществующий продукт',
        );
        await ready(tester);
        expect(
          find.text(
            'Ничего не найдено. Попробуйте другое название или создайте продукт.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Готово'));
        await tester.pumpAndSettle();
        expect(find.text('Открыть поиск'), findsOneWidget);
        expect(c.entries, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
