import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cetok.dart';
import '../models.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Opens Cetok Online; with [search] the search box gets the keyboard.
Future<void> openCetok(BuildContext context, {bool search = false}) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CetokScreen(focusSearch: search)),
    );

/// The Cetok Online card on the Home tab: a title and a search box. Either
/// opens the Cetok Online screen.
class CetokCard extends StatelessWidget {
  const CetokCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openCetok(context),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.inventory_2_outlined, color: AppColors.orangeText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cetok Online',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      Text('Cek, ambil, dan input stok part', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.faint),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.field,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => openCetok(context, search: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: AppColors.faint),
                    const SizedBox(width: 8),
                    Text('Cari part number atau nama part', style: TextStyle(fontSize: 13, color: AppColors.faint)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cetok Online inside MyManual: Stok (look up and open a part), Ambil and
/// Input, using the same database functions as the website.
class CetokScreen extends StatefulWidget {
  const CetokScreen({super.key, this.focusSearch = false});

  final bool focusSearch;

  @override
  State<CetokScreen> createState() => _CetokScreenState();
}

class _CetokScreenState extends State<CetokScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).cetok.open();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cetok = StoreScope.of(context).cetok;
    return ListenableBuilder(
      listenable: cetok,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cetok Online', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
              Text(
                cetok.loading
                    ? 'Memperbarui stok…'
                    : cetok.updated == null
                        ? 'Stok part gudang'
                        : 'Diperbarui ${_time(cetok.updated!)}',
                style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Perbarui stok',
              onPressed: cetok.loading ? null : cetok.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: AppColors.navy,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.orange,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_outlined, size: 20), text: 'Stok', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.outbox_outlined, size: 20), text: 'Ambil', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.add_box_outlined, size: 20), text: 'Input', iconMargin: EdgeInsets.only(bottom: 2)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _StockTab(cetok: cetok, focusSearch: widget.focusSearch),
            _FormScroll(child: TakeForm(cetok: cetok)),
            _FormScroll(child: AddForm(cetok: cetok)),
          ],
        ),
      ),
    );
  }
}

String _time(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
  return '${t.day}/${t.month} $hm';
}

class _FormScroll extends StatelessWidget {
  const _FormScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: child,
      );
}

/// The stock list: search, unit chips, location / status / empty filters.
class _StockTab extends StatefulWidget {
  const _StockTab({required this.cetok, required this.focusSearch});

  final Cetok cetok;
  final bool focusSearch;

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  String? _unit;
  String? _location;

  /// '' all, 'RFU', 'NOT RFU', or 'EMPTY' (no status).
  String _status = '';
  bool _emptyOnly = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CetokPart> get _rows => [
        for (final p in widget.cetok.parts)
          if ((_unit == null || p.unit == _unit) &&
              p.matches(_query.text) &&
              (!_emptyOnly || p.qty <= 0) &&
              (_location == null || p.loc.toLowerCase() == _location!.toLowerCase()) &&
              switch (_status) {
                'EMPTY' => p.status == null,
                '' => true,
                _ => p.status == _status,
              })
            p,
      ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cetok = widget.cetok;
    final rows = _rows;
    final query = _query.text.trim();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            autofocus: widget.focusSearch,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(_query.clear),
                    ),
              hintText: 'Cari part number atau nama part',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final unit in [null, ...cetok.units])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(unit ?? 'Semua', style: const TextStyle(fontSize: 12)),
                    selected: _unit == unit,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _unit = unit),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              _FilterButton(
                label: _location ?? 'Semua lokasi',
                active: _location != null,
                options: [('', 'Semua lokasi'), for (final l in cetok.locations) (l, l)],
                onSelected: (v) => setState(() => _location = v.isEmpty ? null : v),
              ),
              const SizedBox(width: 6),
              _FilterButton(
                label: switch (_status) {
                  'EMPTY' => 'Tanpa status',
                  '' => 'Semua status',
                  _ => _status,
                },
                active: _status.isNotEmpty,
                options: const [('', 'Semua status'), ('RFU', 'RFU'), ('NOT RFU', 'NOT RFU'), ('EMPTY', 'Tanpa status')],
                onSelected: (v) => setState(() => _status = v),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Stok kosong', style: TextStyle(fontSize: 12)),
                selected: _emptyOnly,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() => _emptyOnly = v),
              ),
            ],
          ),
        ),
        if (cetok.error != null)
          _Notice(
            text: cetok.parts.isEmpty
                ? cetok.error!
                : '${cetok.error!} Yang tampil stok terakhir${cetok.updated == null ? '' : ' (${_time(cetok.updated!)})'}.',
            onRetry: cetok.refresh,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: cetok.refresh,
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      Text(
                        cetok.parts.isEmpty
                            ? (cetok.loading ? 'Memuat stok…' : 'Belum ada data stok.')
                            : query.isNotEmpty
                                ? 'Tidak ada part number atau nama yang cocok dengan "$query".'
                                : 'Tidak ada part dengan filter ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: rows.length + 1,
                    separatorBuilder: (_, i) => i == rows.length - 1 ? const SizedBox(height: 8) : const SizedBox(height: 8),
                    itemBuilder: (context, i) => i == rows.length
                        ? Text('${rows.length} part', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted))
                        : PartRow(
                            part: rows[i],
                            highlight: query,
                            onTap: () => showPartSheet(context, cetok, rows[i]),
                          ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.label, required this.active, required this.options, required this.onSelected});

  final String label;
  final bool active;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: PopupMenuButton<String>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => [for (final (value, text) in options) PopupMenuItem(value: value, child: Text(text))],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.navySoft : AppColors.surface,
            border: Border.all(color: active ? AppColors.navy : AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: active ? AppColors.navy : AppColors.inkSoft)),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.greySoft,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.inkSoft))),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

