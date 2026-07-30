import 'package:flutter/material.dart';

/// Rounded-corner shape shared by every popup in the app, first introduced
/// by the goal-reached celebration dialog.
final appDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(20),
);

const appDialogPadding = EdgeInsets.all(24);

/// Standard popup shell: a rounded [Dialog] with consistent padding
/// around [child].
class AppDialog extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppDialog({
    super.key,
    required this.child,
    this.padding = appDialogPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: appDialogShape,
      child: Padding(
        padding: padding,
        // Lets the dialog grow with its content up to the space the
        // keyboard leaves available, then scroll instead of overflowing
        // past the popup's bounds (which would hide the action buttons).
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

/// Bold headline used at the top of every popup.
class AppDialogTitle extends StatelessWidget {
  final String text;
  final TextAlign textAlign;

  const AppDialogTitle(
    this.text, {
    super.key,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

/// Side-by-side outlined/filled action row, or a single full-width filled
/// button when there's no secondary action — matching the celebration popup.
class AppDialogActions extends StatelessWidget {
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  const AppDialogActions({
    super.key,
    this.secondaryLabel,
    this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final primaryButton = FilledButton(
      onPressed: onPrimary,
      child: Text(primaryLabel),
    );

    final secondaryLabel = this.secondaryLabel;
    if (secondaryLabel == null) {
      return SizedBox(width: double.infinity, child: primaryButton);
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onSecondary,
            child: Text(secondaryLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: primaryButton),
      ],
    );
  }
}

/// The smallest multiple of ten strictly greater than [count]. Used as a
/// suggested-goal hint wherever a target must exceed a current count/total.
int nextTenAbove(int count) => (count ~/ 10 + 1) * 10;

/// Upper bound for any user-entered count-like number (goal target, tally
/// step). Keeps values sane and matches the 6-digit width of the largest
/// non-abbreviated badge count before [formatCompactCount] switches to "M".
const maxCounterInput = 999999;
