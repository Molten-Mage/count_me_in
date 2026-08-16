import 'package:cloud_firestore/cloud_firestore.dart';

class GroupMember {
  final String uid;
  final String displayName;
  final int tally;
  final DateTime joinedAt;
  // The group target this member was last notified for reaching 80% of -
  // null if never notified. Compared against the group's current target
  // so a target change makes them eligible for a fresh notification.
  final int? notifiedThresholdFor;

  const GroupMember({
    required this.uid,
    required this.displayName,
    required this.tally,
    required this.joinedAt,
    this.notifiedThresholdFor,
  });

  factory GroupMember.fromFirestore(String uid, Map<String, dynamic> data) =>
      GroupMember(
        uid: uid,
        displayName: data['displayName'] as String,
        tally: data['tally'] as int,
        joinedAt: (data['joinedAt'] as Timestamp).toDate(),
        notifiedThresholdFor: data['notifiedThresholdFor'] as int?,
      );

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'tally': tally,
    'joinedAt': Timestamp.fromDate(joinedAt),
    'notifiedThresholdFor': notifiedThresholdFor,
  };
}
