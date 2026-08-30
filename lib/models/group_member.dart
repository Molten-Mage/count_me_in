import 'package:cloud_firestore/cloud_firestore.dart';

class GroupMember {
  final String uid;
  final String displayName;
  final Map<String, int> tallies;
  final DateTime joinedAt;

  const GroupMember({
    required this.uid,
    required this.displayName,
    required this.tallies,
    required this.joinedAt,
  });

  int tallyFor(String counterId) => tallies[counterId] ?? 0;

  factory GroupMember.fromFirestore(String uid, Map<String, dynamic> data) {
    final rawTallies = data['tallies'] as Map<String, dynamic>?;
    // Pre-multi-counter members (a single `tally` int, no `tallies` map)
    // are synthesized into a single-entry map keyed 'counter_0' - same id
    // Group.fromFirestore synthesizes its legacy "Total" counter under, so
    // the two line up without a real migration.
    final tallies = rawTallies != null
        ? Map<String, int>.from(rawTallies)
        : {if (data['tally'] != null) 'counter_0': data['tally'] as int};

    return GroupMember(
      uid: uid,
      displayName: data['displayName'] as String,
      tallies: tallies,
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'tallies': tallies,
    'joinedAt': Timestamp.fromDate(joinedAt),
  };
}
