import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_dialog.dart';

/// A tally number that's both directly editable (tap it, type an absolute
/// value, commits on losing focus or a keyboard "done"/submit action) and
/// flanked by tonal +/- buttons for a quick nudge by 1. The field's subtle
/// filled background is the "this is editable" cue; the buttons are for
/// the common case of just bumping the count by one without opening the
/// keyboard at all.
class EditableTally extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final TextStyle? style;
  final FocusNode? focusNode;
  final double iconSize;

  const EditableTally({
    super.key,
    required this.value,
    required this.onChanged,
    this.style,
    this.focusNode,
    this.iconSize = 24,
  });

  @override
  State<EditableTally> createState() => _EditableTallyState();
}

class _EditableTallyState extends State<EditableTally> {
  late final _controller = TextEditingController(text: '${widget.value}');
  late final _focusNode = (widget.focusNode ?? FocusNode())
    ..addListener(_onFocusChange);
  // Tracks the last value actually committed via widget.onChanged, kept
  // separate from widget.value - which reflects this page's own
  // optimistic/stream state and may lag a beat behind our own just-sent
  // edit. Comparing against widget.value instead could fire onChanged a
  // second time for the same edit (once from losing focus, again from the
  // unfocus() a "done" submit triggers) before that state catches up.
  late int _committed = widget.value;

  @override
  void didUpdateWidget(EditableTally oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only overwrite while the field isn't focused - rewriting the text out
    // from under someone mid-edit (e.g. from a concurrent server update) is
    // exactly what the detail pages' optimistic-tally overrides elsewhere
    // exist to avoid for the read-only display; same idea here.
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = '${widget.value}';
      _committed = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    final clamped = (parsed ?? _committed).clamp(0, maxCounterInput);
    _controller.text = '$clamped';
    if (clamped != _committed) {
      _committed = clamped;
      widget.onChanged(clamped);
    }
  }

  void _submit() {
    _commit();
    _focusNode.unfocus();
  }

  // Nudges by +/-1 against _committed rather than widget.value, so two
  // quick taps compound correctly (+1 then +1 = +2) even before the first
  // tap's onChanged has round-tripped back into a new widget.value.
  void _nudge(int delta) {
    final newValue = (_committed + delta).clamp(0, maxCounterInput);
    if (newValue == _committed) return;
    HapticFeedback.lightImpact();
    _committed = newValue;
    _controller.text = '$newValue';
    widget.onChanged(newValue);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    // Only dispose a focus node this widget created itself - one passed in
    // via widget.focusNode is owned (and disposed) by whoever created it,
    // since they need it to outlive this widget to force-dismiss the
    // keyboard from outside (see home_page.dart's navigate-away handling).
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          iconSize: widget.iconSize,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease',
          onPressed: () => _nudge(-1),
        ),
        IntrinsicWidth(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: widget.style,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                maxCounterInput.toString().length,
              ),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          iconSize: widget.iconSize,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          tooltip: 'Increase',
          onPressed: () => _nudge(1),
        ),
      ],
    );
  }
}
