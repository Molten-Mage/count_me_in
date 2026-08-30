import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:count_me_in/models/group.dart';
import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

GroupService _serviceFor(
  FakeFirebaseFirestore firestore,
  String uid, {
  String? displayName,
}) {
  return GroupService(
    firestore: firestore,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, displayName: displayName ?? uid),
    ),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAnalyticsLogger fakeAnalytics;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    fakeAnalytics = FakeAnalyticsLogger();
    analyticsService = fakeAnalytics;
  });

  group('createGroup', () {
    test('creates the group and adds the creator as a member', () async {
      final service = _serviceFor(firestore, 'u1', displayName: 'Jo');
      final group = await service.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );

      expect(group.name, 'Family steps');
      expect(group.counters, hasLength(1));
      expect(group.counters.single.name, 'Steps');
      expect(group.createdBy, 'u1');
      expect(group.memberIds, ['u1']);
      expect(group.code, startsWith('G-'));
      expect(group.code, hasLength(8));

      final members = await service.streamMembers(group.id).first;
      expect(members, hasLength(1));
      expect(members.single.uid, 'u1');
      expect(members.single.displayName, 'Jo');
      expect(members.single.tallyFor(group.counters.single.id), 0);
    });

    test('assigns each counter a distinct id', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Chores',
        counterNames: ['Dishes', 'Laundry'],
      );

      expect(group.counters.map((c) => c.id).toSet(), hasLength(2));
      expect(group.counters[0].name, 'Dishes');
      expect(group.counters[1].name, 'Laundry');
    });

    test('logs group_created', () async {
      final service = _serviceFor(firestore, 'u1');
      await service.createGroup(name: 'Test', counterNames: ['Total']);
      expect(fakeAnalytics.events, ['group_created']);
    });

    test('two groups never share an invite code', () async {
      final service = _serviceFor(firestore, 'u1');
      final a = await service.createGroup(name: 'A', counterNames: ['Total']);
      final b = await service.createGroup(name: 'B', counterNames: ['Total']);
      expect(a.code, isNot(b.code));
    });

    test('rejects zero counters', () async {
      final service = _serviceFor(firestore, 'u1');
      expect(
        () => service.createGroup(name: 'Empty', counterNames: []),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('joinGroupByCode', () {
    test('adds the joiner to memberIds and creates their member doc', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );

      final joiner = _serviceFor(firestore, 'u2', displayName: 'Alex');
      final joined = await joiner.joinGroupByCode(group.code);

      expect(joined.id, group.id);
      final members = await owner.streamMembers(group.id).first;
      expect(members.map((m) => m.uid), containsAll(['u1', 'u2']));
    });

    test('logs group_joined only for the joiner, not the creator', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );
      expect(fakeAnalytics.events, ['group_created']);

      final joiner = _serviceFor(firestore, 'u2');
      await joiner.joinGroupByCode(group.code);
      expect(fakeAnalytics.events, ['group_created', 'group_joined']);
    });

    test('joining a code you are already a member of is a no-op', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );
      fakeAnalytics.events.clear();

      await owner.joinGroupByCode(group.code);

      final members = await owner.streamMembers(group.id).first;
      expect(members, hasLength(1));
      expect(fakeAnalytics.events, isEmpty);
    });

    test('throws for an unknown code', () async {
      final service = _serviceFor(firestore, 'u1');
      expect(
        () => service.joinGroupByCode('NOPE99'),
        throwsA(isA<StateError>()),
      );
    });

    test('code lookup is case-insensitive', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );

      final joiner = _serviceFor(firestore, 'u2');
      final joined = await joiner.joinGroupByCode(group.code.toLowerCase());
      expect(joined.id, group.id);
    });

    test('the creator gets exactly one push notification, not a duplicate', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );

      final joiner = _serviceFor(firestore, 'u2', displayName: 'Alex');
      await joiner.joinGroupByCode(group.code);

      final notifications = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u1')
          .get();
      expect(notifications.docs, hasLength(1));
      expect(notifications.docs.single.data()['type'], 'group_joined_owner');
    });

    test('a pre-existing (non-creator) member gets the generic joined notification', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Family steps',
        counterNames: ['Steps'],
      );
      final second = _serviceFor(firestore, 'u2');
      await second.joinGroupByCode(group.code);

      final third = _serviceFor(firestore, 'u3', displayName: 'Sam');
      await third.joinGroupByCode(group.code);

      final notifications = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u2')
          .get();
      expect(notifications.docs, hasLength(1));
      expect(notifications.docs.single.data()['type'], 'group_joined');
    });
  });

  group('tallies', () {
    test('incrementMemberTally increases the tally for that counter', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      final counterId = group.counters.single.id;

      await service.incrementMemberTally(group.id, 'u1', counterId, 5);
      final members = await service.streamMembers(group.id).first;
      expect(members.single.tallyFor(counterId), 5);
    });

    test('separate counters track separate tallies for the same member', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Chores',
        counterNames: ['Dishes', 'Laundry'],
      );
      final dishesId = group.counters[0].id;
      final laundryId = group.counters[1].id;

      await service.incrementMemberTally(group.id, 'u1', dishesId, 3);
      await service.incrementMemberTally(group.id, 'u1', laundryId, 7);

      final members = await service.streamMembers(group.id).first;
      expect(members.single.tallyFor(dishesId), 3);
      expect(members.single.tallyFor(laundryId), 7);
    });

    test('decrementMemberTally clamps at zero', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      final counterId = group.counters.single.id;

      await service.incrementMemberTally(group.id, 'u1', counterId, 3);
      await service.decrementMemberTally(group.id, 'u1', counterId, 10);

      final members = await service.streamMembers(group.id).first;
      expect(members.single.tallyFor(counterId), 0);
    });
  });

  group('tally update notifications', () {
    test('incrementing notifies other members but not the actor', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Chores',
        counterNames: ['Dishes'],
      );
      final second = _serviceFor(firestore, 'u2');
      await second.joinGroupByCode(group.code);
      final counterId = group.counters.single.id;

      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);

      final forActor = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u1')
          .where('type', isEqualTo: 'group_tally_update')
          .get();
      expect(forActor.docs, isEmpty);

      final forOther = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u2')
          .where('type', isEqualTo: 'group_tally_update')
          .get();
      expect(forOther.docs, hasLength(1));
      expect(forOther.docs.single.data()['body'], contains('Dishes'));
      expect(forOther.docs.single.data()['body'], contains('Chores'));
    });

    test('a second increment the same day does not send a second notification', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Chores',
        counterNames: ['Dishes'],
      );
      final second = _serviceFor(firestore, 'u2');
      await second.joinGroupByCode(group.code);
      final counterId = group.counters.single.id;

      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);
      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);

      final notifications = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u2')
          .where('type', isEqualTo: 'group_tally_update')
          .get();
      expect(notifications.docs, hasLength(1));
    });

    test('fires again once the daily cooldown has passed', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Chores',
        counterNames: ['Dishes'],
      );
      final second = _serviceFor(firestore, 'u2');
      await second.joinGroupByCode(group.code);
      final counterId = group.counters.single.id;

      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);
      // Simulate the cooldown having already elapsed, same as a real
      // `lastTallyNotifiedAt` from more than a day ago.
      await firestore.collection('groups').doc(group.id).update({
        'lastTallyNotifiedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 2)),
        ),
      });

      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);

      final notifications = await firestore
          .collection('pushNotifications')
          .where('recipientUid', isEqualTo: 'u2')
          .where('type', isEqualTo: 'group_tally_update')
          .get();
      expect(notifications.docs, hasLength(2));
    });

    test('a solo group (no one else to notify) does not send anything', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Solo',
        counterNames: ['Total'],
      );
      final counterId = group.counters.single.id;

      await owner.incrementMemberTally(group.id, 'u1', counterId, 1);

      final notifications = await firestore
          .collection('pushNotifications')
          .where('type', isEqualTo: 'group_tally_update')
          .get();
      expect(notifications.docs, isEmpty);
    });
  });

  group('updateCounters', () {
    test('replaces the counters list', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Chores',
        counterNames: ['Dishes'],
      );

      await service.updateCounters(group.id, [
        GroupCounter(id: group.counters.single.id, name: 'Dishes'),
        const GroupCounter(id: 'counter_1', name: 'Laundry'),
      ]);

      final updated = await service.streamGroup(group.id).first;
      expect(updated.counters, hasLength(2));
      expect(updated.counters.last.name, 'Laundry');
    });
  });

  group('deleteGroup', () {
    test('removes the group and its member docs, logs group_deleted', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      fakeAnalytics.events.clear();

      await service.deleteGroup(group.id);

      final doc = await firestore.collection('groups').doc(group.id).get();
      expect(doc.exists, isFalse);
      expect(fakeAnalytics.events, ['group_deleted']);
    });
  });

  group('leaveGroup', () {
    test('a non-creator member is just removed', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      final memberService = _serviceFor(firestore, 'u2');
      await memberService.joinGroupByCode(group.code);
      fakeAnalytics.events.clear();

      await memberService.leaveGroup(group.id);

      final updated = await owner.streamGroup(group.id).first;
      expect(updated.memberIds, ['u1']);
      expect(updated.createdBy, 'u1');
      expect(fakeAnalytics.events, ['group_left']);
    });

    test('the sole remaining member leaving deletes the group', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      fakeAnalytics.events.clear();

      await service.leaveGroup(group.id);

      final doc = await firestore.collection('groups').doc(group.id).get();
      expect(doc.exists, isFalse);
      expect(fakeAnalytics.events, ['group_left', 'group_deleted']);
    });

    test(
      'the creator leaving with others remaining hands off to the '
      'longest-standing member',
      () async {
        final owner = _serviceFor(firestore, 'u1');
        final group = await owner.createGroup(
          name: 'Steps',
          counterNames: ['Total'],
        );
        final second = _serviceFor(firestore, 'u2');
        await second.joinGroupByCode(group.code);
        final third = _serviceFor(firestore, 'u3');
        await third.joinGroupByCode(group.code);

        await owner.leaveGroup(group.id);

        final updated = await second.streamGroup(group.id).first;
        expect(updated.memberIds, containsAll(['u2', 'u3']));
        expect(updated.memberIds, isNot(contains('u1')));
        // u2 joined before u3, so ownership goes to u2.
        expect(updated.createdBy, 'u2');
      },
    );
  });

  group('removeMember', () {
    test('removes the target member without affecting others', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(
        name: 'Steps',
        counterNames: ['Total'],
      );
      final second = _serviceFor(firestore, 'u2');
      await second.joinGroupByCode(group.code);

      await owner.removeMember(group.id, 'u2');

      final updated = await owner.streamGroup(group.id).first;
      expect(updated.memberIds, ['u1']);
    });
  });

  group('group order', () {
    test('loadGroupOrder defaults to empty, saveGroupOrder round-trips', () async {
      final service = _serviceFor(firestore, 'u1');
      expect(await service.loadGroupOrder(), isEmpty);

      await service.saveGroupOrder(['g2', 'g1']);
      expect(await service.loadGroupOrder(), ['g2', 'g1']);
    });
  });

  group('propagateDisplayNameChange', () {
    test('updates the caller\'s own member doc across every group they\'re in, '
        'leaves other members alone', () async {
      final owner = _serviceFor(firestore, 'u1', displayName: 'Old Name');
      final other = _serviceFor(firestore, 'u2', displayName: 'Other Person');
      final groupA = await owner.createGroup(
        name: 'Group A',
        counterNames: ['Total'],
      );
      final groupB = await owner.createGroup(
        name: 'Group B',
        counterNames: ['Total'],
      );
      await other.joinGroupByCode(groupA.code);

      await owner.propagateDisplayNameChange('New Name');

      final membersA = await owner.streamMembers(groupA.id).first;
      final membersB = await owner.streamMembers(groupB.id).first;
      expect(
        membersA.firstWhere((m) => m.uid == 'u1').displayName,
        'New Name',
      );
      expect(
        membersA.firstWhere((m) => m.uid == 'u2').displayName,
        'Other Person',
      );
      expect(
        membersB.firstWhere((m) => m.uid == 'u1').displayName,
        'New Name',
      );
    });

    test('is a no-op when the caller is not in any groups', () async {
      final service = _serviceFor(firestore, 'u1');
      await service.propagateDisplayNameChange('New Name');
    });
  });

  group('updateGroup', () {
    test('updates the name', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Old name',
        counterNames: ['Total'],
      );

      await service.updateGroup(group.id, name: 'New name');

      final updated = await service.streamGroup(group.id).first;
      expect(updated.name, 'New name');
    });

    test('updates tally control mode', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Test',
        counterNames: ['Total'],
      );
      expect(group.tallyControl, TallyControl.member);

      await service.updateGroup(
        group.id,
        name: group.name,
        adminControlled: true,
        freeForAll: false,
      );

      final admin = await service.streamGroup(group.id).first;
      expect(admin.tallyControl, TallyControl.admin);

      await service.updateGroup(
        group.id,
        name: group.name,
        adminControlled: false,
        freeForAll: true,
      );

      final free = await service.streamGroup(group.id).first;
      expect(free.tallyControl, TallyControl.free);
    });

    test('leaves tally control mode unchanged when omitted', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Test',
        counterNames: ['Total'],
        adminControlled: true,
      );

      await service.updateGroup(group.id, name: 'Renamed');

      final updated = await service.streamGroup(group.id).first;
      expect(updated.tallyControl, TallyControl.admin);
    });

    test('updates description, leaves it unchanged when omitted', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Test',
        counterNames: ['Total'],
        description: 'Original description',
      );

      await service.updateGroup(
        group.id,
        name: group.name,
        description: 'Updated description',
      );
      final updated = await service.streamGroup(group.id).first;
      expect(updated.description, 'Updated description');

      await service.updateGroup(group.id, name: 'Renamed');
      final renamed = await service.streamGroup(group.id).first;
      expect(renamed.description, 'Updated description');
    });
  });

  group('legacy single-tally groups (no batch migration - see Group.fromFirestore)', () {
    test('a pre-multi-counter group loads as a single "Total" counter', () async {
      final groupRef = firestore.collection('groups').doc('legacy1');
      await groupRef.set({
        'name': 'Legacy family steps',
        'description': '',
        'code': 'G-LEGACY',
        'target': 500,
        'createdBy': 'u1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'memberIds': ['u1'],
        'adminControlled': false,
        'freeForAll': false,
      });
      await groupRef.collection('members').doc('u1').set({
        'displayName': 'Jo',
        'tally': 120,
        'joinedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final service = _serviceFor(firestore, 'u1');
      final group = await service.streamGroup('legacy1').first;
      final members = await service.streamMembers('legacy1').first;

      expect(group.counters, hasLength(1));
      expect(group.counters.single.id, 'counter_0');
      expect(members.single.tallyFor('counter_0'), 120);
    });

    test('incrementing a legacy member writes forward in the new tallies shape', () async {
      final groupRef = firestore.collection('groups').doc('legacy2');
      await groupRef.set({
        'name': 'Legacy chores',
        'description': '',
        'code': 'G-LEGACY2',
        'createdBy': 'u1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'memberIds': ['u1'],
        'adminControlled': false,
        'freeForAll': false,
      });
      await groupRef.collection('members').doc('u1').set({
        'displayName': 'Jo',
        'tally': 10,
        'joinedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final service = _serviceFor(firestore, 'u1');
      await service.incrementMemberTally('legacy2', 'u1', 'counter_0', 5);

      final members = await service.streamMembers('legacy2').first;
      expect(members.single.tallyFor('counter_0'), 5);
    });
  });
}
