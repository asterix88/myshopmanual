import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cetok.dart';
import '../models.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/rise.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Looks for a stock row's part number in every Partsbook, since one part
/// number is often used by several unit models.
Future<void> openInPartsbook(BuildContext context, CetokPart part) {
  if (part.numbers.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Part ini belum punya part number.')));
    return Future.value();
  }
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartsbookSearchScreen(part: part)));
}

class _Found {
  _Found(this.file, this.hit, this.pages, this.number);

  final ManualFile file;
  final SearchHit hit;
  final int pages;

  /// The part number that matched, to mark in the viewer.
  final String number;
}

/// The part number's pages in all Partsbooks, like the Cari tab but only in
/// Partsbooks: the stock row's own unit first, then other units.
class PartsbookSearchScreen extends StatefulWidget {
  const PartsbookSearchScreen({super.key, required this.part});

  final CetokPart part;

  @override
  State<PartsbookSearchScreen> createState() => _PartsbookSearchScreenState();
}

class _PartsbookSearchScreenState extends State<PartsbookSearchScreen> {
  bool _loading = true;
  String? _error;
  int _books = 0;
  var _own = <_Found>[];
  var _other = <_Found>[];

  String get _code => unitModelCode(widget.part.unit);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  static bool _isPartsbook(ManualFile f) => f.type == DocType.partsbook;

  Future<void> _search() async {
    final store = StoreScope.read(context);
    final books = {
      for (final f in store.catalog.files.followedBy(store.local.values.map((m) => m.file)))
        if (_isPartsbook(f)) f.key,
    };
    setState(() {
      _books = books.length;
      _loading = true;
      _error = null;
    });
    if (books.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Belum ada Partsbook di MyManual.';
      });
      return;
    }
    final indexes = await store.aiIndexes(where: _isPartsbook);
    if (!mounted) return;
    if (indexes.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Partsbook belum bisa dicari. Periksa sinyal internet.';
      });
      return;
    }
    // One card per Partsbook: the part number with the most pages there.
    final best = <String, _Found>{};
    for (final number in widget.part.numbers) {
      final result = await searchIndexes(indexes, number, limitPerFile: 1);
      for (final hit in result.hits) {
        final file = store.fileByKey(hit.fileKey);
        if (file == null) continue;
        final pages = result.pageCounts[hit.fileKey] ?? 1;
        final old = best[hit.fileKey];
        if (old == null || pages > old.pages) best[hit.fileKey] = _Found(file, hit, pages, number);
      }
    }
    if (!mounted) return;
    bool mine(ManualFile f) => unitModelCode(f.unitId) == _code || unitModelCode(store.unitNameOf(f)) == _code;
    final found = best.values.toList()
      ..sort((a, b) => store.unitNameOf(a.file).compareTo(store.unitNameOf(b.file)));
    setState(() {
      _loading = false;
      _own = [for (final f in found) if (mine(f.file)) f];
      _other = [for (final f in found) if (!mine(f.file)) f];
    });
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 6, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A64),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Kembali',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cari di Partsbook',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                            Text('Semua unit model', style: TextStyle(fontSize: 12, color: Color(0xFFC9D3E3))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(part.numbers.join(', '),
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                              Text(part.desc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFC9D3E3))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: Text('Stok ${part.unit}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E3A64))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: ExcavatorLoader(label: 'Mencari di $_books partsbook…'));
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: _error!,
        action: TextButton(onPressed: _search, child: const Text('Coba lagi')),
      );
    }
    if (_own.isEmpty && _other.isEmpty) {
      return const EmptyState(icon: Icons.search_off, title: 'Tidak ditemukan di partsbook mana pun');
    }
    var n = 0;
    Widget card(_Found f) => Rise(
          key: ValueKey(f.file.key),
          delay: Duration(milliseconds: 60 + 45 * (n++).clamp(0, 10)),
          child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _ResultCard(found: f)),
        );
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (_own.isNotEmpty) ...[
          const _Group('UNIT STOK INI'),
          for (final f in _own) card(f),
        ],
        if (_other.isNotEmpty) ...[
          _Group(_own.isEmpty ? 'DIPAKAI DI UNIT LAIN' : 'JUGA DIPAKAI DI UNIT LAIN'),
          for (final f in _other) card(f),
        ],
        if (_own.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: Text('Tidak ada di Partsbook ${widget.part.unit}.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.muted)),
      );
}

/// One Partsbook with the part, laid out like a Cari result; opens the page
/// with the part number marked.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.found});

  final _Found found;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final file = found.file;
    final hit = found.hit;
    return AppCard(
      onTap: () => openViewer(context, file, page: hit.page, query: found.number),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Row(
              children: [
                DocTile(docGlyph(file), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.unitNameOf(file),
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.muted)),
                      Text(file.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hit.section != null)
                        Text(hit.section!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      HighlightedSnippet(hit.snippet),
                      const SizedBox(height: 6),
                      Text('${found.pages} halaman ditemukan',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
