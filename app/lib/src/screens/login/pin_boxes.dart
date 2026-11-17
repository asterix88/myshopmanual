part of '../login_screen.dart';

// The four PIN boxes and the shake used when a PIN is wrong.

/// One box per PIN digit, showing a dot (or the digit when [obscure] is
/// off); the typing goes to a hidden text field so the phone's number
/// keyboard and paste work as usual, and it takes no more than [pinLength].
class PinBoxes extends StatefulWidget {
  const PinBoxes({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.obscure = true,
    this.error = false,
    this.shakes = 0,
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscure;

  /// Red boxes, after a wrong PIN.
  final bool error;

  /// Counts wrong PINs: each new one shakes the row (swinging less each
  /// time, like a head shake) and pulses the boxes one after another.
  final int shakes;
  final VoidCallback? onCompleted;

  @override
  State<PinBoxes> createState() => _PinBoxesState();
}

class _PinBoxesState extends State<PinBoxes> with SingleTickerProviderStateMixin {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(PinBoxes old) {
    super.didUpdateWidget(old);
    if (widget.shakes != old.shakes) _shake.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Widget _box(int i, String text) {
    final filled = i < text.length;
    final current = _focus.hasFocus && i == text.length;
    final Color border;
    if (widget.error) {
      border = AppColors.danger;
    } else if (current) {
      border = AppColors.orange;
    } else if (filled) {
      border = AppColors.navy;
    } else {
      border = AppColors.border;
    }
    final box = Container(
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.error
            ? AppColors.danger.withValues(alpha: AppColors.dark ? 0.14 : 0.06)
            : filled || current
            ? AppColors.surface
            : AppColors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: current ? 2 : 1.5, color: border),
      ),
      child: !filled
          ? null
          : widget.obscure
          ? Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
            )
          : Text(
              text[i],
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
    );
    // Each box swells a little in turn while the row shakes.
    return AnimatedBuilder(
      animation: _shake,
      child: box,
      builder: (context, child) {
        final t = ((_shake.value - i * 0.08) / 0.6).clamp(0.0, 1.0);
        return Transform.scale(scale: 1 + 0.07 * math.sin(t * math.pi), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          // Swings of 11 px that die away.
          final dx = t == 0 || t == 1 ? 0.0 : 11 * (1 - t) * math.sin(t * math.pi * 6);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < pinLength; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _box(i, text)),
                ],
              ],
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(pinLength),
                  ],
                  onChanged: (v) {
                    if (v.length == pinLength) widget.onCompleted?.call();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shakes its child from side to side, dying away, each time [shakes] goes up
/// (a refused NRP; the PIN boxes do the same for a wrong PIN).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.shakes, required this.child});

  final int shakes;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.shakes > old.shakes && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = _c.isAnimating ? 11 * (1 - t) * math.sin(t * math.pi * 6) : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
