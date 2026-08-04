import 'package:cloud_firestore/cloud_firestore.dart';

const maxChallengeObjectives = 10;

enum ChallengeVisibility { public, private }

class ChallengeObjective {
  final String id;
  final String name;
  final int? target;

  const ChallengeObjective({required this.id, required this.name, this.target});

  Map<String, dynamic> toFirestore() => {'id': id, 'name': name, 'target': target};

  factory ChallengeObjective.fromFirestore(Map<String, dynamic> data) =>
      ChallengeObjective(
        id: data['id'] as String,
        name: data['name'] as String,
        target: data['target'] as int?,
      );
}

class Challenge {
  final String id;
  final String name;
  final String description;
  final ChallengeVisibility visibility;
  final bool isOfficial;
  final String code;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? endsAt;
  final List<String> memberIds;
  final List<ChallengeObjective> objectives;
  final int emblemIconIndex;
  final int emblemColorIndex;

  const Challenge({
    required this.id,
    required this.name,
    this.description = '',
    required this.visibility,
    this.isOfficial = false,
    required this.code,
    required this.createdBy,
    required this.createdAt,
    this.endsAt,
    required this.memberIds,
    required this.objectives,
    this.emblemIconIndex = 0,
    this.emblemColorIndex = 0,
  });

  bool get hasEnded => endsAt != null && DateTime.now().isAfter(endsAt!);

  factory Challenge.fromFirestore(String id, Map<String, dynamic> data) =>
      Challenge(
        id: id,
        name: data['name'] as String,
        description: data['description'] as String? ?? '',
        visibility: (data['visibility'] as String?) == 'public'
            ? ChallengeVisibility.public
            : ChallengeVisibility.private,
        isOfficial: data['isOfficial'] as bool? ?? false,
        code: data['code'] as String,
        createdBy: data['createdBy'] as String,
        createdAt: (data['createdAt'] as Timestamp).toDate(),
        endsAt: (data['endsAt'] as Timestamp?)?.toDate(),
        memberIds: List<String>.from(data['memberIds'] as List<dynamic>),
        objectives: (data['objectives'] as List<dynamic>)
            .map((e) => ChallengeObjective.fromFirestore(e as Map<String, dynamic>))
            .toList(),
        emblemIconIndex: data['emblemIconIndex'] as int? ?? 0,
        emblemColorIndex: data['emblemColorIndex'] as int? ?? 0,
      );

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'description': description,
    'visibility': visibility == ChallengeVisibility.public ? 'public' : 'private',
    'isOfficial': isOfficial,
    'code': code,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
    'memberIds': memberIds,
    'objectives': objectives.map((o) => o.toFirestore()).toList(),
    'emblemIconIndex': emblemIconIndex,
    'emblemColorIndex': emblemColorIndex,
  };
}
