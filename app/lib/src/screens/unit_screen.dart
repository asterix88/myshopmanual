import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// A unit's folder: one card per manual, each downloaded on its own.
class UnitScreen extends StatefulWidget {
  const UnitScreen({super.key, required this.unitId});

  final String unitId;

  @override
  State<UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<UnitScreen> {
  bool _editing = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = store.units.where((u) => u.id == widget.unitId).firstOrNull;
    if (unit == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.folder_off, title: 'Unit tidak ditemukan'));
    }
    final files = store.filesOf(unit);
    final onPhone = files.where((f) => store.isDownloaded(f.key)).toList();
    final usedBytes = onPhone.fold(0, (s, f) => s + f.downloadSize);
    final remaining = files
        .where((f) => !store.isDownloaded(f.key))
        .fold(0, (s, f) => s + f.downloadSize);

    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_exitEdit);
      },
      child: Scaffold(
        appBar: _editing ? _editBar(onPhone) : _normalBar(unit, onPhone.isNotEmpty),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (!_editing) ...[
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Tersimpan di HP: '),
                        TextSpan(
                          text: '${onPhone.length} dari ${files.length} file',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ]),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: files.isEmpty ? 0 : onPhone.length / files.length,
                        minHeight: 6,
                        color: const Color(0xFF27AE60),
                        backgroundColor: AppColors.divider,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      remaining == 0
                          ? '${formatSize(usedBytes)} terpakai · semua file sudah di HP'
                          : '${formatSize(usedBytes)} terpakai · ${formatSize(remaining)} lagi jika semua diunduh',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Pilih file yang ingin dihapus dari HP. File bisa diunduh lagi kapan saja.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            for (final file in files)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _editing
                    ? _SelectableFile(
                        file: file,
                        enabled: store.isDownloaded(file.key),
                        selected: _selected.contains(file.key),
                        onChanged: (v) => setState(() => v ? _selected.add(file.key) : _selected.remove(file.key)),
                      )
                    : _FileCard(file: file, unit: unit),
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _editing && _selected.isNotEmpty
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                onPressed: () => _deleteSelected(store, files),
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  'Hapus dari HP (${formatSize(files.where((f) => _selected.contains(f.key)).fold(0, (s, f) => s + f.downloadSize))})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            : null,
      ),
    );
  }

  PreferredSizeWidget _normalBar(Unit unit, bool canEdit) => AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(unit.name),
            if (unit.kind.isNotEmpty)
              Text(unit.kind, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 8),
        ],
      );

  PreferredSizeWidget _editBar(List<ManualFile> onPhone) => AppBar(
        leading: IconButton(
          tooltip: 'Selesai edit',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_exitEdit),
        ),
        title: Text('${_selected.length} dipilih'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _selected.addAll(onPhone.map((f) => f.key))),
            child: const Text('Pilih semua', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      );

  void _exitEdit() {
    _editing = false;
    _selected.clear();
  }

  Future<void> _deleteSelected(AppStore store, List<ManualFile> files) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus $count file dari HP?'),
        content: const Text('File bisa diunduh lagi nanti saat ada sinyal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteManuals(_selected);
    if (mounted) setState(_exitEdit);
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.unit});

  final ManualFile file;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final downloaded = store.isDownloaded(file.key);
    final progress = store.downloads[file.key];
    final remote = store.catalog.file(file.key);
    final hasNewVersion = downloaded && remote != null &&
        remote.pdf.sha256 != store.localManual(file.key)!.file.pdf.sha256;
    final withdrawn = downloaded && remote == null;
    final lastPage = store.lastRead?.fileKey == file.key ? store.lastRead!.page : null;

    return AppCard(
      onTap: downloaded ? () => openViewer(context, file, page: lastPage) : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (!file.searchable)
                      const Text(
                        'Hasil scan: tidak bisa dicari',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Pill.docType(file.type),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Field(label: 'Halaman', value: '${file.pages}'),
              _Field(label: 'Ukuran', value: formatSize(file.downloadSize)),
            ],
          ),
          const SizedBox(height: 10),
          if (progress != null)
            _DownloadingRow(progress: progress, onCancel: () => store.cancelDownload(file.key))
          else if (!downloaded)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.navy, width: 1.5),
                foregroundColor: AppColors.navy,
                shape: const StadiumBorder(),
              ),
              onPressed: () => _download(context, store),
              icon: const Icon(Icons.download, size: 18),
              label: Text('Unduh ${formatSize(file.downloadSize)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    withdrawn
                        ? 'Sudah ditarik dari server'
                        : lastPage != null
                            ? 'Terakhir dibuka: hlm $lastPage'
                            : 'Siap dibuka offline',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                if (hasNewVersion)
                  TextButton(
                    onPressed: () => _download(context, store),
                    child: const Text('Perbarui', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                const Pill('Diunduh', background: AppColors.greySoft, foreground: AppColors.ink),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, AppStore store) async {
    try {
      await store.download(store.catalog.file(file.key) ?? file, unitName: unit.name);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _DownloadingRow extends StatelessWidget {
  const _DownloadingRow({required this.progress, required this.onCancel});

  final DownloadProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mengunduh ${formatSize(progress.received)} dari ${formatSize(progress.total)}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 6,
                  color: const Color(0xFF2F80ED),
                  backgroundColor: AppColors.divider,
                ),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Batal')),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SelectableFile extends StatelessWidget {
  const _SelectableFile({
    required this.file,
    required this.enabled,
    required this.selected,
    required this.onChanged,
  });

  final ManualFile file;
  final bool enabled;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.ink : const Color(0xFF9AA0A6);
    return AppCard(
      color: selected ? AppColors.navySoft : null,
      onTap: enabled ? () => onChanged(!selected) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: enabled ? (v) => onChanged(v ?? false) : null),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
                Text(
                  enabled ? 'Di HP · ${formatSize(file.downloadSize)}' : 'Belum diunduh',
                  style: TextStyle(fontSize: 12, color: enabled ? AppColors.muted : color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
