import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';
import '../services/challenge_service.dart';
import '../widgets/challenge_emblem.dart';
import '../widgets/objective_standings.dart';

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

/// Standings for every objective - collapsed by default (just the
/// objective name + goal), expand to see a compact leaderboard rather than
/// listing every participant's name up front.
class ChallengeParticipantsPage extends StatelessWidget {
  final Challenge challenge;

  const ChallengeParticipantsPage({super.key, required this.challenge});

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

  const _ObjectiveLeaderboard({
    required this.objective,
    required this.participants,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.target;

    return Card(
      child: ExpansionTile(
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
          ObjectiveStandings(
            objective: objective,
            participants: participants,
            myUid: myUid,
          ),
        ],
      ),
    );
  }
}
