import 'package:count_me_in/widgets/confirm_delete_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required VoidCallback onConfirm,
    String confirmLabel = 'Delete',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showConfirmDeleteDialog(
              context,
              title: 'Delete counter',
              message: 'Are you sure you want to delete "Water"?',
              confirmLabel: confirmLabel,
              onConfirm: onConfirm,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title and message', (tester) async {
    await pumpDialog(tester, onConfirm: () {});
    expect(find.text('Delete counter'), findsOneWidget);
    expect(find.text('Are you sure you want to delete "Water"?'), findsOneWidget);
  });

  testWidgets('Cancel dismisses without calling onConfirm', (tester) async {
    var confirmed = false;
    await pumpDialog(tester, onConfirm: () => confirmed = true);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.text('Delete counter'), findsNothing);
  });

  testWidgets('confirmLabel calls onConfirm and dismisses', (tester) async {
    var confirmed = false;
    await pumpDialog(tester, onConfirm: () => confirmed = true);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
    expect(find.text('Delete counter'), findsNothing);
  });

  testWidgets('custom confirmLabel is used for the button text', (tester) async {
    await pumpDialog(tester, onConfirm: () {}, confirmLabel: 'Leave');
    expect(find.text('Leave'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });
}
