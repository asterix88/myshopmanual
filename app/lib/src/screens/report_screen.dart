import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics.dart';
import '../theme.dart';

/// What the app knows about recent force closes, to copy and send when
/// something goes wrong.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _report = Diagnostics.report();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan masalah')),
      body: FutureBuilder<String>(
        future: _report,
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Kalau aplikasi tertutup sendiri, salin laporan ini dan kirim ke admin.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan disalin')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Salin laporan'),
              ),
              const SizedBox(height: 16),
              SelectableText(text, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ],
          );
        },
      ),
    );
  }
}
