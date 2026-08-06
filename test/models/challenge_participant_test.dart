import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:count_me_in/models/challenge_participant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final joinedAt = DateTime(2026, 1, 1);

  group('ChallengeParticipant.tallyFor', () {
    test('returns the stored tally for a known objective', () {
      final participant = ChallengeParticipant(
        uid: 'u1',
        displayName: 'Jo',
        joinedAt: joinedAt,
        tallies: const {'obj_0': 5},
      );
      expect(participant.tallyFor('obj_0'), 5);
    });

    test('returns 0 for an objective with no recorded tally', () {
      final participant = ChallengeParticipant(
        uid: 'u1',
        displayName: 'Jo',
        joinedAt: joinedAt,
        tallies: const {},
      );
      expect(participant.tallyFor('obj_0'), 0);
    });
  });

  group('ChallengeParticipant Firestore round-trip', () {
    test(
      'toFirestore/fromFirestore preserves tallies (completedAt excluded)',
      () {
        final participant = ChallengeParticipant(
          uid: 'u1',
          displayName: 'Jo',
          joinedAt: joinedAt,
          tallies: const {'obj_0': 5, 'obj_1': 2},
          completedAt: joinedAt.add(const Duration(days: 3)),
        );

        final data = participant.toFirestore();
        // completedAt is managed transactionally by ChallengeService, not
        // written by toFirestore.
        expect(data.containsKey('completedAt'), isFalse);

        final restored = ChallengeParticipant.fromFirestore('u1', data);
        expect(restored.displayName, 'Jo');
        expect(restored.joinedAt, joinedAt);
        expect(restored.tallies, {'obj_0': 5, 'obj_1': 2});
        // Not present in the written data, so it round-trips as null here.
        expect(restored.completedAt, isNull);
      },
    );

    test('fromFirestore reads completedAt when present in raw data', () {
      final completedAt = joinedAt.add(const Duration(days: 1));
      final data = {
        'displayName': 'Jo',
        'joinedAt': Timestamp.fromDate(joinedAt),
        'tallies': {'obj_0': 10},
        'completedAt': Timestamp.fromDate(completedAt),
      };
      final restored = ChallengeParticipant.fromFirestore('u1', data);
      expect(restored.completedAt, completedAt);
    });

    test('fromFirestore defaults missing tallies to empty', () {
      final data = {
        'displayName': 'Jo',
        'joinedAt': Timestamp.fromDate(joinedAt),
      };
      final restored = ChallengeParticipant.fromFirestore('u1', data);
      expect(restored.tallies, isEmpty);
    });
  });
}
