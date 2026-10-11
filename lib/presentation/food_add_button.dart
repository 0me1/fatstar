import 'package:flutter/material.dart';

class FoodAddButton extends StatelessWidget {
  const FoodAddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF252827),
        disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
        minimumSize: const Size(52, 52),
        side: Theme.of(context).brightness == Brightness.light
            ? const BorderSide(color: Color(0xFFCFDBD8))
            : BorderSide.none,
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.add_rounded, size: 34),
    );
  }
}
