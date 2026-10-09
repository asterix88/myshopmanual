import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../public_downloads.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// A unit's folder: its subfolders first, each opened on its own page, then
/// one card per manual, each downloaded on its own.
class UnitScreen extends StatefulWidget {
  const UnitScreen({super.key, required this.unitId, this.folder = const [], this.focus});

  final String unitId;

  /// The subfolder shown, as its path inside the unit folder (empty: the
  /// unit folder itself).
  final List<String> folder;

  /// A manual to scroll to (from the download notification).
  final String? focus;

  @override
  State<UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<UnitScreen> {
  bool _editing = false;
  final Set<String> _selected = {};
  final _filter = TextEditingController();
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _focusKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target, alignment: 0.2, duration: const Duration(milliseconds: 300));
        }
      });
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// Shown when the folder holds this many manuals or more.
  static const _filterFrom = 6;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = store.units.where((u) => u.id == widget.unitId).firstOrNull;
    if (unit == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.folder_off, title: 'Unit tidak ditemukan'));
    }
    final all = store.filesOf(unit);
    final inFolder = all.where((f) => _startsWith(f.folder, widget.folder)).toList();
    final query = _filter.text.trim().toLowerCase();
    // Typing a name lists the matching manuals of this folder and every
    // folder inside it, without the folders themselves.
    final files = query.isEmpty
        ? all.where((f) => _sameList(f.folder, widget.folder)).toList()
        : inFolder.where((f) => f.title.toLowerCase().contains(query)).toList();
    final subfolders = query.isEmpty ? _subfolders(all, widget.folder) : const <(String, List<ManualFile>)>[];
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
              Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Pilih file yang ingin dihapus dari HP. File bisa diunduh lagi kapan saja.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            if (!_editing && inFolder.length >= _filterFrom)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    hintText: widget.folder.isEmpty ? 'Cari file di ${unit.name}' : 'Cari file di ${widget.folder.last}',
                    prefixIcon: Icon(Icons.search, size: 20, color: AppColors.muted),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(_filter.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            if (!_editing)
              for (final (name, inside) in subfolders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FolderCard(
                    name: name,
                    files: inside,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => UnitScreen(unitId: unit.id, folder: [...widget.folder, name]),
                    )),
                  ),
                ),
            // Below the subfolders, the folder's own files get a heading, so
            // they don't read as part of the last subfolder.
            if (!_editing && subfolders.isNotEmpty && files.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SectionLabel('Manual'),
              ),
            for (final file in files)
              Padding(
                key: file.key == widget.focus ? _focusKey : null,
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
            if (files.isEmpty && subfolders.isEmpty)
              query.isEmpty
                  ? const EmptyState(icon: Icons.folder_off_outlined, title: 'Folder ini kosong')
                  : const EmptyState(icon: Icons.search_off, title: 'Tidak ada file dengan nama itu'),
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
            Text(widget.folder.isEmpty ? unit.name : widget.folder.last),
            // Inside a subfolder the line below says whose folder it is.
            if (widget.folder.isNotEmpty || unit.kind.isNotEmpty)
              Text(
                widget.folder.isEmpty ? unit.kind : [unit.name, ...widget.folder.take(widget.folder.length - 1)].join(' / '),
                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
              ),
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
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    if (!file.searchable)
                      Text(
                        'Gambar atau hasil scan: tidak bisa dicari',
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
                style: TextStyle(fontSize: 12, color: AppColors.muted),
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
            // Compact buttons, each where the left and right half of the card
            // start, as they sat when they filled those halves.
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
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
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: AppColors.navy, width: 1.2),
                        foregroundColor: AppColors.navy,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => _download(context, store),
                      icon: const Icon(Icons.download, size: 15),
                      label: Text(
                        partial > 0 ? 'Lanjutkan unduhan' : 'Unduh',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
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
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                if (hasNewVersion)
                  TextButton(
                    onPressed: () => _download(context, store),
                    child: const Text('Perbarui', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                Pill('Diunduh', background: AppColors.greySoft, foreground: AppColors.ink),
              ],
            ),
          if (downloaded && progress == null)
            // Hidden once the copy is in Download; back if it gets deleted.
            ListenableBuilder(
              listenable: PublicDownloads.instance,
              builder: (context, _) {
                final name = PublicDownloads.fileName(file.title);
                if (!PublicDownloads.instance.canSave(name)) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: AppColors.navy, width: 1.2),
                        foregroundColor: AppColors.navy,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => _saveToDownloads(context, store, name),
                      icon: const Icon(Icons.download, size: 15),
                      label: const Text(
                        'Simpan ke Download',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _saveToDownloads(BuildContext context, AppStore store, String name) async {
    final downloads = PublicDownloads.instance;
    final size = store.localManual(file.key)?.file.pdf.size ?? file.pdf.size;
    final free = await downloads.freeSpace();
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _SaveSheet(name: name, size: size, free: free),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await downloads.save(store.pdfPath(file), name);
      final shown = messenger.showSnackBar(SnackBar(
        content: Text('Tersimpan di Download/MyManual/$name'),
        // A snackbar with an action stays until closed unless told otherwise.
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: 'BUKA',
          onPressed: () async {
            if (!await downloads.open(name)) {
              messenger.showSnackBar(const SnackBar(content: Text('Tidak ada aplikasi untuk membuka PDF')));
            }
          },
        ),
      ));
      // Some phones keep a snackbar with a button up (accessibility
      // settings); close it ourselves after the 2 seconds.
      var open = true;
      shown.closed.then((_) => open = false);
      Timer(const Duration(seconds: 2), () {
        if (open) shown.close();
      });
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
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
          style: TextStyle(fontSize: 12, color: AppColors.muted),
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
    final color = enabled ? AppColors.ink : AppColors.faint;
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

/// A subfolder of the unit folder: tapping it opens its files on their own
/// page.
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.name, required this.files, required this.onTap});

  final String name;

  /// Every manual inside the folder, its own subfolders included.
  final List<ManualFile> files;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final onPhone = files.where((f) => store.isDownloaded(f.key)).length;
    final keys = {for (final f in files) f.key};
    final hasUpdate = store.unseenUpdates.any((u) => keys.contains(u.file.key));
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.folder, size: 34, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  hasUpdate
                      ? 'Ada update manual'
                      : [
                          '${files.length} file',
                          if (onPhone > 0) '$onPhone di HP',
                        ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: hasUpdate ? AppColors.update : AppColors.muted,
                    fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.faint),
        ],
      ),
    );
  }
}

