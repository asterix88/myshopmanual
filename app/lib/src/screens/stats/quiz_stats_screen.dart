/// Statistik quiz: the Quiz tab of Statistik pemakaian on its own page, for
/// an Admin kuis, who may not see the rest of the statistics.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../stats.dart';
import '../../theme.dart';
import '../shell.dart';
import 'person_pages.dart';
import 'quiz_tab.dart';
import 'widgets.dart';

class QuizStatsScreen extends StatefulWidget {
  const QuizStatsScreen({super.key, this.client});

  /// For tests; the app uses its own.
  final http.Client? client;

  @override
  State<QuizStatsScreen> createState() => _QuizStatsScreenState();
}

class _QuizStatsScreenState extends State<QuizStatsScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final StatsApi _api = StatsApi(StoreScope.read(context), _client);

  /// The section chips; the same ones Statistik pemakaian starts with.
  static const _sections = ['TRACK', 'WHEEL', 'SUPPORT'];

  StatsFilter _filter = const StatsFilter();

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _showQuestion(String id) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.surface,
        builder: (_) => StoreScope(
          store: StoreScope.read(context),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: QuizQuestionSheet(load: _api.quizQuestion(_filter, id)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik quiz'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatsSegmented(
                  labels: StatsFilter.periodLabels,
                  selected: StatsFilter.periods.indexOf(_filter.period),
                  onSelected: (i) => setState(() => _filter = _filter.copyWith(period: StatsFilter.periods[i])),
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
                            onTap: () => setState(() => _filter = _filter.copyWith(section: section)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: QuizStatsTab(
              // A new filter loads the numbers again.
              key: ValueKey(_filter.key),
              api: _api,
              filter: _filter,
              onQuestion: _showQuestion,
              onNever: (people) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InactivePage(people: people, sections: _sections, title: 'belum ikut quiz'),
              )),
              showSection: _filter.section.isEmpty,
            ),
          ),
        ],
      ),
    );
  }
}
