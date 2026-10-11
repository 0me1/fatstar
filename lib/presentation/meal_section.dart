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

class _MealSectionState extends State<MealSection> {
  late bool expanded = widget.hasEntries;
  @override
  void didUpdateWidget(covariant MealSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasEntries && widget.hasEntries) expanded = true;
    if (oldWidget.hasEntries && !widget.hasEntries) expanded = false;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        expanded: expanded,
        child: widget.header(
          expanded,
          () => setState(() => expanded = !expanded),
        ),
      ),
      AnimatedSize(
        duration: motionDuration(context),
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: Align(
            heightFactor: expanded ? 1 : 0,
            child: IgnorePointer(
              ignoring: !expanded,
              child: ExcludeSemantics(
                excluding: !expanded,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
