import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../auth.dart';
import '../models.dart';
import '../public_downloads.dart';
import '../quiz.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/unit_icon.dart';
import 'answer_reports_screen.dart';
import 'quiz_admin_screen.dart' show QuizEditScreen;
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
  late final TabController _tabs = TabController(length: 5, vsync: this);
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
        actions: [
          IconButton(
            tooltip: 'Laporan bulanan Excel',
            onPressed: _report,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
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
                  labels: StatsFilter.periodLabels,
                  selected: StatsFilter.periods.indexOf(_filter.period),
                  onSelected: (i) => _setFilter(_filter.copyWith(period: StatsFilter.periods[i])),
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
                            onTap: () => _setFilter(_filter.copyWith(section: section)),
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
                        trend: data?.trendActive,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Number(
                        value: data == null ? '–' : '${data.opens}',
                        label: 'Manual dibuka',
                        trend: data?.trendOpens,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Number(
                        value: data == null ? '–' : '${data.ai}',
                        label: 'Tanya nyel AI',
                        trend: data?.trendAi,
                      ),
                    ),
                  ],
                ),
                if (data != null && data.needsAction) ...[
                  const SizedBox(height: 8),
                  _ActionCard(data: data, onTap: () => _act(data)),
                ],
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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [Tab(text: 'Manual'), Tab(text: 'nyel AI'), Tab(text: 'Cari'), Tab(text: 'Pengguna'), Tab(text: 'Quiz')],
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
    // With one section chosen, rows need not say it again.
    final showSection = _filter.section.isEmpty;
    final views = [
      _ManualTab(data: data, onManual: _showManual),
      _AiTab(data: data, onQuestion: _showAnswer, showSection: showSection),
      _SearchTab(data: data, onMissing: _showSearch),
      _PeopleTab(data: data, onPerson: _openPerson, onInactive: _openInactive, showSection: showSection),
      _QuizTab(
        key: ValueKey(_filter.key),
        api: _api,
        filter: _filter,
        onQuestion: _showQuizQuestion,
        onNever: (people) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _InactivePage(people: people, sections: _sections, title: 'belum ikut quiz'),
        )),
        showSection: showSection,
      ),
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
        showSection: _filter.section.isEmpty,
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

  void _showQuizQuestion(String id) => _sheet(_QuizQuestionSheet(load: _api.quizQuestion(_filter, id)));

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

  /// "Perlu tindakan": to the searches that found nothing, or else to the
  /// answers rated wrong.
  void _act(StatsOverview data) {
    if (data.missing.isNotEmpty) {
      _tabs.animateTo(2);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnswerReportsScreen()));
    }
  }

  Future<void> _report() async {
    final now = DateTime.now();
    final months = [for (var i = 0; i < 3; i++) DateTime(now.year, now.month - i)];
    final month = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Laporan bulanan Excel', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _filter.section.isEmpty ? 'Semua section' : _filter.section,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            for (final (i, m) in months.indexed)
              ListTile(
                leading: Icon(Icons.table_chart_outlined, color: AppColors.navy),
                title: Text(monthLabel(m)),
                subtitle: i == 0 ? const Text('Bulan berjalan') : null,
                onTap: () => Navigator.pop(context, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (month == null || !mounted) return;
    final store = StoreScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final key = '${month.year}-${_two(month.month)}';
    final name = 'Statistik MyManual $key${_filter.section.isEmpty ? '' : ' ${_filter.section}'}.xlsx';
    final path = p.join(store.root.path, 'reports', name);
    messenger.showSnackBar(const SnackBar(content: Text('Membuat laporan…')));
    try {
      await _api.report(key, _filter.section, path);
      final downloads = PublicDownloads.instance;
      if (await downloads.supported()) {
        await downloads.save(path, name);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: const Text('Tersimpan di Download/MyManual'),
          action: SnackBarAction(
            label: 'Buka',
            onPressed: () async {
              if (!await downloads.open(name)) {
                messenger.showSnackBar(const SnackBar(content: Text('Belum ada aplikasi untuk membuka Excel')));
              }
            },
          ),
        ));
      } else {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('Tersimpan: $path')));
      }
    } on AuthException catch (e) {
      messenger.hideCurrentSnackBar();
      if (mounted) showError(context, e);
    } on Exception {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Laporan tidak bisa disimpan')));
    }
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// "Oktober 2026".
String monthLabel(DateTime m) => '${_months[m.month - 1]} ${m.year}';

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
  const _Number({required this.value, required this.label, this.trend});

  final String value;
  final String label;

  /// Percent against the period before; null = nothing to compare with.
  final int? trend;

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
            if (trend case final t?)
              Text(
                '${t >= 0 ? '▲' : '▼'} ${t.abs()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t >= 0 ? AppColors.green : AppColors.danger,
                ),
              ),
          ],
        ),
      );
}

