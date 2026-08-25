import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/challenge_service.dart';
import '../services/group_service.dart';
import 'app_dialog.dart';

Future<void> showEditNameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _EditNameDialog(),
  );
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog();

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _nameController = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Enter a name');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      await user.updateDisplayName(name);
      await user.reload();
      await _propagateToMemberships(name);
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.message ?? 'Something went wrong.';
      });
    }
  }

  /// Fans the new name out to every group/challenge the caller already
  /// belongs to - those store their own denormalized `displayName`
  /// snapshot that otherwise never updates on its own. Best-effort: the
  /// rename itself (above) already succeeded by the time this runs, so a
  /// hiccup here shouldn't block closing the dialog or be reported as the
  /// rename having failed.
  Future<void> _propagateToMemberships(String name) async {
    try {
      await GroupService().propagateDisplayNameChange(name);
    } catch (e) {
      if (kDebugMode) debugPrint('[EditNameDialog] group propagation failed: $e');
    }
    try {
      await ChallengeService().propagateDisplayNameChange(name);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EditNameDialog] challenge propagation failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Edit name'),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Cancel',
            onSecondary: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(),
            primaryLabel: 'Save',
            onPrimary: _isSubmitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
