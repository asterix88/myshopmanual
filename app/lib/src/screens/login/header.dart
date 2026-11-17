part of '../login_screen.dart';

// The navy header with the logo and the white arc under it.

/// Navy band with the logo, name and tagline; a faint torque arrow turns
/// slowly in the corner. [fade] hides the text while the band grows into
/// the introduction's.
class _Header extends StatefulWidget {
  const _Header({required this.fade, this.compact = 0});

  final double fade;

  /// 1 while the keyboard is open: the logo row centred in a slim bar,
  /// the tagline folded away.
  final double compact;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 26));

  @override
  void initState() {
    super.initState();
    // Loops forever, so not in widget tests (pumpAndSettle would wait).
    if (ExcavatorLoader.animate) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -90,
            bottom: -130,
            child: RotationTransition(
              turns: _spin,
              child: const Opacity(opacity: 0.07, child: _WhiteArc(size: 260)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, top + 28 - 12 * widget.compact, 24, 0),
            child: Opacity(
              opacity: 1 - widget.fade.clamp(0.0, 1.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: const LogoMark(size: 30),
                      ),
                      const SizedBox(width: 9),
                      Text.rich(
                        TextSpan(
                          text: 'My',
                          children: [
                            TextSpan(
                              text: 'Manual',
                              style: TextStyle(color: AppColors.orange),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: 1 - widget.compact,
                      child: Opacity(
                        opacity: 1 - widget.compact,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: SizedBox(
                            width: 150,
                            child: Text(
                              'Shop manual dalam genggaman',
                              style: TextStyle(fontSize: 13, height: 1.45, color: Color(0xB8FFFFFF)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo's arrow alone, in white, for backgrounds.
class _WhiteArc extends StatelessWidget {
  const _WhiteArc({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: LogoMark(size: size, nutScale: 0),
    );
  }
}
