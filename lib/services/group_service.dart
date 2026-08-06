import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group.dart';
import '../models/group_member.dart';
import 'analytics_service.dart';

class GroupService {
  final _firestore = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return uid;
  }

  String get _displayName {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name;
    final email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Anonymous';
  }

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  Stream<List<Group>> streamMyGroups() {
    return _groups
        .where('memberIds', arrayContains: _uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Group.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<Group> streamGroup(String groupId) {
    return _groups
        .doc(groupId)
        .snapshots()
        .map((doc) => Group.fromFirestore(doc.id, doc.data()!));
  }

  Stream<List<GroupMember>> streamMembers(String groupId) {
    return _groups
        .doc(groupId)
        .collection('members')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupMember.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Generates a 6-character invite code, retrying on the (extremely rare)
  /// chance it collides with a code already in use.
  Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(
        6,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      final existing = await _groups
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    throw StateError(
      'Could not generate a unique invite code. Please try again.',
    );
  }

  /// The signed-in user's saved group display order (a list of group ids).
  /// Groups not present in this list (e.g. newly joined ones) sort after
  /// the ones that are.
  Future<List<String>> loadGroupOrder() async {
    final doc = await _firestore.collection('users').doc(_uid).get();
    final order = doc.data()?['groupOrder'] as List<dynamic>?;
    return order?.cast<String>() ?? [];
  }

  Future<void> saveGroupOrder(List<String> groupIds) async {
    await _firestore.collection('users').doc(_uid).set(
      {'groupOrder': groupIds},
      SetOptions(merge: true),
    );
  }

  Future<void> updateGroup(
    String groupId, {
    required String name,
    required int? target,
  }) async {
    await _groups.doc(groupId).update({'name': name, 'target': target});
  }

  Future<Group> createGroup({
    required String name,
    int? target,
    bool adminControlled = false,
  }) async {
    final code = await _generateUniqueCode();
    final now = DateTime.now();
    final docRef = _groups.doc();
    final group = Group(
      id: docRef.id,
      name: name,
      code: code,
      target: target,
      createdBy: _uid,
      createdAt: now,
      memberIds: [_uid],
      adminControlled: adminControlled,
    );
    final batch = _firestore.batch();
    batch.set(docRef, group.toFirestore());
    batch.set(
      docRef.collection('members').doc(_uid),
      GroupMember(
        uid: _uid,
        displayName: _displayName,
        tally: 0,
        joinedAt: now,
      ).toFirestore(),
    );
    await batch.commit();
    await analyticsService.logGroupCreated();
    return group;
  }

  Future<Group> joinGroupByCode(String code) async {
    final query = await _groups
        .where('code', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw StateError('No group found with that code.');
    }
    final doc = query.docs.first;
    final group = Group.fromFirestore(doc.id, doc.data());
    if (!group.memberIds.contains(_uid)) {
      final batch = _firestore.batch();
      batch.update(doc.reference, {
        'memberIds': FieldValue.arrayUnion([_uid]),
      });
      batch.set(
        doc.reference.collection('members').doc(_uid),
        GroupMember(
          uid: _uid,
          displayName: _displayName,
          tally: 0,
          joinedAt: DateTime.now(),
        ).toFirestore(),
      );
      await batch.commit();
      await analyticsService.logGroupJoined();
    }
    return group;
  }

  /// Removes a member from the group. Only the group creator can do this
  /// (enforced by Firestore security rules, not just the UI).
  Future<void> removeMember(String groupId, String uid) async {
    final groupRef = _groups.doc(groupId);
    final batch = _firestore.batch();
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayRemove([uid]),
    });
    batch.delete(groupRef.collection('members').doc(uid));
    await batch.commit();
  }

  /// Removes the current user from the group. Unlike [removeMember], any
  /// member can do this for themselves (enforced by Firestore security
  /// rules). If the current user is the creator: ownership transfers to
  /// the longest-standing remaining member, or the whole group is deleted
  /// if no other members remain.
  Future<void> leaveGroup(String groupId) async {
    await analyticsService.logGroupLeft();
    final groupRef = _groups.doc(groupId);
    final groupSnapshot = await groupRef.get();
    final groupData = groupSnapshot.data();
    if (groupData == null) return;
    final group = Group.fromFirestore(groupSnapshot.id, groupData);

    if (group.createdBy != _uid) {
      final batch = _firestore.batch();
      batch.update(groupRef, {
        'memberIds': FieldValue.arrayRemove([_uid]),
      });
      batch.delete(groupRef.collection('members').doc(_uid));
      await batch.commit();
      return;
    }

    if (group.memberIds.length <= 1) {
      await deleteGroup(groupId);
      return;
    }

    final membersSnapshot = await groupRef.collection('members').get();
    final remainingMembers =
        membersSnapshot.docs
            .map((doc) => GroupMember.fromFirestore(doc.id, doc.data()))
            .where((member) => member.uid != _uid)
            .toList()
          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    final newAdminUid = remainingMembers.first.uid;

    final batch = _firestore.batch();
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayRemove([_uid]),
      'createdBy': newAdminUid,
    });
    batch.delete(groupRef.collection('members').doc(_uid));
    await batch.commit();
  }

  Future<void> deleteGroup(String groupId) async {
    final groupRef = _groups.doc(groupId);
    final membersSnapshot = await groupRef.collection('members').get();
    final batch = _firestore.batch();
    for (final doc in membersSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(groupRef);
    await batch.commit();
    await analyticsService.logGroupDeleted();
  }

  /// Increments [uid]'s tally within the group. Firestore rules enforce who
  /// is allowed to do this: the member themselves in a member-controlled
  /// group, or the group's creator in an admin-controlled one.
  Future<void> incrementMemberTally(
    String groupId,
    String uid,
    int amount,
  ) async {
    final groupRef = _groups.doc(groupId);
    await groupRef.collection('members').doc(uid).update({
      'tally': FieldValue.increment(amount),
    });
    await _maybeAwardGroupBadge(groupRef);
  }

  /// Awards a badge for the group's current target if the combined tally
  /// has reached it and no badge has been awarded for that target yet.
  /// Runs as a transaction so concurrent increments from different members
  /// can't award duplicate badges for the same target.
  Future<void> _maybeAwardGroupBadge(
    DocumentReference<Map<String, dynamic>> groupRef,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (groupData == null) return;
      final group = Group.fromFirestore(groupSnapshot.id, groupData);

      final target = group.target;
      if (target == null || target <= 0) return;
      if (group.badges.any((b) => b.value == target)) return;

      var total = 0;
      for (final uid in group.memberIds) {
        final memberSnapshot = await transaction.get(
          groupRef.collection('members').doc(uid),
        );
        total += (memberSnapshot.data()?['tally'] as int?) ?? 0;
      }
      if (total < target) return;

      var updatedBadges = [
        ...group.badges,
        GroupBadge(
          value: target,
          reachedAt: DateTime.now(),
          gainedByName: _displayName,
        ),
      ];
      if (updatedBadges.length > maxGroupBadges) {
        updatedBadges = updatedBadges.sublist(
          updatedBadges.length - maxGroupBadges,
        );
      }
      transaction.update(groupRef, {
        'badges': updatedBadges.map((b) => b.toFirestore()).toList(),
      });
    });
  }

  /// Decrements [uid]'s tally within the group, clamped at zero. Same
  /// permission model as [incrementMemberTally].
  Future<void> decrementMemberTally(
    String groupId,
    String uid,
    int amount,
  ) async {
    final ref = _groups.doc(groupId).collection('members').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = (snapshot.data()?['tally'] as int?) ?? 0;
      transaction.update(ref, {'tally': max(current - amount, 0)});
    });
  }
}
