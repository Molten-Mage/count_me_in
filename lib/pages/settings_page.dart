import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/challenge_templates.dart';
import '../services/analytics_service.dart';
import '../services/challenge_service.dart';
import '../services/premium_service.dart';
import '../services/purchase_service.dart';
import '../services/theme_controller.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/delete_account_dialog.dart';
import '../widgets/edit_name_dialog.dart';
import '../widgets/premium_upsell_dialog.dart';
import 'notification_settings_page.dart';
import 'privacy_policy_page.dart';

class SettingsPage extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onSignIn;

  const SettingsPage({super.key, this.isGuest = false, this.onSignIn});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Created once rather than inline in build()'s `stream:` argument - a
  // fresh Stream instance on every rebuild forces StreamBuilder to
  // unsubscribe and resubscribe, briefly dropping back to its initial state
  // before the new subscription's first snapshot arrives. That
  // subscribe/wait/reconnect cycle was the actual "blink" opening the edit
  // name dialog seemed to cause - not anything about the dialog itself.
  late final Stream<User?> _userChangesStream =
      FirebaseAuth.instance.userChanges();

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()),
    );
  }

  void _openNotificationSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NotificationSettingsPage(),
      ),
    );
  }

  Future<void> _restorePurchases(BuildContext context) async {
    await purchaseService.restore();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for previous purchases…')),
      );
    }
  }

  String _providerLabel(String providerId) {
    switch (providerId) {
      case 'google.com':
        return 'Google';
      case 'apple.com':
        return 'Apple';
      case 'password':
        return 'Email & password';
      default:
        return providerId;
    }
  }

  Widget _buildPremiumSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: premiumStatus,
        builder: (context, isPremium, _) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPremium ? 'Premium' : 'Basic',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Premium unlocks unlimited counters, groups, and '
                    'challenges, and removes ads.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!isPremium) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => showPremiumUpsellDialog(
                          context,
                          source: 'settings',
                        ),
                        child: const Text('Get Premium'),
                      ),
                    ),
                  ],
                  if (isPremium && kDebugMode) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => premiumStatus.setPremium(false),
                        child: const Text('Debug: downgrade to Basic'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
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
    if (widget.isGuest) {
      return Scaffold(
        // This page has no text field of its own - every one lives inside a
        // dialog pushed on top (edit name, change password, etc.), several
        // of which autofocus and bring up the keyboard immediately. Without
        // this, the default resize-to-avoid-keyboard behavior kicks in for
        // *this* page's Scaffold too (MediaQuery's viewInsets are inherited
        // globally, not scoped to whichever route actually owns the
        // focused field), visibly shifting/jittering the whole settings
        // list the instant the dialog's keyboard slides up.
        resizeToAvoidBottomInset: false,
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
                        onPressed: widget.onSignIn,
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
            const _PrivacyOptionsTile(),
            // TODO: remove once Crashlytics reporting is confirmed working.
            if (kDebugMode) ...[
              _ForceCrashTile(
                label: 'Force native test crash',
                subtitle: 'Native crash - needs dSYM to symbolicate',
                onConfirm: () => FirebaseCrashlytics.instance.crash(),
              ),
              _ForceCrashTile(
                label: 'Force Dart test crash',
                subtitle: 'Dart exception - readable without dSYM',
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
      // See the guest-branch Scaffold above for why this is off - same
      // reasoning applies here, and this is the branch the "Edit name"
      // dialog (which autofocuses) actually opens from.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // userChanges() (unlike authStateChanges()) also fires on profile
          // edits like updateDisplayName, so the avatar/name refresh right
          // after the edit-name dialog saves without any manual setState
          // plumbing here.
          StreamBuilder<User?>(
            stream: _userChangesStream,
            initialData: user,
            builder: (context, snapshot) {
              final current = snapshot.data ?? user;
              final name = current?.displayName?.isNotEmpty == true
                  ? current!.displayName!
                  : null;
              return Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      child: Text(
                        (name ?? current?.email ?? '?')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name ?? 'No name set',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit name',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showEditNameDialog(context),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildPremiumSection(context),
          const SizedBox(height: 8),
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
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            onTap: () => _openNotificationSettings(context),
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
          const _PrivacyOptionsTile(),
          // TODO: remove once Crashlytics reporting is confirmed working.
          if (kDebugMode) ...[
            _ForceCrashTile(
              label: 'Force native test crash',
              subtitle: 'Native crash - needs dSYM to symbolicate',
              onConfirm: () => FirebaseCrashlytics.instance.crash(),
            ),
            _ForceCrashTile(
              label: 'Force Dart test crash',
              subtitle: 'Dart exception - readable without dSYM',
              onConfirm: () => throw Exception('Crashlytics Dart test crash'),
            ),
            const _GenerateChallengeTile(),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restore purchases'),
            onTap: () => _restorePurchases(context),
          ),
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
              onConfirm: () {
                analyticsService.logSignOut();
                FirebaseAuth.instance.signOut();
              },
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

/// Only shown when Google's UMP SDK says the user is somewhere that
/// requires offering a way to revisit their ad consent choice (EEA/UK) -
/// Google's policy requires this entry point exist wherever it applies,
/// not that it always be shown.
class _PrivacyOptionsTile extends StatelessWidget {
  const _PrivacyOptionsTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrivacyOptionsRequirementStatus>(
      future: ConsentInformation.instance.getPrivacyOptionsRequirementStatus(),
      builder: (context, snapshot) {
        if (snapshot.data != PrivacyOptionsRequirementStatus.required) {
          return const SizedBox.shrink();
        }
        return ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Ad privacy options'),
          onTap: () => ConsentForm.showPrivacyOptionsForm((_) {}),
        );
      },
    );
  }
}

// TODO: temporary, for verifying Crashlytics reporting end-to-end - remove
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

// Admin ops tool: generates one random official public challenge per tap,
// drawn from lib/data/challenge_templates.dart. Not tied to a fixed set -
// safe to tap repeatedly to build up Explore's pool of official content
// over time. The generating account is never left as a member of what it
// creates (see ChallengeService.createOfficialChallenge).
class _GenerateChallengeTile extends StatelessWidget {
  const _GenerateChallengeTile();

  Future<void> _generate(BuildContext context) async {
    final random = Random();
    final category = challengeCategories[random.nextInt(challengeCategories.length)];
    final name = category.flavorNames[random.nextInt(category.flavorNames.length)];
    final description = category.descriptions[random.nextInt(category.descriptions.length)];
    final objectiveCount = min(2 + random.nextInt(3), category.objectives.length);
    final chosen = (List.of(category.objectives)..shuffle(random)).take(objectiveCount);
    final durationDays = challengeDurationDaysOptions[random.nextInt(
      challengeDurationDaysOptions.length,
    )];

    try {
      final challenge = await ChallengeService().createOfficialChallenge(
        name: name,
        description: description,
        endsAt: DateTime.now().add(Duration(days: durationDays)),
        objectives: [
          for (final o in chosen)
            (
              name: o.name,
              target: o.minTarget + random.nextInt(o.maxTarget - o.minTarget + 1),
            ),
        ],
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generated "${challenge.name}" (${category.name}, '
              '${chosen.length} objectives, $durationDays days).',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate challenge: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('Generate official challenge'),
      subtitle: const Text('Creates one random public challenge from the template library'),
      onTap: () => _generate(context),
    );
  }
}
