import 'package:count_me_in/models/challenge.dart';
import 'package:count_me_in/models/counter.dart';
import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/challenge_service.dart';
import 'package:count_me_in/services/firestore_counter_storage.dart';
import 'package:count_me_in/services/group_service.dart';
import 'package:count_me_in/services/premium_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    analyticsService = FakeAnalyticsLogger();
    premiumStatus.value = false;
  });

  PremiumService serviceFor(String uid) {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, displayName: uid),
    );
    return PremiumService(
      groupService: GroupService(firestore: firestore, auth: auth),
      challengeService: ChallengeService(firestore: firestore, auth: auth),
      counterStorage: FirestoreCounterStorage(firestore: firestore, auth: auth),
      auth: auth,
    );
  }

  PremiumService guestService() {
    return PremiumService(
      auth: MockFirebaseAuth(),
      // Guests can't reach Groups/Challenges, so these are never touched
      // in the guest path - real defaults would throw if they were.
      groupService: GroupService(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'unused')),
      ),
      challengeService: ChallengeService(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'unused')),
      ),
      counterStorage: FirestoreCounterStorage(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'unused')),
      ),
    );
  }

  group('isPremium', () {
    test('reflects the global premiumStatus flag', () {
      final service = serviceFor('u1');
      expect(service.isPremium, isFalse);

      premiumStatus.value = true;
      expect(service.isPremium, isTrue);
    });
  });

  group('countTrackedItems - guest (no signed-in user)', () {
    test('counts only the given counterCount, skipping groups/challenges', () async {
      final total = await guestService().countTrackedItems(counterCount: 3);
      expect(total, 3);
    });
  });

  group('countTrackedItems - signed in', () {
    test('sums counters + groups + joined-and-not-completed challenges', () async {
      final uid = 'u1';
      final service = serviceFor(uid);

      await GroupService(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      ).createGroup(name: 'Group A');

      final challengeService = ChallengeService(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      );
      await challengeService.createChallenge(
        name: 'Not completed',
        visibility: ChallengeVisibility.public,
        objectives: const [(name: 'Push-ups', target: 100)],
      );

      final total = await service.countTrackedItems(counterCount: 2);
      // 2 counters + 1 group + 1 active challenge.
      expect(total, 4);
    });

    test('excludes challenges the user has completed', () async {
      final uid = 'u1';
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid),
      );
      final challengeService = ChallengeService(firestore: firestore, auth: auth);
      final challenge = await challengeService.createChallenge(
        name: 'Will complete',
        visibility: ChallengeVisibility.public,
        objectives: const [(name: 'Push-ups', target: 10)],
      );
      await challengeService.incrementObjectiveTally(challenge.id, 'obj_0', 10);

      final service = PremiumService(
        groupService: GroupService(firestore: firestore, auth: auth),
        challengeService: challengeService,
        counterStorage: FirestoreCounterStorage(firestore: firestore, auth: auth),
        auth: auth,
      );

      final total = await service.countTrackedItems(counterCount: 0);
      expect(total, 0);
    });

    test('excludes challenges the user has not joined', () async {
      final owner = 'owner';
      final ownerAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: owner),
      );
      await ChallengeService(firestore: firestore, auth: ownerAuth).createChallenge(
        name: 'Someone else\'s public challenge',
        visibility: ChallengeVisibility.public,
        objectives: const [(name: 'Reading', target: 10)],
      );

      // A different, uninvolved user should see 0 - they never joined it.
      final total = await serviceFor('u2').countTrackedItems(counterCount: 0);
      expect(total, 0);
    });

    test('omitting counterCount looks counters up itself via FirestoreCounterStorage', () async {
      final uid = 'u1';
      final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
      final counterStorage = FirestoreCounterStorage(firestore: firestore, auth: auth);
      await counterStorage.saveCounters([
        Counter(id: '1', title: 'Water', createdAt: DateTime(2026)),
        Counter(id: '2', title: 'Steps', createdAt: DateTime(2026)),
      ]);

      final service = PremiumService(
        groupService: GroupService(firestore: firestore, auth: auth),
        challengeService: ChallengeService(firestore: firestore, auth: auth),
        counterStorage: counterStorage,
        auth: auth,
      );

      expect(await service.countTrackedItems(), 2);
    });
  });

  group('canAddOne', () {
    test('true when premium, regardless of count', () async {
      premiumStatus.value = true;
      final result = await serviceFor('u1').canAddOne(counterCount: 999);
      expect(result, isTrue);
    });

    test('true when under the free limit', () async {
      final result = await serviceFor('u1').canAddOne(
        counterCount: PremiumService.freeItemLimit - 1,
      );
      expect(result, isTrue);
    });

    test('false at or above the free limit', () async {
      final atLimit = await serviceFor('u1').canAddOne(
        counterCount: PremiumService.freeItemLimit,
      );
      expect(atLimit, isFalse);

      final overLimit = await serviceFor('u1').canAddOne(
        counterCount: PremiumService.freeItemLimit + 1,
      );
      expect(overLimit, isFalse);
    });
  });
}