/// One line under the numbers that leads to what an admin can fix.
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data, required this.onTap});

  final StatsOverview data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (data.missing.isNotEmpty) '${data.missing.length} kata tidak ketemu',
      if (data.bad > 0) '${data.bad} jawaban dinilai salah',
    ];
    return Material(
      color: AppColors.orangeSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Perlu tindakan  ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: parts.join(' · ')),
                  ]),
                  style: TextStyle(fontSize: 12, color: AppColors.ink),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppColors.orangeText),
            ],
          ),
        ),
      ),
    );
  }
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
  const _QuestionTile(this.q, {required this.onTap, this.showName = true, this.showSection = true});

  final QuestionRow q;
  final VoidCallback onTap;
  final bool showName;
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final meta = [
      if (showName) q.name,
      if (showName && showSection && q.sections.isNotEmpty) q.sections.join(', '),
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
  const _AiTab({required this.data, required this.onQuestion, this.showSection = true});

  final StatsOverview data;
  final ValueChanged<int> onQuestion;
  final bool showSection;

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
        const _Caps('Penilaian jawaban'),
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
          _Rows([
            for (final q in data.questions) _QuestionTile(q, showSection: showSection, onTap: () => onQuestion(q.id)),
          ]),
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
  const _PeopleTab({required this.data, required this.onPerson, required this.onInactive, this.showSection = true});

  final StatsOverview data;
  final ValueChanged<String> onPerson;
  final VoidCallback onInactive;
  final bool showSection;

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
                      if (s.hasManual) ...[
                        Expanded(child: _Bar(s.total == 0 ? 0 : s.active / s.total)),
                        SizedBox(
                          width: 52,
                          child: Text('${s.active}/${s.total}',
                              textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                        ),
                      ] else
                        Expanded(
                          child: Text('belum ada manual',
                              textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                            Text(showSection ? '${p.nrp} · ${p.sections.join(', ')}' : p.nrp,
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
  const _SearchSheet({required this.load, required this.onHandled, this.showSection = true});

  final Future<SearchStats> load;
  final Future<void> Function() onHandled;
  final bool showSection;

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
                          if (showSection)
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
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text('Terakhir aktif ${whenLabel(p.last)}',
                                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                _Tag(p.app.isEmpty ? 'app lama' : 'App ${p.app}', warn: p.app.isEmpty),
                              ],
                            ),
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
  const _InactivePage({required this.people, required this.sections, this.title = 'belum aktif'});

  final List<InactiveRow> people;
  final List<String> sections;
  final String title;

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
        title: Text('${people.length} $title'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
        actions: [
          IconButton(
            tooltip: 'Salin daftar',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inactiveText(people, order, groups)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daftar disalin')));
              }
            },
          ),
        ],
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p.never || p.last == null ? 'Belum pernah login' : 'Terakhir ${daysAgo(p.last)}',
                            style: TextStyle(fontSize: 11, color: p.never ? AppColors.amber : AppColors.muted),
                          ),
                          if (p.oldApp && !p.never) ...[
                            const SizedBox(height: 3),
                            const _Tag('app lama', warn: true),
                          ],
                        ],
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

/// A small label: the app version, or "app lama" in amber.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.warn = false, this.danger = false});

  final String text;
  final bool warn;

  /// Red instead of amber.
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: danger ? AppColors.danger.withValues(alpha: .12) : (warn ? AppColors.amberSoft : AppColors.greenSoft),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: danger ? AppColors.danger : (warn ? AppColors.amber : AppColors.green),
          ),
        ),
      );
}

