import 'package:flutter/material.dart';

/// Plays a one-off arrival animation for [child]: sliding down from above
/// ([from] negative) or rising from below, fading in, after [delay]. With
/// [play] off (or reduced motion) the child just shows.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.play,
    required this.child,
    this.from = 0.12,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.fade = true,
  });

  final bool play;
  final Widget child;

  /// Start offset as a fraction of the child's height (negative = above).
  final double from;
  final Duration delay;
  final Duration duration;
  final bool fade;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
    value: widget.play ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = (widget.delay + widget.duration).inMicroseconds;
    final start = total == 0 ? 0.0 : widget.delay.inMicroseconds / total;
    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    final slid = SlideTransition(
      position: Tween(begin: Offset(0, widget.from), end: Offset.zero).animate(t),
      child: widget.child,
    );
    return widget.fade ? FadeTransition(opacity: t, child: slid) : slid;
  }
}
