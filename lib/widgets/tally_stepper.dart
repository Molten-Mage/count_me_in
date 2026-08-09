import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_dialog.dart';

/// Compact +/- control for adjusting a tally by a configurable step. Tonal
/// icon buttons (matching the app's filled, rounded language) bracket a
/// step-size field with a subtle fill so it still reads as editable, all
/// together reading as one control instead of three loose widgets.
class TallyStepper extends StatelessWidget {
  final TextEditingController stepController;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final double iconSize;
  final FocusNode? focusNode;

  const TallyStepper({
    super.key,
    required this.stepController,
    required this.onDecrement,
    required this.onIncrement,
    this.iconSize = 24,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          iconSize: iconSize,
          icon: const Icon(Icons.remove),
          onPressed: () {
            HapticFeedback.lightImpact();
            onDecrement();
          },
        ),
        SizedBox(
          width: iconSize + 20,
          child: TextField(
            controller: stepController,
            focusNode: focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                maxCounterInput.toString().length,
              ),
            ],
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          iconSize: iconSize,
          icon: const Icon(Icons.add),
          onPressed: () {
            HapticFeedback.lightImpact();
            onIncrement();
          },
        ),
      ],
    );
  }
}
