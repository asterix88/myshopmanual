import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/unit_icon.dart';
import 'answer_reports_screen.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Admins: how the mechanics use the app, so it is clear what they need.
/// Period and section filters and three numbers on top; tabs Manual,
/// nyel AI, Cari and Pengguna below, swiped left and right.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.client});

  /// For tests; the app uses its own.
  final http.Client? client;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late final http.Client _client = widget.client ?? http.Client();
  late final StatsApi _api = StatsApi(StoreScope.read(context), _client);

  StatsFilter _filter = const StatsFilter();
  StatsOverview? _data;
  List<String> _sections = const ['TRACK', 'WHEEL', 'SUPPORT'];
  bool _loading = true;
  bool _offline = false;
  String? _error;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    final run = ++_run;
    final filter = _filter;
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await _api.cached(filter);
    if (!mounted || run != _run) return;
    setState(() => _data = cached);
    try {
      // This phone's own latest use counts too.
      if (first) await StoreScope.read(context).usage.send();
      final data = await _api.overview(filter);
      if (!mounted || run != _run) return;
      setState(() {
        _data = data;
        if (data.sectionList.isNotEmpty) _sections = data.sectionList;
        _offline = false;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _loading = false;
        _offline = e.code == 'network';
        if (!_offline) _error = e.message;
      });
    }
  }

  void _setFilter(StatsFilter filter) {
    if (filter.key == _filter.key) return;
    _filter = filter;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik pemakaian'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_offline) const _OfflineBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Segmented(
                  labels: const ['30 hari', 'Semua waktu'],
                  selected: _filter.allTime ? 1 : 0,
                  onSelected: (i) => _setFilter(StatsFilter(allTime: i == 1, section: _filter.section)),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final section in ['', ..._sections])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Chip(
                            label: section.isEmpty ? 'Semua' : section,
                            selected: _filter.section == section,
                            onTap: () => _setFilter(StatsFilter(allTime: _filter.allTime, section: section)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Number(
                        value: data == null ? '–' : '${data.active} / ${data.users}',
                        label: 'Pengguna aktif',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _Number(value: data == null ? '–' : '${data.opens}', label: 'Manual dibuka')),
                    const SizedBox(width: 8),
                    Expanded(child: _Number(value: data == null ? '–' : '${data.ai}', label: 'Tanya nyel AI')),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.navy,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.orange,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: AppColors.line,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [Tab(text: 'Manual'), Tab(text: 'nyel AI'), Tab(text: 'Cari'), Tab(text: 'Pengguna')],
          ),
          Expanded(child: _body(data)),
        ],
      ),
    );
  }

  Widget _body(StatsOverview? data) {
    if (data == null) {
      if (_loading) return const Center(child: ExcavatorLoader(label: 'Memuat statistik…'));
      return Center(
        child: EmptyState(
          icon: _offline ? Icons.wifi_off : Icons.error_outline,
          title: _error ?? 'Statistik butuh internet',
          action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ),
      );
    }
    if (data.isEmpty) {
      return _Empty(caption: '${_filter.section.isEmpty ? 'Semua section' : _filter.section} · ${_filter.periodLabel}');
    }
    final views = [
      _ManualTab(data: data, onManual: _showManual),
      _AiTab(data: data, onQuestion: _showAnswer),
      _SearchTab(data: data, onMissing: _showSearch),
      _PeopleTab(data: data, onPerson: _openPerson, onInactive: _openInactive),
    ];
    return TabBarView(
      controller: _tabs,
      children: [for (final v in views) RefreshIndicator(onRefresh: _load, child: v)],
    );
  }

  Future<void> _sheet(Widget child) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.surface,
        builder: (_) => StoreScope(
          store: StoreScope.read(context),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: child,
          ),
        ),
      );

  void _showManual(String file) => _sheet(_ManualSheet(
        load: _api.manual(_filter, file),
        filter: _filter,
        onPerson: (nrp) {
          Navigator.pop(context);
          _openPerson(nrp);
        },
      ));

  void _showAnswer(int id) => _sheet(_AnswerSheet(
        load: _api.answer(id),
        onPerson: (nrp) {
          Navigator.pop(context);
          _openPerson(nrp);
        },
      ));

  void _showSearch(String query) => _sheet(_SearchSheet(
        load: _api.search(_filter, query),
        onHandled: () async {
          try {
            await _api.markHandled(query);
          } on AuthException catch (e) {
            if (mounted) showError(context, e);
            return;
          }
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ditandai sudah ditangani')));
          _load();
        },
      ));

  void _openPerson(String nrp) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PersonPage(api: _api, filter: _filter, nrp: nrp, onQuestion: _showAnswer),
      ));

  void _openInactive() {
    final data = _data;
    if (data == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _InactivePage(people: data.inactive, sections: _sections),
    ));
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

