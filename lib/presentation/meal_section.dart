import 'package:flutter/material.dart';
import 'motion.dart';

class MealSection extends StatefulWidget {
  const MealSection({
    super.key,
    required this.hasEntries,
    required this.header,
    required this.child,
  });
  final bool hasEntries;
  final Widget Function(bool expanded, VoidCallback toggle) header;
  final Widget child;
  @override
  State<MealSection> createState() => _MealSectionState();
}

class _MealSectionState extends State<MealSection>
    with SingleTickerProviderStateMixin {
  bool expanded = false;
  late final controller = AnimationController(
    vsync: this,
    value: expanded ? 1 : 0,
    duration: const Duration(milliseconds: 280),
  );

  void changeExpansion(bool value) {
    if (expanded == value) return;
    expanded = value;
    controller.duration = motionDuration(context);
    controller.animateTo(value ? 1 : 0, curve: Curves.easeInOutCubic);
  }

  @override
  void didUpdateWidget(covariant MealSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasEntries && !widget.hasEntries) changeExpansion(false);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        expanded: expanded,
        child: widget.header(
          expanded,
          () => setState(() => changeExpansion(!expanded)),
        ),
      ),
      SizeTransition(
        sizeFactor: controller,
        axisAlignment: -1,
        child: IgnorePointer(
          ignoring: !expanded,
          child: ExcludeSemantics(excluding: !expanded, child: widget.child),
        ),
      ),
    ],
  );
}