/// The subfolders directly inside [folder], each with every manual it holds,
/// in the order their files come ([ManualFile.pageOrder], A-Z).
List<(String, List<ManualFile>)> _subfolders(List<ManualFile> files, List<String> folder) {
  final inside = <String, List<ManualFile>>{};
  for (final f in files) {
    final path = f.folder;
    if (path.length > folder.length && _startsWith(path, folder)) {
      (inside[path[folder.length]] ??= []).add(f);
    }
  }
  return [for (final e in inside.entries) (e.key, e.value)];
}

bool _startsWith(List<String> path, List<String> folder) =>
    path.length >= folder.length && _sameList(path.take(folder.length).toList(), folder);

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// "Simpan ke folder Download?": what gets copied where, and its cost in space.
class _SaveSheet extends StatelessWidget {
  const _SaveSheet({required this.name, required this.size, required this.free});

  final String name;
  final int size;
  final int? free;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Simpan ke folder Download?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text('Download/MyManual/', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text(
                    free == null
                        ? formatSize(size)
                        : '${formatSize(size)} · ruang kosong di HP ${formatSize(free!)}',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Salinan ini memakai ruang ${formatSize(size)} lagi.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.navy, width: 1.2),
                    foregroundColor: AppColors.navy,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.navy, shape: const StadiumBorder()),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Simpan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
