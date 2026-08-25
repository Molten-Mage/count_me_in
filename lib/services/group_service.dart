import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/group.dart';
import '../models/group_member.dart';
import 'analytics_service.dart';

/// Runs a best-effort side effect (badge-awarding, push notifications,
/// activity tracking) without letting a failure there look like the tally
/// write itself failed - those are all secondary to the tally update, and
/// the UI's optimistic-update rollback should only trigger for a genuine
/// failure to save the user's own tally.
Future<void> _bestEffort(String label, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (kDebugMode) debugPrint('[GroupService] $label failed: $e');
  }
}

class GroupService {
  GroupService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return uid;
  }

  String get _displayName {
    final user = _auth.currentUser;
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

  /// [description]/[adminControlled]/[freeForAll] are left unchanged when
  /// omitted, so callers that only touch name/target (e.g. the
  /// goal-reached dialog's "set a new goal") don't need to know or care
  /// about the group's current description or tally-control mode.
  Future<void> updateGroup(
    String groupId, {
    required String name,
    String? description,
    required int? target,
    bool? adminControlled,
    bool? freeForAll,
  }) async {
    await _groups.doc(groupId).update({
      'name': name,
      'target': target,
      'description': ?description,
      'adminControlled': ?adminControlled,
      'freeForAll': ?freeForAll,
    });
  }

  Future<Group> createGroup({
    required String name,
    String description = '',
    int? target,
    bool adminControlled = false,
    bool freeForAll = false,
  }) async {
    final code = await _generateUniqueCode();
    final now = DateTime.now();
    final docRef = _groups.doc();
    final group = Group(
      id: docRef.id,
      name: name,
      description: description,
      code: code,
      target: target,
      createdBy: _uid,
      createdAt: now,
      memberIds: [_uid],
      adminControlled: adminControlled,
      freeForAll: freeForAll,
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
    var joined = false;
    final group = await _firestore.runTransaction((transaction) async {
      final groupRef = doc.reference;
      final groupSnapshot = await transaction.get(groupRef);
      final group = Group.fromFirestore(groupSnapshot.id, groupSnapshot.data()!);
      if (group.memberIds.contains(_uid)) return group;

      transaction.update(groupRef, {
        'memberIds': FieldValue.arrayUnion([_uid]),
      });
      transaction.set(
        groupRef.collection('members').doc(_uid),
        GroupMember(
          uid: _uid,
          displayName: _displayName,
          tally: 0,
          joinedAt: DateTime.now(),
        ).toFirestore(),
      );

      final notifications = _firestore.collection('pushNotifications');
      for (final recipientUid in group.memberIds) {
        transaction.set(notifications.doc(), {
          'recipientUid': recipientUid,
          'type': 'group_joined',
          'title': group.name,
          'body': '$_displayName joined the group!',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // Separate, independently-toggleable notification just for the
      // group's creator (a stricter subset of the loop above, which
      // already covers every member including the creator).
      transaction.set(notifications.doc(), {
        'recipientUid': group.createdBy,
        'type': 'group_joined_owner',
        'title': group.name,
        'body': '$_displayName joined your group!',
        'createdAt': FieldValue.serverTimestamp(),
      });

      joined = true;
      return group;
    });
    if (joined) await analyticsService.logGroupJoined();
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
    await _bestEffort('badge award', () => _maybeAwardGroupBadge(groupRef));
    await _bestEffort(
      'threshold notify',
      () => _maybeNotifyThreshold(groupRef, uid),
    );
    await _bestEffort('activity touch', () => _touchGroupActivity(groupRef));
  }

  /// Marks the group as recently active and clears any pending "gone
  /// quiet" reminder - called on every tally change (increment or
  /// decrement) by any member. Read by the `notifyGroupQuiet` scheduled
  /// Cloud Function (functions/index.js) to find groups nobody's touched
  /// in a while; clearing `quietNotifiedAt` here (rather than only ever
  /// setting it) means a group that goes quiet again later isn't blocked
  /// by a stale cooldown timestamp from its last quiet period.
  Future<void> _touchGroupActivity(
    DocumentReference<Map<String, dynamic>> groupRef,
  ) async {
    await groupRef.update({
      'lastActivityAt': FieldValue.serverTimestamp(),
      'quietNotifiedAt': null,
    });
  }

  /// Notifies the rest of the group once [memberUid]'s own tally reaches
  /// 80% of the group's target, once per target value (dedupe mirrors
  /// [_maybeAwardGroupBadge]'s pattern via a field on the member doc
  /// instead of the group's badges list, since this is per-member rather
  /// than combined). Writes are picked up and actually sent by the
  /// `sendPushNotification` Cloud Function (functions/index.js), which
  /// also checks the recipient's notification preference before sending.
  Future<void> _maybeNotifyThreshold(
    DocumentReference<Map<String, dynamic>> groupRef,
    String memberUid,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (groupData == null) return;
      final group = Group.fromFirestore(groupSnapshot.id, groupData);

      final target = group.target;
      if (target == null || target <= 0) return;

      final memberRef = groupRef.collection('members').doc(memberUid);
      final memberSnapshot = await transaction.get(memberRef);
      final memberData = memberSnapshot.data();
      if (memberData == null) return;
      final member = GroupMember.fromFirestore(memberUid, memberData);

      if (member.notifiedThresholdFor == target) return;
      final threshold = (target * 0.8).ceil();
      if (member.tally < threshold) return;

      transaction.update(memberRef, {'notifiedThresholdFor': target});

      final notifications = _firestore.collection('pushNotifications');
      for (final recipientUid in group.memberIds) {
        if (recipientUid == memberUid) continue;
        transaction.set(notifications.doc(), {
          'recipientUid': recipientUid,
          'type': 'group_threshold',
          'title': group.name,
          'body': '${member.displayName} just hit 80% of the group goal!',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
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

      // Everyone but whoever's tally just crossed the line gets a push -
      // they already see the in-app celebration dialog immediately.
      final notifications = _firestore.collection('pushNotifications');
      for (final recipientUid in group.memberIds) {
        if (recipientUid == _uid) continue;
        transaction.set(notifications.doc(), {
          'recipientUid': recipientUid,
          'type': 'group_goal_reached',
          'title': group.name,
          'body': 'Goal reached - $total/$target!',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Decrements [uid]'s tally within the group, clamped at zero. Same
  /// permission model as [incrementMemberTally].
  Future<void> decrementMemberTally(
    String groupId,
    String uid,
    int amount,
  ) async {
    final groupRef = _groups.doc(groupId);
    final ref = groupRef.collection('members').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = (snapshot.data()?['tally'] as int?) ?? 0;
      transaction.update(ref, {'tally': max(current - amount, 0)});
    });
    await _bestEffort('activity touch', () => _touchGroupActivity(groupRef));
  }
}