/// "10.42" today, "kemarin", "3 hari lalu", or a date.
String whenLabel(DateTime? t, {DateTime? now}) {
  if (t == null) return '–';
  now ??= DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return '${_two(t.hour)}.${_two(t.minute)}';
  if (days == 1) return 'kemarin';
  if (days < 30) return '$days hari lalu';
  return '${t.day}/${t.month}/${t.year}';
}

/// "hari ini", "kemarin", "N hari lalu".
String daysAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '–';
  now ??= DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  return days <= 0 ? 'hari ini' : days == 1 ? 'kemarin' : '$days hari lalu';
}

String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return (words.length == 1 ? words.first.substring(0, words.first.length.clamp(0, 2)) : '${words[0][0]}${words[1][0]}')
      .toUpperCase();
}

String _unitName(AppStore store, String unit) => store.unitById(unit)?.name ?? unit;

/// The unit's name, or "Semua section" for a manual every section reads.
String _unitLine(AppStore store, String unit, {bool? shared}) =>
    (shared ?? store.unitById(unit)?.section == sharedSection) ? 'Semua section' : _unitName(store, unit);

class _Caps extends StatelessWidget {
  const _Caps(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.muted),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class _Bar extends StatelessWidget {
  const _Bar(this.fraction);

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.greySoft),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0,
                child: ColoredBox(color: AppColors.navy),
              ),
            ],
          ),
        ),
      );
}

class _Number extends StatelessWidget {
  const _Number({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: value == '–' ? AppColors.faint : null),
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: i == selected ? cardShadow : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                        color: i == selected ? AppColors.navy : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      );
}

class _OfflineBar extends StatelessWidget {
  const _OfflineBar();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.amberSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.wifi_off, size: 18, color: AppColors.amber),
            const SizedBox(width: 10),
            Text('Koneksi terputus',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.amber)),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.bar_chart_rounded, color: AppColors.navy, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Belum ada pemakaian', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(caption, style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      );
}

/// A line of muted text where a list has nothing yet.
class _None extends StatelessWidget {
  const _None(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.muted)),
      );
}

/// Rows in one card, with thin lines between them.
class _Rows extends StatelessWidget {
  const _Rows(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.divider),
              child,
            ],
          ],
        ),
      );
}

/// The unit's picture, or a document tile when there is none.
class _ManualIcon extends StatelessWidget {
  const _ManualIcon({required this.unit, required this.title, this.size = 40});

  final String unit;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (UnitIcon.pictures.contains(UnitIcon.modelCode(unit))) {
      return UnitIcon(unitId: unit, width: size * 1.3, height: size);
    }
    return SizedBox(
      width: size * 1.3,
      child: Center(child: DocTile(glyphForTitle(title) ?? AppGlyph.general, size: size)),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.name, {this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
        child: Text(
          initials(name),
          style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: AppColors.navy),
        ),
      );
}

