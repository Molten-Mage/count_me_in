import 'package:firebase_analytics/firebase_analytics.dart';

/// The event surface the rest of the app logs against. Exists separately
/// from [AnalyticsService] so tests can swap [analyticsService] for a
/// no-op implementation that never touches real Firebase Analytics (which
/// can't be constructed at all without a live Firebase app).
abstract class AnalyticsLogger {
  Future<void> logGoalReachedAction({
    required String source, // 'counter' or 'group'
    required bool startedNewGoal,
  });

  Future<void> logCounterCreated();

  Future<void> logCounterDeleted();

  Future<void> logGroupCreated();

  Future<void> logGroupJoined();

  Future<void> logGroupDeleted();

  Future<void> logGroupLeft();

  Future<void> logGroupInviteShared();

  Future<void> logChallengeCreated();

  Future<void> logChallengeJoined();

  Future<void> logChallengeDeleted();

  Future<void> logChallengeLeft();

  Future<void> logThemeChanged(String mode);

  /// The "Get Premium" / "Not now" decision — fired both when reached via
  /// Settings and via the free-limit paywall, distinguished by [source].
  Future<void> logPremiumPrompt({
    required String source, // 'settings' or 'free_limit'
    required bool accepted,
  });

  Future<void> logLogin(String provider);

  Future<void> logSignOut();

  Future<void> logAccountDeleted();

  /// [restored] distinguishes a fresh purchase from a restore-purchases
  /// replay (e.g. reinstall, new device) reaching the same success path.
  Future<void> logPurchaseCompleted({required bool restored});

  Future<void> logPurchaseFailed();
}

/// Thin wrapper around Firebase Analytics — one method per event we track,
/// so call sites log intent ("counter was created") instead of knowing
/// event names/param shapes.
class AnalyticsService implements AnalyticsLogger {
  final _analytics = FirebaseAnalytics.instance;

  @override
  Future<void> logGoalReachedAction({
    required String source,
    required bool startedNewGoal,
  }) => _analytics.logEvent(
    name: 'goal_reached_action',
    parameters: {
      'source': source,
      'action': startedNewGoal ? 'new_goal' : 'continue',
    },
  );

  @override
  Future<void> logCounterCreated() =>
      _analytics.logEvent(name: 'counter_created');

  @override
  Future<void> logCounterDeleted() =>
      _analytics.logEvent(name: 'counter_deleted');

  @override
  Future<void> logGroupCreated() =>
      _analytics.logEvent(name: 'group_created');

  @override
  Future<void> logGroupJoined() => _analytics.logEvent(name: 'group_joined');

  @override
  Future<void> logGroupDeleted() =>
      _analytics.logEvent(name: 'group_deleted');

  @override
  Future<void> logGroupLeft() => _analytics.logEvent(name: 'group_left');

  @override
  Future<void> logGroupInviteShared() =>
      _analytics.logEvent(name: 'group_invite_shared');

  @override
  Future<void> logChallengeCreated() =>
      _analytics.logEvent(name: 'challenge_created');

  @override
  Future<void> logChallengeJoined() =>
      _analytics.logEvent(name: 'challenge_joined');

  @override
  Future<void> logChallengeDeleted() =>
      _analytics.logEvent(name: 'challenge_deleted');

  @override
  Future<void> logChallengeLeft() =>
      _analytics.logEvent(name: 'challenge_left');

  @override
  Future<void> logThemeChanged(String mode) =>
      _analytics.logEvent(name: 'theme_changed', parameters: {'mode': mode});

  @override
  Future<void> logPremiumPrompt({
    required String source,
    required bool accepted,
  }) => _analytics.logEvent(
    name: 'premium_prompt',
    parameters: {'source': source, 'action': accepted ? 'upgrade' : 'not_now'},
  );

  @override
  Future<void> logLogin(String provider) =>
      _analytics.logLogin(loginMethod: provider);

  @override
  Future<void> logSignOut() => _analytics.logEvent(name: 'sign_out');

  @override
  Future<void> logAccountDeleted() =>
      _analytics.logEvent(name: 'account_deleted');

  @override
  Future<void> logPurchaseCompleted({required bool restored}) =>
      _analytics.logEvent(
        name: 'purchase_completed',
        parameters: {'restored': restored},
      );

  @override
  Future<void> logPurchaseFailed() =>
      _analytics.logEvent(name: 'purchase_failed');
}

/// Swappable in tests (assign a fake [AnalyticsLogger] in `setUp`, restore
/// the real [AnalyticsService] in `tearDown`) — never reassigned in app
/// code.
AnalyticsLogger analyticsService = AnalyticsService();
