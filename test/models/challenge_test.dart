import 'package:count_me_in/models/challenge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1);

  group('Challenge.hasEnded', () {
    test('false with no deadline', () {
      final challenge = Challenge(
        id: '1',
        name: 'Test',
        visibility: ChallengeVisibility.public,
        code: 'ABC123',
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1'],
        objectives: const [],
      );
      expect(challenge.hasEnded, isFalse);
    });

    test('false when the deadline is in the future', () {
      final challenge = Challenge(
        id: '1',
        name: 'Test',
        visibility: ChallengeVisibility.public,
        code: 'ABC123',
        createdBy: 'u1',
        createdAt: createdAt,
        endsAt: DateTime.now().add(const Duration(days: 1)),
        memberIds: const ['u1'],
        objectives: const [],
      );
      expect(challenge.hasEnded, isFalse);
    });

    test('true when the deadline is in the past', () {
      final challenge = Challenge(
        id: '1',
        name: 'Test',
        visibility: ChallengeVisibility.public,
        code: 'ABC123',
        createdBy: 'u1',
        createdAt: createdAt,
        endsAt: DateTime.now().subtract(const Duration(days: 1)),
        memberIds: const ['u1'],
        objectives: const [],
      );
      expect(challenge.hasEnded, isTrue);
    });
  });

  group('Challenge Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves fields, including objectives', () {
      final challenge = Challenge(
        id: 'c1',
        name: 'Push-up week',
        description: 'A week of push-ups',
        visibility: ChallengeVisibility.private,
        isOfficial: true,
        code: 'XYZ789',
        createdBy: 'u1',
        createdAt: createdAt,
        endsAt: createdAt.add(const Duration(days: 7)),
        memberIds: const ['u1', 'u2'],
        objectives: const [
          ChallengeObjective(id: 'obj_0', name: 'Push-ups', target: 100),
          ChallengeObjective(id: 'obj_1', name: 'Squats'),
        ],
        emblemIconIndex: 3,
        emblemColorIndex: 2,
      );

      final restored = Challenge.fromFirestore('c1', challenge.toFirestore());

      expect(restored.name, challenge.name);
      expect(restored.description, challenge.description);
      expect(restored.visibility, ChallengeVisibility.private);
      expect(restored.isOfficial, isTrue);
      expect(restored.code, challenge.code);
      expect(restored.createdBy, challenge.createdBy);
      expect(restored.createdAt, createdAt);
      expect(restored.endsAt, createdAt.add(const Duration(days: 7)));
      expect(restored.memberIds, ['u1', 'u2']);
      expect(restored.objectives, hasLength(2));
      expect(restored.objectives[0].target, 100);
      expect(restored.objectives[1].target, isNull);
      expect(restored.emblemIconIndex, 3);
      expect(restored.emblemColorIndex, 2);
    });

    test('fromFirestore defaults missing optional fields', () {
      final challenge = Challenge(
        id: 'c1',
        name: 'Minimal',
        visibility: ChallengeVisibility.public,
        code: 'AAA111',
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1'],
        objectives: const [ChallengeObjective(id: 'obj_0', name: 'Reading')],
      );
      final data = challenge.toFirestore()
        ..remove('isOfficial')
        ..remove('emblemIconIndex')
        ..remove('emblemColorIndex');
      final restored = Challenge.fromFirestore('c1', data);

      expect(restored.isOfficial, isFalse);
      expect(restored.emblemIconIndex, 0);
      expect(restored.emblemColorIndex, 0);
      expect(restored.endsAt, isNull);
    });

    test('visibility round-trips as "public" or "private" strings', () {
      final publicChallenge = Challenge(
        id: 'c1',
        name: 'Public',
        visibility: ChallengeVisibility.public,
        code: 'PUB001',
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1'],
        objectives: const [],
      );
      expect(publicChallenge.toFirestore()['visibility'], 'public');

      final privateChallenge = Challenge(
        id: 'c2',
        name: 'Private',
        visibility: ChallengeVisibility.private,
        code: 'PRI001',
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1'],
        objectives: const [],
      );
      expect(privateChallenge.toFirestore()['visibility'], 'private');
    });
  });
}
