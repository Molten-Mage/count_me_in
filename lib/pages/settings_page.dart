import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/theme_controller.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/delete_account_dialog.dart';
import 'privacy_policy_page.dart';

class SettingsPage extends StatelessWidget {
  final bool isGuest;
  final VoidCallback? onSignIn;

  const SettingsPage({super.key, this.isGuest = false, this.onSignIn});

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()),
    );
  }

  String _providerLabel(String providerId) {
    switch (providerId) {
      case 'google.com':
        return 'Google';
      case 'password':
        return 'Email & password';
      default:
        return providerId;
    }
  }

  Widget _buildThemeSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeController,
            builder: (context, mode, _) {
              return SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light', maxLines: 1, overflow: TextOverflow.ellipsis),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark', maxLines: 1, overflow: TextOverflow.ellipsis),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) =>
                    themeController.setThemeMode(selection.first),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Column(
          children: [
            const SizedBox(height: 8),
            _buildThemeSection(context),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Using Count Me In without an account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your counters are stored only on this device. They '
                        "won't sync, back up, or be visible on other devices.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: onSignIn,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                        child: const Text('Log in or create an account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () => _openPrivacyPolicy(context),
            ),
            // TODO: remove once Crashlytics reporting is confirmed working.
            if (kDebugMode) ...[
              _ForceCrashTile(
                label: 'Force native test crash',
                subtitle: 'Native crash — needs dSYM to symbolicate',
                onConfirm: () => FirebaseCrashlytics.instance.crash(),
              ),
              _ForceCrashTile(
                label: 'Force Dart test crash',
                subtitle: 'Dart exception — readable without dSYM',
                onConfirm: () =>
                    throw Exception('Crashlytics Dart test crash'),
              ),
            ],
          ],
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final providers = user?.providerData
        .map((info) => _providerLabel(info.providerId))
        .join(', ');
    final hasPassword =
        user?.providerData.any((info) => info.providerId == 'password') ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 32,
            child: Text(
              (user?.displayName?.isNotEmpty == true
                      ? user!.displayName!
                      : (user?.email ?? '?'))[0]
                  .toUpperCase(),
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              user?.displayName?.isNotEmpty == true
                  ? user!.displayName!
                  : 'No name set',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(user?.email ?? 'Unknown'),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Signed in with'),
            subtitle: Text(
              providers?.isNotEmpty == true ? providers! : 'Unknown',
            ),
          ),
          if (hasPassword)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change password'),
              onTap: () => showChangePasswordDialog(context),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(),
          ),
          const SizedBox(height: 8),
          _buildThemeSection(context),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () => _openPrivacyPolicy(context),
          ),
          // TODO: remove once Crashlytics reporting is confirmed working.
          if (kDebugMode) ...[
            _ForceCrashTile(
              label: 'Force native test crash',
              subtitle: 'Native crash — needs dSYM to symbolicate',
              onConfirm: () => FirebaseCrashlytics.instance.crash(),
            ),
            _ForceCrashTile(
              label: 'Force Dart test crash',
              subtitle: 'Dart exception — readable without dSYM',
              onConfirm: () => throw Exception('Crashlytics Dart test crash'),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Sign out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => showConfirmDeleteDialog(
              context,
              title: 'Sign out',
              message: 'Are you sure you want to sign out?',
              confirmLabel: 'Sign out',
              onConfirm: () => FirebaseAuth.instance.signOut(),
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete account',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }
}

// TODO: temporary, for verifying Crashlytics reporting end-to-end — remove
// this whole widget (and both usages of it) once confirmed working.
class _ForceCrashTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onConfirm;

  const _ForceCrashTile({
    required this.label,
    required this.subtitle,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.bug_report_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: Text(subtitle),
      onTap: () => showConfirmDeleteDialog(
        context,
        title: label,
        message:
            'This immediately crashes the app to test Crashlytics '
            "reporting. Relaunch the app afterward and check the "
            'Firebase console in a few minutes.',
        confirmLabel: 'Crash now',
        onConfirm: onConfirm,
      ),
    );
  }
}
