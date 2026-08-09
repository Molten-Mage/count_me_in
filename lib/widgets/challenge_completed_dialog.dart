import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/challenge.dart';
import 'app_dialog.dart';
import 'challenge_emblem.dart';
import 'confetti_overlay.dart';

/// Celebratory popup shown the moment the viewer's own tallies reach every
/// objective in a challenge — same confetti/scale-in language as
/// [showGoalReachedDialog], but without a "new goal" flow, since raising a
/// target doesn't map cleanly onto a multi-objective challenge.
Future<void> showChallengeCompletedDialog(
  BuildContext context, {
  required Challenge challenge,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Challenge completed',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ChallengeCompletedDialog(challenge: challenge);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

class _ChallengeCompletedDialog extends StatefulWidget {
  final Challenge challenge;

  const _ChallengeCompletedDialog({required this.challenge});

  @override
  State<_ChallengeCompletedDialog> createState() =>
      _ChallengeCompletedDialogState();
}

class _ChallengeCompletedDialogState extends State<_ChallengeCompletedDialog> {
  final _confettiKey = GlobalKey<ConfettiOverlayState>();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiKey.currentState?.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: appDialogShape,
      child: ConfettiOverlay(
        key: _confettiKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: ChallengeEmblem(
                  iconIndex: widget.challenge.emblemIconIndex,
                  colorIndex: widget.challenge.emblemColorIndex,
                  size: 88,
                ),
              ),
              const SizedBox(height: 20),
              const AppDialogTitle(
                'Challenge complete!',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve hit every objective in "${widget.challenge.name}". '
                'Nice work!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Nice!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
