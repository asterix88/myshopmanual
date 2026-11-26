part of '../quiz_admin_screen.dart';

// Tab Laporan: questions mechanics reported as wrong.

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.api});

  final QuizApi api;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<QuizReport>? _list;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.reports();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return _error == null ? const Center(child: CircularProgressIndicator()) : EmptyState(icon: Icons.cloud_off_outlined, title: '$_error');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (list.isEmpty)
            const EmptyState(icon: Icons.flag_outlined, title: 'Tidak ada laporan')
          else
            AppCard(
              child: Column(
                children: [
                  for (final (i, r) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.prompt, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${r.note.isEmpty ? 'Tanpa catatan' : r.note} · ${r.name}',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          Text(
                            r.status == 'ditarik' ? 'Soal ditarik, lihat tab Ditarik' : 'Soal masih terbit',
                            style: TextStyle(fontSize: 12, color: r.status == 'ditarik' ? AppColors.amber : AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
