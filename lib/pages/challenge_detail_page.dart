import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';
import '../services/challenge_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/challenge_completed_dialog.dart';
import '../widgets/challenge_emblem.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/error_dialog.dart';
import '../widgets/tally_stepper.dart';
import 'challenge_form_page.dart';
import 'challenge_participants_page.dart';

String _participantsText(Challenge challenge) {
  final count = challenge.memberIds.length;
  return count == 1 ? '1 participant' : '$count participants';
}

ChallengeParticipant? _findMe(
  List<ChallengeParticipant> participants,
  String? myUid,
) {
  for (final participant in participants) {
    if (participant.uid == myUid) return participant;
  }
  return null;
}

/// True once the viewer's own tallies have reached every objective that has
/// a target — `completedAt` is set/cleared transactionally by
/// ChallengeService whenever a tally change crosses that line, so this is
/// just reading the stored fact rather than recomputing it.
bool _isCompletedByMe(ChallengeParticipant? me) => me?.completedAt != null;

/// The viewer's own average completion across every objective that has a
/// target (objectives with no target aren't well-defined as a "%", so
/// they're excluded). Null if no objective has a target, or they haven't
/// joined.
double? _percentComplete(Challenge challenge, ChallengeParticipant? me) {
  final targeted = challenge.objectives
      .where((o) => (o.target ?? 0) > 0)
      .toList();
  if (targeted.isEmpty || me == null) return null;
  final total = targeted.fold<double>(
    0,
    (sum, o) => sum + (me.tallyFor(o.id) / o.target!).clamp(0.0, 1.0),
  );
  return total / targeted.length;
}

class ChallengeDetailPage extends StatefulWidget {
  final Challenge challenge;

  const ChallengeDetailPage({super.key, required this.challenge});

  @override
  State<ChallengeDetailPage> createState() => _ChallengeDetailPageState();
}

class _ChallengeDetailPageState extends State<ChallengeDetailPage> {
  final _challengeService = ChallengeService();
  final Map<String, TextEditingController> _stepControllers = {};
  // null until the first snapshot arrives, so we don't celebrate a
  // challenge that was already complete before this page opened.
  bool? _wasCompletedByMe;

  @override
  void dispose() {
    for (final controller in _stepControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _trackCompletion(Challenge challenge, ChallengeParticipant? me) {
    final isCompleted = _isCompletedByMe(me);
    final was = _wasCompletedByMe;
    _wasCompletedByMe = isCompleted;
    if (was == false && isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // The increment that just completed the challenge may have left a
        // step field focused; popping this dialog can otherwise restore
        // that focus and reopen its keyboard.
        FocusScope.of(context).unfocus();
        await showChallengeCompletedDialog(context, challenge: challenge);
        if (mounted) FocusScope.of(context).unfocus();
      });
    }
  }

  TextEditingController _stepControllerFor(String objectiveId) {
    return _stepControllers.putIfAbsent(
      objectiveId,
      () => TextEditingController(text: '1'),
    );
  }

  int _stepFor(String objectiveId) {
    final step = int.tryParse(_stepControllerFor(objectiveId).text);
    return (step == null || step <= 0) ? 1 : step;
  }

