part of '../chat_screen.dart';

// One chat bubble: the answer text, its page pictures and the rating footer.

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.entry,
    this.popIn = false,
    this.highlight = '',
    this.current = false,
    this.onRate,
  });

  final ChatEntry entry;

  /// Rates the answer 👍 (true) or 👎 (false); null for questions and errors.
  final void Function(bool good)? onRate;

  /// Pops in when first shown (a message just sent or answered).
  final bool popIn;

  /// Words searched for in the conversation, marked in the text.
  final String highlight;

  /// This bubble is the search hit shown now.
  final bool current;

  /// [runs] with every place [highlight] occurs marked.
  List<TextSpan> _spans(List<({String text, bool bold})> runs) {
    final query = highlight.toLowerCase();
    final mark = TextStyle(
      backgroundColor: current ? AppColors.orange : AppColors.highlight,
      color: current ? Colors.white : AppColors.ink,
    );
    return [
      for (final run in runs)
        if (query.isEmpty)
          TextSpan(
            text: run.text,
            style: run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
          )
        else
          TextSpan(
            style: run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
            children: [
              for (final (part, found) in _split(run.text, query)) TextSpan(text: part, style: found ? mark : null),
            ],
          ),
    ];
  }

  static Iterable<(String, bool)> _split(String text, String query) sync* {
    final lower = text.toLowerCase();
    var at = 0;
    while (true) {
      final found = lower.indexOf(query, at);
      if (found < 0) break;
      if (found > at) yield (text.substring(at, found), false);
      yield (text.substring(found, found + query.length), true);
      at = found + query.length;
    }
    if (at < text.length) yield (text.substring(at), false);
  }

  /// The answer laid out in blocks: paragraphs, short titles (a bold line or
  /// one ending in ':'), bullet points and numbered steps with their text
  /// indented, so a long answer reads like a tidy note.
  Widget _answerText(String text) {
    final style = TextStyle(fontSize: 13, height: 1.5, color: entry.failed ? AppColors.danger : AppColors.ink);
    final blocks = <Widget>[];
    var gap = false;
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        gap = true;
        continue;
      }
      final top = blocks.isEmpty ? 0.0 : (gap ? 10.0 : 4.0);
      gap = false;
      final indent = (raw.length - raw.trimLeft().length) >= 2 ? 16.0 : 0.0;
      final bullet = RegExp(r'^\s*[-•*]\s+(.*)$').firstMatch(line);
      final number = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$').firstMatch(line);
      final heading = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(line);
      final plain = line.trim();
      final Widget block;
      if (bullet != null || number != null) {
        block = Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: number != null ? 22 : 16,
                child: Text(
                  number != null ? '${number[1]}.' : '•',
                  style: style.copyWith(fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
              Expanded(child: Text.rich(TextSpan(children: _spans(boldRuns(bullet?[1] ?? number![2]!))), style: style)),
            ],
          ),
        );
      } else if (heading != null ||
          RegExp(r'^\*\*[^*]+\*\*:?$').hasMatch(plain) ||
          (plain.endsWith(':') && plain.length <= 60)) {
        final title = (heading?[1] ?? plain).replaceAll('**', '');
        block = Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 4),
          child: Text.rich(
            TextSpan(children: _spans([(text: title, bold: true)])),
            style: style.copyWith(color: entry.failed ? AppColors.danger : AppColors.navy),
          ),
        );
      } else {
        block = Text.rich(TextSpan(children: _spans(boldRuns(plain))), style: style);
      }
      blocks.add(Padding(padding: EdgeInsets.only(top: top), child: block));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  @override
  Widget build(BuildContext context) {
    final bubble = _bubble(context);
    return popIn ? _PopIn(fromRight: entry.fromUser, child: bubble) : bubble;
  }

  Widget _bubble(BuildContext context) {
    if (entry.fromUser) {
      final page = entry.page;
      final question = Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
          // Selectable like the answers, so a question can be copied. The
          // usual navy highlight and handles vanish on the navy bubble.
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: AppColors.orange.withAlpha(150),
                selectionHandleColor: AppColors.orange,
                cursorColor: AppColors.orange,
              ),
            ),
            child: DefaultSelectionStyle(
              selectionColor: AppColors.orange.withAlpha(150),
              cursorColor: AppColors.orange,
              child: SelectableText.rich(
                TextSpan(children: _spans([(text: entry.text, bold: false)])),
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ),
      );
      if (page == null) return question;
      // The page the question is about, above it like a forwarded message.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.navySoft,
              side: BorderSide.none,
              avatar: AppIcon(docGlyph(page.file), size: 16),
              label: Text(
                '${page.unitName} · ${page.file.typeLabel} · hlm ${page.page}',
                style: TextStyle(fontSize: 12, color: AppColors.navy),
              ),
              onPressed: () => openViewer(context, page.file, page: page.page),
            ),
          ),
          question,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Manual pages first, like a photo sent with a message; the
            // sources stay under the text.
            for (final picture in entry.pictures) ...[_PagePicture(source: picture), const SizedBox(height: 12)],
            SelectionArea(child: _answerText(withoutSourceNumbers(entry.text))),
            if (entry.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Sumber',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in entry.sources)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.navySoft,
                      side: BorderSide.none,
                      avatar: AppIcon(docGlyph(s.file), size: 16),
                      label: Text(
                        '${s.unitName} · ${s.file.typeLabel} · hlm ${s.page}',
                        style: TextStyle(fontSize: 12, color: AppColors.navy),
                      ),
                      onPressed: () => openViewer(context, s.file, page: s.page),
                    ),
                ],
              ),
            ],
            if (!entry.failed) _AnswerFooter(entry: entry, onRate: onRate),
          ],
        ),
      ),
    );
  }
}

