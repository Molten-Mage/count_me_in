import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:count_me_in/models/group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1);

  group('Group Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves fields', () {
      final group = Group(
        id: 'g1',
        name: 'Family steps',
        code: 'STEP01',
        target: 100000,
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1', 'u2'],
        badges: [
          GroupBadge(value: 100000, reachedAt: createdAt, gainedByName: 'Jo'),
        ],
        adminControlled: true,
      );

      final restored = Group.fromFirestore('g1', group.toFirestore());

      expect(restored.name, 'Family steps');
      expect(restored.code, 'STEP01');
      expect(restored.target, 100000);
      expect(restored.createdBy, 'u1');
      expect(restored.createdAt, createdAt);
      expect(restored.memberIds, ['u1', 'u2']);
      expect(restored.badges, hasLength(1));
      expect(restored.badges.single.gainedByName, 'Jo');
      expect(restored.adminControlled, isTrue);
    });

    test('fromFirestore defaults missing badges/adminControlled/target', () {
      final data = {
        'name': 'Minimal group',
        'code': 'MIN001',
        'target': null,
        'createdBy': 'u1',
        'createdAt': Timestamp.fromDate(createdAt),
        'memberIds': ['u1'],
      };
      final restored = Group.fromFirestore('g1', data);
      expect(restored.target, isNull);
      expect(restored.badges, isEmpty);
      expect(restored.adminControlled, isFalse);
    });
  });
}
