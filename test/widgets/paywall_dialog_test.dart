import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/premium_service.dart';
import 'package:count_me_in/widgets/paywall_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

void main() {
  setUp(() {
    analyticsService = FakeAnalyticsLogger();
    premiumStatus.value = false;
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPaywallDialog(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the limit', (tester) async {
    await pumpDialog(tester);
    expect(find.text("You've hit the free limit"), findsOneWidget);
    expect(
      find.textContaining('${PremiumService.freeItemLimit}'),
      findsOneWidget,
    );
  });

  testWidgets('Not now just dismisses', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text("You've hit the free limit"), findsNothing);
  });

  testWidgets('Get Premium hands off to the upsell dialog', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Get Premium'));
    await tester.pumpAndSettle();

    expect(find.text("You've hit the free limit"), findsNothing);
    expect(find.text('Go Premium'), findsOneWidget);
  });
}