/// RFU / NOT RFU / no status, like the website's badges.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'RFU' => (AppColors.greenSoft, AppColors.green),
      'NOT RFU' => (AppColors.orangeSoft, AppColors.orangeText),
      _ => (AppColors.greySoft, AppColors.muted),
    };
    return Pill(status ?? '–', background: bg, foreground: fg);
  }
}

/// One stock row: part number(s), name, status, location, unit and qty.
class PartRow extends StatelessWidget {
  const PartRow({super.key, required this.part, this.highlight = '', this.onTap});

  final CetokPart part;
  final String highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in part.numbers)
                  Text.rich(
                    _marked(n, highlight, AppColors.highlight),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                Text.rich(
                  _marked(part.desc, highlight, AppColors.highlight),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(part.status),
                    if (part.loc.isNotEmpty)
                      Pill(part.loc, background: AppColors.navySoft, foreground: AppColors.navy),
                    Text(part.unit, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
                if (part.remarks != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('KET: ${part.remarks}', style: TextStyle(fontSize: 11, color: AppColors.orangeText)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${part.qty}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: part.qty <= 0 ? AppColors.danger : AppColors.ink,
                ),
              ),
              Text('pcs', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

TextSpan _marked(String text, String query, Color mark) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return TextSpan(text: text);
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var at = 0;
  while (true) {
    final found = lower.indexOf(q, at);
    if (found < 0) break;
    if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
    spans.add(TextSpan(
      text: text.substring(found, found + q.length),
      style: TextStyle(backgroundColor: mark, color: const Color(0xFF1F2328)),
    ));
    at = found + q.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

/// A part's details with what can be done with it, as on the website (Ambil,
/// Pindahkan), plus opening its page in the unit's Partsbook.
Future<void> showPartSheet(BuildContext context, Cetok cetok, CetokPart part) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in part.numbers)
              SelectableText(n, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
            Text(part.desc, style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            _Facts(rows: [
              ('Unit', Text(part.unit)),
              ('Lokasi', Text(part.loc.isEmpty ? '–' : part.loc)),
              ('Status', Align(alignment: Alignment.centerLeft, child: StatusBadge(part.status))),
              ('Qty', Text('${part.qty} pcs', style: TextStyle(color: part.qty <= 0 ? AppColors.danger : null))),
              ('Keterangan', Text(part.remarks ?? '–')),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.orange, minimumSize: const Size.fromHeight(44)),
                    onPressed: part.qty <= 0
                        ? null
                        : () {
                            Navigator.pop(sheet);
                            _pushForm(context, 'Ambil barang', TakeForm(cetok: cetok, part: part));
                          },
                    icon: const Icon(Icons.outbox_outlined, size: 18),
                    label: const Text('Ambil'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: part.qty <= 0
                        ? null
                        : () {
                            Navigator.pop(sheet);
                            _pushForm(context, 'Pindahkan barang', MoveForm(cetok: cetok, part: part));
                          },
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Pindahkan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(44)),
              onPressed: () {
                Navigator.pop(sheet);
                openInPartsbook(context, part);
              },
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text('Buka di Partsbook ${unitModelCode(part.unit)}'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.rows});

  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 96, child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted))),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                    child: value,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

void _pushForm(BuildContext context, String title, Widget form) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _FormScroll(child: form),
    ),
  ));
}

