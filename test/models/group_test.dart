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
        description: '10k steps a day, every day',
        code: 'STEP01',
        counters: const [
          GroupCounter(id: 'counter_0', name: 'Steps'),
          GroupCounter(id: 'counter_1', name: 'Chores'),
        ],
        createdBy: 'u1',
        createdAt: createdAt,
        memberIds: const ['u1', 'u2'],
        adminControlled: true,
      );

      final restored = Group.fromFirestore('g1', group.toFirestore());

      expect(restored.name, 'Family steps');
      expect(restored.description, '10k steps a day, every day');
      expect(restored.code, 'STEP01');
      expect(restored.createdBy, 'u1');
      expect(restored.createdAt, createdAt);
      expect(restored.memberIds, ['u1', 'u2']);
      expect(restored.counters, hasLength(2));
      expect(restored.counters.first.name, 'Steps');
      expect(restored.adminControlled, isTrue);
    });

    test('fromFirestore defaults missing description/adminControlled', () {
      final data = {
        'name': 'Minimal group',
        'code': 'MIN001',
        'counters': [
          {'id': 'counter_0', 'name': 'Total'},
        ],
        'createdBy': 'u1',
        'createdAt': Timestamp.fromDate(createdAt),
        'memberIds': ['u1'],
      };
      final restored = Group.fromFirestore('g1', data);
      expect(restored.description, isEmpty);
      expect(restored.adminControlled, isFalse);
    });

    test('a legacy group (no counters field) synthesizes a single "Total" counter', () {
      final data = {
        'name': 'Legacy group',
        'code': 'LEG001',
        'target': 500,
        'createdBy': 'u1',
        'createdAt': Timestamp.fromDate(createdAt),
        'memberIds': ['u1'],
      };
      final restored = Group.fromFirestore('g1', data);
      expect(restored.counters, hasLength(1));
      expect(restored.counters.single.id, 'counter_0');
      expect(restored.counters.single.name, 'Total');
    });
  });
}
