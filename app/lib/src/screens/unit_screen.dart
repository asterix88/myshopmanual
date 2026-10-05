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
            if (_editing)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Pilih file yang ingin dihapus dari HP. File bisa diunduh lagi kapan saja.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            for (final (group, groupFiles) in _grouped(files))
              for (final (i, file) in groupFiles.indexed) ...[
                // Below the subfolders, the unit folder's own files get a
                // heading too, so they don't read as part of the last one.
                if (i == 0 && (group.isNotEmpty || files.any((f) => f.group.isNotEmpty)))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SectionLabel(group.isEmpty ? 'Manual' : group),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
    // Not downloaded: still readable straight from the server while online.
    final canRead = downloaded || (store.online == true && remote != null);
    final partial = downloaded || progress != null ? 0 : store.partialBytes(file);

    return AppCard(
      onTap: canRead ? () => openViewer(context, file, page: lastPage) : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                    Text(file.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                      '${file.pages} halaman · ${formatSize(file.downloadSize)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    if (!file.searchable)
                      const Text(
                        'Hasil scan: tidak bisa dicari',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              if (file.type != DocType.other) ...[const SizedBox(width: 10), Pill.docType(file.type)],
            ],
          ),
          if (partial > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Terunduh ${formatSize(partial)} dari ${formatSize(file.downloadSize)}, bisa dilanjutkan',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          if (progress != null)
            _DownloadingRow(
              progress: progress,
              onPause: () => store.pauseDownload(file.key),
              onCancel: () => store.cancelDownload(file.key),
            )
          else if (!downloaded)
            // Compact buttons at their own width, not stretched across the card.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.navy,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: canRead ? () => openViewer(context, file, page: lastPage) : null,
                  icon: const Icon(Icons.menu_book_outlined, size: 15),
                  label: const Text('Baca online', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: AppColors.navy, width: 1.2),
                    foregroundColor: AppColors.navy,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _download(context, store),
                  icon: const Icon(Icons.download, size: 15),
                  label: Text(
                    partial > 0 ? 'Lanjutkan unduhan' : 'Unduh ${formatSize(file.downloadSize)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
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
  const _DownloadingRow({required this.progress, required this.onPause, required this.onCancel});

  final DownloadProgress progress;
  final VoidCallback onPause;
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
            TextButton(onPressed: onPause, child: const Text('Jeda')),
            TextButton(onPressed: onCancel, child: const Text('Batal')),
          ],
        ),
      ],
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

/// Consecutive files of one subfolder under one heading ([files] come in
/// [ManualFile.pageOrder]: subfolders first, then the unit folder's own).
List<(String, List<ManualFile>)> _grouped(List<ManualFile> files) {
  final groups = <String, List<ManualFile>>{};
  for (final f in files) {
    (groups[f.group] ??= []).add(f);
  }
  return [
    for (final e in groups.entries)
      if (e.value.isNotEmpty) (e.key, e.value),
  ];
}