/// Finds the part number in the unit's Partsbook and opens that page.
Future<void> openInPartsbook(BuildContext context, CetokPart part) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final code = unitModelCode(part.unit);
  bool ofUnit(ManualFile f) =>
      f.type == DocType.partsbook &&
      (unitModelCode(f.unitId) == code || unitModelCode(store.unitNameOf(f)) == code);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  if (part.numbers.isEmpty) {
    say('Part ini belum punya part number.');
    return;
  }
  if (!store.catalog.files.followedBy(store.local.values.map((m) => m.file)).any(ofUnit)) {
    say('Belum ada Partsbook $code di MyManual.');
    return;
  }
  say('Mencari ${part.numbers.first} di Partsbook $code…');
  final indexes = await store.aiIndexes(where: ofUnit);
  if (indexes.isEmpty) {
    say('Partsbook $code belum bisa dicari. Periksa sinyal internet.');
    return;
  }
  for (final number in part.numbers) {
    final result = await searchIndexes(indexes, number, limitPerFile: 1);
    if (result.hits.isEmpty) continue;
    final hit = result.hits.first;
    final file = store.fileByKey(hit.fileKey);
    if (file == null || !context.mounted) continue;
    messenger.hideCurrentSnackBar();
    await openViewer(context, file, page: hit.page, query: number);
    return;
  }
  say('${part.numbers.join(', ')} tidak ditemukan di Partsbook $code.');
}

// ---------------------------------------------------------------------------
// Forms

InputDecoration _field(String label, {String? hint, String? helper}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

const _upper = TextCapitalization.characters;

Future<bool> _confirm(BuildContext context, String title, String body, String yes) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(yes)),
      ],
    ),
  );
  return ok ?? false;
}

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

int? _qtyOf(TextEditingController c) => int.tryParse(c.text.trim());

/// A whole-number quantity with − and + buttons.
class _QtyField extends StatelessWidget {
  const _QtyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  void _step(int by) {
    final next = ((_qtyOf(controller) ?? 0) + by).clamp(0, 99999);
    controller.text = '$next';
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _field(label).copyWith(
        prefixIcon: IconButton(tooltip: 'Kurangi', icon: const Icon(Icons.remove), onPressed: () => _step(-1)),
        suffixIcon: IconButton(tooltip: 'Tambah', icon: const Icon(Icons.add), onPressed: () => _step(1)),
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'RFU', label: Text('RFU')),
        ButtonSegment(value: 'NOT RFU', label: Text('NOT RFU')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// A free-text location with the stock's locations as suggestions.
class _LocationField extends StatefulWidget {
  const _LocationField({required this.controller, required this.options, required this.label});

  final TextEditingController controller;
  final List<String> options;
  final String label;

  @override
  State<_LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<_LocationField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return widget.options.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: _upper,
        decoration: _field(widget.label, hint: 'cth: LOGISTIK, LAYDOWN'),
      ),
      optionsViewBuilder: (context, onSelected, options) => _Suggestions(
        children: [
          for (final o in options)
            ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
        ],
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
          child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: children),
        ),
      ),
    );
  }
}

/// Picks a stock row by typing its part number or name.
class _PartPicker extends StatefulWidget {
  const _PartPicker({required this.cetok, required this.controller, required this.onPicked});

  final Cetok cetok;
  final TextEditingController controller;
  final ValueChanged<CetokPart> onPicked;

  @override
  State<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends State<_PartPicker> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<CetokPart>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (p) => p.pn,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const [];
        return widget.cetok.parts.where((p) => p.matches(q)).take(30);
      },
      onSelected: widget.onPicked,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: _upper,
        decoration: _field('Parts number', hint: 'Ketik part number atau nama part'),
      ),
      optionsViewBuilder: (context, onSelected, options) => _Suggestions(
        children: [
          for (final p in options)
            ListTile(
              dense: true,
              title: Text(p.pn, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${p.desc} · ${p.unit} · ${p.loc.isEmpty ? '–' : p.loc} · ${p.status ?? '–'}'),
              trailing: Text('${p.qty}', style: TextStyle(color: p.qty <= 0 ? AppColors.danger : null)),
              onTap: () => onSelected(p),
            ),
        ],
      ),
    );
  }
}

class _PickedPart extends StatelessWidget {
  const _PickedPart({required this.part, this.onClear});

  final CetokPart part;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.pn, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(part.desc, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusBadge(part.status),
                  Text('${part.loc.isEmpty ? '–' : part.loc} · ${part.unit}',
                      style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ],
            ),
          ),
          Column(children: [
            Text('${part.qty}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('tersedia', style: TextStyle(fontSize: 10, color: AppColors.muted)),
          ]),
          if (onClear != null) IconButton(tooltip: 'Ganti part', onPressed: onClear, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.busy, required this.onPressed, this.color});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color ?? AppColors.navy, minimumSize: const Size.fromHeight(48)),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label),
    );
  }
}

