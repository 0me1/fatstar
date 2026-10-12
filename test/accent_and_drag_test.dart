import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/presentation/motion.dart';
import 'package:calorie_diary/presentation/color_picker.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/data/database.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  test('accent preserves font and theme in personal settings', () async {
    final c = DiaryController()
      ..db = DiaryDatabase.memory()
      ..userId = '00000000-0000-4000-8000-000000000001';
    await c.saveSettings({'font': 'Comfortaa', 'theme': 'light'});
    await c.saveSettings({'accent': 0xFFFF0000});
    expect(c.font, 'Comfortaa');
    expect(c.theme, 'light');
    expect(c.accent, 0xFFFF0000);
    c.dispose();
  });
  test('extreme accent colors preserve readable controls in both themes', () {
    for (final brightness in Brightness.values) {
      for (final accent in [
        0xFF000000,
        0xFFFFFFFF,
        0xFFFF0000,
        0xFF0000FF,
        0xFF00FF00,
      ]) {
        final scheme = diaryTheme(brightness, accent: accent).colorScheme;
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
  testWidgets('HEX picker validates and applies an arbitrary opaque color', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await pickAccent(context, 0xFF56DCC6);
              },
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#A125FF');
    await tester.pump();
    await tester.ensureVisible(find.text('Применить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(selected, 0xFFA125FF);
  });
  testWidgets(
    'diary follows finger before committing and returns after a short drag',
    (tester) async {
      var day = DateTime(2026, 1, 3);
      Widget page(DateTime date) =>
          SizedBox.expand(child: Center(child: Text('Day ${date.day}')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => DiaryMotion(
                day: day,
                selectDay: (next) => set(() => day = next),
                pageBuilder: page,
                child: page(day),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(tester.getCenter(find.text('Day 3')).dx, greaterThan(450));
      expect(day.day, 3);
      expect(find.text('Day 2'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(day.day, 3);
      expect(tester.getCenter(find.text('Day 3')).dx, closeTo(400, 1));
      await tester.fling(
        find.byKey(const ValueKey('diary-day-swipe')),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(day.day, 2);
    },
  );
}
