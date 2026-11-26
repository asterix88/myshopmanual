part of '../quiz_screen.dart';

// Pieces of the quiz play page: options, tags, skeleton, error view, sheets.

class _RecallTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      message: 'Review soal sebelumnya',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
        decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppGlyph.refresh, size: 12, color: AppColors.orangeText),
            const SizedBox(width: 4),
            Text('Recall', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.orangeText)),
          ],
        ),
      ),
    );
  }
}

enum _OptState { idle, picked, right, wrong, dim }

/// An answer: at least 56 px high and tappable all over (gloves).
class _Option extends StatelessWidget {
  const _Option({required this.letter, required this.text, required this.state, this.onTap});

  final String letter;
  final String text;
  final _OptState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (border, fill, badge, badgeText) = switch (state) {
      _OptState.idle => (AppColors.border, AppColors.surface, AppColors.background, AppColors.inkSoft),
      _OptState.picked => (AppColors.navy, AppColors.navySoft, AppColors.navy, Colors.white),
      _OptState.right => (AppColors.green, AppColors.greenSoft, AppColors.green, Colors.white),
      _OptState.wrong => (AppColors.danger, AppColors.danger.withValues(alpha: .08), AppColors.danger, Colors.white),
      _OptState.dim => (AppColors.line, AppColors.surface, AppColors.background, AppColors.faint),
    };
    return Semantics(
      button: true,
      selected: state == _OptState.picked,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: state == _OptState.idle || state == _OptState.dim ? 1 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                    child: Center(
                      child: switch (state) {
                        _OptState.right => const AppIcon(AppGlyph.check, size: 16, color: Colors.white),
                        _OptState.wrong => const AppIcon(AppGlyph.cross, size: 16, color: Colors.white),
                        _ => Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: badgeText)),
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: state == _OptState.dim ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.glyph, required this.label, required this.onTap});

  final AppGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.navy;
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 40),
        foregroundColor: color,
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(glyph, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _QuizSkeleton extends StatelessWidget {
  const _QuizSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat soal',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 96, height: 22, radius: 6)),
          SizedBox(height: 16),
          SkeletonBox(height: 18),
          SizedBox(height: 8),
          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .7, child: SkeletonBox(height: 18)),
          SizedBox(height: 22),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.unit, required this.onRetry});

  final Object error;
  final String? unit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final code = error is AuthException ? (error as AuthException).code : '';
    final (title, message) = switch (code) {
      'done' => ('Quiz harian sudah selesai', 'Coba Quiz per unit'),
      'empty' => ('Belum ada soal', 'Soal untuk ${unit ?? 'section-mu'} sedang disiapkan'),
      'network' => ('Gagal memuat soal', 'Periksa koneksi internet.'),
      _ => ('Gagal memuat soal', error is AuthException ? (error as AuthException).message : '$error'),
    };
    final retry = code == 'network' || code == 'server' || code == '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(code == 'network' ? AppGlyph.cloudOff : AppGlyph.quiz, size: 36, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 20),
            if (retry)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const AppIcon(AppGlyph.refresh, size: 18, color: Colors.white),
                label: const Text('Coba lagi'),
              )
            else if (code == 'done' || (code == 'empty' && unit == null))
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const QuizUnitsScreen()),
                ),
                child: const Text('Quiz per unit'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.message, required this.children});

  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The white bar at the bottom of a question, above the system bar.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: const Color(0x33101828),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