/// Under an answer: a note when parts of it are not from a manual page, and
/// the 👍 and 👎 "Jawaban salah" buttons.
class _AnswerFooter extends StatelessWidget {
  const _AnswerFooter({required this.entry, required this.onRate});

  final ChatEntry entry;
  final void Function(bool good)? onRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: entry.hasUncheckedParts
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: AppIcon(AppGlyph.info, size: 15, color: AppColors.muted),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sebagian jawaban bukan dari manual.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (entry.rating case final rating?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(rating == 'good' ? AppGlyph.thumbUp : AppGlyph.thumbDown, size: 15, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    rating == 'good' ? 'Membantu' : 'Dilaporkan',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            )
          else if (onRate case final rate?) ...[
            IconButton(
              tooltip: 'Jawaban membantu',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: AppColors.muted,
              icon: AppIcon(AppGlyph.thumbUp, size: 18, color: AppColors.muted),
              onPressed: () => rate(true),
            ),
            IconButton(
              tooltip: 'Jawaban salah',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: AppColors.muted,
              icon: AppIcon(AppGlyph.thumbDown, size: 18, color: AppColors.muted),
              onPressed: () => rate(false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grows a new message out of its corner of the screen, like WhatsApp.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.fromRight, required this.child});

  final bool fromRight;
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // The space opens up (pushing the older messages up) while the bubble
    // grows out of its bottom corner with a small bounce.
    return SizeTransition(
      sizeFactor: grow,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut)),
        child: ScaleTransition(
          alignment: widget.fromRight ? Alignment.bottomRight : Alignment.bottomLeft,
          scale: Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A manual page shown as a picture in an answer. Tapping it opens the page
/// in the viewer to zoom in.
class _PagePicture extends StatefulWidget {
  const _PagePicture({required this.source});

  final AiSource source;

  @override
  State<_PagePicture> createState() => _PagePictureState();
}

class _PagePictureState extends State<_PagePicture> {
  Future<File>? _thumb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drawn once into a small picture file (from the phone when downloaded,
    // else only this page's part of the PDF is fetched), so the chat never
    // keeps whole manuals open.
    _thumb ??= pageThumbnail(StoreScope.of(context), widget.source.file, widget.source.page);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openViewer(context, source.file, page: source.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              child: FutureBuilder<File>(
                future: _thumb,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Gambar tidak bisa dimuat', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    );
                  }
                  final file = snapshot.data;
                  if (file == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  return Image.file(file, fit: BoxFit.contain, cacheHeight: 600);
                },
              ),
            ),
            Container(
              color: AppColors.navySoft,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${source.unitName} · ${source.file.typeLabel} · hlm ${source.page}',
                      style: TextStyle(fontSize: 12, color: AppColors.navy),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 16, color: AppColors.navy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
