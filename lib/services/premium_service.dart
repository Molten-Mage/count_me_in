import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge_service.dart';
import 'firestore_counter_storage.dart';
import 'group_service.dart';

const _premiumPrefsKey = 'debug_is_premium';

/// Entitlement flag, persisted on-device and shared between wherever it's
/// read (`PremiumService.isPremium`, the ad banner) and wherever it's
/// toggled (the paywall dialog's debug "upgrade", Settings' debug
/// "downgrade" button).
///
/// Real purchases aren't wired up yet, so the only way this ever becomes
/// `true` is through those debug-only toggles - [load] forces it back to
/// `false` outside of debug builds even if a stale value is on disk.
class PremiumStatus extends ValueNotifier<bool> {
  PremiumStatus() : super(false);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = kDebugMode && (prefs.getBool(_premiumPrefsKey) ?? false);
  }

  Future<void> setPremium(bool isPremium) async {
    value = isPremium;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumPrefsKey, isPremium);
  }
}

final premiumStatus = PremiumStatus();

/// Entitlement + free-tier limit logic. [isPremium] always reports `false`
/// in release builds - swap it for a real check once in-app purchase
/// products are configured in App Store Connect / Play Console and wired up
/// (e.g. via the `in_app_purchase` package or RevenueCat); the free-tier
/// limit logic below doesn't depend on how that ends up working.
class PremiumService {
  static const freeItemLimit = 8;

  // One-time purchase, placeholder price - swap for the real localized
  // price from the store's ProductDetails once IAP products exist (never
  // hardcode a price once that's live; the store is the source of truth
  // for currency/locale).
  static const priceLabel = r'$4.99';

  PremiumService({
    GroupService? groupService,
    ChallengeService? challengeService,
    FirestoreCounterStorage? counterStorage,
    FirebaseAuth? auth,
  }) : _groupService = groupService ?? GroupService(),
       _challengeService = challengeService ?? ChallengeService(),
       _counterStorage = counterStorage ?? FirestoreCounterStorage(),
       _auth = auth ?? FirebaseAuth.instance;

  final GroupService _groupService;
  final ChallengeService _challengeService;
  final FirestoreCounterStorage _counterStorage;
  final FirebaseAuth _auth;

  bool get isPremium => premiumStatus.value;

  /// Personal counters + groups + challenges joined and not yet completed.
  /// Challenges the user hasn't joined, and ones they've already completed,
  /// don't count.
  ///
  /// Pass [counterCount] when the caller already has counters loaded (e.g.
  /// HomePage's in-memory list) to skip re-fetching them. Omit it to have
  /// this look counters up itself - only valid for signed-in users, since
  /// Groups and Challenges are unreachable for guests anyway.
  Future<int> countTrackedItems({int? counterCount}) async {
    final counters =
        counterCount ?? (await _counterStorage.loadCounters()).length;

    if (_auth.currentUser == null) return counters;

    final groups = await _groupService.streamMyGroups().first;
    final challenges = await _challengeService
        .streamMyChallengesWithParticipation()
        .first;
    final activeChallenges = challenges.where(
      (c) => c.me != null && c.me!.completedAt == null,
    );

    return counters + groups.length + activeChallenges.length;
  }

  Future<bool> canAddOne({int? counterCount}) async {
    if (isPremium) return true;
    return await countTrackedItems(counterCount: counterCount) <
        freeItemLimit;
  }
}
