import 'dart:math';

import 'package:flutter/material.dart';

import '../models/counter.dart';
import '../widgets/app_dialog.dart';
import '../widgets/badge_icon.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/counter_form_dialog.dart';
import '../widgets/goal_reached_dialog.dart';
import '../widgets/tally_stepper.dart';
import 'counter_notes_page.dart';

class CounterDetailPage extends StatefulWidget {
  final Counter counter;
  final void Function(int amount) onIncrement;
  final void Function(int amount) onDecrement;
  final void Function(String title, int? target) onEdit;
  final void Function(String notes) onNotesChanged;
  final void Function(bool clearBadges) onReset;
  final VoidCallback onDelete;

  const CounterDetailPage({
    super.key,
    required this.counter,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEdit,
    required this.onNotesChanged,
    required this.onReset,
    required this.onDelete,
  });

  @override
  State<CounterDetailPage> createState() => _CounterDetailPageState();
}

class _CounterDetailPageState extends State<CounterDetailPage> {
  late Counter _counter = widget.counter;
  final _stepController = TextEditingController(text: '1');

  @override
  void dispose() {
    _stepController.dispose();
    super.dispose();
  }

  int get _step {
    final step = int.tryParse(_stepController.text);
    return (step == null || step <= 0) ? 1 : step;
  }

  void _increment() {
    final amount = _step;
    widget.onIncrement(amount);
    final updated = _counter.incremented(amount);
    final newlyEarnedBadge = updated.badges.length > _counter.badges.length
        ? updated.badges.last
        : null;
    setState(() => _counter = updated);

    if (newlyEarnedBadge != null) {
      showGoalReachedDialog(
        context,
        message:
            '"${_counter.title}" hit ${newlyEarnedBadge.value}. Badge earned!',
        badgeValue: newlyEarnedBadge.value,
        badgeColorIndex: updated.badges.length - 1,
        currentCount: _counter.count,
        onSetNewGoal: (newTarget) {
          widget.onEdit(_counter.title, newTarget);
          setState(
            () => _counter = _counter.withDetails(
              title: _counter.title,
              target: newTarget,
            ),
          );
        },
      );
    }
  }

  void _decrement() {
    final amount = _step;
    widget.onDecrement(amount);
    setState(
      () =>
          _counter = _counter.copyWith(count: max(_counter.count - amount, 0)),
    );
  }

  Future<void> _confirmReset() async {
    bool clearBadges = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AppDialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppDialogTitle('Reset counter'),
                  const SizedBox(height: 8),
                  Text(
                    'Are you sure you want to reset "${_counter.title}" to 0?',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Also clear badges'),
                    value: clearBadges,
                    onChanged: (value) {
                      setDialogState(() => clearBadges = value ?? false);
                    },
                  ),
                  const SizedBox(height: 24),
                  AppDialogActions(
                    secondaryLabel: 'Cancel',
                    onSecondary: () => Navigator.of(context).pop(),
                    primaryLabel: 'Reset',
                    onPrimary: () {
                      widget.onReset(clearBadges);
                      setState(
                        () => _counter = _counter.copyWith(
                          count: 0,
                          badges: clearBadges ? const [] : null,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openNotes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CounterNotesPage(
          initialNotes: _counter.notes,
          onSave: (notes) {
            widget.onNotesChanged(notes);
            setState(() => _counter = _counter.copyWith(notes: notes));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _counter.progress;

    return Scaffold(
      appBar: AppBar(
        title: Text(_counter.title),
        actions: [
          PopupMenuButton<VoidCallback>(
            tooltip: 'More options',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem<VoidCallback>(
                value: () => showCounterFormDialog(
                  context,
                  existing: _counter,
                  onSubmit: (title, target) {
                    widget.onEdit(title, target);
                    setState(
                      () => _counter = _counter.withDetails(
                        title: title,
                        target: target,
                      ),
                    );
                  },
                ),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem<VoidCallback>(
                value: () => showConfirmDeleteDialog(
                  context,
                  title: 'Delete counter',
                  message:
                      'Are you sure you want to delete "${_counter.title}"?',
                  onConfirm: () {
                    widget.onDelete();
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
                    'Delete',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        progress == null
                            ? '${_counter.count}'
                            : '${_counter.count} / ${_counter.target}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: TallyStepper(
                          stepController: _stepController,
                          onDecrement: _decrement,
                          onIncrement: _increment,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openNotes,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _counter.notes.isEmpty ? 'Add notes...' : _counter.notes,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: _counter.notes.isEmpty
                        ? TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.restart_alt,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Reset counter',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: _confirmReset,
              ),
              if (_counter.target != null) ...[
                const SizedBox(height: 32),
                Text('Badges', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_counter.badges.isEmpty)
                  Text(
                    'Reach your goal to earn a badge!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _counter.badges.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final badges = _counter.badges.reversed.toList();
                        final chronologicalIndex =
                            _counter.badges.length - 1 - index;
                        return _BadgeChip(
                          badge: badges[index],
                          colorIndex: chronologicalIndex,
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final CounterBadge badge;
  final int colorIndex;

  const _BadgeChip({required this.badge, required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BadgeIcon(value: badge.value, colorIndex: colorIndex),
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
