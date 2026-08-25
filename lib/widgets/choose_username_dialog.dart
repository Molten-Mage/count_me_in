import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// Shown right after a first-time Google/Apple sign-in so new users can set
/// how their name appears to others - the same displayName field Settings'
/// "Edit name" dialog writes to, just surfaced immediately at account
/// creation instead of making them find it in Settings afterward (mirrors
/// the "Username (optional)" field already offered on the email sign-up
/// form). Purely optional: skipping, or saving blank, leaves whatever name
/// the provider already gave (if any) untouched.
Future<void> showChooseUsernameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _ChooseUsernameDialog(),
  );
}

class _ChooseUsernameDialog extends StatefulWidget {
  const _ChooseUsernameDialog();

  @override
  State<_ChooseUsernameDialog> createState() => _ChooseUsernameDialogState();
}

class _ChooseUsernameDialogState extends State<_ChooseUsernameDialog> {
  late final _nameController = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    await user?.updateDisplayName(name);
    await user?.reload();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Choose a username'),
          const SizedBox(height: 8),
          Text(
            "Shown to others instead of the name from your account. "
            "Optional - you can change it later in Settings.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Username (optional)',
            ),
            autofocus: true,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Skip',
            onSecondary: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(),
            primaryLabel: 'Save',
            onPrimary: _isSubmitting ? null : _save,
          ),
        ],
      ),
    );
  }
}
