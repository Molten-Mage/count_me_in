import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/analytics_service.dart';
import 'app_dialog.dart';
import 'badge_icon.dart';
import 'confetti_overlay.dart';

/// Shows a celebratory popup for a newly reached goal, with a confetti
/// burst, and lets the user immediately set a new target. Used for both
/// personal counters and group goals - [source] ('counter' or 'group')
/// tags which, for analytics.
Future<void> showGoalReachedDialog(
  BuildContext context, {
  required String source,
  required String message,
  required int badgeValue,
  required int badgeColorIndex,
  required int currentCount,
  required void Function(int newTarget) onSetNewGoal,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Goal reached',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _GoalReachedDialog(
        source: source,
        message: message,
        badgeValue: badgeValue,
        badgeColorIndex: badgeColorIndex,
        currentCount: currentCount,
        onSetNewGoal: onSetNewGoal,
      );
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

class _GoalReachedDialog extends StatefulWidget {
  final String source;
  final String message;
  final int badgeValue;
  final int badgeColorIndex;
  final int currentCount;
  final void Function(int newTarget) onSetNewGoal;

  const _GoalReachedDialog({
    required this.source,
    required this.message,
    required this.badgeValue,
    required this.badgeColorIndex,
    required this.currentCount,
    required this.onSetNewGoal,
  });

  @override
  State<_GoalReachedDialog> createState() => _GoalReachedDialogState();
}

class _GoalReachedDialogState extends State<_GoalReachedDialog> {
  final _confettiKey = GlobalKey<ConfettiOverlayState>();
  final _newTargetController = TextEditingController();
  bool _settingNewGoal = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    // Wait a frame so the confetti overlay has a size before it plays.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiKey.currentState?.play();
    });
  }

  @override
  void dispose() {
    _newTargetController.dispose();
    super.dispose();
  }

  bool get _isNewTargetValid {
    final target = int.tryParse(_newTargetController.text);
    return target != null && target > widget.currentCount;
  }

  void _submitNewGoal() {
    final target = int.tryParse(_newTargetController.text);
    if (target == null || target <= widget.currentCount) return;
    widget.onSetNewGoal(target);
    Navigator.of(context).pop();
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
                child: BadgeIcon(
                  value: widget.badgeValue,
                  colorIndex: widget.badgeColorIndex,
                  size: 88,
                ),
              ),
              const SizedBox(height: 20),
              const AppDialogTitle('Goal reached!', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (!_settingNewGoal) ...[
                AppDialogActions(
                  secondaryLabel: 'Continue',
                  onSecondary: () {
                    analyticsService.logGoalReachedAction(
                      source: widget.source,
                      startedNewGoal: false,
                    );
                    Navigator.of(context).pop();
                  },
                  primaryLabel: 'New goal',
                  onPrimary: () {
                    analyticsService.logGoalReachedAction(
                      source: widget.source,
                      startedNewGoal: true,
                    );
                    setState(() => _settingNewGoal = true);
                  },
                ),
              ] else ...[
                TextField(
                  controller: _newTargetController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'New target',
                    hintText: 'e.g. ${nextTenAbove(widget.currentCount)}',
                    helperText: 'Must be higher than ${widget.currentCount}',
                  ),
                  onSubmitted: (_) => _submitNewGoal(),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppDialogActions(
                  secondaryLabel: 'Back',
                  onSecondary: () => setState(() => _settingNewGoal = false),
                  primaryLabel: 'Save',
                  onPrimary: _isNewTargetValid ? _submitNewGoal : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
