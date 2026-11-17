part of '../quiz_admin_screen.dart';

// 'Buat draf kuis': the sheet that asks nyel AI to write questions from a manual.

/// From the viewer (admins): nyel AI drafts questions from this page. The
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
  String _kind = 'campur';
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
      if (!file.searchable) throw Exception('Manual ini berupa gambar, teksnya tidak bisa dibaca.');
      final indexes = await store.aiIndexes(where: (f) => f.key == file.key);
      final path = indexes[file.key];
      if (path == null) throw Exception('Indeks manual belum ada di HP. Coba lagi saat ada sinyal.');
      final page = widget.page;
      final found = await _pageText(path, page);
      final text = found?.text.trim() ?? '';
      if (text.length < 80) throw Exception('Halaman ini hampir tanpa teks. Pilih halaman lain.');
      if (!mounted) return;
      setState(() => _status = 'nyel AI menyusun soal…');
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
      if (result.pictures.isNotEmpty && mounted) {
        setState(() => _status = 'Membuat gambar soal…');
        try {
          await sendQuizPicture(store, QuizApi(store, _client), file, page,
              {for (final id in result.pictures) id: result.callouts[id]});
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

  @override
  Widget build(BuildContext context) {
    final kinds = [('campur', 'Campur'), for (final e in quizTypes.entries) (e.key, e.value)];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Buat soal quiz', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              '${widget.file.title} · hal. ${widget.page}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            const _SheetLabel('Jenis soal'),
            Row(children: [
              for (final (i, (k, label)) in kinds.take(2).indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: label, selected: _kind == k, onTap: _busy ? null : () => setState(() => _kind = k))),
              ],
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, (k, label)) in kinds.skip(2).indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: label, selected: _kind == k, onTap: _busy ? null : () => setState(() => _kind = k))),
              ],
            ]),
            if (_kind == 'gambar')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Mekanik melihat gambar bernomor, tanpa keterangan.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const SizedBox(height: 16),
            const _SheetLabel('Topik'),
            DropdownButtonFormField<String>(
              initialValue: _topic,
              isDense: true,
              icon: Icon(Icons.expand_more, color: AppColors.muted),
              style: TextStyle(fontSize: 14, color: AppColors.ink, fontFamily: 'Poppins'),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.navy)),
              ),
              items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: _busy ? null : (v) => setState(() => _topic = v ?? _topic),
            ),
            const SizedBox(height: 16),
            const _SheetLabel('Jumlah soal'),
            Row(children: [
              for (final (i, n) in const [1, 3, 5].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: '$n', selected: _count == n, onTap: _busy ? null : () => setState(() => _count = n))),
              ],
            ]),
            const SizedBox(height: 20),
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
                    : const Text('Buat draf'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Draf dicek kurator, terbit setelah admin setuju.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
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

/// One option box of the "Buat soal quiz" sheet.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.navySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.navy : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.navy : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
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
