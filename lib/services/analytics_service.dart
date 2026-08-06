import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper around Firebase Analytics — one method per event we track,
/// so call sites log intent ("counter was created") instead of knowing
/// event names/param shapes.
class AnalyticsService {
  final _analytics = FirebaseAnalytics.instance;

  Future<void> logGoalReachedAction({
    required String source, // 'counter' or 'group'
    required bool startedNewGoal,
  }) => _analytics.logEvent(
    name: 'goal_reached_action',
    parameters: {
      'source': source,
      'action': startedNewGoal ? 'new_goal' : 'continue',
    },
  );

  Future<void> logCounterCreated() =>
      _analytics.logEvent(name: 'counter_created');

  Future<void> logCounterDeleted() =>
      _analytics.logEvent(name: 'counter_deleted');

  Future<void> logGroupCreated() =>
      _analytics.logEvent(name: 'group_created');

  Future<void> logGroupJoined() => _analytics.logEvent(name: 'group_joined');

  Future<void> logGroupDeleted() =>
      _analytics.logEvent(name: 'group_deleted');

  Future<void> logGroupLeft() => _analytics.logEvent(name: 'group_left');

  Future<void> logChallengeCreated() =>
      _analytics.logEvent(name: 'challenge_created');

  Future<void> logChallengeJoined() =>
      _analytics.logEvent(name: 'challenge_joined');

  Future<void> logChallengeDeleted() =>
      _analytics.logEvent(name: 'challenge_deleted');

  Future<void> logChallengeLeft() =>
      _analytics.logEvent(name: 'challenge_left');

  Future<void> logThemeChanged(String mode) =>
      _analytics.logEvent(name: 'theme_changed', parameters: {'mode': mode});

  /// The "Get Premium" / "Not now" decision — fired both when reached via
  /// Settings and via the free-limit paywall, distinguished by [source].
  Future<void> logPremiumPrompt({
    required String source, // 'settings' or 'free_limit'
    required bool accepted,
  }) => _analytics.logEvent(
    name: 'premium_prompt',
    parameters: {'source': source, 'action': accepted ? 'upgrade' : 'not_now'},
  );

  Future<void> logLogin(String provider) =>
      _analytics.logLogin(loginMethod: provider);

  Future<void> logSignOut() => _analytics.logEvent(name: 'sign_out');

  Future<void> logAccountDeleted() =>
      _analytics.logEvent(name: 'account_deleted');
}

final analyticsService = AnalyticsService();
