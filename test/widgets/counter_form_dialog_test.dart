import 'package:count_me_in/models/counter.dart';
import 'package:count_me_in/widgets/counter_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    Counter? existing,
    required void Function(String, int?) onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCounterFormDialog(
              context,
              existing: existing,
              onSubmit: onSubmit,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows "Add counter" / "Add" for a new counter', (tester) async {
    await pumpDialog(tester, onSubmit: (_, _) {});
    expect(find.text('Add counter'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('shows "Edit counter" / "Save" and pre-fills for an existing counter', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      existing: Counter(
        id: '1',
        title: 'Water',
        target: 8,
        createdAt: DateTime(2026),
      ),
      onSubmit: (_, _) {},
    );

    expect(find.text('Edit counter'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    // "Add goal?" checkbox is pre-checked, so the target field is visible.
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('Add is disabled until a name is entered', (tester) async {
    await pumpDialog(tester, onSubmit: (_, _) {});

    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add'),
    );
    expect(addButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Push-ups');
    await tester.pump();

    final addButtonAfter = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add'),
    );
    expect(addButtonAfter.onPressed, isNotNull);
  });

  testWidgets('submitting without a goal calls onSubmit with a null target', (
    tester,
  ) async {
    String? submittedTitle;
    int? submittedTarget;
    await pumpDialog(
      tester,
      onSubmit: (title, target) {
        submittedTitle = title;
        submittedTarget = target;
      },
    );

    await tester.enterText(find.byType(TextField).first, 'Push-ups');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(submittedTitle, 'Push-ups');
    expect(submittedTarget, isNull);
  });

  testWidgets('enabling "Add goal?" reveals the target field', (tester) async {
    await pumpDialog(tester, onSubmit: (_, _) {});

    expect(find.text('Target count'), findsNothing);
    await tester.tap(find.text('Add goal?'));
    await tester.pumpAndSettle();
    expect(find.text('Target count'), findsOneWidget);
  });

  testWidgets('a target at or below the current count keeps Add disabled', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      existing: Counter(id: '1', title: 'Steps', count: 10, createdAt: DateTime(2026)),
      onSubmit: (_, _) {},
    );

    await tester.tap(find.text('Add goal?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Target count'), '10');
    await tester.pump();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('submitting with a valid goal calls onSubmit with the target', (
    tester,
  ) async {
    int? submittedTarget;
    await pumpDialog(
      tester,
      onSubmit: (_, target) => submittedTarget = target,
    );

    await tester.enterText(find.byType(TextField).first, 'Steps');
    await tester.tap(find.text('Add goal?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Target count'), '10000');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(submittedTarget, 10000);
  });

  testWidgets('Cancel closes without calling onSubmit', (tester) async {
    var called = false;
    await pumpDialog(tester, onSubmit: (_, _) => called = true);

    await tester.enterText(find.byType(TextField).first, 'Push-ups');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Add counter'), findsNothing);
  });
}
