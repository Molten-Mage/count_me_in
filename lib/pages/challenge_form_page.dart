import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/challenge.dart';
import '../services/challenge_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/error_dialog.dart';

class _ObjectiveInput {
  final String? id; // null in create mode; fixed in edit mode
  final TextEditingController nameController;
  final TextEditingController targetController;

  _ObjectiveInput({this.id, String name = '', int? target})
    : nameController = TextEditingController(text: name),
      targetController = TextEditingController(text: target?.toString() ?? '');

  void dispose() {
    nameController.dispose();
    targetController.dispose();
  }
}

/// Create-a-challenge and edit-objective-targets share this one form.
/// [existingChallenge] null = create mode (everything editable). Non-null =
/// edit mode: name/description/visibility/deadline are shown read-only
/// (matches what firestore.rules actually lets the creator change - only
/// `objectives`), objective names/count are fixed, only targets are
/// editable.
class ChallengeFormPage extends StatefulWidget {
  final ChallengeService challengeService;
  final Challenge? existingChallenge;

  const ChallengeFormPage({
    super.key,
    required this.challengeService,
    this.existingChallenge,
  });

  @override
  State<ChallengeFormPage> createState() => _ChallengeFormPageState();
}

class _ChallengeFormPageState extends State<ChallengeFormPage> {
  bool get _isEditing => widget.existingChallenge != null;

  late final _nameController = TextEditingController(
    text: widget.existingChallenge?.name ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existingChallenge?.description ?? '',
  );
  late final List<_ObjectiveInput> _objectives = widget.existingChallenge != null
      ? [
          for (final o in widget.existingChallenge!.objectives)
            _ObjectiveInput(id: o.id, name: o.name, target: o.target),
        ]
      : [_ObjectiveInput()];
  late ChallengeVisibility _visibility =
      widget.existingChallenge?.visibility ?? ChallengeVisibility.private;
  late bool _hasDeadline = widget.existingChallenge?.endsAt != null;
  DateTime? _deadline;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _deadline = widget.existingChallenge?.endsAt;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (final objective in _objectives) {
      objective.dispose();
    }
    super.dispose();
  }

  void _addObjective() {
    if (_objectives.length >= maxChallengeObjectives) return;
    setState(() => _objectives.add(_ObjectiveInput()));
  }

  void _removeObjective(int index) {
    if (_objectives.length <= 1) return;
    setState(() => _objectives.removeAt(index).dispose());
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    setState(() => _deadline = endOfDay);
  }

  bool get _isValid {
    if (_isEditing) {
      // Targets are optional (an open-ended tally is fine), so there's
      // nothing to validate beyond having at least one objective, which is
      // already guaranteed by construction.
      return true;
    }
    if (_nameController.text.trim().isEmpty) return false;
    if (_hasDeadline && _deadline == null) return false;
    return _objectives.every((o) => o.nameController.text.trim().isNotEmpty);
  }

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      if (_isEditing) {
        await widget.challengeService.updateObjectiveTargets(
          widget.existingChallenge!.id,
          [
            for (final objective in _objectives)
              ChallengeObjective(
                id: objective.id!,
                name: objective.nameController.text,
                target: int.tryParse(objective.targetController.text),
              ),
          ],
        );
      } else {
        await widget.challengeService.createChallenge(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          visibility: _visibility,
          endsAt: _hasDeadline ? _deadline : null,
          objectives: [
            for (final objective in _objectives)
              (
                name: objective.nameController.text.trim(),
                target: int.tryParse(objective.targetController.text),
              ),
          ],
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await showErrorDialog(
        context,
        title: _isEditing ? "Couldn't update objectives" : "Couldn't create challenge",
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  String _formattedDeadline(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Challenge' : 'Create a challenge'),
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
            if (_isEditing) ..._buildReadOnlyInfo(context) else ..._buildEditableInfo(context),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Objectives', style: Theme.of(context).textTheme.titleSmall),
                if (!_isEditing)
                  Text(
                    '${_objectives.length} / $maxChallengeObjectives',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _objectives.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isEditing)
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _objectives[i].nameController.text,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _objectives[i].nameController,
                          decoration: InputDecoration(
                            labelText: 'Objective ${i + 1}',
                            hintText: 'e.g. Push-ups',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _objectives[i].targetController,
                        decoration: const InputDecoration(labelText: 'Target'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            maxCounterInput.toString().length,
                          ),
                        ],
                      ),
                    ),
                    if (!_isEditing)
                      IconButton(
                        onPressed: _objectives.length > 1
                            ? () => _removeObjective(i)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
              ),
            if (!_isEditing)
              OutlinedButton.icon(
                onPressed: _objectives.length < maxChallengeObjectives
                    ? _addObjective
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add objective'),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEditableInfo(BuildContext context) {
    return [
      TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Name'),
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        decoration: const InputDecoration(labelText: 'Description (optional)'),
        maxLines: 2,
      ),
      const SizedBox(height: 20),
      Text('Who can join?', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<ChallengeVisibility>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ChallengeVisibility.private,
            label: Text('Private', maxLines: 1, overflow: TextOverflow.ellipsis),
            icon: Icon(Icons.lock_outlined),
          ),
          ButtonSegment(
            value: ChallengeVisibility.public,
            label: Text('Public', maxLines: 1, overflow: TextOverflow.ellipsis),
            icon: Icon(Icons.public),
          ),
        ],
        selected: {_visibility},
        onSelectionChanged: (selection) =>
            setState(() => _visibility = selection.first),
      ),
      const SizedBox(height: 4),
      Text(
        _visibility == ChallengeVisibility.public
            ? 'Anyone can find and join this challenge from Explore.'
            : "Only people with the invite code can join.",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.event_outlined),
        title: const Text('Set a deadline?'),
        value: _hasDeadline,
        onChanged: (value) => setState(() {
          _hasDeadline = value ?? false;
          if (_hasDeadline) _deadline ??= DateTime.now().add(const Duration(days: 7));
        }),
      ),
      if (_hasDeadline)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: Text(
            _deadline == null ? 'Choose a date' : _formattedDeadline(_deadline!),
          ),
          onTap: _pickDeadline,
        ),
    ];
  }

  List<Widget> _buildReadOnlyInfo(BuildContext context) {
    final subtleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return [
      Text(_nameController.text, style: Theme.of(context).textTheme.titleLarge),
      if (_descriptionController.text.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(_descriptionController.text, style: subtleStyle),
      ],
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(
            _visibility == ChallengeVisibility.public
                ? Icons.public
                : Icons.lock_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            _visibility == ChallengeVisibility.public ? 'Public' : 'Private',
            style: subtleStyle,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Icon(
            Icons.event_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            _deadline == null ? 'No deadline' : _formattedDeadline(_deadline!),
            style: subtleStyle,
          ),
        ],
      ),
    ];
  }
}
