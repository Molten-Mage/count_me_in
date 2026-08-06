import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/theme_controller.dart';
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
  });

  test('defaults to system theme', () {
    expect(ThemeController().value, ThemeMode.system);
  });

  test('load() restores a previously saved mode', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final controller = ThemeController();
    await controller.load();
    expect(controller.value, ThemeMode.dark);
  });

  test('load() falls back to system for an unrecognized stored value', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'not_a_real_mode'});
    final controller = ThemeController();
    await controller.load();
    expect(controller.value, ThemeMode.system);
  });

  test('setThemeMode updates value, persists it, and logs analytics', () async {
    final controller = ThemeController();
    await controller.setThemeMode(ThemeMode.light);

    expect(controller.value, ThemeMode.light);
    expect(fakeAnalytics.events, ['theme_changed:light']);

    // Persisted — a fresh controller loading from the same prefs sees it.
    final reloaded = ThemeController();
    await reloaded.load();
    expect(reloaded.value, ThemeMode.light);
  });

  test('load() does not log analytics (only real user changes do)', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final controller = ThemeController();
    await controller.load();
    expect(fakeAnalytics.events, isEmpty);
  });
}
