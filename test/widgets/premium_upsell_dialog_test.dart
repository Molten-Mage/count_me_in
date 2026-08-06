import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/premium_service.dart';
import 'package:count_me_in/widgets/premium_upsell_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_analytics_logger.dart';

void main() {
  late FakeAnalyticsLogger fakeAnalytics;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAnalytics = FakeAnalyticsLogger();
    analyticsService = fakeAnalytics;
    premiumStatus.value = false;
  });

  Future<void> pumpDialog(WidgetTester tester, {String source = 'settings'}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPremiumUpsellDialog(context, source: source),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the pitch and price', (tester) async {
    await pumpDialog(tester);
    expect(find.text('Go Premium'), findsOneWidget);
    expect(find.textContaining(PremiumService.priceLabel), findsOneWidget);
    expect(find.textContaining('One-time purchase'), findsOneWidget);
  });

  testWidgets('Not now logs a decline and does not grant premium', (tester) async {
    await pumpDialog(tester, source: 'free_limit');

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(premiumStatus.value, isFalse);
    expect(fakeAnalytics.events, ['premium_prompt:free_limit:not_now']);
  });

  testWidgets('Upgrade in debug mode grants premium and logs acceptance', (
    tester,
  ) async {
    await pumpDialog(tester, source: 'settings');

    await tester.tap(find.textContaining('Upgrade'));
    await tester.pump(); // process tap, run sync part of onPrimary
    await tester.pump(); // flush the awaited setPremium() Future
    await tester.pump(const Duration(milliseconds: 100)); // snackbar enters

    expect(premiumStatus.value, isTrue);
    expect(fakeAnalytics.events, ['premium_prompt:settings:upgrade']);
    expect(find.text('Debug: upgraded to Premium'), findsOneWidget);
  });
}
