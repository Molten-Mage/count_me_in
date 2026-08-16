import 'package:count_me_in/services/analytics_service.dart';

/// Records every call instead of touching real Firebase Analytics (which
/// can't be constructed at all in a plain `flutter test` environment — it
/// touches `FirebaseAnalytics.instance` in its constructor, which throws
/// without a real Firebase app). Assign to the global `analyticsService` in
/// `setUp`. Don't restore the real [AnalyticsService] in `tearDown` —
/// constructing it throws the same way; each test file already runs in its
/// own isolate, so there's nothing to leak into other files.
class FakeAnalyticsLogger implements AnalyticsLogger {
  final List<String> events = [];

  @override
  Future<void> logGoalReachedAction({
    required String source,
    required bool startedNewGoal,
  }) async {
    events.add(
      'goal_reached_action:$source:${startedNewGoal ? 'new_goal' : 'continue'}',
    );
  }

  @override
  Future<void> logCounterCreated() async => events.add('counter_created');

  @override
  Future<void> logCounterDeleted() async => events.add('counter_deleted');

  @override
  Future<void> logGroupCreated() async => events.add('group_created');

  @override
  Future<void> logGroupJoined() async => events.add('group_joined');

  @override
  Future<void> logGroupDeleted() async => events.add('group_deleted');

  @override
  Future<void> logGroupLeft() async => events.add('group_left');

  @override
  Future<void> logGroupInviteShared() async =>
      events.add('group_invite_shared');

  @override
  Future<void> logChallengeCreated() async => events.add('challenge_created');

  @override
  Future<void> logChallengeJoined() async => events.add('challenge_joined');

  @override
  Future<void> logChallengeDeleted() async =>
      events.add('challenge_deleted');

  @override
  Future<void> logChallengeLeft() async => events.add('challenge_left');

  @override
  Future<void> logThemeChanged(String mode) async =>
      events.add('theme_changed:$mode');

  @override
  Future<void> logPremiumPrompt({
    required String source,
    required bool accepted,
  }) async {
    events.add(
      'premium_prompt:$source:${accepted ? 'upgrade' : 'not_now'}',
    );
  }

  @override
  Future<void> logLogin(String provider) async =>
      events.add('login:$provider');

  @override
  Future<void> logSignOut() async => events.add('sign_out');

  @override
  Future<void> logAccountDeleted() async => events.add('account_deleted');

  @override
  Future<void> logPurchaseCompleted({required bool restored}) async =>
      events.add('purchase_completed:$restored');

  @override
  Future<void> logPurchaseFailed() async => events.add('purchase_failed');
}
