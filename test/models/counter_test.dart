import 'package:count_me_in/models/counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1);

  group('Counter.progress', () {
    test('is null with no target', () {
      final counter = Counter(
        id: '1',
        title: 'Water',
        count: 5,
        createdAt: createdAt,
      );
      expect(counter.progress, isNull);
    });

    test('is null with a zero or negative target', () {
      final counter = Counter(
        id: '1',
        title: 'Water',
        target: 0,
        count: 5,
        createdAt: createdAt,
      );
      expect(counter.progress, isNull);
    });

    test('is the count/target ratio', () {
      final counter = Counter(
        id: '1',
        title: 'Water',
        target: 10,
        count: 4,
        createdAt: createdAt,
      );
      expect(counter.progress, 0.4);
    });

    test('clamps at 1 when count exceeds target', () {
      final counter = Counter(
        id: '1',
        title: 'Water',
        target: 10,
        count: 15,
        createdAt: createdAt,
      );
      expect(counter.progress, 1.0);
    });
  });

  group('Counter.incremented', () {
    test('adds the amount to count', () {
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        count: 3,
        createdAt: createdAt,
      );
      expect(counter.incremented(5).count, 8);
    });

    test('awards a badge on crossing the target', () {
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        target: 10,
        count: 8,
        createdAt: createdAt,
      );
      final updated = counter.incremented(2);
      expect(updated.count, 10);
      expect(updated.badges, hasLength(1));
      expect(updated.badges.single.value, 10);
    });

    test('does not award a badge for undershooting the target', () {
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        target: 10,
        count: 5,
        createdAt: createdAt,
      );
      final updated = counter.incremented(2);
      expect(updated.count, 7);
      expect(updated.badges, isEmpty);
    });

    test('does not re-award a badge for a target already earned', () {
      // Simulates: reached 10 once (badge awarded), then decremented back
      // down below target without the target changing. Crossing it again
      // shouldn't add a second badge for the same value.
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        target: 10,
        count: 8,
        badges: [CounterBadge(value: 10, reachedAt: createdAt)],
        createdAt: createdAt,
      );
      final updated = counter.incremented(2);
      expect(updated.count, 10);
      expect(updated.badges, hasLength(1));
    });

    test('awards a new badge after the target is raised and re-crossed', () {
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        target: 20,
        count: 18,
        badges: [CounterBadge(value: 10, reachedAt: createdAt)],
        createdAt: createdAt,
      );
      final updated = counter.incremented(2);
      expect(updated.badges, hasLength(2));
      expect(updated.badges.map((b) => b.value), [10, 20]);
    });

    test('caps badges at 15, dropping the oldest', () {
      final oldBadges = List.generate(
        15,
        (i) => CounterBadge(value: (i + 1) * 10, reachedAt: createdAt),
      );
      final counter = Counter(
        id: '1',
        title: 'Push-ups',
        target: 160,
        count: 158,
        badges: oldBadges,
        createdAt: createdAt,
      );
      final updated = counter.incremented(2);
      expect(updated.badges, hasLength(15));
      expect(updated.badges.first.value, 20); // the original 10 was dropped
      expect(updated.badges.last.value, 160);
    });
  });

  group('Counter JSON round-trip', () {
    test('toJson/fromJson preserves all fields', () {
      final counter = Counter(
        id: 'abc',
        title: 'Water',
        target: 8,
        count: 3,
        notes: 'Drink more',
        badges: [CounterBadge(value: 8, reachedAt: createdAt)],
        createdAt: createdAt,
      );
      final restored = Counter.fromJson(counter.toJson());

      expect(restored.id, counter.id);
      expect(restored.title, counter.title);
      expect(restored.target, counter.target);
      expect(restored.count, counter.count);
      expect(restored.notes, counter.notes);
      expect(restored.badges.single.value, 8);
      expect(restored.badges.single.reachedAt, createdAt);
      expect(restored.createdAt, createdAt);
    });

    test('fromJson defaults missing notes/badges', () {
      final counter = Counter(id: 'abc', title: 'Water', createdAt: createdAt);
      final json = counter.toJson()
        ..remove('notes')
        ..remove('badges');
      final restored = Counter.fromJson(json);
      expect(restored.notes, '');
      expect(restored.badges, isEmpty);
    });
  });

  group('Counter.withDetails / copyWith', () {
    test('withDetails updates title and target only', () {
      final counter = Counter(
        id: '1',
        title: 'Old',
        count: 5,
        createdAt: createdAt,
      );
      final updated = counter.withDetails(title: 'New', target: 10);
      expect(updated.title, 'New');
      expect(updated.target, 10);
      expect(updated.count, 5);
      expect(updated.id, '1');
    });

    test('copyWith only overrides given fields', () {
      final counter = Counter(
        id: '1',
        title: 'Water',
        target: 10,
        count: 5,
        createdAt: createdAt,
      );
      final updated = counter.copyWith(count: 7);
      expect(updated.count, 7);
      expect(updated.title, 'Water');
      expect(updated.target, 10);
    });
  });
}
