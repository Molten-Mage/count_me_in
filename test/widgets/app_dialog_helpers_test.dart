import 'package:count_me_in/widgets/app_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextTenAbove', () {
    test('rounds up to the next multiple of ten', () {
      expect(nextTenAbove(0), 10);
      expect(nextTenAbove(1), 10);
      expect(nextTenAbove(9), 10);
    });

    test('a value already on a multiple of ten still goes to the next one', () {
      expect(nextTenAbove(10), 20);
      expect(nextTenAbove(100), 110);
    });

    test('works for larger values', () {
      expect(nextTenAbove(999), 1000);
      expect(nextTenAbove(1001), 1010);
    });
  });
}
