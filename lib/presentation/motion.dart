import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/nutrition.dart';

String _motionNumber(num value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

Duration motionDuration(BuildContext context, [int milliseconds = 280]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

AnimationStyle sheetMotion(BuildContext context) => AnimationStyle(
  duration: motionDuration(context),
  reverseDuration: motionDuration(context, 220),
);

class MotionSwap extends StatelessWidget {
  const MotionSwap({super.key, required this.child, this.scale = false});
  final Widget child;
  final bool scale;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, 180),
    switchInCurve: Curves.easeOutCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: scale
          ? ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
              child: child,
            )
          : child,
    ),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: [
        ...previous.map(
          (child) => IgnorePointer(child: ExcludeSemantics(child: child)),
        ),
        if (current != null) current,
      ],
    ),
    child: child,
  );
}

class MotionNumber extends StatelessWidget {
  const MotionNumber({
    super.key,
    required this.value,
    this.style,
    this.digits = 0,
    this.prefix = '',
    this.suffix = '',
  });
  final double value;
  final TextStyle? style;
  final int digits;
  final String prefix, suffix;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$prefix${_motionNumber(value, digits)}$suffix',
    child: ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: value, end: value),
        duration: motionDuration(context, 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) =>
            Text('$prefix${_motionNumber(value, digits)}$suffix', style: style),
      ),
    ),
  );
}

class MotionProgress extends StatelessWidget {
  const MotionProgress({
    super.key,
    required this.value,
    required this.circular,
    this.label,
  });
  final double value;
  final bool circular;
  final String? label;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: value, end: value),
    duration: motionDuration(context, 420),
    curve: Curves.easeOutCubic,
    builder: (context, progress, _) => circular
        ? CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            semanticsLabel: label,
            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          )
        : LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            semanticsLabel: label,
          ),
  );
}

class GoalPulse extends StatefulWidget {
  const GoalPulse({super.key, required this.reached, required this.child});
  final bool reached;
  final Widget child;
  @override
  State<GoalPulse> createState() => _GoalPulseState();
}

class _GoalPulseState extends State<GoalPulse>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  @override
  void didUpdateWidget(covariant GoalPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.reached &&
        widget.reached &&
        !MediaQuery.disableAnimationsOf(context)) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => Transform.scale(
      scale: 1 + math.sin(controller.value * math.pi) * 0.04,
      child: child,
    ),
    child: widget.child,
  );
}

class DiaryMotion extends StatefulWidget {
  const DiaryMotion({
    super.key,
    required this.day,
    required this.selectDay,
    required this.child,
    this.pageBuilder,
  });
  final DateTime day;
  final ValueChanged<DateTime> selectDay;
  final Widget child;
  final Widget Function(DateTime)? pageBuilder;
  @override
  State<DiaryMotion> createState() => _DiaryMotionState();
}

