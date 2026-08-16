import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Last updated: August 9, 2026',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _Paragraph(
            'Count Me In ("the app") is a personal goal and group tally '
            "tracker. This policy explains what data the app collects, how "
            "it's used, and who it's shared with.",
          ),
          const _Section('Data we collect'),
          const _Paragraph(
            'If you use the app without an account (guest mode): your '
            'personal counters, targets, notes, and badges are stored '
            'locally only, using standard on-device storage, and are '
            'never sent to us or anyone else. This applies to your '
            'counter data specifically - guest mode does not exempt you '
            'from the app usage analytics and advertising data described '
            'below, which apply to every user of the app, account or not.',
          ),
          const _Paragraph('If you create an account, we additionally collect:'),
          const _Bullet(
            'Account info - an email address and password (if you sign up '
            'with email), or your name and email as shared by Google or '
            'Apple (if you sign in with one of those). Passwords are '
            'handled entirely by our authentication provider (Firebase '
            'Authentication) - the app never sees or stores your password '
            'itself.',
          ),
          const _Bullet(
            'Display name - the name shown to other members of any group '
            'you join. This comes from your Google/Apple account, or a '
            'username you choose when registering with email.',
          ),
          const _Bullet(
            'App data - the personal counters, targets, notes, and badges '
            'you create, and any groups you create or join, including '
            'group names, invite codes, targets, member tallies, and '
            'badges earned.',
          ),
          const _Paragraph('For every user, account or guest, we collect:'),
          const _Bullet(
            'Usage analytics - we use Firebase Analytics to understand how '
            'the app is used: which features get tapped (e.g. creating a '
            'counter, reaching a goal, joining a group), general '
            'app-open/session activity, and basic device/OS information. '
            'This is tied to an anonymous device identifier, not your name '
            'or email, and never includes the actual content of your '
            'counters or notes.',
          ),
          const _Bullet(
            "Advertising data - unless you're on the paid Premium tier "
            '(which removes ads entirely), the app shows banner ads served '
            'by Google AdMob. AdMob and its partners may use advertising '
            "identifiers (Apple's IDFA or Android's advertising ID) and "
            'similar technologies to serve and measure ads, and - only '
            'with your consent - to personalize them.',
          ),
          const _Section('Ad consent'),
          const _Paragraph(
            'Where required by law (the EEA, UK, and similar '
            "jurisdictions), the app shows a consent form - provided by "
            "Google's User Messaging Platform - the first time it would "
            'show you an ad, letting you choose whether ads can be '
            "personalized. On iOS, the app also asks for Apple's App "
            'Tracking Transparency permission before using identifiers '
            "that track you across other apps. Declining either doesn't "
            "stop the app from working - you'll just see non-personalized "
            'ads instead.',
          ),
          const _Paragraph(
            "If you're somewhere this choice applies to you, you can "
            'change it anytime from Settings → Ad privacy options.',
          ),
          const _Section('How we use your data'),
          const _Paragraph(
            'Your account and app data are used to provide the app\'s '
            'functionality: syncing your counters across your devices, and '
            "running shared group tallies and leaderboards for the groups "
            "you're part of. Usage analytics is used to understand which "
            'features people actually use so we can improve the app. '
            'Advertising data is used to serve and measure the ads that '
            'support the free tier, and - only with consent where '
            'required - to personalize them.',
          ),
          const _Section('Who your data is shared with'),
          const _Bullet(
            'Other app users: if you join or create a group, your display '
            'name and tally within that group are visible to other people '
            'using the app (so they can see group progress and who earned '
            'which badge). Your email address and personal (non-group) '
            'counters are never shown to other users.',
          ),
          const _Bullet(
            'Service providers: we use Google Firebase (Authentication, '
            'Cloud Firestore, and Analytics) to sign you in, store your '
            'data securely, and understand app usage. We use Google AdMob '
            'to serve ads. We use Google Sign-In and/or Sign in with Apple '
            'if you choose those sign-in methods. These providers process '
            "data on our behalf under their own privacy policies (Google's "
            "and Apple's).",
          ),
          const _Paragraph(
            'We do not sell your data. Beyond the ad-serving and analytics '
            "described above, we don't share your data with anyone else "
            'for advertising or marketing purposes.',
          ),
          const _Section('Data retention and deletion'),
          const _Paragraph(
            'You can delete your account at any time from Settings → '
            'Delete account. This permanently removes your personal '
            "counters, your account, and your membership in any groups "
            "you're part of. This can't be undone. Group data you created "
            "(e.g. a group's name or shared tallies) may persist for "
            'remaining group members after you leave or delete your '
            'account, since it\'s shared, not personal, data.',
          ),
          const _Section("Children's privacy"),
          const _Paragraph(
            'Count Me In is not directed at children under 13, and we do '
            'not knowingly collect personal information from children '
            'under 13.',
          ),
          const _Section('Security'),
          const _Paragraph(
            "We rely on Firebase's infrastructure and security practices "
            'to protect your data, including encryption in transit. No '
            'method of storage or transmission is 100% secure, but we '
            'take reasonable steps to protect your information.',
          ),
          const _Section('Changes to this policy'),
          const _Paragraph(
            'If this policy changes, we\'ll update the "Last updated" '
            'date above. Continued use of the app after a change means '
            'you accept the updated policy.',
          ),
          const _Section('Contact'),
          const _Paragraph(
            'Questions about this policy, or general support, can be sent '
            'to contact.moltenmage@gmail.com.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;

  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;

  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
