part of '../quiz_admin_screen.dart';

// 'Buat draf kuis': the sheet that asks Nyel AI to write questions from a manual.

/// From the viewer (admins): Nyel AI drafts questions from this page. The
/// page text comes from the manual's search index on the phone.
class QuizGenerateSheet extends StatefulWidget {
  const QuizGenerateSheet({super.key, required this.file, required this.page, this.client});

  final ManualFile file;
  final int page;
  final http.Client? client;

  @override
  State<QuizGenerateSheet> createState() => _QuizGenerateSheetState();
}

class _QuizGenerateSheetState extends State<QuizGenerateSheet> {
  late final http.Client _client = widget.client ?? http.Client();
  String _topic = 'struktur';
  String _kind = 'pg';
  int _count = 3;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _go() async {
    final store = StoreScope.read(context);
    final file = widget.file;
    setState(() {
      _busy = true;
      _status = 'Membaca halaman ${widget.page}…';
    });
    try {
      if (!file.searchable) throw Exception('Dokumen hasil scan, tidak bisa melakukan pencarian pada dokumen ini');
      final indexes = await store.aiIndexes(where: (f) => f.key == file.key);
      final path = indexes[file.key];
      if (path == null) throw Exception('Indeks manual belum ada di HP. Coba lagi saat ada sinyal.');
      final page = widget.page;
      final found = await _pageText(path, page);
      final text = found?.text.trim() ?? '';
      if (text.length < 80) throw Exception('Halaman ini hampir tanpa teks. Pilih halaman lain.');
      if (!mounted) return;
      setState(() => _status = 'Nyel AI menyusun soal…');
      final result = await QuizApi(store, _client).generate(
        section: store.unitById(file.unitId)?.section ?? 'TRACK',
        unit: file.unitId,
        topic: _topic,
        manualId: file.key,
        page: page,
        text: text,
        count: _count,
        kind: _kind,
      );
      if ((result.pictures.isNotEmpty || result.references.isNotEmpty) && mounted) {
        setState(() => _status = 'Membuat gambar soal…');
        try {
          await sendQuizPicture(store, QuizApi(store, _client), file, page, {
            for (final id in result.pictures) id: (drawn) => QuizEdit.auto(drawn, result.callouts[id]),
            for (final id in result.references) id: QuizEdit.reference,
          });
        } on Object {
          // Made again when the question is approved.
        }
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(result.saved == 0
            ? 'Tidak ada soal yang layak dari halaman ini.'
            : '${result.saved} draf soal dibuat${result.dropped > 0 ? ', ${result.dropped} dibuang kurator' : ''}. '
                'Tinjau di menu ⋮ > Kelola soal quiz.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      showError(context, e);
    }
  }

  /// The question types on the sheet, in the order of the approved design
  /// (mockup Kuis Kartu v4): one row of icon tiles.
  static const _kinds = [
    (kind: 'pg', label: 'Pilihan ganda', glyph: AppGlyph.typePg),
    (kind: 'bs', label: 'Benar/Salah', glyph: AppGlyph.typeBs),
    (kind: 'gambar', label: 'Gambar', glyph: AppGlyph.typeGambar),
    (kind: 'kartu', label: 'Kartu', glyph: AppGlyph.typeKartu),
    (kind: 'campur', label: 'Campur', glyph: AppGlyph.typeCampur),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(title: 'Buat soal quiz', subtitle: '${widget.file.title} · hal. ${widget.page}'),
            const SizedBox(height: 16),
            const _SheetLabel('Jenis soal'),
            Row(children: [
              for (final (i, k) in _kinds.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _KindTile(
                    label: k.label,
                    glyph: k.glyph,
                    isNew: k.kind == 'kartu',
                    selected: _kind == k.kind,
                    onTap: _busy ? null : () => setState(() => _kind = k.kind),
                  ),
                ),
              ],
            ]),
            if (_kindHint case final hint?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hint, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const SizedBox(height: 16),
            const _SheetLabel('Topik'),
            DropdownButtonFormField<String>(
              initialValue: _topic,
              isDense: true,
              icon: Icon(Icons.expand_more, color: AppColors.muted),
              style: TextStyle(fontSize: 13, color: AppColors.ink, fontFamily: 'Poppins'),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.navy)),
              ),
              items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: _busy ? null : (v) => setState(() => _topic = v ?? _topic),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Jumlah', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.inkSoft)),
                const Spacer(),
                _CountPicker(
                  counts: const [1, 3, 5],
                  value: _count,
                  onChanged: _busy ? null : (n) => setState(() => _count = n),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _go,
                child: _busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text(_status ?? ''),
                        ],
                      )
                    : Text('Buat $_count ${_kind == 'kartu' ? 'kartu' : 'soal'}'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dicek kurator, terbit setelah admin setuju.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// One line under the types, for the ones that work differently.
  String? get _kindHint => switch (_kind) {
        'gambar' => 'Mekanik melihat gambar bernomor, tanpa keterangan.',
        'kartu' => 'Mekanik menjawab sendiri, lalu melihat halaman ini.',
        _ => null,
      };
}

/// Title and the page the questions come from, with a small page icon.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(child: AppIcon(AppGlyph.shopManual, size: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.inkSoft)),
      );
}

/// One question type: its icon over its name; [isNew] adds a "BARU" badge.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.label, required this.glyph, required this.selected, required this.onTap, this.isNew = false});

  final String label;
  final AppGlyph glyph;
  final bool selected;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: selected ? AppColors.navySoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.navy : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 68,
          // Full width also inside the Stack that holds the BARU badge.
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(glyph, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.navy : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: !isNew
          ? tile
          : Stack(
              clipBehavior: Clip.none,
              children: [
                tile,
                Positioned(
                  top: -7,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(999)),
                    child: const Text('BARU',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A small segmented row of numbers (1 / 3 / 5).
class _CountPicker extends StatelessWidget {
  const _CountPicker({required this.counts, required this.value, required this.onChanged});

  final List<int> counts;
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, n) in counts.indexed)
            Semantics(
              selected: n == value,
              button: true,
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(n),
                child: Container(
                  width: 48,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: n == value ? AppColors.navy : null,
                    border: i == 0 ? null : Border(left: BorderSide(color: AppColors.border)),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: n == value ? FontWeight.w600 : FontWeight.w400,
                      color: n == value ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reads one page's text in the background. A top-level function, so the
/// isolate gets only the path and page number and never the screen's state
/// (a closure inside the State drags the widget tree along, which an isolate
/// refuses).
Future<({String text, String? section})?> _pageText(String path, int page) =>
    Isolate.run(() => pageTextSync(path, page));