  void _openInfo(Challenge challenge, {String? objectiveId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChallengeParticipantsPage(
          challenge: challenge,
          initialExpandedObjectiveId: objectiveId,
        ),
      ),
    );
  }

  Future<void> _joinChallenge(Challenge challenge) async {
    try {
      // The only way to land on this page as a non-member is via a public
      // challenge's Explore row.
      await _challengeService.joinPublicChallenge(challenge.id);
    } catch (_) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: "Couldn't join challenge",
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  void _showInviteCode(Challenge challenge) {
    var justCopied = false;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> copyCode() async {
              await Clipboard.setData(ClipboardData(text: challenge.code));
              setDialogState(() => justCopied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (context.mounted) setDialogState(() => justCopied = false);
              });
            }

            void shareCode() {
              SharePlus.instance.share(
                ShareParams(
                  text:
                      'Join my challenge "${challenge.name}" on Count Me In! '
                      'Use invite code ${challenge.code} to join.',
                ),
              );
            }

            return AppDialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppDialogTitle('Invite code'),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code so others can join "${challenge.name}":',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: copyCode,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              challenge.code,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                            ),
                          ),
                          Icon(
                            justCopied ? Icons.check : Icons.copy_outlined,
                            color: justCopied
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    justCopied
                        ? 'Copied to clipboard!'
                        : 'Tap the code to copy',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: justCopied
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppDialogActions(
                    secondaryLabel: 'Close',
                    onSecondary: () => Navigator.of(context).pop(),
                    primaryLabel: 'Share',
                    onPrimary: shareCode,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmLeaveChallenge(Challenge challenge) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isCreator = challenge.createdBy == myUid;
    final isLastMember = challenge.memberIds.length <= 1;

    final message = !isCreator
        ? 'Are you sure you want to leave "${challenge.name}"?'
        : isLastMember
        ? 'You\'re the only member left. Leaving will delete '
              '"${challenge.name}".'
        : 'You created this challenge. Leaving will hand ownership off to '
              'another member.';

    showConfirmDeleteDialog(
      context,
      title: 'Leave challenge',
      message: message,
      confirmLabel: 'Leave',
      onConfirm: () {
        _challengeService.leaveChallenge(challenge.id);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<Challenge>(
      stream: _challengeService.streamChallenge(widget.challenge.id),
      initialData: widget.challenge,
      builder: (context, challengeSnapshot) {
        final challenge = challengeSnapshot.data ?? widget.challenge;
        final isCreator = challenge.createdBy == myUid;
        final isMember = challenge.memberIds.contains(myUid);

        return Scaffold(
          appBar: AppBar(
            title: Text(challenge.name),
            actions: [
              PopupMenuButton<VoidCallback>(
                tooltip: 'More options',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem<VoidCallback>(
                    value: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            ChallengeParticipantsPage(challenge: challenge),
                      ),
                    ),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('Challenge info'),
                    ),
                  ),
                  if (isCreator)
                    PopupMenuItem<VoidCallback>(
                      value: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ChallengeFormPage(
                            challengeService: _challengeService,
                            existingChallenge: challenge,
                          ),
                        ),
                      ),
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit challenge'),
                      ),
                    ),
                  PopupMenuItem<VoidCallback>(
                    value: () => _showInviteCode(challenge),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share),
                      title: Text('Invite code'),
                    ),
                  ),
                  if (isMember)
                    PopupMenuItem<VoidCallback>(
                      value: () => _confirmLeaveChallenge(challenge),
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout),
                        title: Text('Leave challenge'),
                      ),
                    ),
                  if (isCreator)
                    PopupMenuItem<VoidCallback>(
                      value: () => showConfirmDeleteDialog(
                        context,
                        title: 'Delete challenge',
                        message:
                            'Are you sure you want to delete "${challenge.name}"? '
                            'This removes it for everyone.',
                        onConfirm: () {
                          _challengeService.deleteChallenge(challenge.id);
                          Navigator.of(context).pop();
                        },
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          'Delete challenge',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: StreamBuilder<List<ChallengeParticipant>>(
              stream: _challengeService.streamParticipants(challenge.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Something went wrong: ${snapshot.error}'),
                  );
                }
                final participants =
                    snapshot.data ?? const <ChallengeParticipant>[];
                final me = _findMe(participants, myUid);
                _trackCompletion(challenge, me);

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _ChallengeHeader(
                      challenge: challenge,
                      me: me,
                      onTap: () => _openInfo(challenge),
                    ),
                    if (!isMember) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _joinChallenge(challenge),
                          icon: const Icon(Icons.add),
                          label: const Text('Join Challenge'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (challenge.description.isNotEmpty) ...[
                      Text(
                        challenge.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final objective in challenge.objectives)
                      _ObjectiveCard(
                        objective: objective,
                        me: me,
                        canEdit: !challenge.hasEnded && me != null,
                        stepController: _stepControllerFor(objective.id),
                        onDecrement: () =>
                            _challengeService.decrementObjectiveTally(
                              challenge.id,
                              objective.id,
                              _stepFor(objective.id),
                            ),
                        onIncrement: () =>
                            _challengeService.incrementObjectiveTally(
                              challenge.id,
                              objective.id,
                              _stepFor(objective.id),
                            ),
                        onTap: () =>
                            _openInfo(challenge, objectiveId: objective.id),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ChallengeHeader extends StatelessWidget {
  final Challenge challenge;
  final ChallengeParticipant? me;
  final VoidCallback onTap;

  const _ChallengeHeader({
    required this.challenge,
    required this.me,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
    final myPercent = _percentComplete(challenge, me);
    final onColor = ended
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ended
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ChallengeEmblem(
              iconIndex: challenge.emblemIconIndex,
              colorIndex: challenge.emblemColorIndex,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [_participantsText(challenge), ?deadlineText].join(' · '),
                    style: TextStyle(color: onColor),
                  ),
                  if (myPercent != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Your progress: ${(myPercent * 100).round()}%',
                      style: TextStyle(
                        color: onColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: onColor),
          ],
        ),
      ),
    );
  }
}

class _ObjectiveCard extends StatelessWidget {
  final ChallengeObjective objective;
  final ChallengeParticipant? me;
  final bool canEdit;
  final TextEditingController stepController;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onTap;

  const _ObjectiveCard({
    required this.objective,
    required this.me,
    required this.canEdit,
    required this.stepController,
    required this.onDecrement,
    required this.onIncrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.target;
    final myTally = me?.tallyFor(objective.id) ?? 0;
    final done = target != null && myTally >= target;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      objective.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          target != null ? '$myTally / $target' : '$myTally',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (done) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (canEdit)
                TallyStepper(
                  stepController: stepController,
                  iconSize: 20,
                  onDecrement: onDecrement,
                  onIncrement: onIncrement,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
