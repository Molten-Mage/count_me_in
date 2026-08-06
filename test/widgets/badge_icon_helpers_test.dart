import 'package:count_me_in/widgets/badge_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCompactCount', () {
    test('leaves small numbers as-is', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(999), '999');
    });

    test('abbreviates thousands with "k"', () {
      expect(formatCompactCount(1000), '1k');
      expect(formatCompactCount(1400), '1.4k');
      expect(formatCompactCount(999999), '1000k'); // just under 1M
    });

    test('abbreviates millions with "M"', () {
      expect(formatCompactCount(1000000), '1M');
      expect(formatCompactCount(2500000), '2.5M');
    });

    test('drops a trailing .0', () {
      expect(formatCompactCount(2000), '2k');
      expect(formatCompactCount(3000000), '3M');
    });
  });

  group('formatBadgeDate', () {
    test('formats as "Mon D"', () {
      expect(formatBadgeDate(DateTime(2026, 7, 22)), 'Jul 22');
      expect(formatBadgeDate(DateTime(2026, 1, 1)), 'Jan 1');
      expect(formatBadgeDate(DateTime(2026, 12, 31)), 'Dec 31');
    });
  });

  group('initialsFor', () {
    test('two words uses first letter of each', () {
      expect(initialsFor('Johanna Jennekvist'), 'JJ');
    });

    test('single word uses its first two letters', () {
      expect(initialsFor('Anonymous'), 'AN');
    });

    test('single-letter word uses just that letter', () {
      expect(initialsFor('J'), 'J');
    });

    test('empty/whitespace-only name falls back to "?"', () {
      expect(initialsFor(''), '?');
      expect(initialsFor('   '), '?');
    });

    test('extra whitespace between words is ignored', () {
      expect(initialsFor('  Jo   Jenne  '), 'JJ');
    });

    test('more than two words only uses the first two', () {
      expect(initialsFor('Jo Middle Jenne'), 'JM');
    });
  });
}
