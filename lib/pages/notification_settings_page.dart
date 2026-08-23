import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/notification_preferences_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _service = NotificationPreferencesService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: StreamBuilder<NotificationPreferences>(
        stream: _service.stream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final prefs = snapshot.data!;
          // Individual toggles stay visible but disabled (and keep showing
          // their real stored value, not forced off) while the master
          // switch is off - so turning it back on restores whatever was
          // set before, same pattern as iOS/Android's own notification
          // settings.
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('All notifications'),
                subtitle: const Text(
                  'Turn every notification below on or off at once',
                ),
                value: prefs.allEnabled,
                onChanged: (value) => _service.setAllEnabled(value),
              ),
              const Divider(height: 1),
              const _SectionHeader('Groups'),
              SwitchListTile(
                secondary: const Icon(Icons.groups_outlined),
                title: const Text('Group progress'),
                subtitle: const Text(
                  "Notify me when someone in a group I'm in reaches 80% "
                  'of the goal',
                ),
                value: prefs.groupThreshold,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setGroupThreshold(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.emoji_events_outlined),
                title: const Text('Group goal reached'),
                subtitle: const Text(
                  "Notify me when a group I'm in hits its goal",
                ),
                value: prefs.groupGoalReached,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setGroupGoalReached(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_off_outlined),
                title: const Text('Group gone quiet'),
                subtitle: const Text(
                  "Notify me when a group I'm in hasn't had any activity "
                  'in a while',
                ),
                value: prefs.groupQuiet,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setGroupQuiet(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.person_add_alt_outlined),
                title: const Text('Someone joins'),
                subtitle: const Text(
                  'Notify me when someone joins a group I\'m in',
                ),
                value: prefs.groupMemberJoined,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setGroupMemberJoined(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Someone joins your group'),
                subtitle: const Text(
                  'Notify me when someone joins a group I created',
                ),
                value: prefs.myGroupMemberJoined,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setMyGroupMemberJoined(value)
                    : null,
              ),
              const _SectionHeader('Challenges'),
              SwitchListTile(
                secondary: const Icon(Icons.flag_outlined),
                title: const Text('Challenge halfway point'),
                subtitle: const Text(
                  "Notify me when a challenge I'm in reaches its "
                  'halfway point',
                ),
                value: prefs.challengeHalfway,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setChallengeHalfway(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.timer_outlined),
                title: const Text('Challenge deadline approaching'),
                subtitle: const Text(
                  "Notify me when a challenge I'm in is close to ending",
                ),
                value: prefs.challengeDeadline,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setChallengeDeadline(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.leaderboard_outlined),
                title: const Text('Passed on the leaderboard'),
                subtitle: const Text(
                  'Notify me when someone passes my overall progress in '
                  'a challenge',
                ),
                value: prefs.challengePassed,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setChallengePassed(value)
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Someone joins your challenge'),
                subtitle: const Text(
                  'Notify me when someone joins a challenge I created',
                ),
                value: prefs.myChallengeMemberJoined,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setMyChallengeMemberJoined(value)
                    : null,
              ),
              const _SectionHeader('Personal counters'),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_paused_outlined),
                title: const Text('Inactivity reminders'),
                subtitle: const Text(
                  "Remind me about a personal counter I haven't updated "
                  'in a while',
                ),
                value: prefs.counterInactivity,
                onChanged: prefs.allEnabled
                    ? (value) => _service.setCounterInactivity(value)
                    : null,
              ),
              if (kDebugMode) ...[
                const _SectionHeader('Debug'),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Send test notification'),
                  subtitle: const Text(
                    'Sends a real push through the full pipeline (Firestore '
                    "-> Cloud Function -> FCM) to this account's own device",
                  ),
                  onTap: _sendTestNotification,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('pushNotifications').add({
        'recipientUid': uid,
        'type': 'debug_test',
        'title': 'Test notification',
        'body': 'If you see this, push delivery is working.',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sent - check the Cloud Function logs or wait for the push.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
