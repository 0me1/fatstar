import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/presentation/screens.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  for (final brightness in Brightness.values) {
    testWidgets(
      'Diary ${brightness.name}: empty meals, no invented activity, calendar navigation',
      (tester) async {
        final c = DiaryController()
          ..db = DiaryDatabase.memory()
          ..day = DateTime(2026, 10, 11)
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
        await tester.tap(find.byTooltip('Следующий день'));
        await tester.pumpAndSettle();
        expect(c.day.day, 12);
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
