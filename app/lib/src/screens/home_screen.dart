import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../widgets/machine_icon.dart';
import '../widgets/unit_icon.dart';
import 'machine_screen.dart';
import 'report_screen.dart';
import 'updates_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final updateCount = store.unseenUpdates.length;
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
            onSelected: (value) => value == 'report'
                ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen()))
                : _editServer(context, store),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'server', child: Text('Alamat server')),
              PopupMenuItem(value: 'report', child: Text('Laporan masalah')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.list(children: [
              if (store.online == false) _OfflineBanner(store: store),
              if (store.lastRead != null) _ContinueReading(lastRead: store.lastRead!),
            ]),
            // The machine folders sit in the middle of whatever space is left.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: _MachineFolders(store: store)),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.lastError ?? 'Tidak ada koneksi internet.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const Text(
                  'Manual yang sudah diunduh tetap bisa dibuka.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
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
    final file = store.fileByKey(lastRead.fileKey);
    // A manual read online can only be continued while online.
    if (file == null || (store.localManual(file.key) == null && store.online != true)) {
      return const SizedBox.shrink();
    }
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
                    // The unit's machine picture, like in its folder.
                    Container(
                      width: 72,
                      height: 56,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: UnitIcon(unitId: file.unitId, width: 64, height: 48),
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
                            [store.unitNameOf(file), if (lastRead.section != null) lastRead.section!, 'hlm ${lastRead.page}'].join(' · '),
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

/// The home screen's folders: EXCAVATOR and BULLDOZER, plus LAINNYA when a
/// unit fits neither.
class _MachineFolders extends StatelessWidget {
  const _MachineFolders({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final units = store.units;
    final machines = [
      Machine.excavator,
      Machine.bulldozer,
      if (units.any((u) => u.machine == Machine.other)) Machine.other,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'Jenis alat',
            trailing: Text(
              '${formatSize(store.usedBytes)} di HP',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 4),
          for (final machine in machines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FolderCard(
                machine: machine,
                units: [for (final u in units) if (u.machine == machine) u],
                store: store,
              ),
            ),
          if (units.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                store.online == null
                    ? 'Memuat daftar unit…'
                    : store.online == false
                        ? 'Sambungkan HP ke internet sekali untuk mengambil daftar manual.'
                        : 'Belum ada manual di server.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.machine, required this.units, required this.store});

  final Machine machine;
  final List<Unit> units;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final keys = {for (final u in units) for (final f in store.filesOf(u)) f.key};
    final hasUpdate = store.unseenUpdates.any((u) => keys.contains(u.file.key));
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MachineScreen(machine: machine)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          Badge(
            isLabelVisible: hasUpdate,
            smallSize: 10,
            backgroundColor: const Color(0xFFE8541E),
            child: Container(
              width: 104,
              height: 76,
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: MachineIcon(machine, width: 86),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machine.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  units.isEmpty ? 'belum ada model' : '${units.length} model unit',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (hasUpdate)
                  const Text(
                    'Ada update manual',
                    style: TextStyle(fontSize: 12, color: Color(0xFFC2410C), fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF9AA0A6)),
        ],
      ),
    );
  }
}