/// The "belum aktif" list as text for WhatsApp, by section.
String inactiveText(List<InactiveRow> people, List<String> order, Map<String, List<InactiveRow>> groups) {
  final b = StringBuffer('Belum aktif di MyManual (${people.length} orang)\n');
  for (final section in order) {
    b.write('\n*$section* (${groups[section]!.length})\n');
    for (final (i, p) in groups[section]!.indexed) {
      final note = p.never || p.last == null ? 'belum pernah login' : 'terakhir ${daysAgo(p.last)}';
      b.write('${i + 1}. ${p.name} (${p.nrp}) - $note${p.oldApp && !p.never ? ', app lama' : ''}\n');
    }
  }
  return b.toString().trimRight();
}

// ── Quiz ───────────────────────────────────────────────────────────────

/// Quiz: who plays, which topics and questions go wrong, who is ahead.
/// Loads its own numbers, only once the tab is opened.
class _QuizTab extends StatefulWidget {
  const _QuizTab({
    super.key,
    required this.api,
    required this.filter,
    required this.onQuestion,
    required this.onNever,
    this.showSection = true,
  });

  final StatsApi api;
  final StatsFilter filter;
  final ValueChanged<String> onQuestion;
  final ValueChanged<List<InactiveRow>> onNever;
  final bool showSection;

