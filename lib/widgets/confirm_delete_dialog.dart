import 'package:flutter/material.dart';

import 'app_dialog.dart';

Future<void> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  required VoidCallback onConfirm,
  String confirmLabel = 'Delete',
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AppDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDialogTitle(title),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            AppDialogActions(
              secondaryLabel: 'Cancel',
              onSecondary: () => Navigator.of(context).pop(),
              primaryLabel: confirmLabel,
              destructive: true,
              onPrimary: () {
                onConfirm();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    },
  );
}
