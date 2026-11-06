import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../quiz.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'quiz_screen.dart';
import 'shell.dart';

/// "Buat draf kuis": nyel AI makes drafts from a whole manual. The phone
/// sends the manual's table of contents, nyel AI picks pages, the phone sends
/// those pages' text from its search index, and the server does the rest
/// (writing, the curator, checking numbers) while the app may be closed.
class QuizJobScreen extends StatefulWidget {
  const QuizJobScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizJobScreen> createState() => _QuizJobScreenState();
}

class _QuizJobScreenState extends State<QuizJobScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  String? _unit;
  String? _fileKey;
  int _count = 30;
  QuizMix _mix = const QuizMix();
  String _topic = 'semua';
  bool _busy = false;
  String? _status;

  static const _mixes = [
    ('Campur (60 / 20 / 20)', QuizMix()),
    ('Tanpa gambar (80 / 20 / 0)', QuizMix(pg: 80, bs: 20, gambar: 0)),
    ('Banyak gambar (40 / 20 / 40)', QuizMix(pg: 40, bs: 20, gambar: 40)),
    ('Pilihan ganda saja', QuizMix(pg: 100, bs: 0, gambar: 0)),
  ];

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  /// Manuals nyel AI can read: text (not scanned), and not partsbooks.
  List<ManualFile> _files(Unit unit) => [
        for (final f in StoreScope.read(context).filesOf(unit))
          if (f.searchable && f.type != DocType.partsbook) f,
      ];

  Future<void> _start() async {
    final store = StoreScope.read(context);
    final file = _fileKey == null ? null : store.fileByKey(_fileKey!);
    if (file == null) return;
    final api = QuizApi(store, _client);
    setState(() {
      _busy = true;
      _status = 'Membaca daftar isi…';
    });
    try {
      final indexes = await store.aiIndexes(where: (f) => f.key == file.key);
      final path = indexes[file.key];
      if (path == null) throw Exception('Indeks manual ini belum ada di HP. Coba lagi saat ada sinyal.');
      final toc = await loadTocInBackground(path);
      if (toc.isEmpty) throw Exception('File ini tidak punya daftar isi (bookmark). Buat soal dari halaman saja.');
      final lines = [for (final t in toc) '${t.page}\t${'  ' * (t.level.clamp(0, 6))}${t.title}'].join('\n');

      if (!mounted) return;
      setState(() => _status = 'nyel AI memilih halaman…');
      final pages = await api.plan(
        unit: file.unitId,
        topic: _topic,
        toc: lines,
        pages: file.pages,
        count: _count,
        mix: _mix,
      );

      if (!mounted) return;
      setState(() => _status = 'Mengambil teks ${pages.length} halaman…');
      final texts = await _pageTexts(path, [for (final p in pages) p.page]);
      final withText = [
        for (final p in pages)
          if ((texts[p.page] ?? '').trim().length >= 80)
            {'page': p.page, 'kind': p.kind, 'topic': p.topic, 'text': texts[p.page]},
      ];
      if (withText.isEmpty) throw Exception('Halaman yang dipilih tidak punya teks (mungkin hasil scan).');

      if (!mounted) return;
      setState(() => _status = 'Mengirim ke server…');
      await api.startJob(
        section: store.unitById(file.unitId)?.section ?? 'TRACK',
        unit: file.unitId,
        manualId: file.key,
        title: file.title,
        topic: _topic,
        count: _count,
        mix: _mix,
        pages: withText,
      );
      QuizApi.changed.value++;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('nyel AI mulai membuat draf. Prosesnya sekitar 5 sampai 10 menit, aplikasi boleh ditutup.'),
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
    final store = StoreScope.of(context);
    final units = [for (final u in store.units) if (_files(u).isNotEmpty) u];
    final unit = units.where((u) => u.id == _unit).firstOrNull;
    final files = unit == null ? const <ManualFile>[] : _files(unit);
    final file = files.where((f) => f.key == _fileKey).firstOrNull;
    final split = _mix.split(_count);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Buat draf kuis'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: unit?.id,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: [for (final u in units) DropdownMenuItem(value: u.id, child: Text(u.name))],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _unit = v;
                      final list = v == null ? const <ManualFile>[] : _files(units.firstWhere((u) => u.id == v));
                      _fileKey = list.where((f) => f.type == DocType.shopManual).firstOrNull?.key ?? list.firstOrNull?.key;
                    }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_unit),
            initialValue: file?.key,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'File',
              helperText: file == null ? null : '${file.pages} halaman',
            ),
            items: [
              for (final f in files)
                DropdownMenuItem(value: f.key, child: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _fileKey = v),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Jumlah soal'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [10, 20, 30, 50])
                ChoiceChip(label: Text('$n'), selected: _count == n, onSelected: _busy ? null : (_) => setState(() => _count = n)),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel('Campuran jenis soal'),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        if (split.pg > 0) Expanded(flex: split.pg, child: ColoredBox(color: AppColors.navy)),
                        if (split.bs > 0) Expanded(flex: split.bs, child: ColoredBox(color: AppColors.orange)),
                        if (split.gambar > 0) Expanded(flex: split.gambar, child: ColoredBox(color: AppColors.green)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final (label, n, color) in [
                      ('Pilihan ganda', split.pg, AppColors.navy),
                      ('Benar/Salah', split.bs, AppColors.orange),
                      ('Gambar', split.gambar, AppColors.green),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 4),
                          Text('$label $n', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                  onPressed: _busy ? null : _chooseMix,
                  child: const Text('Ubah campuran'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Topik'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (k, label) in [('semua', 'Semua'), for (final e in quizTopics.entries) (e.key, e.value)])
                ChoiceChip(label: Text(label), selected: _topic == k, onSelected: _busy ? null : (_) => setState(() => _topic = k)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Berjalan di server sekitar 5 sampai 10 menit, aplikasi boleh ditutup. Hasilnya masuk ke tab Draf. '
            'Perkiraan biaya AI sekitar Rp${(_count * 18).clamp(100, 2000)}.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy || file == null ? null : _start,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(_status ?? '', overflow: TextOverflow.ellipsis)),
                    ],
                  )
                : Text(file == null ? 'Pilih unit dan file' : 'Mulai buat draf'),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseMix() async {
    final picked = await showModalBottomSheet<QuizMix>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, mix) in _mixes)
              ListTile(
                title: Text(label, style: const TextStyle(fontSize: 14)),
                trailing: mix.pg == _mix.pg && mix.bs == _mix.bs ? Icon(Icons.check, color: AppColors.navy) : null,
                onTap: () => Navigator.pop(context, mix),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _mix = picked);
  }
}

/// Text of several pages, read on another isolate. Top-level on purpose: a
/// closure made inside a State carries the widget tree, which an isolate
/// refuses.
Future<Map<int, String>> _pageTexts(String path, List<int> pages) => Isolate.run(() => {
      for (final p in pages) p: pageTextSync(path, p)?.text ?? '',
    });
