import 'package:flutter/material.dart';

import '../services/premium_service.dart';
import 'app_dialog.dart';
import 'premium_upsell_dialog.dart';

/// Shown when the free-tier item limit is hit — explains the limit, then
/// hands off to [showPremiumUpsellDialog] for the actual sales pitch.
Future<void> showPaywallDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppDialogTitle("You've hit the free limit"),
          const SizedBox(height: 8),
          Text(
            'Free accounts can track up to ${PremiumService.freeItemLimit} '
            'counters, groups, and challenges combined. Upgrade to Premium '
            'for unlimited tracking and an ad-free experience.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          AppDialogActions(
            secondaryLabel: 'Not now',
            onSecondary: () => Navigator.of(dialogContext).pop(),
            primaryLabel: 'Get Premium',
            onPrimary: () {
              Navigator.of(dialogContext).pop();
              if (context.mounted) {
                showPremiumUpsellDialog(context, source: 'free_limit');
              }
            },
          ),
        ],
      ),
    ),
  );
}
