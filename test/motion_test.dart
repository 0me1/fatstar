import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/presentation/motion.dart';
import 'package:calorie_diary/presentation/food_add_button.dart';

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'numbers start at the real value and animate subsequent changes',
    (tester) async {
      await tester.pumpWidget(host(const MotionNumber(value: 120)));
      expect(find.text('120'), findsOneWidget);
      await tester.pumpWidget(host(const MotionNumber(value: 240)));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('120'), findsNothing);
      expect(find.text('240'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('240'), findsOneWidget);
    },
  );
  testWidgets('reduced motion changes values immediately', (tester) async {
    await tester.pumpWidget(
      host(const MotionNumber(value: 120), reduced: true),
    );
    await tester.pumpWidget(
      host(const MotionNumber(value: 240), reduced: true),
    );
    await tester.pump();
    expect(find.text('240'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('cancelled selection never shows a success check', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(FoodAddButton(tooltip: 'Add', onAdd: () async => false)),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('successful selection shows temporary confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(FoodAddButton(tooltip: 'Add', onAdd: () async => true)),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final fill = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fill.heightFactor, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });
  testWidgets('undo during removal retains one interactive row', (
    tester,
  ) async {
    const row = Text('Entry', key: ValueKey('entry'));
    await tester.pumpWidget(host(const MotionRows(children: [row])));
    await tester.pumpWidget(host(const MotionRows(children: [])));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(host(const MotionRows(children: [row])));
    await tester.pumpAndSettle();
    expect(find.text('Entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('day pages slide side by side without fading or overlapping', (
    tester,
  ) async {
    Widget page(String label) =>
        SizedBox.expand(child: Center(child: Text(label)));
    await tester.pumpWidget(
      host(
        DiaryMotion(
          day: DateTime(2026, 10, 9),
          selectDay: (_) {},
          child: page('Old day'),
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        DiaryMotion(
          day: DateTime(2026, 10, 10),
          selectDay: (_) {},
          child: page('New day'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final oldCenter = tester.getCenter(find.text('Old day'));
    final newCenter = tester.getCenter(find.text('New day'));
    expect(newCenter.dx - oldCenter.dx, closeTo(800, 1));
    expect(oldCenter.dx, closeTo(0, 1));
    expect(newCenter.dx, closeTo(800, 1));
    expect(find.byType(FadeTransition), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Old day'), findsNothing);
    expect(tester.getCenter(find.text('New day')).dx, closeTo(400, 1));
  });
}
