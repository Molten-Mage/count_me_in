import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/group.dart';
import '../models/group_member.dart';
import '../services/analytics_service.dart';
import '../services/group_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/badge_icon.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/editable_tally.dart';
import '../widgets/goal_reached_dialog.dart';
import 'group_form_page.dart';

class GroupDetailPage extends StatefulWidget {
  final Group group;

  const GroupDetailPage({super.key, required this.group});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final _groupService = GroupService();
  // Created once rather than inline in build()'s `stream:` argument - a
  // fresh Stream instance on every rebuild forces StreamBuilder to
  // unsubscribe and resubscribe, briefly dropping back to its loading
  // state before the new subscription's first snapshot arrives. That
  // subscribe/wait/reconnect cycle, firing on every optimistic setState,
  // was the actual "blink" - not a display-value race.
  late final Stream<Group> _groupStream = _groupService.streamGroup(
    widget.group.id,
  );
  late final Stream<List<GroupMember>> _membersStream = _groupService
      .streamMembers(widget.group.id);
  int _currentTotal = 0;
  int? _lastKnownTotal;
  // Displayed immediately on tap, ahead of the member-tally write actually
  // landing and this page's StreamBuilder catching up - otherwise every
  // tap waits on a full round trip before showing anything, which makes
  // rapid tapping feel unresponsive. Keyed by member uid.
  //
  // Cleared reactively in _effectiveTally once the stream's own value
  // matches the prediction, NOT as soon as the write's Future resolves -
  // that write can be acknowledged before its snapshot listener actually
  // fires, and clearing on "resolved" produced a visible revert-to-old-
  // value flash right before the stream caught up and it jumped forward
  // again. Each entry also carries a fallback timer in case a concurrent
  // edit (e.g. an admin editing the same member) means the stream's value
  // never exactly matches what was predicted, so the display doesn't get
  // stuck on a stale guess forever.
  final Map<String, int> _tallyOverrides = {};
  // Row order is captured once from the first snapshot of this visit to
  // the page, then held fixed - re-sorting live as confirmed tallies cross
  // each other would otherwise make rows jump around under a member's
  // finger mid-session. Rank numbers (CircleAvatar below) still update
  // live against the real standings; only which row a member occupies
  // stays put until the page is reopened. Null until the first snapshot
  // arrives.
  List<String>? _frozenMemberOrder;

  /// Orders [rawMembers] by [_frozenMemberOrder], capturing that order
  /// (by real tally, highest first) on the first call this visit. A
  /// member who joins mid-visit is appended in whatever order the stream
  /// delivered them, and starts tracking their own frozen position from
  /// then on; a member who leaves just drops out of the rendered list
  /// without disturbing anyone else's position.
  List<GroupMember> _orderedMembers(List<GroupMember> rawMembers) {
    final byUid = {for (final m in rawMembers) m.uid: m};
    var frozen = _frozenMemberOrder;
    if (frozen == null) {
      final initial = List<GroupMember>.of(rawMembers)
        ..sort((a, b) => b.tally.compareTo(a.tally));
      frozen = initial.map((m) => m.uid).toList();
    }
    final ordered = [
      for (final uid in frozen)
        if (byUid[uid] != null) byUid[uid]!,
    ];
    final newcomers = rawMembers
        .where((m) => !frozen!.contains(m.uid))
        .toList();
    if (newcomers.isNotEmpty) {
      frozen = [...frozen, ...newcomers.map((m) => m.uid)];
      ordered.addAll(newcomers);
    }
    _frozenMemberOrder = frozen;
    return ordered;
  }

  int _effectiveTally(GroupMember member) {
    final override = _tallyOverrides[member.uid];
    if (override == null) return member.tally;
    if (override == member.tally) {
      // The stream has caught up - safe to drop now, displays identically
      // either way. No setState: this is cache cleanup, not a value
      // change (this frame renders the same number regardless).
      _tallyOverrides.remove(member.uid);
    }
    return override;
  }

