import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/data/database.dart';
import 'package:calorie_diary/presentation/activities.dart';
import 'package:calorie_diary/presentation/controller.dart';

void main() {
  testWidgets('search activity, live minutes calculation and local save', (
    tester,
  ) async {
    final c = DiaryController()
      ..db = DiaryDatabase.memory()
      ..loading = false;
    await c.save('weight', {'day': '2026-10-12', 'kg': 70});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diaryProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          home: ActivitySearchScreen(day: DateTime(2026, 10, 12)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'ходь');
    await tester.pumpAndSettle();
    expect(find.text('Бег, обычный'), findsNothing);
    await tester.tap(find.text('Ходьба, обычная'));
    await tester.pumpAndSettle();
    expect(find.text('103 ккал сожжено'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('activity-minutes')),
      '60',
    );
    await tester.pump();
    expect(find.text('206 ккал сожжено'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(c.of('activity'), hasLength(1));
    expect(c.of('activity').single.data['kcal'], closeTo(205.8, .001));
    expect(c.of('activity').single.data['day'], '2026-10-12');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
