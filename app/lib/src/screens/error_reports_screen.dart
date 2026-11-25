import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth.dart';
import '../error_reports.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

/// Admins: problems the phones reported by themselves (errors and Android
/// closing the app), the same problem from every phone counted together,
/// newest first. Reports are kept for 90 days.
class ErrorReportsScreen extends StatefulWidget {
  const ErrorReportsScreen({super.key, this.client});

  /// For tests; the app uses its own.
  final http.Client? client;

  @override
  State<ErrorReportsScreen> createState() => _ErrorReportsScreenState();
}

class _ErrorReportsScreenState extends State<ErrorReportsScreen> {
  http.Client? _own;
  List<ErrorGroup>? _groups;
  String? _error;

  http.Client get _client {
    if (widget.client case final client?) return client;
    final store = StoreScope.read(context);
    return _own ??= SessionClient(http.Client(), session: () => store.session, renew: store.renewSession);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _own?.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = await fetchErrorGroups(_client);
      if (mounted) {
        setState(() {
          _groups = groups;
          _error = null;
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Koneksi terputus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan error'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: groups == null
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
          : groups.isEmpty
              ? const EmptyState(icon: Icons.verified_outlined, title: 'Belum ada laporan error')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: groups.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => i == 0
                        ? Text(
                            'Dikirim otomatis · 90 hari terakhir.',
                            style: TextStyle(fontSize: 12, color: AppColors.muted),
                          )
                        : _GroupCard(group: groups[i - 1]),
                  ),
                ),
    );
  }
}

String _when(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)}/${at.year} ${two(at.hour)}.${two(at.minute)}';
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final ErrorGroup group;

  @override
  Widget build(BuildContext context) {
    final color = group.closedApp ? AppColors.danger : AppColors.orangeText;
    return AppCard(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _GroupSheet(group: group),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(group.closedApp ? Icons.error : Icons.warning_amber_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text(group.kindLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              const Spacer(),
              Text(_when(group.last), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            group.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${group.count}x · ${group.phones} HP · versi ${group.apps.isEmpty ? '-' : group.apps.join(', ')}',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _GroupSheet extends StatelessWidget {
  const _GroupSheet({required this.group});

  final ErrorGroup group;

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted);
    final detail = [
      '${group.kindLabel}: ${group.message}',
      'Terjadi ${group.count}x di ${group.phones} HP, terakhir ${_when(group.last)}',
      'Versi: ${group.apps.join(', ')}',
      'Mekanik: ${group.people.join(', ')}',
      '',
      group.stack,
    ].join('\n');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(group.message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('Terjadi', style: label),
          Text('${group.count}x di ${group.phones} HP, terakhir ${_when(group.last)}'),
          const SizedBox(height: 8),
          Text('Versi aplikasi', style: label),
          Text(group.apps.isEmpty ? '-' : group.apps.join(', ')),
          const SizedBox(height: 8),
          Text('Mekanik', style: label),
          Text(group.people.isEmpty ? '-' : group.people.join(', ')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Detail teknis', style: label)),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: detail));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Detail disalin')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Salin'),
              ),
            ],
          ),
          SelectableText(
            group.stack.isEmpty ? '-' : group.stack,
            style: TextStyle(fontSize: 11, height: 1.4, fontFamily: 'monospace', color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
