import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// What changed on the server: new manuals, new versions, withdrawn manuals.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late List<ManualUpdate> _shown;
  AppStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store == null) {
      _store = StoreScope.read(context);
      // Freeze the list for this visit, then mark it seen so the bell clears.
      _shown = _store!.listedUpdates;
      WidgetsBinding.instance.addPostFrameCallback((_) => _store!.markUpdatesSeen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final checked = store.lastChecked;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update manual', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
            Text(
              store.online == true && checked != null
                  ? 'Dicek dari server · ${_time(checked)}'
                  : 'Belum tersambung ke server',
              style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (_shown.isNotEmpty)
            IconButton(
              tooltip: 'Hapus notifikasi',
              icon: const AppIcon(AppGlyph.trash),
              onPressed: () => _confirmClear(store),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await store.refresh();
          setState(() => _shown = store.listedUpdates);
          store.markUpdatesSeen();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (store.online == false)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Tidak ada sinyal. Update dicek otomatis saat HP tersambung internet.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            if (_shown.isEmpty)
              const EmptyState(icon: Icons.notifications_none, title: 'Tidak ada update')
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_shown.length} perubahan file manual di server.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              for (final update in _shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UpdateCard(update: update),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(AppStore store) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Hapus semua notifikasi?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Manual yang sudah diunduh tidak ikut terhapus.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Hapus'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    store.clearUpdates();
    setState(() => _shown = []);
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.update});

  final ManualUpdate update;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final file = update.file;
    final progress = store.downloads[file.key];
    final downloaded = store.isDownloaded(file.key);
    final upToDate = downloaded &&
        store.localManual(file.key)!.file.pdf.sha256 == file.pdf.sha256 &&
        update.kind != UpdateKind.withdrawn;

    final (pill, description) = switch (update.kind) {
      UpdateKind.added => (
          Pill('Baru', background: AppColors.greenSoft, foreground: AppColors.green),
          '${update.unitName} · ${formatSize(file.downloadSize)}',
        ),
      UpdateKind.newVersion => (
          Pill('Versi baru', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
          '${update.unitName} · file di HP sudah lama · unduh ulang ${formatSize(file.downloadSize)}',
        ),
      UpdateKind.withdrawn => (
          Pill('Ditarik', background: AppColors.greySoft, foreground: AppColors.ink),
          'Sudah tidak ada di server. File yang sudah diunduh tetap bisa dibuka.',
        ),
    };

    Widget? action;
    if (progress != null) {
      action = LinearProgressIndicator(value: progress.fraction, minHeight: 6, borderRadius: BorderRadius.circular(3));
    } else if (update.kind == UpdateKind.withdrawn) {
      action = null;
    } else if (upToDate) {
      action = Align(
        alignment: Alignment.centerLeft,
        child: Pill('Diunduh', background: AppColors.greySoft, foreground: AppColors.ink),
      );
    } else {
      final isUpdate = update.kind == UpdateKind.newVersion;
      action = isUpdate
          ? FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(40)),
              onPressed: () => _download(context, store),
              child: const Text('Perbarui'),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                side: BorderSide(color: AppColors.navy, width: 1.5),
                foregroundColor: AppColors.navy,
              ),
              onPressed: () => _download(context, store),
              child: const Text('Unduh'),
            );
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              pill,
              const Spacer(),
              if (file.updatedAt != null)
                Text(_date(file.updatedAt!), style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DocTile(docGlyph(file), size: 40, muted: update.kind == UpdateKind.withdrawn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(description, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, AppStore store) async {
    try {
      await store.download(update.file, unitName: update.unitName);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  static String _date(DateTime d) {
    final local = d.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }
}