  void _showSaveError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Save failed - check your connection and try again.'),
      ),
    );
  }

  void _clearOverrideAfterDelay(String uid) {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _tallyOverrides.remove(uid));
    });
  }

  Future<void> _incrementMember(
    Group group,
    GroupMember member,
    int amount,
  ) async {
    setState(
      () => _tallyOverrides[member.uid] = _effectiveTally(member) + amount,
    );
    try {
      await _groupService.incrementMemberTally(group.id, member.uid, amount);
      _clearOverrideAfterDelay(member.uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides.remove(member.uid));
      _showSaveError();
    }
  }

  Future<void> _decrementMember(
    Group group,
    GroupMember member,
    int amount,
  ) async {
    setState(() {
      _tallyOverrides[member.uid] = max(
        _effectiveTally(member) - amount,
        0,
      );
    });
    try {
      await _groupService.decrementMemberTally(group.id, member.uid, amount);
      _clearOverrideAfterDelay(member.uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides.remove(member.uid));
      _showSaveError();
    }
  }

  /// Directly editing a member's tally field is expressed as a delta
  /// against their current (optimistic-aware) tally, then routed through
  /// [_incrementMember]/[_decrementMember] - reuses their existing
  /// optimistic-update, badge-award, and rollback logic rather than
  /// duplicating it for a third mutation path.
  Future<void> _setMemberTally(
    Group group,
    GroupMember member,
    int newValue,
  ) async {
    final delta = newValue - _effectiveTally(member);
    if (delta > 0) {
      await _incrementMember(group, member, delta);
    } else if (delta < 0) {
      await _decrementMember(group, member, -delta);
    }
  }

  void _showInviteCode(Group group) {
    var justCopied = false;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> copyCode() async {
              await Clipboard.setData(ClipboardData(text: group.code));
              setDialogState(() => justCopied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (context.mounted) setDialogState(() => justCopied = false);
              });
            }

            void shareCode() {
              analyticsService.logGroupInviteShared();
              SharePlus.instance.share(
                ShareParams(
                  text:
                      'Join my group "${group.name}" on Count Me In! '
                      'Use invite code ${group.code} to join, or tap this '
                      'link: https://count-me-in-links.pages.dev/join/group/'
                      '${group.code}',
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
                    'Share this code so others can join "${group.name}":',
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
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.code,
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
                    justCopied ? 'Copied to clipboard!' : 'Tap the code to copy',
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

  Future<void> _openEditGroupPage(Group group, int currentTotal) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroupFormPage(
          groupService: _groupService,
          existingGroup: group,
          currentTotal: currentTotal,
          onShowMembers: () => _showGroupMembersDialog(group),
        ),
      ),
    );
  }

  Future<void> _showGroupMembersDialog(Group group) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AppDialog(
          child: StreamBuilder<List<GroupMember>>(
            stream: _groupService.streamMembers(group.id),
            builder: (context, snapshot) {
              final members = snapshot.data ?? const <GroupMember>[];

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppDialogTitle('Group members'),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final member in members)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                member.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('${member.tally}'),
                              trailing: member.uid == myUid
                                  ? null
                                  : IconButton(
                                      icon: Icon(
                                        Icons.person_remove_outlined,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      tooltip: 'Remove member',
                                      onPressed: () =>
                                          _confirmRemoveMember(group, member),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _confirmRemoveMember(Group group, GroupMember member) {
    showConfirmDeleteDialog(
      context,
      title: 'Remove member',
      message:
          'Are you sure you want to remove ${member.displayName} from '
          '"${group.name}"?',
      confirmLabel: 'Remove',
      onConfirm: () => _groupService.removeMember(group.id, member.uid),
    );
  }

  void _confirmLeaveGroup(Group group) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isCreator = group.createdBy == myUid;
    final isLastMember = group.memberIds.length <= 1;

    final message = !isCreator
        ? 'Are you sure you want to leave "${group.name}"?'
        : isLastMember
        ? 'You\'re the only member left. Leaving will delete '
              '"${group.name}".'
        : 'You created this group. Leaving will hand off ownership to '
              'another member.';

    showConfirmDeleteDialog(
      context,
      title: 'Leave group',
      message: message,
      confirmLabel: 'Leave',
      onConfirm: () {
        _groupService.leaveGroup(group.id);
        Navigator.of(context).pop();
      },
    );
  }

  void _celebrateGoalReached(Group group, int target, int total) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showGoalReachedDialog(
        context,
        source: 'group',
        message: '"${group.name}" hit $total! Great teamwork.',
        badgeValue: target,
        badgeColorIndex: 0,
        currentCount: total,
        onSetNewGoal: (newTarget) {
          _groupService.updateGroup(group.id, name: group.name, target: newTarget);
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<Group>(
      stream: _groupStream,
      initialData: widget.group,
      builder: (context, groupSnapshot) {
        final group = groupSnapshot.data ?? widget.group;

        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              PopupMenuButton<VoidCallback>(
                tooltip: 'More options',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (group.createdBy == myUid)
                    PopupMenuItem<VoidCallback>(
                      value: () =>
                          _openEditGroupPage(group, _currentTotal),
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit group'),
                      ),
                    ),
                  PopupMenuItem<VoidCallback>(
                    value: () => _showInviteCode(group),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share),
                      title: Text('Share code'),
                    ),
                  ),
                  PopupMenuItem<VoidCallback>(
                    value: () => _confirmLeaveGroup(group),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout),
                      title: Text('Leave group'),
                    ),
                  ),
                  if (group.createdBy == myUid)
                    PopupMenuItem<VoidCallback>(
                      value: () => showConfirmDeleteDialog(
                        context,
                        title: 'Delete group',
                        message:
                            'Are you sure you want to delete "${group.name}"? '
                            'This removes it for everyone in the group.',
                        onConfirm: () {
                          _groupService.deleteGroup(group.id);
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
                          'Delete group',
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
            child: StreamBuilder<List<GroupMember>>(
              stream: _membersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Something went wrong: ${snapshot.error}'),
                  );
                }
                final rawMembers = snapshot.data ?? const <GroupMember>[];
                final members = _orderedMembers(rawMembers);
                // Independent of row order above: rank numbers still track
                // the real (server-confirmed) standings live, so a row that
                // stays put can still show a rank that's moved.
                final rankedByTally = List<GroupMember>.of(rawMembers)
                  ..sort((a, b) => b.tally.compareTo(a.tally));
                final rankByUid = {
                  for (var i = 0; i < rankedByTally.length; i++)
                    rankedByTally[i].uid: i + 1,
                };
                // `total` (server truth, drives the goal-reached celebration
                // below) vs `displayTotal` (includes optimistic overrides,
                // what's actually shown) - kept separate so a celebration
                // never fires ahead of the write it's celebrating actually
                // landing.
                int total = 0;
                int displayTotal = 0;
                for (final member in members) {
                  total += member.tally;
                  displayTotal += _effectiveTally(member);
                }
                _currentTotal = total;
                final target = group.target;
                final adminName = _adminDisplayName(members, group.createdBy);

                final previousTotal = _lastKnownTotal;
                _lastKnownTotal = total;
                if (target != null &&
                    target > 0 &&
                    previousTotal != null &&
                    previousTotal < target &&
                    total >= target) {
                  _celebrateGoalReached(group, target, total);
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      target != null
                          ? 'Team goal: $displayTotal / $target'
                          : 'Team total: $displayTotal',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (target != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (displayTotal / target).clamp(0, 1).toDouble(),
                      ),
                    ],
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        group.description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    for (var i = 0; i < members.length; i++)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                child: Text('${rankByUid[members[i].uid]}'),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  members[i].displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (switch (group.tallyControl) {
                                TallyControl.admin => group.createdBy == myUid,
                                TallyControl.free => true,
                                TallyControl.member => members[i].uid == myUid,
                              })
                                EditableTally(
                                  value: _effectiveTally(members[i]),
                                  onChanged: (value) => _setMemberTally(
                                    group,
                                    members[i],
                                    value,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                )
                              else
                                Text(
                                  '${_effectiveTally(members[i])}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (target != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Badges',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (group.badges.isEmpty)
                        Text(
                          'Reach your goal to earn a badge!',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: group.badges.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final badges = group.badges.reversed.toList();
                              final chronologicalIndex =
                                  group.badges.length - 1 - index;
                              return _GroupBadgeChip(
                                badge: badges[index],
                                colorIndex: chronologicalIndex,
                              );
                            },
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Group code',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      group.code,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Group admin',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      adminName,
                      style: Theme.of(context).textTheme.bodyMedium,
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

String _adminDisplayName(List<GroupMember> members, String creatorUid) {
  for (final member in members) {
    if (member.uid == creatorUid) return member.displayName;
  }
  return 'Unknown';
}

class _GroupBadgeChip extends StatelessWidget {
  final GroupBadge badge;
  final int colorIndex;

  const _GroupBadgeChip({required this.badge, required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              BadgeIcon(value: badge.value, colorIndex: colorIndex),
              Positioned(
                left: -6,
                top: -6,
                child: Tooltip(
                  message: badge.gainedByName,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      initialsFor(badge.gainedByName),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatBadgeDate(badge.reachedAt),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
