import 'package:count_me_in/models/challenge.dart';
import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/challenge_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

ChallengeService _serviceFor(
  FakeFirebaseFirestore firestore,
  String uid, {
  String? displayName,
}) {
  return ChallengeService(
    firestore: firestore,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, displayName: displayName ?? uid),
    ),
  );
}

// fake_cloud_firestore's snapshot streams don't reliably re-emit after a
// runTransaction() write (used by tally updates), even though the
// underlying document is updated correctly — read directly instead of via
// ChallengeService's stream methods for anything checked right after one.
Future<Challenge> _getChallenge(
  FakeFirebaseFirestore firestore,
  String challengeId,
) async {
  final doc = await firestore.collection('challenges').doc(challengeId).get();
  return Challenge.fromFirestore(doc.id, doc.data()!);
}

Future<Map<String, dynamic>> _getParticipant(
  FakeFirebaseFirestore firestore,
  String challengeId,
  String uid,
) async {
  final doc = await firestore
      .collection('challenges')
      .doc(challengeId)
      .collection('participants')
      .doc(uid)
      .get();
  return doc.data()!;
}

const _objectives = [(name: 'Push-ups', target: 100)];

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAnalyticsLogger fakeAnalytics;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    fakeAnalytics = FakeAnalyticsLogger();
    analyticsService = fakeAnalytics;
  });

  group('createChallenge', () {
    test('creates the challenge and adds the creator as a participant', () async {
      final service = _serviceFor(firestore, 'u1', displayName: 'Jo');
      final challenge = await service.createChallenge(
        name: 'Push-up week',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      expect(challenge.name, 'Push-up week');
      expect(challenge.createdBy, 'u1');
      expect(challenge.memberIds, ['u1']);
      expect(challenge.objectives, hasLength(1));
      expect(challenge.objectives.single.id, 'obj_0');
      expect(challenge.code, hasLength(6));

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      expect(participant['displayName'], 'Jo');
    });

    test('logs challenge_created', () async {
      final service = _serviceFor(firestore, 'u1');
      await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      expect(fakeAnalytics.events, ['challenge_created']);
    });

    test('rejects zero objectives', () async {
      final service = _serviceFor(firestore, 'u1');
      expect(
        () => service.createChallenge(
          name: 'Test',
          visibility: ChallengeVisibility.public,
          objectives: const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects more than maxChallengeObjectives', () async {
      final service = _serviceFor(firestore, 'u1');
      final tooMany = List.generate(
        maxChallengeObjectives + 1,
        (i) => (name: 'Objective $i', target: null),
      );
      expect(
        () => service.createChallenge(
          name: 'Test',
          visibility: ChallengeVisibility.public,
          objectives: tooMany,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('createOfficialChallenge', () {
    test('the generating account ends up with zero members', () async {
      final service = _serviceFor(firestore, 'admin');
      final challenge = await service.createOfficialChallenge(
        name: 'Official',
        objectives: _objectives,
      );

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.memberIds, isEmpty);
      expect(stored.isOfficial, isTrue);
      expect(stored.visibility, ChallengeVisibility.public);

      final participantDoc = await firestore
          .collection('challenges')
          .doc(challenge.id)
          .collection('participants')
          .doc('admin')
          .get();
      expect(participantDoc.exists, isFalse);
    });
  });

  group('joining', () {
    test('joinChallengeByCode adds the joiner as a member and participant', () async {
      final owner = _serviceFor(firestore, 'u1');
      final challenge = await owner.createChallenge(
        name: 'Push-up week',
        visibility: ChallengeVisibility.private,
        objectives: _objectives,
      );

      final joiner = _serviceFor(firestore, 'u2', displayName: 'Alex');
      await joiner.joinChallengeByCode(challenge.code);

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.memberIds, containsAll(['u1', 'u2']));
      final participant = await _getParticipant(firestore, challenge.id, 'u2');
      expect(participant['displayName'], 'Alex');
    });

    test('joinPublicChallenge works the same way', () async {
      final owner = _serviceFor(firestore, 'u1');
      final challenge = await owner.createChallenge(
        name: 'Public challenge',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      final joiner = _serviceFor(firestore, 'u2');
      await joiner.joinPublicChallenge(challenge.id);

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.memberIds, contains('u2'));
    });

    test('logs challenge_joined only for the actual joiner', () async {
      final owner = _serviceFor(firestore, 'u1');
      final challenge = await owner.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      expect(fakeAnalytics.events, ['challenge_created']);

      final joiner = _serviceFor(firestore, 'u2');
      await joiner.joinPublicChallenge(challenge.id);
      expect(fakeAnalytics.events, ['challenge_created', 'challenge_joined']);
    });

    test('joining twice does not duplicate the membership or re-log', () async {
      final owner = _serviceFor(firestore, 'u1');
      final challenge = await owner.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      fakeAnalytics.events.clear();

      await owner.joinPublicChallenge(challenge.id);

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.memberIds, ['u1']);
      expect(fakeAnalytics.events, isEmpty);
    });

    test('joinChallengeByCode throws for an unknown code', () async {
      final service = _serviceFor(firestore, 'u1');
      expect(
        () => service.joinChallengeByCode('NOPE99'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('tallies and completion', () {
    test('incrementObjectiveTally increases the tally', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      await service.incrementObjectiveTally(challenge.id, 'obj_0', 30);

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      expect(participant['tallies']['obj_0'], 30);
    });

    test('decrementObjectiveTally clamps at zero', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      await service.incrementObjectiveTally(challenge.id, 'obj_0', 5);
      await service.decrementObjectiveTally(challenge.id, 'obj_0', 20);

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      expect(participant['tallies']['obj_0'], 0);
    });

    test('completedAt is set once every targeted objective is reached', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives, // single objective, target 100
      );

      await service.incrementObjectiveTally(challenge.id, 'obj_0', 100);

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      expect(participant['completedAt'], isNotNull);
    });

    test('completedAt clears if a tally drops back below target', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      await service.incrementObjectiveTally(challenge.id, 'obj_0', 100);
      await service.decrementObjectiveTally(challenge.id, 'obj_0', 1);

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      expect(participant['completedAt'], isNull);
    });

    test('an objective with no target never contributes to completion', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: const [(name: 'Journaling', target: null)],
      );

      await service.incrementObjectiveTally(challenge.id, 'obj_0', 1000);

      final participant = await _getParticipant(firestore, challenge.id, 'u1');
      // No targeted objectives at all => "every targeted objective
      // reached" is vacuously false, per the targeted.isNotEmpty guard.
      expect(participant['completedAt'], isNull);
    });
  });

  group('updateObjectiveTargets', () {
    test('updates target numbers, names/ids stay fixed', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );

      await service.updateObjectiveTargets(challenge.id, [
        const ChallengeObjective(id: 'obj_0', name: 'Push-ups', target: 200),
      ]);

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.objectives.single.target, 200);
    });
  });

  group('deleteChallenge', () {
    test('removes the challenge and participants, logs challenge_deleted', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      fakeAnalytics.events.clear();

      await service.deleteChallenge(challenge.id);

      final doc = await firestore.collection('challenges').doc(challenge.id).get();
      expect(doc.exists, isFalse);
      expect(fakeAnalytics.events, ['challenge_deleted']);
    });
  });

  group('leaveChallenge', () {
    test('a non-creator member is just removed', () async {
      final owner = _serviceFor(firestore, 'u1');
      final challenge = await owner.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      final memberService = _serviceFor(firestore, 'u2');
      await memberService.joinPublicChallenge(challenge.id);
      fakeAnalytics.events.clear();

      await memberService.leaveChallenge(challenge.id);

      final stored = await _getChallenge(firestore, challenge.id);
      expect(stored.memberIds, ['u1']);
      expect(fakeAnalytics.events, ['challenge_left']);
    });

    test('the sole remaining member leaving deletes the challenge', () async {
      final service = _serviceFor(firestore, 'u1');
      final challenge = await service.createChallenge(
        name: 'Test',
        visibility: ChallengeVisibility.public,
        objectives: _objectives,
      );
      fakeAnalytics.events.clear();

      await service.leaveChallenge(challenge.id);

      final doc = await firestore.collection('challenges').doc(challenge.id).get();
      expect(doc.exists, isFalse);
      expect(fakeAnalytics.events, ['challenge_left', 'challenge_deleted']);
    });

    test(
      'the creator leaving with others remaining hands off to the '
      'longest-standing member',
      () async {
        final owner = _serviceFor(firestore, 'u1');
        final challenge = await owner.createChallenge(
          name: 'Test',
          visibility: ChallengeVisibility.public,
          objectives: _objectives,
        );
        final second = _serviceFor(firestore, 'u2');
        await second.joinPublicChallenge(challenge.id);
        final third = _serviceFor(firestore, 'u3');
        await third.joinPublicChallenge(challenge.id);

        await owner.leaveChallenge(challenge.id);

        final stored = await _getChallenge(firestore, challenge.id);
        expect(stored.memberIds, containsAll(['u2', 'u3']));
        expect(stored.memberIds, isNot(contains('u1')));
        expect(stored.createdBy, 'u2');
      },
    );
  });
}
