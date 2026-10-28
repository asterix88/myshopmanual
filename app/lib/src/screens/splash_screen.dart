import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/logo_mark.dart';

/// Same grey as the Android launch screen, so the hand-over is invisible.
const splashBackground = Color(0xFFF5F6F8);

/// Size of the logo on the Android launch screen (drawable/launch_logo).
const splashLogoSize = 92.0;

/// The opening animation (Anas chose option "Kunci torsi", 28 Oct 2026): the
/// logo the phone already shows turns its arrow once like a torque wrench
/// tightening the nut, then the name slides out beside it. Shown when the app
/// starts after a day or more, or before logging in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone, this.ready});

  final VoidCallback onDone;

  /// Holds the logo still until this completes (the notification
  /// permission dialog on the first start).
  final Future<void>? ready;

  static const duration = Duration(milliseconds: 3300);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SplashScreen.duration);

  // Parts of the 3.3 s, as fractions.
  static const _turn = Interval(0.06, 0.40);
  static const _click = Interval(0.38, 0.45);
  static const _name = Interval(0.44, 0.62, curve: Curves.easeOutCubic);
  static const _tag = Interval(0.59, 0.74, curve: Curves.easeOut);
  static const _out = Interval(0.88, 1, curve: Curves.easeIn);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await widget.ready;
    if (!mounted) return;
    // A short beat after the dialog closes, so the turn is seen.
    if (widget.ready != null) await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _c.forward();
    if (mounted) widget.onDone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Phones set to reduce motion get the end state straight away.
    if (MediaQuery.disableAnimationsOf(context) && _c.value < 0.6) _c.value = 0.6;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _at(Interval i) => i.transform(_c.value);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: splashBackground,
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // One clockwise turn that runs a little past and settles back.
            final t = _at(_turn);
            final turn = -2 * math.pi * (1 - Curves.easeOutBack.transform(t));
            final click = _at(_click);
            final nut = 1 - 0.08 * math.sin(click * math.pi);
            final name = _at(_name);
            final out = _at(_out);
            return Opacity(
              opacity: 1 - out,
              child: Transform.scale(
                scale: 1 - 0.03 * out,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Fill the screen so the logo sits in its middle, where
                    // the Android launch screen drew it.
                    const SizedBox.expand(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LogoMark(size: splashLogoSize, arcTurn: turn, nutScale: nut),
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: name,
                            child: Opacity(
                              opacity: name,
                              child: const Padding(padding: EdgeInsets.only(left: 6), child: _Wordmark()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Transform.translate(
                      offset: Offset(0, 66 + 6 * (1 - _at(_tag))),
                      child: Opacity(
                        opacity: _at(_tag),
                        child: const Text(
                          'Shop manual dalam genggaman',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7480)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        text: 'My',
        children: [
          TextSpan(
            text: 'Manual',
            style: TextStyle(color: Color(0xFFF08A1C)),
          ),
        ],
      ),
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Color(0xFF1E3A64)),
    );
  }
}
