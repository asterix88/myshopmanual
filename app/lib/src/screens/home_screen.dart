import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'unit_screen.dart';
import 'updates_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = store.units;
    final updateCount = store.updates.length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE6E8EB))),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 42, height: 42),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MyManual',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.15),
                ),
                Text(
                  'TRACK SECTION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: Color(0xFFC86A0A),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: updateCount == 0 ? 'Update manual' : 'Update manual, $updateCount baru',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UpdatesScreen()),
            ),
            icon: Badge(
              isLabelVisible: updateCount > 0,
              label: Text('$updateCount'),
              backgroundColor: const Color(0xFFE8541E),
              child: const Icon(Icons.notifications, color: AppColors.navy, size: 26),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Lainnya',
            icon: const Icon(Icons.more_vert, color: AppColors.navy),
            onSelected: (_) => _editServer(context, store),
            itemBuilder: (_) => const [PopupMenuItem(value: 'server', child: Text('Alamat server'))],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (store.online == false) _OfflineBanner(store: store),
            if (store.lastRead != null) _ContinueReading(lastRead: store.lastRead!),
            Container(
              margin: const EdgeInsets.only(top: 10),
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel(
                    'Model unit',
                    trailing: Text(
                      '${formatSize(store.usedBytes)} di HP',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  if (units.isEmpty)
                    EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: store.online == null ? 'Memuat daftar unit…' : 'Belum ada daftar unit',
                      message: store.online == false
                          ? 'Sambungkan HP ke internet sekali untuk mengambil daftar manual.'
                          : null,
                    )
                  else
                    for (final (i, unit) in units.indexed)
                      _UnitRow(unit: unit, store: store, showDivider: i > 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editServer(BuildContext context, AppStore store) async {
    final controller = TextEditingController(text: store.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alamat server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://pub-xxxx.r2.dev'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (url != null) await store.setServerUrl(url);
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.greySoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Mode offline. Manual yang sudah diunduh tetap bisa dibuka.',
              style: TextStyle(fontSize: 12, color: AppColors.ink),
            ),
          ),
          TextButton(onPressed: store.refresh, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _ContinueReading extends StatelessWidget {
  const _ContinueReading({required this.lastRead});

  final LastRead lastRead;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final manual = store.localManual(lastRead.fileKey);
    if (manual == null) return const SizedBox.shrink();
    final file = manual.file;
    final progress = file.pages == 0 ? 0.0 : lastRead.page / file.pages;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Lanjutkan membaca',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openViewer(context, file, page: lastRead.page),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                      alignment: Alignment.center,
                      child: Text(
                        file.type == DocType.shopManual ? 'SM' : file.type.label.substring(0, 3).toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFC86A0A)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [if (lastRead.section != null) lastRead.section!, 'hlm ${lastRead.page}'].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFC9D3E3), fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              color: AppColors.orange,
                              backgroundColor: const Color(0xFF3A5582),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.store, required this.showDivider});

  final Unit unit;
  final AppStore store;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final files = store.filesOf(unit);
    final onPhone = files.where((f) => store.isDownloaded(f.key)).length;
    final keys = {for (final f in files) f.key};
    final hasUpdate = store.updates.any((u) => keys.contains(u.file.key));
    final subtitle = hasUpdate
        ? 'Ada update manual'
        : [
            if (unit.kind.isNotEmpty) unit.kind,
            onPhone == 0 ? 'belum ada file di HP' : '$onPhone dari ${files.length} file di HP',
          ].join(' · ');
    return Column(
      children: [
        if (showDivider) const Divider(indent: 72),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UnitScreen(unitId: unit.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(
                    _shortCode(unit),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.orangeText),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUpdate ? const Color(0xFFC2410C) : AppColors.muted,
                          fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF9AA0A6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _shortCode(Unit unit) {
    final code = unit.id.split(RegExp(r'[-_ ]')).first.toUpperCase();
    return code.length > 5 ? code.substring(0, 5) : code;
  }
}
