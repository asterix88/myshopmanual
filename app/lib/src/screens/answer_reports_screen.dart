import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

/// Admins: how mechanics rated nyel AI's answers, 👍 or 👎 "Jawaban salah",
/// newest first.
class AnswerReportsScreen extends StatefulWidget {
  const AnswerReportsScreen({super.key, this.client});

  /// For tests; the app uses its own.
  final http.Client? client;

  @override
  State<AnswerReportsScreen> createState() => _AnswerReportsScreenState();
}

class _AnswerReportsScreenState extends State<AnswerReportsScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  List<AnswerReport>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final reports = await AiChat(store: StoreScope.read(context), client: _client).reports();
      if (mounted) {
        setState(() {
          _reports = reports;
          _error = null;
        });
      }
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Penilaian nyel AI'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: reports == null
          ? Center(
              child: _error == null
                  ? const ExcavatorLoader(label: 'Memuat laporan…')
                  : EmptyState(
                      icon: Icons.cloud_off,
                      title: _error!,
                      action: TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _load();
                        },
                        child: const Text('Coba lagi'),
                      ),
                    ),
            )
          : reports.isEmpty
              ? const EmptyState(icon: Icons.thumb_up_alt_outlined, title: 'Belum ada penilaian jawaban.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ReportCard(report: reports[i]),
                  ),
                ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final AnswerReport report;

  @override
  Widget build(BuildContext context) {
    final at = report.at;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${two(at.day)}/${two(at.month)}/${at.year} ${two(at.hour)}.${two(at.minute)}';
    final label = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.muted);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report.good ? Icons.thumb_up : Icons.thumb_down,
                size: 16,
                color: report.good ? AppColors.green : AppColors.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${report.good ? 'Membantu' : 'Jawaban salah'} · ${report.name} · NRP ${report.nrp} · $when',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Pertanyaan', style: label),
          Text(report.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (report.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Yang salah menurut mekanik', style: label),
            Text(report.note, style: TextStyle(fontSize: 14, color: AppColors.danger)),
          ],
          const SizedBox(height: 8),
          Text('Jawaban nyel AI', style: label),
          SelectableText(report.answer, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
          if (report.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Sumber', style: label),
            for (final s in report.sources) Text(s, style: TextStyle(fontSize: 12, color: AppColors.navy)),
          ],
        ],
      ),
    );
  }
}
