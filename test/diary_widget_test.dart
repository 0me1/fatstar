import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/presentation/screens.dart';
import 'package:calorie_diary/presentation/food_add_button.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  for (final brightness in Brightness.values) {
    testWidgets(
      'Diary ${brightness.name}: empty meals, no invented activity, calendar navigation',
      (tester) async {
        final c = DiaryController()
          ..db = DiaryDatabase.memory()
          ..day = DateTime.now().subtract(const Duration(days: 1))
          ..loading = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [diaryProvider.overrideWith((ref) => c)],
            child: MaterialApp(
              theme: diaryTheme(brightness),
              home: const DiaryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Цель не задана'), findsOneWidget);
        expect(find.text('Завтрак'), findsOneWidget);
        expect(find.text('Сожжено'), findsNothing);
        final add = tester.widget<IconButton>(
          find.descendant(
            of: find.byType(FoodAddButton).first,
            matching: find.byType(IconButton),
          ),
        );
        final foreground = add.style!.foregroundColor!.resolve({})!;
        final background = add.style!.backgroundColor!.resolve({})!;
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        final ratio = a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        await tester.tap(find.byTooltip('Следующий день'));
        await tester.pumpAndSettle();
        expect(DateUtils.isSameDay(c.day, DateTime.now()), isTrue);
        expect(
          tester.widget<IconButton>(find.byTooltip('Следующий день')).onPressed,
          isNull,
        );
        await tester.fling(
          find.byKey(const ValueKey('diary-day-swipe')),
          const Offset(-240, 0),
          800,
        );
        await tester.pumpAndSettle();
        expect(DateUtils.isSameDay(c.day, DateTime.now()), isTrue);
        await tester.fling(
          find.byKey(const ValueKey('diary-day-swipe')),
          const Offset(240, 0),
          800,
        );
        await tester.pumpAndSettle();
        expect(
          DateUtils.isSameDay(
            c.day,
            DateTime.now().subtract(const Duration(days: 1)),
          ),
          isTrue,
        );
        await tester.fling(
          find.byKey(const ValueKey('diary-day-swipe')),
          const Offset(-240, 0),
          800,
        );
        await tester.pumpAndSettle();
        expect(DateUtils.isSameDay(c.day, DateTime.now()), isTrue);
        c.selectDay(DateTime.now().add(const Duration(days: 1)));
        expect(DateUtils.isSameDay(c.day, DateTime.now()), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Unknown macros show known subtotal rather than confirmed zero', (
    tester,
  ) async {
    final c = DiaryController()
      ..db = DiaryDatabase.memory()
      ..day = DateTime(2026, 10, 11)
      ..loading = false;
    c.records = [
      Record(
        id: '00000000-0000-4000-8000-000000000001',
        kind: 'entry',
        data: {
          'name': 'Быстрые КБЖУ',
          'day': '2026-10-11',
          'meal': 'breakfast',
          'amount': 1,
          'unit': 'quick',
          'nutrition': {
            'kcal': 120,
            'protein': null,
            'fat': null,
            'carbs': null,
          },
        },
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          theme: diaryTheme(Brightness.dark),
          home: const DiaryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('≥ 0 / — г'), findsNWidgets(3));
    expect(find.text('120'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