  @override
  State<_QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<_QuizTab> with AutomaticKeepAliveClientMixin {
  late Future<QuizStats> _data = widget.api.quiz(widget.filter);

  @override
  bool get wantKeepAlive => true;

  Color _scoreColor(int pct) => pct < 60 ? AppColors.danger : (pct < 75 ? AppColors.amber : AppColors.navy);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<QuizStats>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: EmptyState(
              icon: Icons.wifi_off,
              title: 'Gagal memuat quiz',
              action: TextButton(
                onPressed: () => setState(() => _data = widget.api.quiz(widget.filter)),
                child: const Text('Coba lagi'),
              ),
            ),
          );
        }
        final d = snap.data;
        if (d == null) return const Center(child: ExcavatorLoader(label: 'Memuat quiz…'));
        final muted = TextStyle(fontSize: 11, color: AppColors.muted);
        return ListView(
          padding: _listPadding,
          children: [
            const _Caps('Ringkasan quiz'),
            _Tiles([
              ('${d.players}/${d.users}', 'Ikut quiz'),
              ('${d.correct}%', d.trendCorrect == null ? 'Benar' : 'Benar ${d.trendCorrect! >= 0 ? '▲' : '▼'}${d.trendCorrect!.abs()}'),
              ('${d.sets}', 'Set selesai'),
            ]),
            if (widget.showSection && d.perSection.isNotEmpty) ...[
              const _Caps('Ikut quiz per section'),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    for (final s in d.perSection)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(width: 76, child: Text(s.section, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(child: _Bar(s.total == 0 ? 0 : s.players / s.total)),
                            SizedBox(
                              width: 52,
                              child: Text('${s.players}/${s.total}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const _Caps('Topik terlemah'),
            if (d.topics.isEmpty)
              const _None('Belum ada jawaban.')
            else
              _Rows([
                for (final t in d.topics.take(5))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(quizTopics[t.topic] ?? t.topic, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('${t.answers} jawaban', style: muted),
                              const SizedBox(height: 6),
                              _ScoreBar(t.correct / 100, color: _scoreColor(t.correct)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${t.correct}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            const _Caps('Soal paling sering salah'),
            if (d.hard.isEmpty)
              const _None('Belum ada soal dengan 5 jawaban atau lebih.')
            else
              _Rows([
                for (final q in d.hard)
                  InkWell(
                    onTap: () => widget.onQuestion(q.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.prompt,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text([if (q.unit.isNotEmpty) q.unit, quizTopics[q.topic] ?? q.topic, '${q.answers} jawaban'].join(' · '),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Tag('${q.correct}% benar', warn: true, danger: q.correct < 40),
                          Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                        ],
                      ),
                    ),
                  ),
              ]),
            const _Caps('Paling rajin'),
            if (d.top.isEmpty)
              const _None('Belum ada yang ikut quiz.')
            else
              _Rows([
                for (final (i, p) in d.top.indexed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ),
                        _Initials(p.name, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text([if (widget.showSection) p.section, if (p.streak > 0) 'streak ${p.streak} hari'].join(' · '), style: muted),
                            ],
                          ),
                        ),
                        Text('${p.xp} XP', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            if (d.never.isNotEmpty) ...[
              const _Caps('Belum pernah ikut quiz'),
              AppCard(
                onTap: () => widget.onNever(d.never),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d.never.length} orang', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(_neverBySection(d.never), style: muted),
                        ],
                      ),
                    ),
                    Text('Lihat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _neverBySection(List<InactiveRow> people) {
    final n = <String, int>{};
    for (final p in people) {
      final s = p.sections.firstOrNull ?? defaultSection;
      n[s] = (n[s] ?? 0) + 1;
    }
    return [for (final e in n.entries) '${e.key} ${e.value}'].join(' · ');
  }
}

/// A bar in a status colour (red, amber or navy).
class _ScoreBar extends StatelessWidget {
  const _ScoreBar(this.fraction, {required this.color});

  final double fraction;
  final Color color;

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
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      );
}

/// A question that often goes wrong: which choice people pick, then
/// Buka manual, Ubah soal or Tarik soal.
class _QuizQuestionSheet extends StatelessWidget {
  const _QuizQuestionSheet({required this.load});

  final Future<QuizQuestionStats> load;

  @override
  Widget build(BuildContext context) => _Loading<QuizQuestionStats>(
        load: load,
        show: (context, s) {
          final admin = AdminQuestion(s.question);
          final q = admin.question;
          final total = s.picks.fold<int>(0, (a, b) => a + b);
          final rightPct = total == 0 ? 0 : (s.picks.elementAtOrNull(q.answer) ?? 0) * 100 ~/ total;
          final store = StoreScope.read(context);
          final file = q.manualId.isEmpty ? null : store.fileByKey(q.manualId);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                [if (q.unit != null) q.unit!, q.topicName, if (q.page > 0) 'hal. ${q.page}'].join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.45)),
              const SizedBox(height: 4),
              Text('${s.answers} jawaban · $rightPct% benar', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              for (final (i, c) in q.choices.indexed) ...[
                Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == q.answer ? FontWeight.w600 : FontWeight.w400,
                            color: i == q.answer ? AppColors.green : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: _ScoreBar(
                          total == 0 ? 0 : (s.picks.elementAtOrNull(i) ?? 0) / total,
                          color: i == q.answer ? AppColors.green : AppColors.faint,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${total == 0 ? 0 : (s.picks.elementAtOrNull(i) ?? 0) * 100 ~/ total}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: file == null
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ViewerScreen(fileKey: file.key, initialPage: q.page),
                              )),
                      child: const Text('Buka manual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizEditScreen(question: admin))),
                      child: const Text('Ubah soal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Tarik soal ini?'),
                      content: const Text('Soal tidak muncul lagi di quiz.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tarik')),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await QuizApi(store, http.Client()).decide(q.id, 'tarik');
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soal ditarik')));
                  } on Object catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Tarik soal'),
              ),
            ],
          );
        },
      );
}
