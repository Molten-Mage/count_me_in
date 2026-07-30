import 'dart:math';

import 'package:flutter/material.dart';

import '../models/counter.dart';
import '../services/counter_storage.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/counter_form_dialog.dart';
import '../widgets/goal_reached_dialog.dart';
import '../widgets/tally_stepper.dart';
import 'counter_detail_page.dart';

class HomePage extends StatefulWidget {
  final CounterStorage storage;

  const HomePage({super.key, required this.storage});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CounterStorage _storage = widget.storage;
  final Map<String, TextEditingController> _stepControllers = {};
  List<Counter> _counters = [];
  bool _loading = true;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadCounters();
  }

  @override
  void dispose() {
    for (final controller in _stepControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _stepControllerFor(Counter counter) {
    return _stepControllers.putIfAbsent(
      counter.id,
      () => TextEditingController(text: '1'),
    );
  }

  int _stepFor(Counter counter) {
    final step = int.tryParse(_stepControllerFor(counter).text);
    return (step == null || step <= 0) ? 1 : step;
  }

  Future<void> _loadCounters() async {
    final counters = await _storage.loadCounters();
    setState(() {
      _counters = counters;
      _loading = false;
    });
  }

  Future<void> _addCounter(String title, int? target) async {
    final counter = Counter(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      target: target,
      createdAt: DateTime.now(),
    );
    setState(() => _counters = [..._counters, counter]);
    await _storage.saveCounters(_counters);
  }

  Future<void> _increment(
    Counter counter,
    int amount, {
    bool celebrate = true,
  }) async {
    final current = _counters.firstWhere(
      (c) => c.id == counter.id,
      orElse: () => counter,
    );
    final updated = current.incremented(amount);
    final newlyEarnedBadge = updated.badges.length > current.badges.length
        ? updated.badges.last
        : null;

    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id == counter.id) updated else c,
      ];
    });
    await _storage.saveCounters(_counters);
    if (!mounted) return;

    if (celebrate && newlyEarnedBadge != null) {
      showGoalReachedDialog(
        context,
        message:
            '"${updated.title}" hit ${newlyEarnedBadge.value}. Badge earned!',
        badgeValue: newlyEarnedBadge.value,
        badgeColorIndex: updated.badges.length - 1,
        currentCount: updated.count,
        onSetNewGoal: (newTarget) {
          _updateCounter(updated, updated.title, newTarget);
        },
      );
    }
  }

  Future<void> _decrement(Counter counter, int amount) async {
    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id == counter.id)
            c.copyWith(count: max(c.count - amount, 0))
          else
            c,
      ];
    });
    await _storage.saveCounters(_counters);
  }

  Future<void> _deleteCounter(Counter counter) async {
    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id != counter.id) c,
      ];
    });
    _stepControllers.remove(counter.id)?.dispose();
    await _storage.saveCounters(_counters);
  }

  Future<void> _updateCounter(
    Counter counter,
    String title,
    int? target,
  ) async {
    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id == counter.id)
            c.withDetails(title: title, target: target)
          else
            c,
      ];
    });
    await _storage.saveCounters(_counters);
  }

  Future<void> _updateNotes(Counter counter, String notes) async {
    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id == counter.id) c.copyWith(notes: notes) else c,
      ];
    });
    await _storage.saveCounters(_counters);
  }

  Future<void> _resetCounter(Counter counter, bool clearBadges) async {
    setState(() {
      _counters = [
        for (final c in _counters)
          if (c.id == counter.id)
            c.copyWith(count: 0, badges: clearBadges ? const [] : null)
          else
            c,
      ];
    });
    await _storage.saveCounters(_counters);
  }

  Future<void> _reorderCounters(int oldIndex, int newIndex) async {
    setState(() {
      final counter = _counters.removeAt(oldIndex);
      _counters.insert(newIndex, counter);
    });
    await _storage.saveCounters(_counters);
  }

  void _confirmDeleteCounter(Counter counter) {
    showConfirmDeleteDialog(
      context,
      title: 'Delete counter',
      message:
          'Are you sure you want to delete "${counter.title}"? '
          'This can\'t be undone.',
      onConfirm: () => _deleteCounter(counter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Counters'),
        actions: [
          if (_counters.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(_editMode ? Icons.done : Icons.edit_outlined),
              tooltip: _editMode ? 'Done' : 'Edit',
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _counters.isEmpty
            ? const Center(child: Text('No counters yet. Tap + to add one.'))
            : _editMode
            ? ReorderableListView.builder(
                padding: const EdgeInsets.all(8),
                buildDefaultDragHandles: false,
                itemCount: _counters.length,
                onReorderItem: _reorderCounters,
                itemBuilder: (context, index) {
                  final counter = _counters[index];
                  return Card(
                    key: ValueKey(counter.id),
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(
                        counter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        onPressed: () => _confirmDeleteCounter(counter),
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        tooltip: 'Delete counter',
                      ),
                    ),
                  );
                },
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _counters.length,
                itemBuilder: (context, index) {
                  final counter = _counters[index];
                  final progress = counter.progress;
                  return Card(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CounterDetailPage(
                              counter: counter,
                              onIncrement: (amount) => _increment(
                                counter,
                                amount,
                                celebrate: false,
                              ),
                              onDecrement: (amount) =>
                                  _decrement(counter, amount),
                              onEdit: (title, target) =>
                                  _updateCounter(counter, title, target),
                              onNotesChanged: (notes) =>
                                  _updateNotes(counter, notes),
                              onReset: (clearBadges) =>
                                  _resetCounter(counter, clearBadges),
                              onDelete: () => _deleteCounter(counter),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    counter.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  progress == null
                                      ? '${counter.count}'
                                      : '${counter.count} / ${counter.target}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (progress != null)
                              LinearProgressIndicator(value: progress),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TallyStepper(
                                  stepController: _stepControllerFor(counter),
                                  onDecrement: () =>
                                      _decrement(counter, _stepFor(counter)),
                                  onIncrement: () =>
                                      _increment(counter, _stepFor(counter)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_page_fab',
        onPressed: () => showCounterFormDialog(
          context,
          onSubmit: (title, target) => _addCounter(title, target),
        ),
        tooltip: 'Add counter',
        child: const Icon(Icons.add),
      ),
    );
  }
}
