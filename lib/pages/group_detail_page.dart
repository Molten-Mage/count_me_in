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
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/editable_tally.dart';
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
  // Displayed immediately on tap, ahead of the member-tally write actually
  // landing and this page's StreamBuilder catching up - otherwise every
  // tap waits on a full round trip before showing anything, which makes
  // rapid tapping feel unresponsive. Keyed by counter id, then member uid.
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
  final Map<String, Map<String, int>> _tallyOverrides = {};
  // Row order is captured once per counter from the first snapshot of this
  // visit to the page, then held fixed for that counter - re-sorting live
  // as confirmed tallies cross each other would otherwise make rows jump
  // around under a member's finger mid-session. Rank numbers (CircleAvatar
  // below) still update live against the real standings; only which row a
  // member occupies stays put until the page is reopened. Keyed by
  // counter id; a counter's list is null until its first snapshot arrives.
  final Map<String, List<String>> _frozenMemberOrderByCounter = {};

  // One ExpansibleController per counter (created lazily, kept for the
  // page's lifetime) so the "Collapse all"/"Expand all" button can drive
  // every card at once - an ExpansionTile is otherwise uncontrolled, so
  // there'd be no way to force all of them open/closed from outside.
  // Mirrors each tile's own current state, updated via its
  // onExpansionChanged - missing entries mean "never touched", which
  // defaults to true (expanded) to match the tiles' own initiallyExpanded.
  final Map<String, ExpansibleController> _counterControllers = {};
  final Map<String, bool> _counterExpanded = {};

  ExpansibleController _counterController(String counterId) =>
      _counterControllers.putIfAbsent(counterId, () => ExpansibleController());

  bool _allCountersCollapsed(List<GroupCounter> counters) =>
      counters.every((c) => !(_counterExpanded[c.id] ?? true));

  void _toggleAllCounters(List<GroupCounter> counters) {
    final expand = _allCountersCollapsed(counters);
    for (final counter in counters) {
      if (expand) {
        _counterController(counter.id).expand();
      } else {
        _counterController(counter.id).collapse();
      }
    }
    setState(() {
      for (final counter in counters) {
        _counterExpanded[counter.id] = expand;
      }
    });
  }

  /// Orders [rawMembers] by the frozen order for [counterId], capturing
  /// that order (by real tally on this counter, highest first) on the
  /// first call this visit. A member who joins mid-visit is appended in
  /// whatever order the stream delivered them, and starts tracking their
  /// own frozen position from then on; a member who leaves just drops out
  /// of the rendered list without disturbing anyone else's position.
  List<GroupMember> _orderedMembers(
    String counterId,
    List<GroupMember> rawMembers,
  ) {
    final byUid = {for (final m in rawMembers) m.uid: m};
    var frozen = _frozenMemberOrderByCounter[counterId];
    if (frozen == null) {
      final initial = List<GroupMember>.of(rawMembers)
        ..sort((a, b) => b.tallyFor(counterId).compareTo(a.tallyFor(counterId)));
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
    _frozenMemberOrderByCounter[counterId] = frozen;
    return ordered;
  }

  int _effectiveTally(GroupMember member, String counterId) {
    final override = _tallyOverrides[counterId]?[member.uid];
    if (override == null) return member.tallyFor(counterId);
    final real = member.tallyFor(counterId);
    if (override == real) {
      // The stream has caught up - safe to drop now, displays identically
      // either way. No setState: this is cache cleanup, not a value
      // change (this frame renders the same number regardless).
      _tallyOverrides[counterId]?.remove(member.uid);
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

  void _clearOverrideAfterDelay(String counterId, String uid) {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _tallyOverrides[counterId]?.remove(uid));
    });
  }

  Future<void> _incrementMember(
    Group group,
    GroupMember member,
    String counterId,
    int amount,
  ) async {
    setState(
      () => (_tallyOverrides[counterId] ??= {})[member.uid] =
          _effectiveTally(member, counterId) + amount,
    );
    try {
      await _groupService.incrementMemberTally(
        group.id,
        member.uid,
        counterId,
        amount,
      );
      _clearOverrideAfterDelay(counterId, member.uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides[counterId]?.remove(member.uid));
      _showSaveError();
    }
  }

  Future<void> _decrementMember(
    Group group,
    GroupMember member,
    String counterId,
    int amount,
  ) async {
    setState(() {
      (_tallyOverrides[counterId] ??= {})[member.uid] = max(
        _effectiveTally(member, counterId) - amount,
        0,
      );
    });
    try {
      await _groupService.decrementMemberTally(
        group.id,
        member.uid,
        counterId,
        amount,
      );
      _clearOverrideAfterDelay(counterId, member.uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tallyOverrides[counterId]?.remove(member.uid));
      _showSaveError();
    }
  }

  /// Directly editing a member's tally field is expressed as a delta
  /// against their current (optimistic-aware) tally, then routed through
  /// [_incrementMember]/[_decrementMember] - reuses their existing
  /// optimistic-update and rollback logic rather than duplicating it for a
  /// third mutation path.
  Future<void> _setMemberTally(
    Group group,
    GroupMember member,
    String counterId,
    int newValue,
  ) async {
    final delta = newValue - _effectiveTally(member, counterId);
    if (delta > 0) {
      await _incrementMember(group, member, counterId, delta);
    } else if (delta < 0) {
      await _decrementMember(group, member, counterId, -delta);
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

  Future<void> _openEditGroupPage(Group group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroupFormPage(
          groupService: _groupService,
          existingGroup: group,
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
                              subtitle: Text(
                                '${member.tallies.values.fold<int>(0, (a, b) => a + b)} total',
                              ),
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
                      value: () => _openEditGroupPage(group),
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
                final adminName = _adminDisplayName(rawMembers, group.createdBy);

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (group.description.isNotEmpty) ...[
                      Text(
                        group.description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (group.counters.length > 1) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _toggleAllCounters(group.counters),
                          icon: Icon(
                            _allCountersCollapsed(group.counters)
                                ? Icons.unfold_more
                                : Icons.unfold_less,
                          ),
                          label: Text(
                            _allCountersCollapsed(group.counters)
                                ? 'Expand all'
                                : 'Collapse all',
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    for (final counter in group.counters)
                      _GroupCounterCard(
                        key: ValueKey(counter.id),
                        counter: counter,
                        group: group,
                        members: _orderedMembers(counter.id, rawMembers),
                        rankedMembers: rawMembers,
                        myUid: myUid,
                        effectiveTally: _effectiveTally,
                        controller: _counterController(counter.id),
                        onExpansionChanged: (expanded) => setState(
                          () => _counterExpanded[counter.id] = expanded,
                        ),
                        onChanged: (member, value) => _setMemberTally(
                          group,
                          member,
                          counter.id,
                          value,
                        ),
                      ),
                    const SizedBox(height: 12),
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

/// One counter, expandable in place - collapsed shows just the name and
/// the combined total across every member; expanded shows every member's
/// own tally for this counter, editable wherever [group.tallyControl]
/// permits it. Same expand-in-place pattern as `_ObjectiveCard` on the
/// challenge detail page, but showing every member (not just the viewer's
/// own row) since who's allowed to edit whom depends on tally-control
/// mode, not just "is this me".
class _GroupCounterCard extends StatelessWidget {
  final GroupCounter counter;
  final Group group;
  // Frozen display order for this counter (see _orderedMembers).
  final List<GroupMember> members;
  // Unfrozen, for computing live ranks.
  final List<GroupMember> rankedMembers;
  final String? myUid;
  final int Function(GroupMember member, String counterId) effectiveTally;
  final ExpansibleController controller;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(GroupMember member, int value) onChanged;

  const _GroupCounterCard({
    super.key,
    required this.counter,
    required this.group,
    required this.members,
    required this.rankedMembers,
    required this.myUid,
    required this.effectiveTally,
    required this.controller,
    required this.onExpansionChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final combinedTotal = members.fold<int>(
      0,
      (sum, member) => sum + effectiveTally(member, counter.id),
    );
    final ranked = List<GroupMember>.of(rankedMembers)
      ..sort(
        (a, b) => b.tallyFor(counter.id).compareTo(a.tallyFor(counter.id)),
      );
    final rankByUid = {
      for (var i = 0; i < ranked.length; i++) ranked[i].uid: i + 1,
    };

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        controller: controller,
        onExpansionChanged: onExpansionChanged,
        title: Row(
          children: [
            Expanded(
              child: Text(
                counter.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '$combinedTotal',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final member in members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(child: Text('${rankByUid[member.uid]}')),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (switch (group.tallyControl) {
                    TallyControl.admin => group.createdBy == myUid,
                    TallyControl.free => true,
                    TallyControl.member => member.uid == myUid,
                  })
                    EditableTally(
                      value: effectiveTally(member, counter.id),
                      onChanged: (value) => onChanged(member, value),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    )
                  else
                    Text(
                      '${effectiveTally(member, counter.id)}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
