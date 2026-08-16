import 'package:count_me_in/models/counter.dart';
import 'package:count_me_in/services/counter_storage.dart';

/// In-memory [CounterStorage] for widget tests - no SharedPreferences, no
/// Firestore, just a list that mirrors what a real implementation would
/// persist.
class FakeCounterStorage implements CounterStorage {
  FakeCounterStorage([List<Counter> initial = const []])
    : _counters = List.of(initial);

  final List<Counter> _counters;
  int saveCount = 0;

  @override
  Future<List<Counter>> loadCounters() async => List.of(_counters);

  @override
  Future<void> saveCounters(List<Counter> counters) async {
    saveCount++;
    _counters
      ..clear()
      ..addAll(counters);
  }
}
