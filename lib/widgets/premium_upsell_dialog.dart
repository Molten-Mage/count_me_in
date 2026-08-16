import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/premium_service.dart';
import '../services/purchase_service.dart';
import 'app_dialog.dart';

/// The actual sales pitch - positive framing, no mention of limits. Shown
/// after tapping "Get Premium" on [showPaywallDialog], and directly from
/// Settings' "Get Premium" button, which has no limit-hit context to show.
/// [source] ('settings' or 'free_limit') tags which, for analytics.
Future<void> showPremiumUpsellDialog(
  BuildContext context, {
  required String source,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      // Captured once per dialog instance (StatefulBuilder's own rebuilds
      // don't re-run this outer closure) - same pattern as the invite
      // dialogs' `justCopied` flag elsewhere in this app.
      var isPurchasing = false;

      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> upgrade() async {
            analyticsService.logPremiumPrompt(source: source, accepted: true);

            if (kDebugMode) {
              Navigator.of(dialogContext).pop();
              await premiumStatus.setPremium(true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Debug: upgraded to Premium')),
                );
              }
              return;
            }

            // Only reports whether the store's native payment sheet
            // actually appeared - the real grant lands later via
            // PurchaseService's stream listener flipping premiumStatus,
            // which the rest of the app (ad banner, item limits) already
            // reacts to on its own.
            setDialogState(() => isPurchasing = true);
            final started = await purchaseService.buyPremium();
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            if (!started && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Purchases aren't available right now - check back soon!",
                  ),
                ),
              );
            }
          }

          return AppDialog(
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
                const AppDialogTitle('Upgrade your tracking!'),
                const SizedBox(height: 8),
                Text(
                  'With Premium you unlock unlimited counters, groups and '
                  'challenges. You can also enjoy Count Me In '
                  'completely ad-free.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'One-time purchase. No subscription.',
                  style: Theme.of(dialogContext).textTheme.bodySmall
                      ?.copyWith(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                AppDialogActions(
                  secondaryLabel: 'Not now',
                  onSecondary: isPurchasing
                      ? null
                      : () {
                          analyticsService.logPremiumPrompt(
                            source: source,
                            accepted: false,
                          );
                          Navigator.of(dialogContext).pop();
                        },
                  primaryLabel: isPurchasing
                      ? 'Upgrading…'
                      : 'Go Premium\n'
                      '${PremiumService.priceLabel}',
                  onPrimary: isPurchasing ? null : upgrade,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
