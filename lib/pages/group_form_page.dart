import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../widgets/error_dialog.dart';

class _CounterInput {
  // Null for a counter not yet saved to Firestore (a brand new one, in
  // either create mode or added while editing an existing group) -
  // _submit assigns it a real id from the unused counter_0..counter_9 pool
  // at save time. Non-null for one that already exists server-side.
  final String? id;
  final TextEditingController nameController;

  _CounterInput({this.id, String name = ''})
    : nameController = TextEditingController(text: name);

  void dispose() => nameController.dispose();
}

/// Create-a-group and edit-a-group share this one full-screen form -
/// unlike challenges, name/description/tally-control stay editable after
/// creation too, matching what firestore.rules already lets the creator
/// change. Counters - names, and the set of counters (add/remove) - are
/// fully editable in both modes, same shape as ChallengeFormPage's
/// objectives editor.
class GroupFormPage extends StatefulWidget {
  final GroupService groupService;
  final Group? existingGroup;
  // Only offered in edit mode; null hides the "Group Members" button.
  final VoidCallback? onShowMembers;

  const GroupFormPage({
    super.key,
    required this.groupService,
    this.existingGroup,
    this.onShowMembers,
  });

  @override
  State<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends State<GroupFormPage> {
  bool get _isEditing => widget.existingGroup != null;

  late final _nameController = TextEditingController(
    text: widget.existingGroup?.name ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existingGroup?.description ?? '',
  );
  late final List<_CounterInput> _counters = widget.existingGroup != null
      ? [
          for (final c in widget.existingGroup!.counters)
            _CounterInput(id: c.id, name: c.name),
        ]
      : [_CounterInput()];
  late TallyControl _tallyControl =
      widget.existingGroup?.tallyControl ?? TallyControl.member;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (final counter in _counters) {
      counter.dispose();
    }
    super.dispose();
  }

  void _addCounter() {
    if (_counters.length >= maxGroupCounters) return;
    setState(() => _counters.add(_CounterInput()));
  }

  void _removeCounter(int index) {
    if (_counters.length <= 1) return;
    setState(() => _counters.removeAt(index).dispose());
  }

  void _reorderCounters(int oldIndex, int newIndex) {
    setState(() {
      final counter = _counters.removeAt(oldIndex);
      _counters.insert(newIndex, counter);
    });
  }

  bool get _isValid {
    final countersValid = _counters.every(
      (c) => c.nameController.text.trim().isNotEmpty,
    );
    return _nameController.text.trim().isNotEmpty && countersValid;
  }

  /// Assigns a real id to any newly-added counter (id == null) from
  /// whichever `counter_0`..`counter_9` slots the group's existing
  /// counters aren't already using - same id-pool approach as
  /// ChallengeFormPage._resolveEditedObjectives.
  List<GroupCounter> _resolveEditedCounters() {
    final usedIds = _counters.map((c) => c.id).whereType<String>().toSet();
    final freeIds = [
      for (var i = 0; i < maxGroupCounters; i++)
        if (!usedIds.contains('counter_$i')) 'counter_$i',
    ];
    var nextFreeId = 0;
    return [
      for (final counter in _counters)
        GroupCounter(
          id: counter.id ?? freeIds[nextFreeId++],
          name: counter.nameController.text.trim(),
        ),
    ];
  }

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final adminControlled = _tallyControl == TallyControl.admin;
    final freeForAll = _tallyControl == TallyControl.free;

    try {
      if (_isEditing) {
        await widget.groupService.updateGroup(
          widget.existingGroup!.id,
          name: name,
          description: description,
          adminControlled: adminControlled,
          freeForAll: freeForAll,
        );
        await widget.groupService.updateCounters(
          widget.existingGroup!.id,
          _resolveEditedCounters(),
        );
      } else {
        await widget.groupService.createGroup(
          name: name,
          description: description,
          counterNames: [
            for (final counter in _counters) counter.nameController.text.trim(),
          ],
          adminControlled: adminControlled,
          freeForAll: freeForAll,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await showErrorDialog(
        context,
        title: _isEditing ? "Couldn't save group" : "Couldn't create group",
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit group' : 'Create a group'),
        actions: [
          TextButton(
            onPressed: (_isValid && !_isSubmitting) ? _submit : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: !_isEditing,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Counters', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${_counters.length} / $maxGroupCounters',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _counters.length,
              onReorderItem: _reorderCounters,
              itemBuilder: (context, i) {
                final counter = _counters[i];
                return Padding(
                  key: ValueKey(counter),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: counter.nameController,
                          decoration: InputDecoration(
                            labelText: 'Counter ${i + 1}',
                            hintText: 'e.g. Steps',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        onPressed: _counters.length > 1
                            ? () => _removeCounter(i)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: _counters.length < maxGroupCounters
                  ? _addCounter
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Add counter'),
            ),
            const SizedBox(height: 20),
            Text(
              'Who controls tallies?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<TallyControl>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: TallyControl.member,
                  label: Text(
                    'Member',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  icon: Icon(Icons.people_outline),
                ),
                ButtonSegment(
                  value: TallyControl.admin,
                  label: Text(
                    'Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  icon: Icon(Icons.shield_outlined),
                ),
                ButtonSegment(
                  value: TallyControl.free,
                  label: Text(
                    'Free',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                TallyControl.admin =>
                  'Only you will be able to update members\' tallies.',
                TallyControl.free => 'Everyone can update everyone\'s tally.',
                TallyControl.member =>
                  'Each member can update their own tally.',
              },
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_isEditing && widget.onShowMembers != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onShowMembers!();
                },
                icon: const Icon(Icons.group_outlined),
                label: const Text('Group Members'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
