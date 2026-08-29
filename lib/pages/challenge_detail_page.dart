import 'dart:math' as math;

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
import '../widgets/editable_tally.dart';
import '../widgets/error_dialog.dart';
import '../widgets/objective_standings.dart';
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
/// a target - `completedAt` is set/cleared transactionally by
/// ChallengeService whenever a tally change crosses that line, so this is
/// just reading the stored fact rather than recomputing it.
bool _isCompletedByMe(ChallengeParticipant? me) => me?.completedAt != null;

/// The viewer's own average completion across every objective that has a
/// target (objectives with no target aren't well-defined as a "%", so
/// they're excluded). Null if no objective has a target, or they haven't
/// joined. Takes a plain tallies map (rather than a ChallengeParticipant)
/// so the caller can merge in optimistic overrides before computing this.
double? _percentComplete(Challenge challenge, Map<String, int>? tallies) {
  final targeted = challenge.objectives
      .where((o) => (o.target ?? 0) > 0)
      .toList();
  if (targeted.isEmpty || tallies == null) return null;
  final total = targeted.fold<double>(
    0,
    (sum, o) => sum + ((tallies[o.id] ?? 0) / o.target!).clamp(0.0, 1.0),
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
  // Created once rather than inline in build()'s `stream:` argument - a
  // fresh Stream instance on every rebuild forces StreamBuilder to
  // unsubscribe and resubscribe, briefly dropping back to its loading
  // state before the new subscription's first snapshot arrives. That
  // subscribe/wait/reconnect cycle, firing on every optimistic setState,
  // was the actual "blink" - not a display-value race.
  late final Stream<Challenge> _challengeStream = _challengeService
      .streamChallenge(widget.challenge.id);
  late final Stream<List<ChallengeParticipant>> _participantsStream =
      _challengeService.streamParticipants(widget.challenge.id);
  // null until the first snapshot arrives, so we don't celebrate a
  // challenge that was already complete before this page opened.
  bool? _wasCompletedByMe;
  // Displayed immediately on tap, ahead of the objective-tally write
  // actually landing and this page's StreamBuilder catching up -
  // otherwise every tap waits on a full round trip before showing
  // anything, which is what made incrementing one objective then
  // immediately tapping another look like the whole page was reloading.
  // Keyed by objective id.
  //
  // Cleared reactively in _effectiveTally once the stream's own value
  // matches the prediction, NOT as soon as the write's Future resolves -
  // that write can be acknowledged before its snapshot listener actually
  // fires, and clearing on "resolved" produced a visible revert-to-old-
  // value flash right before the stream caught up and it jumped forward
  // again. Each write also sets a fallback timer in case a concurrent
  // edit means the stream's value never exactly matches what was
  // predicted, so the display doesn't get stuck on a stale guess forever.
  //
  // Completion (`completedAt`) deliberately isn't predicted the same way
  // - it stays server-truth-driven via `_trackCompletion`, so the
  // completed-challenge celebration never fires ahead of the server
  // actually confirming it.
  final Map<String, int> _tallyOverrides = {};

  int _effectiveTally(ChallengeParticipant? me, String objectiveId) {
    final override = _tallyOverrides[objectiveId];
    if (override == null) return me?.tallyFor(objectiveId) ?? 0;
    final real = me?.tallyFor(objectiveId) ?? 0;
    if (override == real) {
      // The stream has caught up - safe to drop now, displays identically
      // either way. No setState: this is cache cleanup, not a value
      // change (this frame renders the same number regardless).
      _tallyOverrides.remove(objectiveId);
    }
    return override;
  }

  Map<String, int> _effectiveTallies(ChallengeParticipant? me) => {
    ...?me?.tallies,
    ..._tallyOverrides,
  };

  void _showSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Save failed - check your connection and try again.'),
      ),
    );
  }

  void _clearOverrideAfterDelay(String objectiveId) {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _tallyOverrides.remove(objectiveId));
    });
  }

  Future<void> _incrementObjective(
    Challenge challenge,
    ChallengeParticipant? me,
    ChallengeObjective objective,
    int amount,
  ) async {
    setState(
      () => _tallyOverrides[objective.id] =
          _effectiveTally(me, objective.id) + amount,
    );
    try {
      await _challengeService.incrementObjectiveTally(
        challenge.id,
        objective.id,
        amount,
      );
      _clearOverrideAfterDelay(objective.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides.remove(objective.id));
      _showSaveError();
    }
  }

  Future<void> _decrementObjective(
    Challenge challenge,
    ChallengeParticipant? me,
    ChallengeObjective objective,
    int amount,
  ) async {
    setState(() {
      _tallyOverrides[objective.id] = math.max(
        _effectiveTally(me, objective.id) - amount,
        0,
      );
    });
    try {
      await _challengeService.decrementObjectiveTally(
        challenge.id,
        objective.id,
        amount,
      );
      _clearOverrideAfterDelay(objective.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides.remove(objective.id));
      _showSaveError();
    }
  }

  Future<void> _resetObjective(
    Challenge challenge,
    ChallengeObjective objective,
  ) async {
    setState(() => _tallyOverrides[objective.id] = 0);
    try {
      await _challengeService.resetObjectiveTally(challenge.id, objective.id);
      _clearOverrideAfterDelay(objective.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides.remove(objective.id));
      _showSaveError();
    }
  }

  Future<void> _resetAll(Challenge challenge) async {
    setState(() {
      for (final objective in challenge.objectives) {
        _tallyOverrides[objective.id] = 0;
      }
    });
    try {
      await _challengeService.resetAllTallies(challenge.id);
      for (final objective in challenge.objectives) {
        _clearOverrideAfterDelay(objective.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (final objective in challenge.objectives) {
          _tallyOverrides.remove(objective.id);
        }
      });
      _showSaveError();
    }
  }

  void _trackCompletion(Challenge challenge, ChallengeParticipant? me) {
    final isCompleted = _isCompletedByMe(me);
    final was = _wasCompletedByMe;
    _wasCompletedByMe = isCompleted;
    if (was == false && isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // The increment that just completed the challenge may have left a
        // tally field focused; popping this dialog can otherwise restore
        // that focus and reopen its keyboard.
        FocusScope.of(context).unfocus();
        await showChallengeCompletedDialog(context, challenge: challenge);
        if (mounted) FocusScope.of(context).unfocus();
      });
    }
  }

  /// Directly editing an objective's tally field is expressed as a delta
  /// against its current (optimistic-aware) tally, then routed through
  /// [_incrementObjective]/[_decrementObjective] - reuses their existing
  /// optimistic-update, completion-tracking, and rollback logic rather than
  /// duplicating it for a third mutation path.
  Future<void> _setObjectiveTally(
    Challenge challenge,
    ChallengeParticipant? me,
    ChallengeObjective objective,
    int newValue,
  ) async {
    final delta = newValue - _effectiveTally(me, objective.id);
    if (delta > 0) {
      await _incrementObjective(challenge, me, objective, delta);
    } else if (delta < 0) {
      await _decrementObjective(challenge, me, objective, -delta);
    }
  }

  void _openInfo(Challenge challenge) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChallengeParticipantsPage(challenge: challenge),
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
                      'Use invite code ${challenge.code} to join, or tap this '
                      'link: https://count-me-in-links.pages.dev/join/challenge/'
                      '${challenge.code}',
                ),
              );
            }

            return AppDialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppDialogTitle('Share code'),
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

  void _confirmResetAll(Challenge challenge) {
    showConfirmDeleteDialog(
      context,
      title: 'Reset progress',
      message:
          'Are you sure you want to reset all of your objective tallies in '
          '"${challenge.name}" back to zero?',
      confirmLabel: 'Reset',
      onConfirm: () => _resetAll(challenge),
    );
  }

  void _confirmResetObjective(Challenge challenge, ChallengeObjective objective) {
    showConfirmDeleteDialog(
      context,
      title: 'Reset objective',
      message:
          'Are you sure you want to reset your tally for '
          '"${objective.name}" back to zero?',
      confirmLabel: 'Reset',
      onConfirm: () => _resetObjective(challenge, objective),
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
      stream: _challengeStream,
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
                      title: Text('Share code'),
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
              stream: _participantsStream,
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
                      tallies: me == null ? null : _effectiveTallies(me),
                      onTap: () => _openInfo(challenge),
                    ),
                    if (me != null && !challenge.hasEnded) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmResetAll(challenge),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset progress'),
                        ),
                      ),
                    ],
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
                        key: ValueKey(objective.id),
                        objective: objective,
                        myTally: _effectiveTally(me, objective.id),
                        canEdit: !challenge.hasEnded && me != null,
                        participants: participants,
                        myUid: myUid,
                        onChanged: (value) => _setObjectiveTally(
                          challenge,
                          me,
                          objective,
                          value,
                        ),
                        onReset: () =>
                            _confirmResetObjective(challenge, objective),
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
  // Null if the viewer hasn't joined; otherwise their tallies merged with
  // any optimistic overrides still in flight (see _effectiveTallies).
  final Map<String, int>? tallies;
  final VoidCallback onTap;

  const _ChallengeHeader({
    required this.challenge,
    required this.tallies,
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
    final myPercent = _percentComplete(challenge, tallies);
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
                    'Code: ${challenge.code}',
                    style: TextStyle(color: onColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
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

/// An objective card that doubles as its own collapsed/expanded standings
/// view - collapsed shows just the viewer's own tally (editable in place
/// via [EditableTally]), expanded adds the same top-3-plus-around-me
/// leaderboard as the full challenge info page, so switching pages isn't
/// needed just to see how others are doing on one objective.
class _ObjectiveCard extends StatelessWidget {
  final ChallengeObjective objective;
  // Already resolved by the parent via _effectiveTally - includes any
  // optimistic override still in flight for this objective.
  final int myTally;
  final bool canEdit;
  final List<ChallengeParticipant> participants;
  final String? myUid;
  final ValueChanged<int> onChanged;
  final VoidCallback onReset;

  const _ObjectiveCard({
    super.key,
    required this.objective,
    required this.myTally,
    required this.canEdit,
    required this.participants,
    required this.myUid,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.target;
    final done = target != null && myTally >= target;
    final subtleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Card(
      child: ExpansionTile(
        title: Row(
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
                      if (canEdit)
                        EditableTally(
                          value: myTally,
                          onChanged: onChanged,
                          style: subtleStyle,
                          iconSize: 20,
                        )
                      else
                        Text('$myTally', style: subtleStyle),
                      if (target != null)
                        Text(' / $target', style: subtleStyle),
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
            // Always present (just disabled at zero) rather than
            // conditionally shown/hidden - an optimistic tally update and
            // the stream value briefly disagreeing about the zero boundary
            // would otherwise make this icon flicker in and out.
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.restart_alt),
                iconSize: 20,
                tooltip: 'Reset',
                onPressed: myTally > 0 ? onReset : null,
              ),
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
