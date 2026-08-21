import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../models/group_member.dart';
import '../services/group_service.dart';
import '../services/premium_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/error_dialog.dart';
import '../widgets/paywall_dialog.dart';
import 'group_detail_page.dart';

class GroupsListPage extends StatefulWidget {
  final bool active;

  const GroupsListPage({super.key, this.active = true});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage> {
  final _groupService = GroupService();
  final _premiumService = PremiumService();
  List<String> _groupOrder = [];
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadGroupOrder();
  }

  @override
  void didUpdateWidget(covariant GroupsListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _editMode) {
      setState(() => _editMode = false);
    }
  }

  Future<void> _loadGroupOrder() async {
    final order = await _groupService.loadGroupOrder();
    if (!mounted) return;
    setState(() => _groupOrder = order);
  }

  // Groups not yet present in the saved order (e.g. newly created or
  // joined) sort after the ones that are, in whatever order the stream
  // returned them.
  List<Group> _sortedGroups(List<Group> groups) {
    final orderIndex = {
      for (var i = 0; i < _groupOrder.length; i++) _groupOrder[i]: i,
    };
    final sorted = [...groups];
    sorted.sort((a, b) {
      final aIndex = orderIndex[a.id];
      final bIndex = orderIndex[b.id];
      if (aIndex == null && bIndex == null) return 0;
      if (aIndex == null) return 1;
      if (bIndex == null) return -1;
      return aIndex.compareTo(bIndex);
    });
    return sorted;
  }

  Future<void> _reorderGroups(
    List<Group> currentOrder,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...currentOrder];
    final group = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, group);
    final newOrder = reordered.map((g) => g.id).toList();
    setState(() => _groupOrder = newOrder);
    await _groupService.saveGroupOrder(newOrder);
  }

  void _confirmDeleteOrLeaveGroup(Group group) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isCreator = group.createdBy == myUid;
    final isLastMember = group.memberIds.length <= 1;

    if (isCreator && !isLastMember) {
      showConfirmDeleteDialog(
        context,
        title: 'Delete group',
        message:
            'Are you sure you want to delete "${group.name}"? '
            'This removes it for everyone in the group.',
        onConfirm: () => _groupService.deleteGroup(group.id),
      );
      return;
    }

    final message = !isCreator
        ? 'Are you sure you want to leave "${group.name}"?'
        : 'You\'re the only member left. Leaving will delete '
              '"${group.name}".';

    showConfirmDeleteDialog(
      context,
      title: 'Leave group',
      message: message,
      confirmLabel: 'Leave',
      onConfirm: () => _groupService.leaveGroup(group.id),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CreateGroupDialog(onCreate: _createGroup),
    );
  }

  // Closes the dialog immediately (assuming success) rather than waiting on
  // the network round-trip; shows an error popup on top of the groups list
  // in the rare case it actually fails.
  Future<void> _createGroup(
    String name,
    int? target,
    bool adminControlled,
    bool freeForAll,
  ) async {
    try {
      await _groupService.createGroup(
        name: name,
        target: target,
        adminControlled: adminControlled,
        freeForAll: freeForAll,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        title: "Couldn't create group",
        message: e.message ?? 'Something went wrong. Please try again.',
      );
    } catch (_) {
      if (!mounted) return;
      showErrorDialog(
        context,
        title: "Couldn't create group",
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> _showJoinGroupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _JoinGroupDialog(onJoin: _joinGroup),
    );
  }

  // Same optimistic-close approach as create: pop immediately, only surface
  // an error popup if joining actually failed (bad code, network, etc.).
  // Dismissing the error popup reopens the join dialog so the user can
  // immediately retry (e.g. fix a typo'd code) without going back through
  // the FAB menu.
  Future<void> _joinGroup(String code) async {
    try {
      await _groupService.joinGroupByCode(code);
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
    await showErrorDialog(context, title: "Couldn't join group", message: message);
    if (!mounted) return;
    _showJoinGroupDialog();
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
                title: const Text('Create a group'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final canAdd = await _premiumService.canAddOne();
                  if (!mounted) return;
                  if (!canAdd) {
                    showPaywallDialog(context);
                    return;
                  }
                  _showCreateGroupDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_add),
                title: const Text('Join a group'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final canAdd = await _premiumService.canAddOne();
                  if (!mounted) return;
                  if (!canAdd) {
                    showPaywallDialog(context);
                    return;
                  }
                  _showJoinGroupDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          StreamBuilder<List<Group>>(
            stream: _groupService.streamMyGroups(),
            builder: (context, snapshot) {
              if ((snapshot.data ?? const []).isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                onPressed: () => setState(() => _editMode = !_editMode),
                icon: Icon(_editMode ? Icons.done : Icons.edit_outlined),
                tooltip: _editMode ? 'Done' : 'Edit',
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Group>>(
        stream: _groupService.streamMyGroups(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Something went wrong: ${snapshot.error}'),
            );
          }
          final groups = _sortedGroups(snapshot.data ?? []);
          if (groups.isEmpty) {
            return const Center(
              child: Text('No groups yet. Tap + to create or join one.'),
            );
          }
          if (_editMode) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              buildDefaultDragHandles: false,
              itemCount: groups.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderGroups(groups, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final group = groups[index];
                final myUid = FirebaseAuth.instance.currentUser?.uid;
                final isCreator = group.createdBy == myUid;
                return Card(
                  key: ValueKey(group.id),
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      onPressed: () => _confirmDeleteOrLeaveGroup(group),
                      icon: Icon(
                        isCreator ? Icons.delete_outline : Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: isCreator ? 'Delete group' : 'Leave group',
                    ),
                  ),
                );
              },
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                child: ListTile(
                  title: Text(group.name),
                  subtitle: StreamBuilder<List<GroupMember>>(
                    stream: _groupService.streamMembers(group.id),
                    builder: (context, snapshot) {
                      final members = snapshot.data ?? const <GroupMember>[];
                      final total = members.fold<int>(
                        0,
                        (sum, member) => sum + member.tally,
                      );
                      final target = group.target;
                      return Text(
                        target != null
                            ? 'Group progress: $total/$target'
                            : 'Group counter: $total',
                      );
                    },
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(group.code),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GroupDetailPage(group: group),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'groups_list_page_fab',
        onPressed: _showAddOptions,
        tooltip: 'Add group',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  final void Function(String name, int? target, bool adminControlled, bool freeForAll)
  onCreate;

  const _CreateGroupDialog({required this.onCreate});

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  bool _hasTarget = false;
  TallyControl _tallyControl = TallyControl.member;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const currentTotal = 0;
    final target = int.tryParse(_targetController.text);
    final isTargetValid =
        !_hasTarget ||
        (target != null &&
            target > currentTotal &&
            target <= maxCounterInput);
    final isNameValid = _nameController.text.trim().isNotEmpty;

    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Create a group'),
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
                hintText: 'e.g. ${nextTenAbove(currentTotal)}',
                helperText:
                    'Must be between ${currentTotal + 1} and $maxCounterInput',
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
          Text('Who controls tallies?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<TallyControl>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: TallyControl.member,
                label: Text('Member', maxLines: 1, overflow: TextOverflow.ellipsis),
                icon: Icon(Icons.people_outline),
              ),
              ButtonSegment(
                value: TallyControl.admin,
                label: Text('Admin', maxLines: 1, overflow: TextOverflow.ellipsis),
                icon: Icon(Icons.shield_outlined),
              ),
              ButtonSegment(
                value: TallyControl.free,
                label: Text('Free', maxLines: 1, overflow: TextOverflow.ellipsis),
                icon: Icon(Icons.all_inclusive),
              ),
            ],
            selected: {_tallyControl},
            onSelectionChanged: (selection) =>
                setState(() => _tallyControl = selection.first),
          ),
          const SizedBox(height: 4),
          Text(
            switch (_tallyControl) {
              TallyControl.admin => 'Only you will be able to update members\' tallies.',
              TallyControl.free => 'Everyone can update everyone\'s tally.',
              TallyControl.member => 'Each member can update their own tally.',
            },
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Cancel',
            onSecondary: () => Navigator.of(context).pop(),
            primaryLabel: 'Create',
            onPrimary: (isTargetValid && isNameValid)
                ? () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;

                    Navigator.of(context).pop();
                    widget.onCreate(
                      name,
                      _hasTarget ? target : null,
                      _tallyControl == TallyControl.admin,
                      _tallyControl == TallyControl.free,
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _JoinGroupDialog extends StatefulWidget {
  final void Function(String code) onJoin;

  const _JoinGroupDialog({required this.onJoin});

  @override
  State<_JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<_JoinGroupDialog> {
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
          const AppDialogTitle('Join a group'),
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
