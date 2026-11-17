/// Statistik pemakaian (admins only). This file holds the screen itself:
/// period/section filters, the three numbers on top and the tab bar.
/// Everything else lives under `stats/`:
///
/// - `manual_tab.dart`, `ai_tab.dart`, `search_tab.dart`, `people_tab.dart`,
///   `quiz_tab.dart`   one file per tab
/// - `sheets.dart`        bottom sheets: a manual, a nyel AI answer, a search
/// - `person_pages.dart`  one person's page and the "belum aktif" list
/// - `widgets.dart`       small pieces every tab shares
/// - `format.dart`        date/name text helpers (tested in stats_test.dart)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../auth.dart';
import '../public_downloads.dart';
import '../stats.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'answer_reports_screen.dart';
import 'shell.dart';
import 'stats/ai_tab.dart';
import 'stats/format.dart';
import 'stats/manual_tab.dart';
import 'stats/people_tab.dart';
import 'stats/person_pages.dart';
import 'stats/quiz_tab.dart';
import 'stats/search_tab.dart';
import 'stats/sheets.dart';
import 'stats/widgets.dart';

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
          if (_offline) const StatsOfflineBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatsSegmented(
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
                          child: StatsChip(
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
                      child: StatsNumber(
                        value: data == null ? '–' : '${data.active} / ${data.users}',
                        label: 'Pengguna aktif',
                        trend: data?.trendActive,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatsNumber(
                        value: data == null ? '–' : '${data.opens}',
                        label: 'Manual dibuka',
                        trend: data?.trendOpens,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatsNumber(
                        value: data == null ? '–' : '${data.ai}',
                        label: 'Tanya nyel AI',
                        trend: data?.trendAi,
                      ),
                    ),
                  ],
                ),
                if (data != null && data.needsAction) ...[
                  const SizedBox(height: 8),
                  StatsActionCard(data: data, onTap: () => _act(data)),
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
    // With one section chosen, rows need not say it again.
    final showSection = _filter.section.isEmpty;
    // Quiz plays are kept apart from the usage log, so the Quiz tab has its
    // own numbers even when nobody opened a manual, searched or asked.
    Widget used(Widget tab) => data.isEmpty
        ? ListView(children: [
            SizedBox(
              height: 360,
              child: StatsEmpty(caption: '${_filter.section.isEmpty ? 'Semua section' : _filter.section} · ${_filter.periodLabel}'),
            ),
          ])
        : tab;
    final views = [
      used(ManualTab(data: data, onManual: _showManual)),
      used(AiTab(data: data, onQuestion: _showAnswer, showSection: showSection)),
      used(SearchTab(data: data, onMissing: _showSearch)),
      used(PeopleTab(data: data, onPerson: _openPerson, onInactive: _openInactive, showSection: showSection)),
      QuizStatsTab(
        key: ValueKey(_filter.key),
        api: _api,
        filter: _filter,
        onQuestion: _showQuizQuestion,
        onNever: (people) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InactivePage(people: people, sections: _sections, title: 'belum ikut quiz'),
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

  void _showManual(String file) => _sheet(ManualSheet(
        load: _api.manual(_filter, file),
        filter: _filter,
        onPerson: (nrp) {
          Navigator.pop(context);
          _openPerson(nrp);
        },
      ));

  void _showAnswer(int id) => _sheet(AnswerSheet(
        load: _api.answer(id),
        onPerson: (nrp) {
          Navigator.pop(context);
          _openPerson(nrp);
        },
      ));

  void _showSearch(String query) => _sheet(SearchSheet(
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
          unawaited(_load());
        },
      ));

  void _showQuizQuestion(String id) => _sheet(QuizQuestionSheet(load: _api.quizQuestion(_filter, id)));

  void _openPerson(String nrp) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonPage(api: _api, filter: _filter, nrp: nrp, onQuestion: _showAnswer),
      ));

  void _openInactive() {
    final data = _data;
    if (data == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InactivePage(people: data.inactive, sections: _sections),
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
    final key = '${month.year}-${twoDigits(month.month)}';
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
