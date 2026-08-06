import 'package:count_me_in/models/counter.dart';
import 'package:count_me_in/services/local_counter_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadCounters returns empty when nothing has been saved', () async {
    final storage = LocalCounterStorage();
    expect(await storage.loadCounters(), isEmpty);
  });

  test('saveCounters then loadCounters round-trips', () async {
    final storage = LocalCounterStorage();
    final counters = [
      Counter(id: '1', title: 'Water', count: 3, createdAt: DateTime(2026)),
      Counter(id: '2', title: 'Steps', target: 10000, createdAt: DateTime(2026)),
    ];

    await storage.saveCounters(counters);
    final loaded = await storage.loadCounters();

    expect(loaded, hasLength(2));
    expect(loaded[0].id, '1');
    expect(loaded[0].count, 3);
    expect(loaded[1].target, 10000);
  });

  test('saveCounters overwrites the previous list, not appends', () async {
    final storage = LocalCounterStorage();
    await storage.saveCounters([
      Counter(id: '1', title: 'First', createdAt: DateTime(2026)),
    ]);
    await storage.saveCounters([
      Counter(id: '2', title: 'Second', createdAt: DateTime(2026)),
    ]);

    final loaded = await storage.loadCounters();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, '2');
  });

  test('a fresh LocalCounterStorage instance reads what another wrote', () async {
    await LocalCounterStorage().saveCounters([
      Counter(id: '1', title: 'Water', createdAt: DateTime(2026)),
    ]);

    final loaded = await LocalCounterStorage().loadCounters();
    expect(loaded, hasLength(1));
  });
}
