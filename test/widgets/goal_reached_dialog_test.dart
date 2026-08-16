import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/widgets/goal_reached_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

void main() {
  late FakeAnalyticsLogger fakeAnalytics;

  setUp(() {
    fakeAnalytics = FakeAnalyticsLogger();
    analyticsService = fakeAnalytics;
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    String source = 'counter',
    void Function(int)? onSetNewGoal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showGoalReachedDialog(
              context,
              source: source,
              message: '"Push-ups" hit 50! Badge earned!',
              badgeValue: 50,
              badgeColorIndex: 0,
              currentCount: 50,
              onSetNewGoal: onSetNewGoal ?? (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    // Confetti/scale-in animation - advance rather than pumpAndSettle so we
    // don't wait out the whole confetti lifetime.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows the celebration message', (tester) async {
    await pumpDialog(tester);
    expect(find.text('Goal reached!'), findsOneWidget);
    expect(find.text('"Push-ups" hit 50! Badge earned!'), findsOneWidget);
  });

  testWidgets('Continue logs "continue" and closes the dialog', (tester) async {
    await pumpDialog(tester, source: 'counter');

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeAnalytics.events, ['goal_reached_action:counter:continue']);
    expect(find.text('Goal reached!'), findsNothing);
  });

  testWidgets('New goal logs "new_goal" and reveals the target field', (
    tester,
  ) async {
    await pumpDialog(tester, source: 'group');

    await tester.tap(find.text('New goal'));
    await tester.pumpAndSettle();

    expect(fakeAnalytics.events, ['goal_reached_action:group:new_goal']);
    expect(find.text('New target'), findsOneWidget);
  });

  testWidgets('setting a valid new goal calls onSetNewGoal and closes', (
    tester,
  ) async {
    int? newTarget;
    await pumpDialog(tester, onSetNewGoal: (t) => newTarget = t);

    await tester.tap(find.text('New goal'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(newTarget, 100);
    expect(find.text('Goal reached!'), findsNothing);
  });

  testWidgets('Save is disabled for a target at or below the current count', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.text('New goal'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '50');
    await tester.pump();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('Back returns to the initial Continue/New goal step', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.text('New goal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('New target'), findsNothing);
  });
}
