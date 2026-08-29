import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';
import '../services/app_navigation.dart';
import '../services/challenge_service.dart';
import '../services/invite_code_service.dart';
import '../services/premium_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/challenge_emblem.dart';
import '../widgets/error_dialog.dart';
import '../widgets/paywall_dialog.dart';
import 'challenge_detail_page.dart';
import 'challenge_form_page.dart';
import 'group_detail_page.dart';

String _participantsText(Challenge challenge) {
  final count = challenge.memberIds.length;
  return count == 1 ? '1 participant' : '$count participants';
}

String? _deadlineText(Challenge challenge) {
  final endsAt = challenge.endsAt;
  if (endsAt == null) return null;
  final daysLeft = endsAt.difference(DateTime.now()).inDays;
  return daysLeft <= 0 ? 'Ends today' : 'Ends in $daysLeft d';
}

/// Objectives + participants + deadline, with no progress line - used for
/// challenges the viewer hasn't joined yet (Explore), where "my progress"
/// isn't a meaningful thing to show.
String _subtitleFor(Challenge challenge) {
  final objectiveCount = challenge.objectives.length;
  final objectivesText = objectiveCount == 1 ? '1 objective' : '$objectiveCount objectives';
  final firstLine = '$objectivesText · ${_participantsText(challenge)}';
  final deadlineText = _deadlineText(challenge);
  return deadlineText == null ? firstLine : '$firstLine\n$deadlineText';
}

/// True once the viewer's own tallies have reached every objective that has
/// a target - `completedAt` is set/cleared transactionally by
/// ChallengeService whenever a tally change crosses that line, so this is
/// just reading the stored fact rather than recomputing it.
bool _isCompletedByMe(ChallengeParticipant? me) => me?.completedAt != null;

/// The viewer's own average completion across every objective that has a
/// target (objectives with no target aren't well-defined as a "%", so
/// they're excluded). Null if no objective has a target, or they haven't
/// joined.
double? _percentComplete(Challenge challenge, ChallengeParticipant? me) {
  final targeted = challenge.objectives.where((o) => (o.target ?? 0) > 0).toList();
  if (targeted.isEmpty || me == null) return null;
  final total = targeted.fold<double>(
    0,
    (sum, o) => sum + (me.tallyFor(o.id) / o.target!).clamp(0.0, 1.0),
  );
  return total / targeted.length;
}

/// Ascending by time remaining (soonest deadline first); challenges with no
/// deadline sort last, since there's no urgency to rank them by.
int _byTimeRemaining(Challenge a, Challenge b) {
  final aEnds = a.endsAt;
  final bEnds = b.endsAt;
  if (aEnds == null && bEnds == null) return 0;
  if (aEnds == null) return 1;
  if (bEnds == null) return -1;
  return aEnds.compareTo(bEnds);
}

class ChallengesListPage extends StatefulWidget {
  const ChallengesListPage({super.key});

  @override
  State<ChallengesListPage> createState() => _ChallengesListPageState();
}

