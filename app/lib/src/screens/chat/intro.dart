part of '../chat_screen.dart';

// What shows above the conversation: the intro, the attached page and the questions left today.

/// What the chat shows before the first question about a manual page.
class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Tanya tentang halaman ini',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
        ),
      ),
    );
  }
}

/// The manual page the next question is about, with ready-made questions.
class _AttachedPage extends StatelessWidget {
  const _AttachedPage({
    required this.file,
    required this.page,
    required this.suggestions,
    required this.onSuggestion,
    required this.onRemove,
  });

  final ManualFile file;
  final int page;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestion;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: AppColors.border),
                        shape: const StadiumBorder(),
                        label: Text(s, style: TextStyle(fontSize: 13, color: AppColors.navy)),
                        onPressed: onSuggestion == null ? null : () => onSuggestion!(s),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 22, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Halaman $page',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                        ),
                        Text(
                          '${store.unitNameOf(file)} · ${file.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lepas halaman',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.hasManuals, required this.onExample});

  final List<String> examples;
  final bool hasManuals;
  final ValueChanged<String>? onExample;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: AppIcon(AppGlyph.nyel, size: 30, color: AppColors.orange),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Tanya soal teknis',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Dijawab dari semua manual.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        if (!hasManuals) ...[
          const SizedBox(height: 8),
          Text(
            'Daftar manual belum tersedia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.orangeText),
          ),
          const Center(child: RetryButton()),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'CONTOH',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted),
          ),
        ),
        for (final example in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: onExample == null ? null : () => onExample!(example),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(child: Text(example, style: const TextStyle(fontSize: 13))),
                  Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
