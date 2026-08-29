import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';

/// Which ranks to show for an objective's standings - always the top 3,
/// plus (if the viewer isn't already in the top 3) a small window around
/// their own rank. Firestore rules has no loop construct so this kind of
/// "top-N + around me" trick doesn't apply there, but it's the same idea
/// as a typical game leaderboard.
List<int> visibleObjectiveRanks(int total, int? myRank) {
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

/// Compact leaderboard for one objective - top 3 plus a window around the
/// viewer's own rank. Shared by the challenge detail page (expanded inline
/// on each objective card) and the full challenge info page.
class ObjectiveStandings extends StatelessWidget {
  final ChallengeObjective objective;
  final List<ChallengeParticipant> participants;
  final String? myUid;

  const ObjectiveStandings({
    super.key,
    required this.objective,
    required this.participants,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.target;
    final sorted = List<ChallengeParticipant>.of(participants)
      ..sort(
        (a, b) => b
            .tallyFor(objective.id)
            .compareTo(a.tallyFor(objective.id)),
      );

    int? myRank;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].uid == myUid) {
        myRank = i + 1;
        break;
      }
    }

    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No participants yet.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final visibleRanks = visibleObjectiveRanks(sorted.length, myRank);

    return Column(
      children: [
        for (var i = 0; i < visibleRanks.length; i++) ...[
          if (i > 0 && visibleRanks[i] - visibleRanks[i - 1] > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '···',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.4),
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
