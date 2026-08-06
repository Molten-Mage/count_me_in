import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/premium_service.dart';
import 'app_dialog.dart';

/// The actual sales pitch — positive framing, no mention of limits. Shown
/// after tapping "Get Premium" on [showPaywallDialog], and directly from
/// Settings' "Get Premium" button, which has no limit-hit context to show.
/// [source] ('settings' or 'free_limit') tags which, for analytics.
Future<void> showPremiumUpsellDialog(
  BuildContext context, {
  required String source,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.workspace_premium,
            size: 40,
            color: Theme.of(dialogContext).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          const AppDialogTitle('Go Premium'),
          const SizedBox(height: 8),
          Text(
            'Track everything you want — unlimited counters, groups, and '
            'challenges — and enjoy Count Me In completely ad-free.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'One-time purchase — pay once, unlocked forever.',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Not now',
            onSecondary: () {
              analyticsService.logPremiumPrompt(
                source: source,
                accepted: false,
              );
              Navigator.of(dialogContext).pop();
            },
            primaryLabel: 'Upgrade — ${PremiumService.priceLabel}',
            onPrimary: () async {
              analyticsService.logPremiumPrompt(
                source: source,
                accepted: true,
              );
              Navigator.of(dialogContext).pop();
              if (kDebugMode) {
                await premiumStatus.setPremium(true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debug: upgraded to Premium'),
                    ),
                  );
                }
                return;
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Purchases aren't set up yet — check back soon!",
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}
