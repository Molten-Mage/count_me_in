import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:count_me_in/models/group_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GroupMember toFirestore/fromFirestore round-trip', () {
    final joinedAt = DateTime(2026, 1, 1);
    final member = GroupMember(
      uid: 'u1',
      displayName: 'Jo',
      tally: 42,
      joinedAt: joinedAt,
    );

    final restored = GroupMember.fromFirestore('u1', member.toFirestore());

    expect(restored.uid, 'u1');
    expect(restored.displayName, 'Jo');
    expect(restored.tally, 42);
    expect(restored.joinedAt, joinedAt);
  });

  test('GroupMember uid comes from the document id, not the stored data', () {
    final data = {
      'displayName': 'Jo',
      'tally': 5,
      'joinedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    };
    final member = GroupMember.fromFirestore('doc-id-123', data);
    expect(member.uid, 'doc-id-123');
  });
}
