import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/error_dialog.dart';

/// Create-a-group and edit-a-group share this one full-screen form -
/// unlike challenges, every field here (name, description, goal, tally
/// control) stays editable after creation too, matching what
/// firestore.rules already lets the creator change, so there's no
/// create/edit split in which fields show or are read-only.
class GroupFormPage extends StatefulWidget {
  final GroupService groupService;
  final Group? existingGroup;
  // Only meaningful in edit mode - the goal-target field's lower bound, so
  // you can't set a target below what the group has already collectively
  // reached. Always 0 in create mode, since nothing's been tallied yet.
  final int currentTotal;
  // Only offered in edit mode; null hides the "Group Members" button.
  final VoidCallback? onShowMembers;

  const GroupFormPage({
    super.key,
    required this.groupService,
    this.existingGroup,
    this.currentTotal = 0,
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
  late final _targetController = TextEditingController(
    text: widget.existingGroup?.target?.toString() ?? '',
  );
  late bool _hasTarget = widget.existingGroup?.target != null;
  late TallyControl _tallyControl =
      widget.existingGroup?.tallyControl ?? TallyControl.member;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final target = int.tryParse(_targetController.text);
    final isTargetValid =
        !_hasTarget ||
        (target != null &&
            target > widget.currentTotal &&
            target <= maxCounterInput);
    return _nameController.text.trim().isNotEmpty && isTargetValid;
  }

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final target = _hasTarget ? int.tryParse(_targetController.text) : null;
    final adminControlled = _tallyControl == TallyControl.admin;
    final freeForAll = _tallyControl == TallyControl.free;

    try {
      if (_isEditing) {
        await widget.groupService.updateGroup(
          widget.existingGroup!.id,
          name: name,
          description: description,
          target: target,
          adminControlled: adminControlled,
          freeForAll: freeForAll,
        );
      } else {
        await widget.groupService.createGroup(
          name: name,
          description: description,
          target: target,
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
                      'Must be between ${widget.currentTotal + 1} and '
                      '$maxCounterInput',
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
