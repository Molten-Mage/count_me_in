import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';
import '../services/challenge_service.dart';
import '../widgets/challenge_emblem.dart';

String _participantsText(Challenge challenge) {
  final count = challenge.memberIds.length;
  return count == 1 ? '1 participant' : '$count participants';
}

ChallengeParticipant? _find(List<ChallengeParticipant> participants, String? uid) {
  for (final participant in participants) {
    if (participant.uid == uid) return participant;
  }
  return null;
}

/// Which ranks to show for an objective's standings — always the top 3,
/// plus (if the viewer isn't already in the top 3) a small window around
/// their own rank. Firestore rules has no loop construct so this kind of
/// "top-N + around me" trick doesn't apply there, but it's the same idea
/// as a typical game leaderboard.
List<int> _visibleRanks(int total, int? myRank) {
  final ranks = <int>{};
  for (var r = 1; r <= (total < 3 ? total : 3); r++) {
    ranks.add(r);
  }
  if (myRank != null) {
    for (var r = myRank - 1; r <= myRank + 1; r++) {
      if (r >= 1 && r <= total) ranks.add(r);
    }
  }
  return ranks.toList()..sort();
}

/// Standings for every objective — collapsed by default (just the
/// objective name + goal), expand to see a compact leaderboard rather than
/// listing every participant's name up front.
class ChallengeParticipantsPage extends StatelessWidget {
  final Challenge challenge;
  // If set, that objective's standings open already expanded — used by the
  // "jump straight to this objective" shortcut on the detail page.
  final String? initialExpandedObjectiveId;

  const ChallengeParticipantsPage({
    super.key,
    required this.challenge,
    this.initialExpandedObjectiveId,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Challenge Info')),
      body: StreamBuilder<List<ChallengeParticipant>>(
        stream: ChallengeService().streamParticipants(challenge.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Something went wrong: ${snapshot.error}'));
          }
          final participants = snapshot.data ?? const <ChallengeParticipant>[];

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _InfoHeader(
                challenge: challenge,
                participants: participants,
                myUid: myUid,
              ),
              if (challenge.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  challenge.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              for (final objective in challenge.objectives)
                _ObjectiveLeaderboard(
                  objective: objective,
                  participants: participants,
                  myUid: myUid,
                  initiallyExpanded: objective.id == initialExpandedObjectiveId,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  final Challenge challenge;
  final List<ChallengeParticipant> participants;
  final String? myUid;

  const _InfoHeader({
    required this.challenge,
    required this.participants,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final me = _find(participants, myUid);
    final creator = _find(participants, challenge.createdBy);

    final ended = challenge.hasEnded;
    final endsAt = challenge.endsAt;
    String? deadlineText;
    if (endsAt != null) {
      final daysLeft = endsAt.difference(DateTime.now()).inDays;
      deadlineText = ended
          ? 'Ended'
          : daysLeft <= 0
          ? 'Ends today'
          : 'Ends in $daysLeft day${daysLeft == 1 ? '' : 's'}';
    }

    final targeted = challenge.objectives.where((o) => (o.target ?? 0) > 0).toList();
    double? myPercent;
    if (targeted.isNotEmpty && me != null) {
      final total = targeted.fold<double>(
        0,
        (sum, o) => sum + (me.tallyFor(o.id) / o.target!).clamp(0.0, 1.0),
      );
      myPercent = total / targeted.length;
    }

    final completed = participants.where((p) => p.completedAt != null).toList()
      ..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    final completionRate = participants.isEmpty
        ? 0
        : (completed.length / participants.length * 100).round();

    final creatorName = challenge.isOfficial ? 'Count Me In' : (creator?.displayName ?? 'Unknown');

    final subtleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChallengeEmblem(
                  iconIndex: challenge.emblemIconIndex,
                  colorIndex: challenge.emblemColorIndex,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([_participantsText(challenge), ?deadlineText].join(' · ')),
                      if (myPercent != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Your progress: ${(myPercent * 100).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Created by $creatorName', style: subtleStyle),
                if (challenge.isOfficial) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.verified, size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
            if (completed.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'First to complete: ${completed.first.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtleStyle,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text('Participant completion rate: $completionRate%', style: subtleStyle),
          ],
        ),
      ),
    );
  }
}

class _ObjectiveLeaderboard extends StatelessWidget {
  final ChallengeObjective objective;
  final List<ChallengeParticipant> participants;
  final String? myUid;
  final bool initiallyExpanded;

  const _ObjectiveLeaderboard({
    required this.objective,
    required this.participants,
    required this.myUid,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.target;
    final sorted = List<ChallengeParticipant>.of(participants)
      ..sort((a, b) => b.tallyFor(objective.id).compareTo(a.tallyFor(objective.id)));

    int? myRank;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].uid == myUid) {
        myRank = i + 1;
        break;
      }
    }
    final visibleRanks = _visibleRanks(sorted.length, myRank);

    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Row(
          children: [
            Expanded(
              child: Text(
                objective.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (target != null) Text('Goal: $target'),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No participants yet.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (var i = 0; i < visibleRanks.length; i++) ...[
              if (i > 0 && visibleRanks[i] - visibleRanks[i - 1] > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '···',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              _LeaderboardRow(
                rank: visibleRanks[i],
                participant: sorted[visibleRanks[i] - 1],
                objectiveId: objective.id,
                target: target,
                isMe: sorted[visibleRanks[i] - 1].uid == myUid,
              ),
            ],
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final ChallengeParticipant participant;
  final String objectiveId;
  final int? target;
  final bool isMe;

  const _LeaderboardRow({
    required this.rank,
    required this.participant,
    required this.objectiveId,
    required this.target,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final tally = participant.tallyFor(objectiveId);
    final done = target != null && tally >= target!;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: isMe
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? 'You' : participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isMe ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          if (done) ...[
            Icon(
              Icons.check_circle,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '$tally',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
