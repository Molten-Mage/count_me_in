import 'package:cloud_firestore/cloud_firestore.dart';

const maxGroupCounters = 10;

class GroupCounter {
  final String id;
  final String name;

  const GroupCounter({required this.id, required this.name});

  Map<String, dynamic> toFirestore() => {'id': id, 'name': name};

  factory GroupCounter.fromFirestore(Map<String, dynamic> data) =>
      GroupCounter(id: data['id'] as String, name: data['name'] as String);
}

enum TallyControl { member, admin, free }

class Group {
  final String id;
  final String name;
  final String description;
  final String code;
  final List<GroupCounter> counters;
  final String createdBy;
  final DateTime createdAt;
  final List<String> memberIds;
  final bool adminControlled;
  final bool freeForAll;

  const Group({
    required this.id,
    required this.name,
    this.description = '',
    required this.code,
    required this.counters,
    required this.createdBy,
    required this.createdAt,
    required this.memberIds,
    this.adminControlled = false,
    this.freeForAll = false,
  });

  TallyControl get tallyControl => freeForAll
      ? TallyControl.free
      : (adminControlled ? TallyControl.admin : TallyControl.member);

  factory Group.fromFirestore(String id, Map<String, dynamic> data) {
    final rawCounters = data['counters'] as List<dynamic>?;
    // Pre-multi-counter groups (a single `tally` per member, an optional
    // `target`, no `counters` field at all) are never batch-migrated -
    // they're synthesized into a single "Total" counter here instead, so
    // they keep working immediately under the new shape. GroupMember's own
    // fromFirestore does the matching synthesis for `tally` -> `tallies`,
    // both keyed on this same 'counter_0' id.
    final counters = rawCounters == null
        ? const [GroupCounter(id: 'counter_0', name: 'Total')]
        : rawCounters
              .map((e) => GroupCounter.fromFirestore(e as Map<String, dynamic>))
              .toList();

    return Group(
      id: id,
      name: data['name'] as String,
      description: data['description'] as String? ?? '',
      code: data['code'] as String,
      counters: counters,
      createdBy: data['createdBy'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      memberIds: List<String>.from(data['memberIds'] as List<dynamic>),
      adminControlled: data['adminControlled'] as bool? ?? false,
      freeForAll: data['freeForAll'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'description': description,
    'code': code,
    'counters': counters.map((c) => c.toFirestore()).toList(),
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'memberIds': memberIds,
    'adminControlled': adminControlled,
    'freeForAll': freeForAll,
  };
}
