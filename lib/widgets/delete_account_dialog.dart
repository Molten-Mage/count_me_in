import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/group_service.dart';
import 'app_dialog.dart';

const _confirmPhrase = 'DELETE';

Future<void> showDeleteAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _DeleteAccountDialog(),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmController = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isConfirmed => _confirmController.text.trim() == _confirmPhrase;

  Future<void> _submit() async {
    if (_isSubmitting || !_isConfirmed) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final groupService = GroupService();
      final groups = await groupService.streamMyGroups().first;
      for (final group in groups) {
        await groupService.leaveGroup(group.id);
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();
      await analyticsService.logAccountDeleted();
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.code == 'requires-recent-login'
            ? 'For your security, please sign out and sign back in, '
                  'then try deleting your account again.'
            : (e.message ?? 'Something went wrong. Please try again.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle('Delete account'),
          const SizedBox(height: 8),
          Text(
            'This permanently deletes your account, your personal '
            "counters, and your membership in any groups. This can't "
            'be undone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Type $_confirmPhrase to confirm'),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
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
            primaryLabel: _isSubmitting ? 'Deleting…' : 'Delete',
            destructive: true,
            onPrimary: (_isConfirmed && !_isSubmitting) ? _submit : null,
          ),
        ],
      ),
    );
  }
}
