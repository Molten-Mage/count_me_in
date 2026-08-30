import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/group.dart';
import '../models/group_member.dart';
import 'analytics_service.dart';

/// Runs a best-effort side effect (push notifications, activity tracking)
/// without letting a failure there look like the tally write itself
/// failed - those are secondary to the tally update, and the UI's
/// optimistic-update rollback should only trigger for a genuine failure to
/// save the user's own tally.
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

  /// Generates a "G-" prefixed 6-character invite code, retrying on the
  /// (extremely rare) chance it collides with a code already in use. The
  /// prefix (challenges get "C-", see ChallengeService) makes it obvious at
  /// a glance which kind of code someone's looking at - joinByCode below
  /// still falls back to the other type if the prefix doesn't match, so a
  /// code typed into the wrong dialog isn't a dead end.
  Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code =
          'G-${List.generate(6, (_) => chars[random.nextInt(chars.length)]).join()}';
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

  /// Propagates a new display name into every [GroupMember] doc the caller
  /// currently has - one per group they belong to. Those are denormalized
  /// snapshots taken at join time and otherwise never update on their own,
  /// so a Settings rename would otherwise leave every existing membership
  /// showing the old name indefinitely (new joins/creates already pick up
  /// the current name naturally, since they write it fresh).
  Future<void> propagateDisplayNameChange(String newName) async {
    final snapshot = await _groups
        .where('memberIds', arrayContains: _uid)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference.collection('members').doc(_uid), {
        'displayName': newName,
      });
    }
    await batch.commit();
  }

  /// [description]/[adminControlled]/[freeForAll] are left unchanged when
  /// omitted, so callers that only touch name (e.g. a future "rename only"
  /// flow) don't need to know or care about the group's current
  /// description or tally-control mode.
  Future<void> updateGroup(
    String groupId, {
    required String name,
    String? description,
    bool? adminControlled,
    bool? freeForAll,
  }) async {
    await _groups.doc(groupId).update({
      'name': name,
      'description': ?description,
      'adminControlled': ?adminControlled,
      'freeForAll': ?freeForAll,
    });
  }

  /// Assigns a real id to any newly-added counter (matched by list
  /// position against [GroupCounter]s the caller already resolved ids
  /// for) from whichever `counter_0`..`counter_9` slots aren't already in
  /// use - same id-pool approach as
  /// ChallengeService.updateObjectives/ChallengeFormPage. No transaction:
  /// unlike a per-participant tally change, there's no derived state here
  /// that a concurrent edit could leave inconsistent.
  Future<void> updateCounters(
    String groupId,
    List<GroupCounter> counters,
  ) async {
    await _groups.doc(groupId).update({
      'counters': counters.map((c) => c.toFirestore()).toList(),
    });
  }

  Future<Group> createGroup({
    required String name,
    String description = '',
    required List<String> counterNames,
    bool adminControlled = false,
    bool freeForAll = false,
  }) async {
    if (counterNames.isEmpty || counterNames.length > maxGroupCounters) {
      throw ArgumentError(
        'A group needs between 1 and $maxGroupCounters counters.',
      );
    }

    final code = await _generateUniqueCode();
    final now = DateTime.now();
    final docRef = _groups.doc();
    final group = Group(
      id: docRef.id,
      name: name,
      description: description,
      code: code,
      counters: [
        for (var i = 0; i < counterNames.length; i++)
          GroupCounter(id: 'counter_$i', name: counterNames[i]),
      ],
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
        tallies: const {},
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
          tallies: const {},
          joinedAt: DateTime.now(),
        ).toFirestore(),
      );

      final notifications = _firestore.collection('pushNotifications');
      for (final recipientUid in group.memberIds) {
        // The creator gets their own `group_joined_owner` notification
        // below instead - sending both to them here was a duplicate "X
        // joined" push for the same event.
        if (recipientUid == group.createdBy) continue;
        transaction.set(notifications.doc(), {
          'recipientUid': recipientUid,
          'type': 'group_joined',
          'title': group.name,
          'body': '$_displayName joined the group!',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // Separate, independently-toggleable notification just for the
      // group's creator.
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

  /// Increments [uid]'s tally for [counterId] within the group. Firestore
  /// rules enforce who is allowed to do this: the member themselves in a
  /// member-controlled group, the group's creator in an admin-controlled
  /// one, or anyone in a free-for-all one. A dot-path update on the
  /// tallies map, same as before this had multiple counters - Firestore
  /// treats a missing nested field as 0, so a first-ever tally on a given
  /// counter needs no extra branch.
  Future<void> incrementMemberTally(
    String groupId,
    String uid,
    String counterId,
    int amount,
  ) async {
    final groupRef = _groups.doc(groupId);
    await groupRef.collection('members').doc(uid).update({
      'tallies.$counterId': FieldValue.increment(amount),
    });
    await _bestEffort('activity touch', () => _touchGroupActivity(groupRef));
    await _bestEffort(
      'tally update notify',
      () => _maybeNotifyTallyUpdate(groupRef, uid, counterId),
    );
  }

  /// Decrements [uid]'s tally for [counterId], clamped at zero. Same
  /// permission model as [incrementMemberTally]. Needs a transaction
  /// (unlike the increment above) since clamping at zero requires reading
  /// the current value first.
  Future<void> decrementMemberTally(
    String groupId,
    String uid,
    String counterId,
    int amount,
  ) async {
    final groupRef = _groups.doc(groupId);
    final ref = groupRef.collection('members').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final tallies = Map<String, int>.from(
        (snapshot.data()?['tallies'] as Map<String, dynamic>?) ?? {},
      );
      final current = tallies[counterId] ?? 0;
      transaction.update(ref, {'tallies.$counterId': max(current - amount, 0)});
    });
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

  /// Notifies the rest of the group that [memberUid] upped their tally for
  /// [counterId], at most once per day per group (not per member/counter -
  /// a group with several people tallying several counters throughout the
  /// day should still only ever produce one of these a day, not a flood).
  /// Runs as a transaction so two increments landing close together can't
  /// both slip past the same dedupe check and double-send.
  Future<void> _maybeNotifyTallyUpdate(
    DocumentReference<Map<String, dynamic>> groupRef,
    String memberUid,
    String counterId,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (groupData == null) return;
      final group = Group.fromFirestore(groupSnapshot.id, groupData);
      if (group.memberIds.length <= 1) return;

      final lastNotified =
          (groupData['lastTallyNotifiedAt'] as Timestamp?)?.toDate();
      if (lastNotified != null &&
          DateTime.now().difference(lastNotified) < const Duration(days: 1)) {
        return;
      }

      String? counterName;
      for (final counter in group.counters) {
        if (counter.id == counterId) {
          counterName = counter.name;
          break;
        }
      }
      if (counterName == null) return;

      transaction.update(groupRef, {
        'lastTallyNotifiedAt': FieldValue.serverTimestamp(),
      });

      final notifications = _firestore.collection('pushNotifications');
      for (final recipientUid in group.memberIds) {
        if (recipientUid == memberUid) continue;
        transaction.set(notifications.doc(), {
          'recipientUid': recipientUid,
          'type': 'group_tally_update',
          'title': group.name,
          'body':
              '$_displayName has upped their count for $counterName in '
              '${group.name}!',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
