import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/main.dart';
import 'package:calorie_diary/domain/nutrition.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/presentation/controller.dart';
import 'package:calorie_diary/presentation/goals.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Json oldGoal({bool manual = false}) => {
  'effective_from': dayKey(DateTime.now().subtract(const Duration(days: 1))),
  'nutrition': const Nutrition(2619, 128, 84, 319).toJson(),
  'mode': manual ? 'manual' : 'auto',
  'formula': 'mifflin',
  'sex': 'male',
  'goal': 'muscle',
  'activity': 1.375,
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
};
Future<void> open(WidgetTester tester, DiaryController c) async {
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: diaryTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => editGoal(context, c),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'auto preview updates with activity, weight and template; history stays intact',
    (tester) async {
      final c = DiaryController()
        ..db = DiaryDatabase.memory()
        ..loading = false;
      final old = await c.save('goal', oldGoal());
      await open(tester, c);
      expect(find.byKey(const ValueKey('auto-goal-preview')), findsOneWidget);
      expect(field('Белки, г'), findsNothing);
      expect(c.goal!.data['nutrition']['protein'], 128);
      final activity = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<double>,
      );
      await tester.tap(activity);
      await tester.pumpAndSettle();
      for (final description in activityDescriptions) {
        expect(find.text(description), findsWidgets);
      }
      await tester.tap(find.text(activityNames[3]).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Больше белка'));
      await tester.pump();
      expect(find.text('Белки: 156,2 г'), findsOneWidget);
      await tester.enterText(field('Исходный / расчетный вес, кг'), '70');
      await tester.pump();
      expect(find.text('Белки: 154,0 г'), findsOneWidget);
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(c.of('goal'), hasLength(2));
      final current = c.goal!;
      expect(current.data['macro_mode'], 'Автоматически');
      final n = entryNutrition(current);
      expect(n.protein, 154);
      expect(n.protein! * 4 + n.fat! * 9 + n.carbs! * 4, closeTo(n.kcal, 1e-8));
      expect(
        (await c.db!.find('goal', old.id))!.data['nutrition']['protein'],
        128,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
    },
  );
  testWidgets('manual grams remain editable and are not capped or rebalanced', (
    tester,
  ) async {
    final c = DiaryController()
      ..db = DiaryDatabase.memory()
      ..loading = false;
    await c.save('goal', oldGoal(manual: true));
    await open(tester, c);
    expect(find.byKey(const ValueKey('auto-goal-preview')), findsNothing);
    await tester.enterText(field('Белки, г'), '200');
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(c.goal!.data['nutrition']['protein'], 200);
    expect(c.goal!.data['nutrition']['kcal'], 2619);
    expect(c.goal!.data['nutrition']['fat'], 84);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
  });
}
