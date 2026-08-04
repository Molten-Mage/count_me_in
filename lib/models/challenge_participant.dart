import 'package:cloud_firestore/cloud_firestore.dart';

class ChallengeParticipant {
  final String uid;
  final String displayName;
  final DateTime joinedAt;
  final Map<String, int> tallies;
  // Set/cleared transactionally by ChallengeService whenever a tally change
  // crosses (or un-crosses) "every targeted objective reached". Not part of
  // the doc at creation, so it's not written by toFirestore() below.
  final DateTime? completedAt;

  const ChallengeParticipant({
    required this.uid,
    required this.displayName,
    required this.joinedAt,
    required this.tallies,
    this.completedAt,
  });

  int tallyFor(String objectiveId) => tallies[objectiveId] ?? 0;

  factory ChallengeParticipant.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) => ChallengeParticipant(
    uid: uid,
    displayName: data['displayName'] as String,
    joinedAt: (data['joinedAt'] as Timestamp).toDate(),
    tallies: Map<String, int>.from(
      (data['tallies'] as Map<String, dynamic>?) ?? {},
    ),
    completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'joinedAt': Timestamp.fromDate(joinedAt),
    'tallies': tallies,
  };
}
