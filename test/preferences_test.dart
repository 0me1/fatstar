import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/presentation/meal_section.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/domain/fonts.dart';

void main() {
  test(
    'font and theme edits preserve each other and queue personal settings',
    () async {
      final c = DiaryController()
        ..db = DiaryDatabase.memory()
        ..userId = '00000000-0000-4000-8000-000000000001';
      expect(c.font, 'Rubik');
      await c.saveSettings({'font': 'Manrope'});
      expect(c.font, 'Manrope');
      expect(c.theme, 'dark');
      await c.saveSettings({'theme': 'light'});
      expect(c.font, 'Manrope');
      expect(c.theme, 'light');
      await c.saveSettings({'font': 'Comfortaa'});
      expect(c.theme, 'light');
      expect(c.font, 'Comfortaa');
      expect(await c.db!.operations(), hasLength(3));
      c.dispose();
    },
  );
  test('all eight fonts apply to body and bold headings', () {
    expect(diaryFonts, hasLength(8));
    for (final family in diaryFonts.keys) {
      final theme = diaryTheme(Brightness.dark, font: family);
      expect(theme.textTheme.bodyMedium!.fontFamily, family);
      expect(theme.appBarTheme.titleTextStyle!.fontFamily, family);
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w900);
    }
  });
  testWidgets('empty meals collapse and open automatically on first entry', (
    tester,
  ) async {
    Widget host(bool entries) => MaterialApp(
      home: Scaffold(
        body: MealSection(
          hasEntries: entries,
          header: (expanded, toggle) => TextButton(
            onPressed: toggle,
            child: Text(expanded ? 'Hide' : 'Show'),
          ),
          child: const SizedBox(height: 80, child: Text('Meal contents')),
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    expect(find.text('Show'), findsOneWidget);
    expect(tester.getSize(find.byType(ClipRect).last).height, 0);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ClipRect).last).height, 80);
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('Hide'), findsOneWidget);
    expect(tester.getSize(find.byType(ClipRect).last).height, 80);
  });
  testWidgets('removing a meal during collapse safely disposes its animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealSection(
            hasEntries: true,
            header: (expanded, toggle) =>
                TextButton(onPressed: toggle, child: const Text('Collapse')),
            child: const SizedBox(height: 80),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Collapse'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
