/// Quiz per unit: how far each unit's questions are done.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../quiz.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/unit_icon.dart';
import '../quiz_screen.dart';
import '../shell.dart';

/// Quiz per unit: the units with published questions, and how much of each
/// is mastered.
class QuizUnitsScreen extends StatefulWidget {
  const QuizUnitsScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizUnitsScreen> createState() => _QuizUnitsScreenState();
}

class _QuizUnitsScreenState extends State<QuizUnitsScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  List<QuizUnit>? _units;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final units = await QuizApi(StoreScope.read(context), _client).units();
      if (mounted) setState(() => _units = units);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = _units;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Quiz per unit'),
      body: units == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Gagal memuat unit',
                  message: 'Periksa koneksi internet',
                  action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
                ))
          : units.isEmpty
              ? const EmptyState(icon: Icons.quiz_outlined, title: 'Belum ada soal per unit', message: 'Soal baru sedang disiapkan')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppCard(
                      child: Column(
                        children: [
                          for (final (i, u) in units.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => QuizPlayScreen(unit: u.unit)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Row(
                                  children: [
                                    UnitIcon(unitId: u.unit, width: 56, height: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(store.unitById(u.unit)?.name ?? u.unit,
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(3),
                                            child: LinearProgressIndicator(
                                              value: u.total == 0 ? 0 : (u.seen / u.total).clamp(0, 1),
                                              minHeight: 6,
                                              color: AppColors.navy,
                                              backgroundColor: AppColors.line,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text('${u.seen} dari ${u.total} soal',
                                                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                              ),
                                              Text(
                                                '${u.total == 0 ? 0 : (u.seen * 100 / u.total).round().clamp(0, 100)}%',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.chevron_right, color: AppColors.muted),
                                  ],
                                ),
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