/// Ambil: takes stock out (ambil_barang). With [part] it is fixed (opened
/// from a part's details) and the page closes when saved.
class TakeForm extends StatefulWidget {
  const TakeForm({super.key, required this.cetok, this.part});

  final Cetok cetok;
  final CetokPart? part;

  @override
  State<TakeForm> createState() => _TakeFormState();
}

class _TakeFormState extends State<TakeForm> {
  late CetokPart? _part = widget.part;
  final _pn = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_pn, _qty, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final part = _part;
    final qty = _qtyOf(_qty) ?? 0;
    final error = part == null
        ? 'Pilih parts number dari daftar stok'
        : qty <= 0
            ? 'Quantity harus lebih dari 0'
            : qty > part.qty
                ? 'Stok tidak cukup. Stok tersedia: ${part.qty}'
                : _note.text.trim().isEmpty
                    ? 'Keterangan keperluan wajib diisi'
                    : _name.text.trim().isEmpty
                        ? 'Nama pengambil wajib diisi'
                        : null;
    if (error != null) return _toast(context, error);
    final ok = await _confirm(
      context,
      'Ambil $qty pcs?',
      '${part!.pn} ${part.desc} dari ${part.loc.isEmpty ? '–' : part.loc} (${part.status ?? 'tanpa status'}).\n'
          'Sisa stok jadi ${part.qty - qty} pcs.\nKeperluan: ${_note.text.trim().toUpperCase()}',
      'Ya, ambil',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.take(part, qty: qty, note: _note.text, name: _name.text);
      if (!mounted) return;
      _toast(context, 'Ambil barang tersimpan untuk ${part.pn}');
      if (widget.part != null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _part = null;
        _pn.clear();
        _qty.text = '1';
        _note.clear();
      });
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final part = _part;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (part == null)
          _PartPicker(cetok: widget.cetok, controller: _pn, onPicked: (p) => setState(() => _part = p))
        else
          _PickedPart(part: part, onClear: widget.part == null ? () => setState(() => _part = null) : null),
        const SizedBox(height: 14),
        _QtyField(controller: _qty, label: 'Quantity diambil'),
        const SizedBox(height: 14),
        TextField(controller: _note, textCapitalization: _upper, decoration: _field('Keterangan keperluan')),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          textCapitalization: _upper,
          decoration: _field('Nama pengambil', helper: 'Diingat untuk transaksi berikutnya'),
        ),
        const SizedBox(height: 20),
        _SubmitButton(label: 'Simpan Ambil Barang', busy: _busy, onPressed: _save, color: AppColors.orange),
      ],
    );
  }
}

/// Pindahkan: moves stock to another location and/or status (transfer_stok).
class MoveForm extends StatefulWidget {
  const MoveForm({super.key, required this.cetok, required this.part});

  final Cetok cetok;
  final CetokPart part;

  @override
  State<MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends State<MoveForm> {
  late final _qty = TextEditingController(text: '${widget.part.qty}');
  final _location = TextEditingController();
  late String _status = widget.part.status ?? 'RFU';
  final _note = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_qty, _location, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final part = widget.part;
    final qty = _qtyOf(_qty) ?? 0;
    final location = _location.text.trim();
    final error = qty <= 0
        ? 'Quantity harus lebih dari 0'
        : qty > part.qty
            ? 'Stok tidak cukup. Stok tersedia: ${part.qty}'
            : location.isEmpty
                ? 'Lokasi tujuan wajib diisi'
                : _name.text.trim().isEmpty
                    ? 'Nama wajib diisi'
                    : location.toLowerCase() == part.loc.toLowerCase() && _status == (part.status ?? '')
                        ? 'Lokasi dan status tujuan sama dengan asal, tidak ada yang perlu dipindah'
                        : null;
    if (error != null) return _toast(context, error);
    final ok = await _confirm(
      context,
      'Pindahkan $qty pcs?',
      '${part.pn} ${part.desc}\n'
          'Dari ${part.loc.isEmpty ? '–' : part.loc} (${part.status ?? 'tanpa status'}) '
          'ke ${location.toUpperCase()} ($_status).',
      'Ya, pindahkan',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.move(part, qty: qty, location: location, status: _status, note: _note.text, name: _name.text);
      if (!mounted) return;
      _toast(context, '$qty pcs ${part.pn} dipindah ke ${location.toUpperCase()} ($_status)');
      Navigator.of(context).pop();
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PickedPart(part: widget.part),
        const SizedBox(height: 14),
        _QtyField(controller: _qty, label: 'Quantity dipindah'),
        const SizedBox(height: 14),
        _LocationField(controller: _location, options: widget.cetok.locations, label: 'Lokasi tujuan'),
        const SizedBox(height: 14),
        Text('Status tujuan', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 6),
        _StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
        const SizedBox(height: 14),
        TextField(controller: _note, textCapitalization: _upper, decoration: _field('Keterangan (opsional)')),
        const SizedBox(height: 14),
        TextField(controller: _name, textCapitalization: _upper, decoration: _field('Nama')),
        const SizedBox(height: 20),
        _SubmitButton(label: 'Simpan Transfer', busy: _busy, onPressed: _save),
      ],
    );
  }
}

