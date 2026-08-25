import 'package:count_me_in/models/counter.dart';
import 'package:count_me_in/pages/home_page.dart';
import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/premium_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';
import '../support/fake_counter_storage.dart';
import '../support/firebase_core_mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

Future<void> _tapAddCounterFab(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add counter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add a counter'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAnalyticsLogger fakeAnalytics;

  setUpAll(() async {
    await setupFirebaseCoreMocks();
  });

  setUp(() {
    fakeAnalytics = FakeAnalyticsLogger();
    analyticsService = fakeAnalytics;
    premiumStatus.value = false;
  });

  testWidgets('shows the empty state when there are no counters', (tester) async {
    await tester.pumpWidget(_wrap(HomePage(storage: FakeCounterStorage())));
    await tester.pumpAndSettle();

    expect(find.text('No counters yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('shows counters loaded from storage', (tester) async {
    final storage = FakeCounterStorage([
      Counter(id: '1', title: 'Water', count: 3, createdAt: DateTime(2026)),
      Counter(
        id: '2',
        title: 'Steps',
        count: 500,
        target: 10000,
        createdAt: DateTime(2026),
      ),
    ]);

    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text(' / 10000'), findsOneWidget);
  });

  testWidgets('adding a counter saves it, shows it, and logs analytics', (
    tester,
  ) async {
    final storage = FakeCounterStorage();
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await _tapAddCounterFab(tester);

    await tester.enterText(find.byType(TextField).first, 'Push-ups');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Push-ups'), findsOneWidget);
    expect(storage.saveCount, greaterThan(0));
    expect(fakeAnalytics.events, contains('counter_created'));
  });

  testWidgets(
    'editing the tally field to a higher value bumps the count and persists it',
    (tester) async {
      final storage = FakeCounterStorage([
        Counter(id: '1', title: 'Water', count: 3, createdAt: DateTime(2026)),
      ]);
      await tester.pumpWidget(_wrap(HomePage(storage: storage)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('9'), findsOneWidget);
      final saved = await storage.loadCounters();
      expect(saved.single.count, 9);
    },
  );

  testWidgets(
    'editing the tally field to a lower value lowers the count and persists it',
    (tester) async {
      final storage = FakeCounterStorage([
        Counter(id: '1', title: 'Water', count: 5, createdAt: DateTime(2026)),
      ]);
      await tester.pumpWidget(_wrap(HomePage(storage: storage)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      final saved = await storage.loadCounters();
      expect(saved.single.count, 2);
    },
  );

  testWidgets('tapping + bumps the count by 1 and persists it', (
    tester,
  ) async {
    final storage = FakeCounterStorage([
      Counter(id: '1', title: 'Water', count: 3, createdAt: DateTime(2026)),
    ]);
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Increase'));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    final saved = await storage.loadCounters();
    expect(saved.single.count, 4);
  });

  testWidgets('tapping - lowers the count by 1, clamped at zero', (
    tester,
  ) async {
    final storage = FakeCounterStorage([
      Counter(id: '1', title: 'Water', count: 0, createdAt: DateTime(2026)),
    ]);
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Decrease'));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    final saved = await storage.loadCounters();
    expect(saved.single.count, 0);
  });

  testWidgets('deleting a counter in edit mode removes it and logs analytics', (
    tester,
  ) async {
    final storage = FakeCounterStorage([
      Counter(id: '1', title: 'Water', createdAt: DateTime(2026)),
    ]);
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete counter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Water'), findsNothing);
    expect(find.text('No counters yet. Tap + to add one.'), findsOneWidget);
    expect(fakeAnalytics.events, contains('counter_deleted'));
  });

  testWidgets('hitting the free-tier limit shows the paywall instead of the form', (
    tester,
  ) async {
    final storage = FakeCounterStorage(
      List.generate(
        PremiumService.freeItemLimit,
        (i) => Counter(id: '$i', title: 'Counter $i', createdAt: DateTime(2026)),
      ),
    );
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await _tapAddCounterFab(tester);

    expect(find.text("You've hit the free limit"), findsOneWidget);
    expect(find.text('Add'), findsNothing);
  });

  testWidgets('premium accounts bypass the free-tier limit', (tester) async {
    premiumStatus.value = true;
    final storage = FakeCounterStorage(
      List.generate(
        PremiumService.freeItemLimit,
        (i) => Counter(id: '$i', title: 'Counter $i', createdAt: DateTime(2026)),
      ),
    );
    await tester.pumpWidget(_wrap(HomePage(storage: storage)));
    await tester.pumpAndSettle();

    await _tapAddCounterFab(tester);

    expect(find.text("You've hit the free limit"), findsNothing);
    // The counter-form dialog is showing instead.
    expect(find.text('Add counter'), findsOneWidget);
  });
}
