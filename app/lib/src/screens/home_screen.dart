import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/machine_icon.dart';
import '../widgets/tool_icons.dart';
import '../widgets/unit_icon.dart';
import 'answer_reports_screen.dart';
import 'cetok_screen.dart';
import 'convert_screen.dart';
import 'employees_screen.dart';
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
    // The navy header runs up under the status bar, so its icons turn white.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Column(
          children: [
            _Header(
              name: store.session?.name,
              onSearch: onOpenSearch,
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
                    child: const Icon(Icons.notifications, color: Colors.white, size: 26),
                  ),
                ),
                _menu(context, store),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: store.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // The bottom bar is drawn over the page (see HomeShell).
                  padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    if (store.online == false) _OfflineBanner(store: store),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (store.lastRead != null) _ContinueReading(lastRead: store.lastRead!),
                          _MachineFolders(store: store),
                          const SizedBox(height: 20),
                          const _HomeLabel('Fitur lainnya'),
                          const _Tools(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, AppStore store) {
    return PopupMenuButton<String>(
      tooltip: 'Lainnya',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (value) => switch (value) {
        'report' => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen())),
        'employees' => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeesScreen())),
        'answers' => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnswerReportsScreen())),
        'theme' => _chooseTheme(context, store),
        'cetok' => showDialog<void>(context: context, builder: (_) => const _CetokDataDialog()),
        'logout' => _logout(context, store),
        _ => _editServer(context, store),
      },
      itemBuilder: (_) => [
        if (store.session case final session?)
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                Text(
                  session.admin ? 'NRP ${session.nrp} · Admin' : 'NRP ${session.nrp}',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        if (store.session?.admin ?? false)
          const PopupMenuItem(value: 'employees', child: Text('Kelola karyawan')),
        if (store.session?.admin ?? false)
          const PopupMenuItem(value: 'answers', child: Text('Penilaian nyel AI')),
        if (store.session?.admin ?? false)
          const PopupMenuItem(value: 'cetok', child: Text('Data Cetok Online')),
        const PopupMenuItem(value: 'theme', child: Text('Tampilan (terang / gelap)')),
        const PopupMenuItem(value: 'report', child: Text('Laporan masalah')),
        if (store.session?.admin ?? false)
          const PopupMenuItem(value: 'server', child: Text('Alamat server')),
        if (store.loggedIn)
          PopupMenuItem(value: 'logout', child: Text('Keluar', style: TextStyle(color: AppColors.danger))),
      ],
    );
  }

  Future<void> _chooseTheme(BuildContext context, AppStore store) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tampilan'),
        children: [
          for (final (value, label) in const [
            ('system', 'Ikuti pengaturan HP'),
            ('light', 'Terang'),
            ('dark', 'Gelap'),
          ])
            ListTile(
              leading: Icon(
                store.themeMode == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: AppColors.navy,
              ),
              title: Text(label, style: _optionStyle),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (mode != null) store.setThemeMode(mode);
  }

  Future<void> _logout(BuildContext context, AppStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Manual yang sudah diunduh tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok ?? false) await store.signOut();
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
          Icon(Icons.cloud_off, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.lastError ?? 'Tidak ada koneksi internet.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                Text(
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

/// The navy top of Home: logo, "Selamat siang, Anas", the bell and menu,
/// and the search box that opens the Cari tab.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onSearch, required this.actions});

  final String? name;
  final VoidCallback onSearch;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF1E3A64),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: ClipOval(child: Image.asset('assets/images/logo.png')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "My" white, "Manual" in the app's orange.
                    Text.rich(
                      TextSpan(
                        text: 'My',
                        children: [TextSpan(text: 'Manual', style: TextStyle(color: AppColors.orange))],
                      ),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
                    ),
                    Text(
                      greeting(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFC9D3E3)),
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: const Key('home-search'),
              borderRadius: BorderRadius.circular(12),
              onTap: onSearch,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: Color(0xFF6B7178)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cari manual, part number, kode error',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Color(0xFF6B7178)),
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

/// "Selamat siang, Anas" from the time of day and the login name (its
/// first word, AHMAD -> Ahmad).
String greeting(String? name, [DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  final part = switch (hour) {
    < 4 => 'malam',
    < 11 => 'pagi',
    < 15 => 'siang',
    < 18 => 'sore',
    _ => 'malam',
  };
  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  if (first.isEmpty) return 'Selamat $part';
  return 'Selamat $part, ${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: const Color(0xFF1E3A64),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openViewer(context, file, page: lastRead.page),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // The unit's machine picture, like in its folder.
                Container(
                  width: 52,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: UnitIcon(unitId: file.unitId, width: 46, height: 34),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lanjutkan membaca',
                        style: TextStyle(color: Color(0xFFF5B26B), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        [file.title, 'hlm ${lastRead.page}'].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: AppColors.orange,
                          backgroundColor: const Color(0xFF3A5582),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Color(0xFFC9D3E3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The home screen's folders, two to a row: EXCAVATOR and BULLDOZER, plus
/// LAINNYA when a unit fits neither.
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
    Widget card(Machine machine) => _FolderCard(
      machine: machine,
      units: [for (final u in units) if (u.machine == machine) u],
      store: store,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeLabel(
          'Dokumen teknis',
          trailing: units.isEmpty
              ? null
              : Text('${units.length} model unit', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
        for (var i = 0; i < machines.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: card(machines[i])),
                  const SizedBox(width: 12),
                  Expanded(child: i + 1 < machines.length ? card(machines[i + 1]) : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        if (units.isEmpty && store.online == null)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: ExcavatorLoader(label: 'Memuat daftar unit…'),
          )
        else if (units.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              store.online == false
                      ? 'Sambungkan HP ke internet sekali untuk mengambil daftar manual.'
                      : 'Belum ada manual di server.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}

/// A Home section title: Dokumen teknis, Fitur lainnya.
class _HomeLabel extends StatelessWidget {
  const _HomeLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The type of the Home folder names (Excavator, Bulldozer).
TextStyle get homeTitleStyle => TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink);

/// EXCAVATOR -> Excavator.
String titleCase(String label) =>
    label.isEmpty ? label : '${label[0].toUpperCase()}${label.substring(1).toLowerCase()}';

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.machine, required this.units, required this.store});

  final Machine machine;
  final List<Unit> units;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final keys = {for (final u in units) for (final f in store.filesOf(u)) f.key};
    final updates = store.unseenUpdates.where((u) => keys.contains(u.file.key)).length;
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MachineScreen(machine: machine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The machine picture fills the top of the card.
          Stack(
            children: [
              Container(
                height: 104,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navySoft, Color.lerp(AppColors.navySoft, AppColors.navy, 0.12)!],
                  ),
                ),
                alignment: Alignment.center,
                child: MachineIcon(machine, width: 140),
              ),
              if (updates > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8541E), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '$updates baru',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleCase(machine.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: homeTitleStyle,
                      ),
                      Text(
                        units.isEmpty ? 'belum ada model' : '${units.length} model',
                        style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fitur lainnya: the tools beside the manuals, icon on top, name below.
class _Tools extends StatelessWidget {
  const _Tools();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ToolTile(
              key: const Key('tool-convert'),
              icon: const ToolIcon.gauge(),
              title: 'Konversi satuan',
              onTap: () => openConvert(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ToolTile(
              key: const Key('tool-cetok'),
              icon: const ToolIcon.partSearch(),
              title: 'Cetok Online',
              onTap: () => openCetok(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({super.key, required this.icon, required this.title, required this.onTap});

  final Widget icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          icon,
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// Choices in the dialogs, written like the ⋮ menu's items (Material's
/// default list text is larger and spaced out).
const _optionStyle = TextStyle(fontFamily: 'Poppins', fontSize: 15, letterSpacing: 0.1);
const _optionNote = TextStyle(fontFamily: 'Poppins', fontSize: 12.5, letterSpacing: 0, height: 1.35);

/// Admins only: whether Cetok Online shows every location or hides some,
/// for every phone at once (kept on the MyManual server, no app update).
class _CetokDataDialog extends StatefulWidget {
  const _CetokDataDialog();

  @override
  State<_CetokDataDialog> createState() => _CetokDataDialogState();
}

class _CetokDataDialogState extends State<_CetokDataDialog> {
  late bool _all = StoreScope.read(context).cetok.showAll;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final store = StoreScope.read(context);
    final session = store.session;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.auth.setAppConfig(session, cetokAll: _all);
    } on AuthException catch (e) {
      if (e.code == 'refresh' && await store.renewSession() != null) return _save();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    store.cetok.showAll = _all;
    unawaited(store.cetok.refresh());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Data Cetok Online'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<bool>(
            groupValue: _all,
            onChanged: (v) => setState(() => _all = v ?? _all),
            child: const Column(
              children: [
                RadioListTile(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Sebagian', style: _optionStyle),
                  subtitle: Text('LOGISTIK, FABRIKASI, LAYDOWN, TRACKINDO (seperti cetok-online)', style: _optionNote),
                ),
                RadioListTile(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Semua lokasi', style: _optionStyle),
                  subtitle: Text('Tanpa filter (seperti stock-spareparts)', style: _optionNote),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Berlaku untuk semua HP saat Cetok Online dibuka.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 13, color: AppColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
      ],
    );
  }
}