class _ChallengesListPageState extends State<ChallengesListPage>
    with SingleTickerProviderStateMixin {
  final _challengeService = ChallengeService();
  final _premiumService = PremiumService();
  late final _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showAddOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create a challenge'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final canAdd = await _premiumService.canAddOne();
                  if (!mounted) return;
                  if (!canAdd) {
                    showPaywallDialog(context);
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          ChallengeFormPage(challengeService: _challengeService),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Join with a code'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final canAdd = await _premiumService.canAddOne();
                  if (!mounted) return;
                  if (!canAdd) {
                    showPaywallDialog(context);
                    return;
                  }
                  _showJoinDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showJoinDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _JoinChallengeDialog(onJoin: _joinByCode),
    );
  }

  Future<void> _joinByCode(String code) async {
    try {
      final joined = await joinChallengeOrGroupByCode(code);
      final group = joined.group;
      // A group code typed into "Join a challenge" - already joined via the
      // fallback above, just needs to land the viewer on it since it won't
      // show up in this page's own (challenge) list.
      if (group != null && mounted) {
        appNavigation.selectedTab.value = AppNavigation.groupsTabIndex;
        appNavigation.groupsNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
        );
      }
    } on StateError catch (e) {
      await _showJoinErrorThenRetry(e.message);
    } on FirebaseException catch (e) {
      await _showJoinErrorThenRetry(
        e.message ?? 'Something went wrong. Please try again.',
      );
    } catch (_) {
      await _showJoinErrorThenRetry('Something went wrong. Please try again.');
    }
  }

  Future<void> _showJoinErrorThenRetry(String message) async {
    if (!mounted) return;
    await showErrorDialog(context, title: "Couldn't join challenge", message: message);
    if (!mounted) return;
    _showJoinDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        bottom: TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: const [
            Tab(text: 'My Challenges'),
            Tab(text: 'Explore'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyChallengesTab(challengeService: _challengeService),
          _ExploreChallengesTab(challengeService: _challengeService),
          _CompletedChallengesTab(challengeService: _challengeService),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'challenges_list_page_fab',
        onPressed: _showAddOptions,
        tooltip: 'Add challenge',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MyChallengesTab extends StatelessWidget {
  final ChallengeService challengeService;

  const _MyChallengesTab({required this.challengeService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChallengeWithParticipation>>(
      stream: challengeService.streamMyChallengesWithParticipation(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong: ${snapshot.error}'));
        }
        // Finished all your own objectives early - belongs in Completed
        // now, even though the deadline hasn't passed.
        final entries = (snapshot.data ?? [])
            .where((e) => !e.challenge.hasEnded && !_isCompletedByMe(e.me))
            .toList()
          ..sort((a, b) => _byTimeRemaining(a.challenge, b.challenge));
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'No challenges yet. Tap + to create one or join with a code.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _ChallengeListTile(
              challenge: entry.challenge,
              subtitle: _subtitleFor(entry.challenge, entry.me),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChallengeDetailPage(challenge: entry.challenge),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _subtitleFor(Challenge challenge, ChallengeParticipant? me) {
    final objectiveCount = challenge.objectives.length;
    final objectivesText = objectiveCount == 1 ? '1 objective' : '$objectiveCount objectives';
    final firstLine = '$objectivesText · ${_participantsText(challenge)}';

    final percent = ((_percentComplete(challenge, me) ?? 0) * 100).round();
    final deadlineText = _deadlineText(challenge);
    final secondLine = ['Progress: $percent%', ?deadlineText].join(' · ');

    return '$firstLine\n$secondLine';
  }
}

class _CompletedChallengesTab extends StatelessWidget {
  final ChallengeService challengeService;

  const _CompletedChallengesTab({required this.challengeService});

  // Personal completion date if set, otherwise the challenge's deadline -
  // whichever reason a challenge landed in this tab, this is "when it
  // became history" from the viewer's point of view. Only ever called for
  // entries that already passed the tab's inclusion check below, so one of
  // the two is always non-null.
  DateTime _completedDate(ChallengeWithParticipation entry) =>
      entry.me?.completedAt ?? entry.challenge.endsAt!;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChallengeWithParticipation>>(
      stream: challengeService.streamMyChallengesWithParticipation(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong: ${snapshot.error}'));
        }
        final entries = (snapshot.data ?? [])
            .where((e) => e.challenge.hasEnded || _isCompletedByMe(e.me))
            .toList()
          ..sort((a, b) => _completedDate(b).compareTo(_completedDate(a)));
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              "Challenges you've finished will show up here once you "
              "complete every objective, or their deadline passes.",
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final challenge = entry.challenge;
            final status = _isCompletedByMe(entry.me) ? 'Completed!' : 'Ended';
            final objectiveCount = challenge.objectives.length;
            final objectivesText =
                objectiveCount == 1 ? '1 objective' : '$objectiveCount objectives';
            final percent = ((_percentComplete(challenge, entry.me) ?? 0) * 100).round();

            return _ChallengeListTile(
              challenge: challenge,
              subtitle:
                  '$objectivesText · ${_participantsText(challenge)}\n'
                  'Progress: $percent% · $status',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChallengeDetailPage(challenge: challenge),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ChallengeListTile extends StatelessWidget {
  final Challenge challenge;
  final String subtitle;
  final VoidCallback onTap;

  const _ChallengeListTile({
    required this.challenge,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ChallengeEmblem(
          iconIndex: challenge.emblemIconIndex,
          colorIndex: challenge.emblemColorIndex,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(child: Text(challenge.name)),
                if (challenge.isOfficial) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, size: 16),
                ],
              ],
            ),
            Text(
              'Code: ${challenge.code}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ExploreChallengesTab extends StatelessWidget {
  final ChallengeService challengeService;

  const _ExploreChallengesTab({required this.challengeService});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<Challenge>>(
      stream: challengeService.streamPublicChallenges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong: ${snapshot.error}'));
        }
        final challenges = (snapshot.data ?? [])
            .where((c) => !c.memberIds.contains(myUid) && !c.hasEnded)
            .toList()
          ..sort(_byTimeRemaining);
        if (challenges.isEmpty) {
          return const Center(
            child: Text(
              'No public challenges to join right now.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: challenges.length,
          itemBuilder: (context, index) {
            final challenge = challenges[index];
            return _ChallengeListTile(
              challenge: challenge,
              subtitle: _subtitleFor(challenge),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChallengeDetailPage(challenge: challenge),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _JoinChallengeDialog extends StatefulWidget {
  final void Function(String code) onJoin;

  const _JoinChallengeDialog({required this.onJoin});

  @override
  State<_JoinChallengeDialog> createState() => _JoinChallengeDialogState();
}

class _JoinChallengeDialogState extends State<_JoinChallengeDialog> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Join a challenge'),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(labelText: 'Code'),
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Cancel',
            onSecondary: () => Navigator.of(context).pop(),
            primaryLabel: 'Join',
            onPrimary: () {
              final code = _codeController.text.trim();
              if (code.isEmpty) return;

              Navigator.of(context).pop();
              widget.onJoin(code);
            },
          ),
        ],
      ),
    );
  }
}

