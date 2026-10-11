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
}
