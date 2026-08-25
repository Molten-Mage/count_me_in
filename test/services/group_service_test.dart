import 'package:count_me_in/models/group.dart';
import 'package:count_me_in/services/analytics_service.dart';
import 'package:count_me_in/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_analytics_logger.dart';

// fake_cloud_firestore's snapshot streams don't reliably re-emit after a
// runTransaction() write (used by the badge-awarding logic), even though
// the underlying document is updated correctly - read directly instead of
// via GroupService's streamGroup() for anything checked right after one.
Future<Group> _getGroup(FakeFirebaseFirestore firestore, String groupId) async {
  final doc = await firestore.collection('groups').doc(groupId).get();
  return Group.fromFirestore(doc.id, doc.data()!);
}

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
      final group = await service.createGroup(name: 'Family steps', target: 100);

      expect(group.name, 'Family steps');
      expect(group.target, 100);
      expect(group.createdBy, 'u1');
      expect(group.memberIds, ['u1']);
      expect(group.code, hasLength(6));

      final members = await service.streamMembers(group.id).first;
      expect(members, hasLength(1));
      expect(members.single.uid, 'u1');
      expect(members.single.displayName, 'Jo');
      expect(members.single.tally, 0);
    });

    test('logs group_created', () async {
      final service = _serviceFor(firestore, 'u1');
      await service.createGroup(name: 'Test');
      expect(fakeAnalytics.events, ['group_created']);
    });

    test('two groups never share an invite code', () async {
      final service = _serviceFor(firestore, 'u1');
      final a = await service.createGroup(name: 'A');
      final b = await service.createGroup(name: 'B');
      expect(a.code, isNot(b.code));
    });
  });

  group('joinGroupByCode', () {
    test('adds the joiner to memberIds and creates their member doc', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(name: 'Family steps');

      final joiner = _serviceFor(firestore, 'u2', displayName: 'Alex');
      final joined = await joiner.joinGroupByCode(group.code);

      expect(joined.id, group.id);
      final members = await owner.streamMembers(group.id).first;
      expect(members.map((m) => m.uid), containsAll(['u1', 'u2']));
    });

    test('logs group_joined only for the joiner, not the creator', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(name: 'Family steps');
      expect(fakeAnalytics.events, ['group_created']);

      final joiner = _serviceFor(firestore, 'u2');
      await joiner.joinGroupByCode(group.code);
      expect(fakeAnalytics.events, ['group_created', 'group_joined']);
    });

    test('joining a code you are already a member of is a no-op', () async {
      final owner = _serviceFor(firestore, 'u1');
      final group = await owner.createGroup(name: 'Family steps');
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
      final group = await owner.createGroup(name: 'Family steps');

      final joiner = _serviceFor(firestore, 'u2');
      final joined = await joiner.joinGroupByCode(group.code.toLowerCase());
      expect(joined.id, group.id);
    });
  });

  group('tallies and badges', () {
    test('incrementMemberTally increases the tally', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps');

      await service.incrementMemberTally(group.id, 'u1', 5);
      final members = await service.streamMembers(group.id).first;
      expect(members.single.tally, 5);
    });

    test('decrementMemberTally clamps at zero', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps');

      await service.incrementMemberTally(group.id, 'u1', 3);
      await service.decrementMemberTally(group.id, 'u1', 10);

      final members = await service.streamMembers(group.id).first;
      expect(members.single.tally, 0);
    });

    test('awards a badge once the combined tally reaches the target', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps', target: 10);

      await service.incrementMemberTally(group.id, 'u1', 10);

      final updated = await _getGroup(firestore, group.id);
      expect(updated.badges, hasLength(1));
      expect(updated.badges.single.value, 10);
    });

    test('does not award a duplicate badge for the same target', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps', target: 10);

      await service.incrementMemberTally(group.id, 'u1', 10);
      await service.incrementMemberTally(group.id, 'u1', 1);

      final updated = await _getGroup(firestore, group.id);
      expect(updated.badges, hasLength(1));
    });

    test('no badge is awarded below the target', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps', target: 10);

      await service.incrementMemberTally(group.id, 'u1', 5);

      final updated = await _getGroup(firestore, group.id);
      expect(updated.badges, isEmpty);
    });
  });

  group('deleteGroup', () {
    test('removes the group and its member docs, logs group_deleted', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Steps');
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
      final group = await owner.createGroup(name: 'Steps');
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
      final group = await service.createGroup(name: 'Steps');
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
        final group = await owner.createGroup(name: 'Steps');
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
      final group = await owner.createGroup(name: 'Steps');
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
      final groupA = await owner.createGroup(name: 'Group A');
      final groupB = await owner.createGroup(name: 'Group B');
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
    test('updates name and target', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Old name');

      await service.updateGroup(group.id, name: 'New name', target: 50);

      final updated = await service.streamGroup(group.id).first;
      expect(updated.name, 'New name');
      expect(updated.target, 50);
    });

    test('updates tally control mode', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(name: 'Test');
      expect(group.tallyControl, TallyControl.member);

      await service.updateGroup(
        group.id,
        name: group.name,
        target: group.target,
        adminControlled: true,
        freeForAll: false,
      );

      final admin = await service.streamGroup(group.id).first;
      expect(admin.tallyControl, TallyControl.admin);

      await service.updateGroup(
        group.id,
        name: group.name,
        target: group.target,
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
        adminControlled: true,
      );

      await service.updateGroup(group.id, name: 'Renamed', target: null);

      final updated = await service.streamGroup(group.id).first;
      expect(updated.tallyControl, TallyControl.admin);
    });

    test('updates description, leaves it unchanged when omitted', () async {
      final service = _serviceFor(firestore, 'u1');
      final group = await service.createGroup(
        name: 'Test',
        description: 'Original description',
      );

      await service.updateGroup(
        group.id,
        name: group.name,
        target: group.target,
        description: 'Updated description',
      );
      final updated = await service.streamGroup(group.id).first;
      expect(updated.description, 'Updated description');

      await service.updateGroup(group.id, name: 'Renamed', target: null);
      final renamed = await service.streamGroup(group.id).first;
      expect(renamed.description, 'Updated description');
    });
  });
}
