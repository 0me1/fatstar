import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'forms.dart' show message;
import 'motion.dart';

class FoodAddButton extends StatefulWidget {
  const FoodAddButton({super.key, required this.tooltip, this.onPressed, this.onAdd});
  final String tooltip;
  final VoidCallback? onPressed;
  final Future<bool> Function()? onAdd;
  @override
  State<FoodAddButton> createState() => _FoodAddButtonState();
}
class _FoodAddButtonState extends State<FoodAddButton> {
  bool pressed = false, confirmed = false, busy = false;
  Timer? reset;
  @override
  void dispose() { reset?.cancel(); super.dispose(); }
  Future<void> activate() async {
    unawaited(HapticFeedback.selectionClick());
    if (widget.onAdd == null) { widget.onPressed?.call(); return; }
    setState(() => busy = true);
    try {
      final added = await widget.onAdd!();
      if (!mounted) return;
      setState(() { busy = false; confirmed = added; });
      reset?.cancel();
      if (added) reset = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => confirmed = false);
      });
    } catch (error) {
      if (mounted) { setState(() => busy = false); message(context, error); }
    }
  }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = !busy && (widget.onPressed != null || widget.onAdd != null);
    return Listener(
      onPointerDown: enabled ? (_) => setState(() => pressed = true) : null,
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: AnimatedScale(scale: pressed ? 0.92 : 1, duration: motionDuration(context, 110),
        child: IconButton.filled(
          tooltip: widget.tooltip, onPressed: enabled ? activate : null,
          style: IconButton.styleFrom(backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF252827),
            disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.12),
            disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
            minimumSize: const Size(52, 52),
            side: Theme.of(context).brightness == Brightness.light ? const BorderSide(color: Color(0xFFCFDBD8)) : BorderSide.none,
            shape: const CircleBorder()),
          icon: MotionSwap(scale: true, child: Icon(confirmed ? Icons.check_rounded : Icons.add_rounded,
            key: ValueKey(confirmed), size: 34)),
        )),
    );
  }
}