/// Input: adds stock (input_barang). A part number that is already in stock
/// is suggested, so its quantity is added to that row instead of a new one.
class AddForm extends StatefulWidget {
  const AddForm({super.key, required this.cetok});

  final Cetok cetok;

  @override
  State<AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<AddForm> {
  String _unit = Cetok.unitModels.first;
  final _pn = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _qty = TextEditingController(text: '1');
  String _status = 'RFU';
  final _remarks = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_pn, _desc, _location, _qty, _remarks, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillFrom(CetokPart p) {
    setState(() {
      _pn.text = p.pn;
      _desc.text = p.desc;
      if (Cetok.unitModels.contains(p.unit)) _unit = p.unit;
      if (_location.text.trim().isEmpty) _location.text = p.loc;
    });
  }

  Future<void> _save() async {
    final qty = _qtyOf(_qty) ?? 0;
    final error = _pn.text.trim().isEmpty || _desc.text.trim().isEmpty
        ? 'Parts number dan description wajib diisi'
        : qty <= 0
            ? 'Quantity harus lebih dari 0'
            : _name.text.trim().isEmpty
                ? 'Nama penginput wajib diisi'
                : null;
    if (error != null) return _toast(context, error);
    final location = _location.text.trim().toUpperCase();
    final ok = await _confirm(
      context,
      'Input $qty pcs?',
      '${_pn.text.trim().toUpperCase()} ${_desc.text.trim().toUpperCase()}\n'
          '$_unit · ${location.isEmpty ? 'tanpa lokasi' : location} · $_status',
      'Ya, simpan',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.add(
        unit: _unit,
        pn: _pn.text,
        desc: _desc.text,
        location: _location.text,
        qty: qty,
        status: _status,
        remarks: _remarks.text,
        name: _name.text,
      );
      if (!mounted) return;
      _toast(context, 'Input tersimpan untuk ${_pn.text.trim().toUpperCase()} di $_unit ($_status)');
      setState(() {
        _pn.clear();
        _desc.clear();
        _location.clear();
        _qty.text = '1';
        _status = 'RFU';
        _remarks.clear();
      });
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _pn.text.trim();
    final similar = q.length < 3 ? const <CetokPart>[] : widget.cetok.parts.where((p) => p.matches(q)).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _unit,
          decoration: _field('Unit model'),
          items: [for (final u in Cetok.unitModels) DropdownMenuItem(value: u, child: Text(u))],
          onChanged: (u) => setState(() => _unit = u ?? _unit),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pn,
          textCapitalization: _upper,
          onChanged: (_) => setState(() {}),
          decoration: _field('Parts number'),
        ),
        if (similar.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final p in similar)
                  ListTile(
                    dense: true,
                    title: Text(p.pn, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p.desc} · ${p.unit} · ${p.loc.isEmpty ? '–' : p.loc} · ${p.qty} pcs'),
                    trailing: const Text('Pakai'),
                    onTap: () => _fillFrom(p),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        TextField(controller: _desc, textCapitalization: _upper, decoration: _field('Parts description')),
        const SizedBox(height: 14),
        _LocationField(controller: _location, options: widget.cetok.locations, label: 'Lokasi penyimpanan'),
        const SizedBox(height: 14),
        _QtyField(controller: _qty, label: 'Quantity'),
        const SizedBox(height: 14),
        Text('Status', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 6),
        _StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
        const SizedBox(height: 14),
        TextField(controller: _remarks, textCapitalization: _upper, decoration: _field('Remarks (opsional)')),
        const SizedBox(height: 14),
        TextField(controller: _name, textCapitalization: _upper, decoration: _field('Nama penginput')),
        const SizedBox(height: 20),
        _SubmitButton(label: 'Simpan Input Barang', busy: _busy, onPressed: _save),
      ],
    );
  }
}