class _Tiles extends StatelessWidget {
  const _Tiles(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final (i, (value, label)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
}

const _listPadding = EdgeInsets.fromLTRB(16, 0, 16, 32);

// ── Tabs ───────────────────────────────────────────────────────────────

class _ManualTab extends StatelessWidget {
  const _ManualTab({required this.data, required this.onManual});

  final StatsOverview data;
  final ValueChanged<String> onManual;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final top = data.manuals.fold(1, (a, m) => m.n > a ? m.n : a);
    final unitTop = data.units.fold(1, (a, u) => u.n > a ? u.n : a);
    return ListView(
      padding: _listPadding,
      children: [
        const _Caps('Paling sering dibuka'),
        if (data.manuals.isEmpty)
          const _None('Belum ada manual dibuka.')
        else
          _Rows([
            for (final m in data.manuals)
              InkWell(
                onTap: () => onManual(m.file),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      _ManualIcon(unit: m.unit, title: m.title),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(m.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Text('${m.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _Bar(m.n / top),
                            const SizedBox(height: 5),
                            Text(
                              '${_unitLine(store, m.unit, shared: m.shared)} · ${m.people} orang',
                              style: TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ]),
        if (data.units.isNotEmpty) ...[
          const _Caps('Per unit'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              children: [
                for (final u in data.units)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(_unitName(store, u.unit),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(child: _Bar(u.n / unitTop)),
                        SizedBox(
                          width: 40,
                          child: Text('${u.n}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile(this.q, {required this.onTap, this.showName = true});

  final QuestionRow q;
  final VoidCallback onTap;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final meta = [
      if (showName) q.name,
      if (showName && q.sections.isNotEmpty) q.sections.join(', '),
      if (q.unit.isNotEmpty) _unitName(store, q.unit),
      whenLabel(q.at),
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(meta.join(' · '), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class _AiTab extends StatelessWidget {
  const _AiTab({required this.data, required this.onQuestion});

  final StatsOverview data;
  final ValueChanged<int> onQuestion;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _listPadding,
      children: [
        const _Caps('Topik paling ditanya'),
        if (data.topics.isEmpty)
          const _None('Belum ada pertanyaan.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in data.topics)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: cardShadow,
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: t.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${t.n}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ])),
                ),
            ],
          ),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final (icon, color, text) in [
                      (Icons.thumb_up_alt_outlined, AppColors.green, '${data.good} membantu'),
                      (Icons.thumb_down_alt_outlined, AppColors.danger, '${data.bad} salah'),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AnswerReportsScreen()),
                ),
                child: const Text('Lihat'),
              ),
            ],
          ),
        ),
        const _Caps('Pertanyaan terbaru'),
        if (data.questions.isEmpty)
          const _None('Belum ada pertanyaan.')
        else
          _Rows([for (final q in data.questions) _QuestionTile(q, onTap: () => onQuestion(q.id))]),
      ],
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({required this.data, required this.onMissing});

  final StatsOverview data;
  final ValueChanged<String> onMissing;

  @override
  Widget build(BuildContext context) {
    final top = data.searches.fold(1, (a, s) => s.n > a ? s.n : a);
    return ListView(
      padding: _listPadding,
      children: [
        const _Caps('Paling dicari'),
        if (data.searches.isEmpty)
          const _None('Belum ada pencarian.')
        else
          _Rows([
            for (final s in data.searches)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text('${s.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _Bar(s.n / top),
                  ],
                ),
              ),
          ]),
        _Caps('Tidak ketemu', trailing: Text('0 hasil', style: TextStyle(fontSize: 11, color: AppColors.muted))),
        if (data.missing.isEmpty)
          const _None('Semua pencarian ketemu di manual.')
        else
          _Rows([
            for (final s in data.missing)
              InkWell(
                onTap: () => onMissing(s.query),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text('${s.n}× · ${s.people} orang', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({required this.data, required this.onPerson, required this.onInactive});

  final StatsOverview data;
  final ValueChanged<String> onPerson;
  final VoidCallback onInactive;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _listPadding,
      children: [
        const _Caps('Aktif per section'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            children: [
              for (final s in data.perSection)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(s.section, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(child: _Bar(s.total == 0 ? 0 : s.active / s.total)),
                      SizedBox(
                        width: 52,
                        child: Text('${s.active}/${s.total}',
                            textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _Caps(
          'Paling aktif',
          trailing: data.inactive.isEmpty
              ? null
              : InkWell(
                  onTap: onInactive,
                  child: Text(
                    '${data.inactive.length} belum aktif',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ),
        ),
        if (data.people.isEmpty)
          const _None('Belum ada yang memakai aplikasi.')
        else
          _Rows([
            for (final p in data.people)
              InkWell(
                onTap: () => onPerson(p.nrp),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      _Initials(p.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('${p.nrp} · ${p.sections.join(', ')}',
                                style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${p.manuals} manual · ${p.ai} AI', style: const TextStyle(fontSize: 12)),
                          Text(whenLabel(p.last), style: TextStyle(fontSize: 11, color: AppColors.faint)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}

// ── Sheets and pages ───────────────────────────────────────────────────

/// A sheet that waits for [load], then shows [show].
class _Loading<T> extends StatelessWidget {
  const _Loading({required this.load, required this.show});

  final Future<T> load;
  final Widget Function(BuildContext context, T data) show;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: load,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return EmptyState(
              icon: Icons.wifi_off,
              title: e is AuthException ? e.message : 'Koneksi terputus',
            );
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: ExcavatorLoader(label: 'Memuat…')),
            );
          }
          return show(context, snap.data as T);
        },
      );
}

class _ManualSheet extends StatelessWidget {
  const _ManualSheet({required this.load, required this.filter, required this.onPerson});

  final Future<ManualStats> load;
  final StatsFilter filter;
  final ValueChanged<String> onPerson;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return _Loading<ManualStats>(
      load: load,
      show: (context, m) {
        final section = store.unitById(m.unit)?.section;
        final chapterTop = m.chapters.fold(1, (a, c) => c.n > a ? c.n : a);
        final file = store.fileByKey(m.file);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                _ManualIcon(unit: m.unit, title: m.title, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(
                        [
                          _unitName(store, m.unit),
                          section == null ? null : (section == sharedSection ? 'Semua section' : section),
                          filter.periodLabel,
                        ].whereType<String>().join(' · '),
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Tiles([('${m.opens}×', 'Dibuka'), ('${m.people}', 'Orang'), ('${m.downloads}', 'Diunduh')]),
            if (m.chapters.isNotEmpty) ...[
              const _Caps('Bab paling sering dilihat'),
              for (final c in m.chapters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(c.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ),
                          Text('${c.n}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _Bar(c.n / chapterTop),
                    ],
                  ),
                ),
            ],
            if (m.readers.isNotEmpty) ...[
              const _Caps('Paling sering membuka'),
              for (final r in m.readers)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onPerson(r.nrp),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        _Initials(r.name, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Text('${r.n}×', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
            ],
            if (file != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  openViewer(context, file);
                },
                child: const Text('Buka manual'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet({required this.load, required this.onPerson});

  final Future<AnswerStats> load;
  final ValueChanged<String> onPerson;

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return _Loading<AnswerStats>(
      load: widget.load,
      show: (context, a) {
        final q = a.question;
        final meta = [
          q.sections.join(', '),
          if (q.unit.isNotEmpty) _unitName(store, q.unit),
          whenLabel(q.at),
        ].where((s) => s.isNotEmpty);
        final (IconData icon, Color color, String rated) = switch (a.rating) {
          'good' => (Icons.thumb_up_alt_outlined, AppColors.green, 'Dinilai membantu'),
          'bad' => (Icons.thumb_down_alt_outlined, AppColors.danger, 'Dinilai salah'),
          _ => (Icons.remove_circle_outline, AppColors.faint, 'Belum dinilai'),
        };
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(q.question, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => widget.onPerson(q.nrp),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: q.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy)),
                TextSpan(text: ' · ${meta.join(' · ')}'),
              ]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            const _Caps('Jawaban nyel AI'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.answer.isEmpty ? '–' : a.answer,
                    maxLines: _full ? null : 5,
                    overflow: _full ? null : TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
                  ),
                  if (a.sources.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in a.sources)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(AppGlyph.shopManual, size: 14),
                                const SizedBox(width: 4),
                                Text(s, style: TextStyle(fontSize: 11, color: AppColors.navy)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$rated${a.topic.isEmpty ? '' : ' · topik ${a.topic}'}',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            if (!_full && a.answer.length > 200)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _full = true),
                  child: const Text('Lihat jawaban lengkap'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchSheet extends StatelessWidget {
  const _SearchSheet({required this.load, required this.onHandled});

  final Future<SearchStats> load;
  final Future<void> Function() onHandled;

  @override
  Widget build(BuildContext context) => _Loading<SearchStats>(
        load: load,
        show: (context, s) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(s.query, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('0 hasil di semua manual',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amber)),
            const SizedBox(height: 14),
            _Tiles([('${s.n}×', 'Dicari'), ('${s.people}', 'Orang')]),
            const _Caps('Yang mencari'),
            for (final w in s.who)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    _Initials(w.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(w.sections.join(', '), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Text(whenLabel(w.at), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onHandled, child: const Text('Tandai sudah ditangani')),
          ],
        ),
      );
}

class _PersonPage extends StatelessWidget {
  const _PersonPage({required this.api, required this.filter, required this.nrp, required this.onQuestion});

  final StatsApi api;
  final StatsFilter filter;
  final String nrp;
  final ValueChanged<int> onQuestion;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengguna'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: _Loading<PersonStats>(
        load: api.person(filter, nrp),
        show: (context, p) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _Initials(p.name.isEmpty ? nrp : p.name, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name.isEmpty ? nrp : p.name,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            Text('${p.nrp} · ${p.sections.join(', ')}',
                                style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            Text('Terakhir aktif ${whenLabel(p.last)}',
                                style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Tiles([
                    ('${p.manualsOpened}', 'Manual dibuka'),
                    ('${p.ai}', 'Tanya nyel AI'),
                    ('${p.searches}', 'Pencarian'),
                  ]),
                ],
              ),
            ),
            const _Caps('Manual yang dibuka'),
            if (p.manuals.isEmpty)
              const _None('Belum membuka manual.')
            else
              _Rows([
                for (final m in p.manuals)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        _ManualIcon(unit: m.unit, title: m.title, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(_unitLine(store, m.unit), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Text('${m.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            const _Caps('Pertanyaan terakhir'),
            if (p.questions.isEmpty)
              const _None('Belum bertanya ke nyel AI.')
            else
              _Rows([
                for (final q in p.questions) _QuestionTile(q, showName: false, onTap: () => onQuestion(q.id)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _InactivePage extends StatelessWidget {
  const _InactivePage({required this.people, required this.sections});

  final List<InactiveRow> people;
  final List<String> sections;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<InactiveRow>>{};
    for (final p in people) {
      groups.putIfAbsent(p.sections.firstOrNull ?? defaultSection, () => []).add(p);
    }
    final order = [
      ...sections.where(groups.containsKey),
      ...groups.keys.where((s) => !sections.contains(s)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${people.length} belum aktif'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: ListView(
        padding: _listPadding,
        children: [
          for (final section in order) ...[
            _Caps('$section · ${groups[section]!.length}'),
            _Rows([
              for (final p in groups[section]!)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      _Initials(p.name, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(p.nrp, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Text(
                        p.never || p.last == null ? 'Belum pernah login' : 'Terakhir ${daysAgo(p.last)}',
                        style: TextStyle(fontSize: 11, color: p.never ? AppColors.amber : AppColors.muted),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
