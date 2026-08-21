import 'package:cloud_firestore/cloud_firestore.dart';

const maxGroupBadges = 15;

enum TallyControl { member, admin, free }

class GroupBadge {
  final int value;
  final DateTime reachedAt;
  final String gainedByName;

  const GroupBadge({
    required this.value,
    required this.reachedAt,
    required this.gainedByName,
  });

  Map<String, dynamic> toFirestore() => {
    'value': value,
    'reachedAt': Timestamp.fromDate(reachedAt),
    'gainedByName': gainedByName,
  };

  factory GroupBadge.fromFirestore(Map<String, dynamic> data) => GroupBadge(
    value: data['value'] as int,
    reachedAt: (data['reachedAt'] as Timestamp).toDate(),
    gainedByName: data['gainedByName'] as String,
  );
}

class Group {
  final String id;
  final String name;
  final String code;
  final int? target;
  final String createdBy;
  final DateTime createdAt;
  final List<String> memberIds;
  final List<GroupBadge> badges;
  final bool adminControlled;
  final bool freeForAll;

  const Group({
    required this.id,
    required this.name,
    required this.code,
    this.target,
    required this.createdBy,
    required this.createdAt,
    required this.memberIds,
    this.badges = const [],
    this.adminControlled = false,
    this.freeForAll = false,
  });

  TallyControl get tallyControl => freeForAll
      ? TallyControl.free
      : (adminControlled ? TallyControl.admin : TallyControl.member);

  factory Group.fromFirestore(String id, Map<String, dynamic> data) => Group(
    id: id,
    name: data['name'] as String,
    code: data['code'] as String,
    target: data['target'] as int?,
    createdBy: data['createdBy'] as String,
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    memberIds: List<String>.from(data['memberIds'] as List<dynamic>),
    badges:
        (data['badges'] as List<dynamic>?)
            ?.map((e) => GroupBadge.fromFirestore(e as Map<String, dynamic>))
            .toList() ??
        const [],
    adminControlled: data['adminControlled'] as bool? ?? false,
    freeForAll: data['freeForAll'] as bool? ?? false,
  );

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'code': code,
    'target': target,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'memberIds': memberIds,
    'badges': badges.map((b) => b.toFirestore()).toList(),
    'adminControlled': adminControlled,
    'freeForAll': freeForAll,
  };
}