class _DiaryMotionState extends State<DiaryMotion>
    with TickerProviderStateMixin {
  double drag = 0, width = 1;
  bool dragging = false;
  Widget? preview;
  DateTime? previewDay, pendingDay;
  late final finger = AnimationController.unbounded(vsync: this);
  int direction = 1;
  Widget? previous;
  DateTime? previousDay;
  late final bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final slide = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 360),
  );
  @override
  void initState() {
    super.initState();
    slide.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && previous != null) {
        setState(() => previous = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DiaryMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.day, widget.day)) {
      if (DateUtils.isSameDay(pendingDay, widget.day)) {
        previous = null;
        pendingDay = null;
        preview = null;
        previewDay = null;
        dragging = false;
        finger.value = 0;
        slide.value = 1;
        return;
      }
      finger.stop();
      dragging = false;
      preview = null;
      previewDay = null;
      direction = widget.day.isAfter(oldWidget.day) ? 1 : -1;
      if (MediaQuery.disableAnimationsOf(context)) {
        previous = null;
        slide.value = 1;
      } else {
        previous = oldWidget.child;
        previousDay = oldWidget.day;
        slide.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    finger.dispose();
    bounce.dispose();
    slide.dispose();
    super.dispose();
  }

  DateTime? adjacent(double offset) {
    if (offset == 0) return null;
    final next = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day + (offset > 0 ? -1 : 1),
    );
    final now = DateTime.now();
    return next.isBefore(DateTime(2000)) ||
            next.isAfter(DateTime(now.year, now.month, now.day))
        ? null
        : next;
  }

  void beginDrag() {
    if (slide.isAnimating || finger.isAnimating) return;
    setState(() {
      drag = 0;
      dragging = true;
      preview = null;
      previewDay = null;
      finger.value = 0;
    });
  }

  void moveDrag(DragUpdateDetails details) {
    if (!dragging || finger.isAnimating) return;
    drag = (drag + details.delta.dx).clamp(-width, width);
    final next = adjacent(drag);
    if (!DateUtils.isSameDay(next, previewDay)) {
      previewDay = next;
      preview = next == null ? null : widget.pageBuilder?.call(next);
    }
    finger.value = next == null ? drag * 0.16 : drag;
  }

  Future<void> endDrag([double velocity = 0, bool cancel = false]) async {
    if (!dragging || finger.isAnimating) return;
    final next = adjacent(drag);
    final complete =
        !cancel &&
        next != null &&
        (drag.abs() >= width * 0.2 ||
            (velocity.abs() >= 500 && velocity * drag > 0));
    if (MediaQuery.disableAnimationsOf(context)) {
      if (complete) {
        pendingDay = next;
        widget.selectDay(next);
      } else {
        setState(() {
          dragging = false;
          finger.value = 0;
          preview = null;
        });
      }
      return;
    }
    final target = complete ? (drag > 0 ? width : -width) : 0.0;
    final duration = Duration(
      milliseconds: math.max(
        100,
        (300 * (target - finger.value).abs() / width).round(),
      ),
    );
    try {
      await finger
          .animateTo(target, duration: duration, curve: Curves.easeOutCubic)
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    if (complete) {
      pendingDay = next;
      widget.selectDay(next);
    } else {
      setState(() {
        dragging = false;
        preview = null;
        previewDay = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('diary-day-swipe'), behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: (_) => beginDrag(), onHorizontalDragUpdate: moveDrag,
    onHorizontalDragEnd: (details) => endDrag(details.primaryVelocity ?? 0),
    onHorizontalDragCancel: () => endDrag(0, true),
    child: LayoutBuilder(builder: (context, constraints) {
      width = constraints.maxWidth;
      return AnimatedBuilder(animation: Listenable.merge([slide, bounce, finger]),
        builder: (context, _) {
          final reduced = MediaQuery.disableAnimationsOf(context);
          final progress = reduced ? 1.0 : Curves.easeInOutCubic.transform(slide.value);
          final currentOffset = reduced ? 0.0 : dragging ? finger.value : direction * (1-progress) * width;
          return ClipRect(child: Transform.translate(
            offset: Offset(reduced || dragging ? 0 : -math.sin(bounce.value * math.pi) * 12, 0),
            child: Stack(fit: StackFit.expand, children: [
              if (!dragging && previous != null && progress < 1)
                Transform.translate(key: ValueKey('page/${dayKey(previousDay!)}'),
                  offset: Offset(-direction * progress * width, 0),
                  child: IgnorePointer(child: ExcludeSemantics(child: KeyedSubtree(
                    key: ValueKey(dayKey(previousDay!)), child: previous!)))),
              Transform.translate(key: ValueKey('page/${dayKey(widget.day)}'),
                offset: Offset(currentOffset, 0),
                child: IgnorePointer(ignoring: dragging || slide.isAnimating,
                  child: ExcludeSemantics(excluding: false, child: KeyedSubtree(
                    key: ValueKey(dayKey(widget.day)), child: widget.child)))),
              if (dragging && !reduced && previewDay != null && preview != null)
                Transform.translate(key: ValueKey('page/${dayKey(previewDay!)}'),
                  offset: Offset(finger.value + (drag > 0 ? -width : width), 0),
                  child: IgnorePointer(child: ExcludeSemantics(child: KeyedSubtree(
                    key: ValueKey(dayKey(previewDay!)), child: preview!)))),
            ])));
        });
    }),
  );
}

class MotionRows extends StatefulWidget {
  const MotionRows({super.key, required this.children});
  final List<Widget> children;
  @override
  State<MotionRows> createState() => _MotionRowsState();
}

class _MotionRow {
  _MotionRow(this.child, this.controller);
  Widget child;
  final AnimationController controller;
  bool leaving = false;
}

class _MotionRowsState extends State<MotionRows> with TickerProviderStateMixin {
  final rows = <_MotionRow>[];
  @override
  void initState() {
    super.initState();
    for (final child in widget.children) {
      rows.add(
        _MotionRow(
          child,
          AnimationController(
            vsync: this,
            value: 1,
            duration: const Duration(milliseconds: 240),
          ),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MotionRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keys = widget.children.map((c) => c.key).toSet();
    for (final child in widget.children) {
      final existing = rows.where((r) => r.child.key == child.key).firstOrNull;
      if (existing != null) {
        existing.child = child;
        if (existing.leaving) {
          existing.leaving = false;
          existing.controller.forward();
        }
      } else {
        rows.add(
          _MotionRow(
            child,
            AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 240),
            )..forward(),
          ),
        );
      }
    }
    for (final row in rows.toList()) {
      if (!keys.contains(row.child.key) && !row.leaving) {
        row.leaving = true;
        row.controller.reverse().then((_) {
          if (mounted && row.leaving) {
            setState(() {
              rows.remove(row);
              row.controller.dispose();
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Column(children: widget.children);
    }
    return Column(
      children: rows
          .map(
            (row) => KeyedSubtree(
              key: row.child.key,
              child: IgnorePointer(
                ignoring: row.leaving,
                child: ExcludeSemantics(
                  excluding: row.leaving,
                  child: SizeTransition(
                    sizeFactor: row.controller,
                    axisAlignment: -1,
                    child: FadeTransition(
                      opacity: row.controller,
                      child: row.child,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class SyncStatus extends StatelessWidget {
  const SyncStatus({
    super.key,
    required this.running,
    required this.failed,
    required this.succeeded,
  });
  final bool running, failed, succeeded;
  @override
  Widget build(BuildContext context) => MotionSwap(
    child: running
        ? Semantics(
            label: 'Синхронизация выполняется',
            child: SizedBox(
              key: const ValueKey('running'),
              width: 22,
              height: 22,
              child: MediaQuery.disableAnimationsOf(context)
                  ? const Icon(Icons.sync)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Icon(
            failed
                ? Icons.sync_problem
                : succeeded
                ? Icons.check_circle_outline
                : Icons.cloud_queue,
            key: ValueKey('$failed/$succeeded'),
            semanticLabel: failed
                ? 'Ошибка синхронизации'
                : succeeded
                ? 'Синхронизация завершена'
                : 'Ожидает синхронизации',
            color: failed
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
  );
}
