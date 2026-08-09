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
import '../widgets/goal_reached_dialog.dart';
import '../widgets/tally_stepper.dart';

class GroupDetailPage extends StatefulWidget {
  final Group group;

  const GroupDetailPage({super.key, required this.group});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final _groupService = GroupService();
  final _stepController = TextEditingController(text: '1');
  int _currentTotal = 0;
  int? _lastKnownTotal;

  @override
  void dispose() {
    _stepController.dispose();
    super.dispose();
  }

  int get _step {
    final step = int.tryParse(_stepController.text);
    return (step == null || step <= 0) ? 1 : step;
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
                      'link if you already have the app: '
                      'countmein://join/group/${group.code}',
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

  Future<void> _showEditGroupDialog(Group group, int currentTotal) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EditGroupDialog(
        group: group,
        currentTotal: currentTotal,
        onSave: (name, target) =>
            _groupService.updateGroup(group.id, name: name, target: target),
        onShowMembers: () => _showGroupMembersDialog(group),
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
      stream: _groupService.streamGroup(widget.group.id),
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
                          _showEditGroupDialog(group, _currentTotal),
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
                      title: Text('Invite code'),
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
              stream: _groupService.streamMembers(group.id),
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
                final members = List<GroupMember>.of(rawMembers)
                  ..sort((a, b) => b.tally.compareTo(a.tally));
                int total = 0;
                for (final member in members) {
                  total += member.tally;
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
                          ? 'Team goal: $total / $target'
                          : 'Team total: $total',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (target != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (total / target).clamp(0, 1).toDouble(),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(child: Text('${i + 1}')),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      members[i].displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${members[i].tally}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (group.adminControlled
                                  ? group.createdBy == myUid
                                  : members[i].uid == myUid) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TallyStepper(
                                      stepController: _stepController,
                                      onDecrement: () => _groupService
                                          .decrementMemberTally(
                                            group.id,
                                            members[i].uid,
                                            _step,
                                          ),
                                      onIncrement: () => _groupService
                                          .incrementMemberTally(
                                            group.id,
                                            members[i].uid,
                                            _step,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
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

class _EditGroupDialog extends StatefulWidget {
  final Group group;
  final int currentTotal;
  final Future<void> Function(String name, int? target) onSave;
  final VoidCallback onShowMembers;

  const _EditGroupDialog({
    required this.group,
    required this.currentTotal,
    required this.onSave,
    required this.onShowMembers,
  });

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final _nameController = TextEditingController(text: widget.group.name);
  late final _targetController = TextEditingController(
    text: widget.group.target?.toString() ?? '',
  );
  late bool _hasTarget = widget.group.target != null;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);

    final target = int.tryParse(_targetController.text);
    await widget.onSave(name, _hasTarget ? target : null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final target = int.tryParse(_targetController.text);
    final isTargetValid =
        !_hasTarget ||
        (target != null &&
            target > widget.currentTotal &&
            target <= maxCounterInput);
    final isNameValid = _nameController.text.trim().isNotEmpty;

    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Edit group'),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.flag_outlined),
            title: const Text('Add goal?'),
            value: _hasTarget,
            onChanged: (value) {
              setState(() => _hasTarget = value ?? false);
            },
          ),
          if (_hasTarget)
            TextField(
              controller: _targetController,
              decoration: InputDecoration(
                labelText: 'Target count',
                hintText: 'e.g. ${nextTenAbove(widget.currentTotal)}',
                helperText:
                    'Must be between ${widget.currentTotal + 1} and $maxCounterInput',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  maxCounterInput.toString().length,
                ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onShowMembers();
              },
              icon: const Icon(Icons.group_outlined),
              label: const Text('Group Members'),
            ),
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Cancel',
            onSecondary: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(),
            primaryLabel: 'Save',
            onPrimary: (isTargetValid && isNameValid && !_isSubmitting)
                ? _submit
                : null,
          ),
        ],
      ),
    );
  }
}
