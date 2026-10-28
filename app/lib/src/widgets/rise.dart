import 'package:flutter/widgets.dart';

/// Fades and lifts its child in once, after [delay]; lists use it so their
/// cards arrive one after another.
class Rise extends StatefulWidget {
  const Rise({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  /// A delay for the [i]th item of a list: the first ten arrive in turn.
  static Duration stagger(int i, {int step = 35}) => Duration(milliseconds: i < 10 ? i * step : 0);

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 320);
  late final _c = AnimationController(vsync: this, duration: widget.delay + _length)..forward();
  late final _a = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delay.inMicroseconds / (widget.delay + _length).inMicroseconds, 1,
        curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, 14 * (1 - _a.value)), child: child),
        ),
      );
}
