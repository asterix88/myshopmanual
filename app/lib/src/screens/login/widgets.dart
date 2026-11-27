part of '../login_screen.dart';

// Small pieces shared by the login pages: labels, fields, errors, buttons.

/// A red line under a field, sliding in when it appears.
class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -6 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 2),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The orange button that shrinks to a spinner while logging in and turns
/// into a green tick when it worked.
class _MorphButton extends StatelessWidget {
  const _MorphButton({super.key, required this.label, required this.busy, required this.done, required this.onPressed});

  final String label;
  final bool busy;
  final bool done;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final round = busy || done;
    // The form is at most 420 wide with 24 on each side.
    final wide = math.min(MediaQuery.sizeOf(context).width, 420.0) - 48;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: round ? 52 : wide,
        height: 52,
        decoration: BoxDecoration(
          color: done ? AppColors.green : AppColors.orange,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: round ? null : onPressed,
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 28)
                  : busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.muted),
      ),
    );
  }
}

InputDecoration _inputDecoration({bool error = false}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: 1.5),
  );
  return InputDecoration(
    filled: true,
    fillColor: AppColors.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: border(error ? AppColors.danger : AppColors.border),
    focusedBorder: border(error ? AppColors.danger : AppColors.navy),
  );
}

/// A red note under the fields saying what went wrong.
class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: AppColors.dark ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 19, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({super.key, required this.label, required this.busy, required this.onPressed, this.color});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  /// Orange unless given.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
