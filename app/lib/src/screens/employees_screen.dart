import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

enum _Filter { all, active, fresh, off }

/// Admins only (menu ⋮ > Kelola karyawan): who can log in, a new starting
/// PIN for someone who forgot theirs, and switching an NRP off or on. The
/// list itself comes from karyawan.xlsx on Anas's PC (update-karyawan.bat).
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee>? _employees;
  String? _error;
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = StoreScope.read(context);
    final session = store.session;
    if (session == null) return;
    try {
      final list = await store.auth.employees(session);
      if (mounted) {
        setState(() {
          _employees = list;
          _error = null;
        });
      }
    } on AuthException catch (e) {
      if (e.code == 'refresh' && await store.renewSession() != null) return _load();
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _matches(Employee e) => _inFilter(e, _filter) && _found(e);

  bool _found(Employee e) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || e.name.toLowerCase().contains(q) || e.nrp.toLowerCase().contains(q);
  }

  static bool _inFilter(Employee e, _Filter filter) => switch (filter) {
      _Filter.all => true,
      _Filter.active => e.active && !e.isNew,
      _Filter.fresh => e.active && e.isNew,
      _Filter.off => !e.active,
    };

  @override
  Widget build(BuildContext context) {
    final employees = _employees;
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola karyawan'), shape: Border(bottom: BorderSide(color: AppColors.line))),
      body: employees == null
          ? Center(
              child: _error == null
                  ? const ExcavatorLoader(label: 'Memuat daftar karyawan…')
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  ..._requests(employees),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama atau NRP',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.surface,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (f, label) in [
                        (_Filter.all, 'Semua'),
                        (_Filter.active, 'Aktif'),
                        (_Filter.fresh, 'Belum login'),
                        (_Filter.off, 'Nonaktif'),
                      ])
                        ChoiceChip(
                          label: Text('$label ${employees.where((e) => _inFilter(e, f) && _found(e)).length}'),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final e in employees.where(_matches)) ...[
                    _EmployeeRow(employee: e, onTap: () => _open(e)),
                    const SizedBox(height: 8),
                  ],
                  if (!employees.any(_matches))
                    const EmptyState(icon: Icons.person_search, title: 'Tidak ada karyawan yang cocok.'),
                ],
              ),
            ),
    );
  }

  /// "Permintaan reset PIN": employees who tapped Lupa PIN, newest first.
  List<Widget> _requests(List<Employee> employees) {
    final asked = [for (final e in employees) if (e.resetAt != null && e.active) e]
      ..sort((a, b) => b.resetAt!.compareTo(a.resetAt!));
    if (asked.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Permintaan reset PIN',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy),
              ),
            ),
            Pill('${asked.length}', background: AppColors.orange, foreground: Colors.white),
          ],
        ),
      ),
      for (final e in asked) ...[
        _ResetRequest(
          key: ValueKey('reset-${e.nrp}'),
          employee: e,
          onDone: () => setState(() => e.resetAt = null),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 10),
    ];
  }

  Future<void> _open(Employee e) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _EmployeeSheet(employee: e, onChanged: () => setState(() {})),
    );
  }
}

String _when(DateTime t) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(t.hour)}.${two(t.minute)}';
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days == 0) return time;
  if (days == 1) return 'Kemarin $time';
  return '${t.day}/${t.month} $time';
}

/// Shows a temporary PIN the admin made, to pass on to the employee.
Future<void> _showPin(BuildContext context, Employee e, String pin) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('PIN sementara'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${e.name} · ${e.nrp}', style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < pin.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      pin[i],
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.navy),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: pin)),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Salin'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai')),
      ],
    ),
  );
}

/// One "Lupa PIN" request: make a temporary PIN, or dismiss it.
class _ResetRequest extends StatefulWidget {
  const _ResetRequest({super.key, required this.employee, required this.onDone});

  final Employee employee;
  final VoidCallback onDone;

  @override
  State<_ResetRequest> createState() => _ResetRequestState();
}

class _ResetRequestState extends State<_ResetRequest> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(AppStore store, Session session) action) async {
    final store = StoreScope.read(context);
    final session = store.session;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      await action(store, session);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final initials = e.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.navySoft,
                child: Text(
                  initials,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      'NRP ${e.nrp} · ${_when(e.resetAt!)}',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run((store, session) async {
                            await store.auth.dismissReset(session, e.nrp);
                            widget.onDone();
                          }),
                  child: const Text('Abaikan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: Key('reset-pin-${e.nrp}'),
                  onPressed: _busy
                      ? null
                      : () => _run((store, session) async {
                            final pin = await store.auth.newPin(session, e.nrp);
                            if (!context.mounted) return;
                            await _showPin(context, e, pin);
                            widget.onDone();
                          }),
                  child: const Text('Buat PIN sementara'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _lastSeen(DateTime? t) {
  if (t == null) return 'belum pernah';
  final days = DateTime.now().difference(t).inDays;
  if (days == 0) return 'online hari ini';
  if (days == 1) return 'kemarin';
  return '$days hari lalu';
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.onTap});

  final Employee employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final detail = e.isNew
        ? '${e.nrp} · belum login'
        : '${e.nrp} · ${e.devices.length} HP · ${_lastSeen(e.lastSeen)}';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.admin ? '${e.name} (admin)' : e.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          _StatusPill(e),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.e);

  final Employee e;

  @override
  Widget build(BuildContext context) {
    if (!e.active) return Pill('Nonaktif', background: AppColors.danger.withValues(alpha: 0.12), foreground: AppColors.danger);
    if (e.isNew) return Pill('Belum login', background: AppColors.greySoft, foreground: AppColors.muted);
    return Pill('Aktif', background: AppColors.greenSoft, foreground: AppColors.green);
  }
}

class _EmployeeSheet extends StatefulWidget {
  const _EmployeeSheet({required this.employee, required this.onChanged});

  final Employee employee;
  final VoidCallback onChanged;

  @override
  State<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends State<_EmployeeSheet> {
  bool _busy = false;

  Future<bool> _confirm(String title, String message, String action, {bool danger = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
              FilledButton(
                style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run(Future<void> Function(AppStore store, Session session) action) async {
    final store = StoreScope.read(context);
    final session = store.session;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      await action(store, session);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newPin() async {
    final e = widget.employee;
    if (!await _confirm(
      'Buat PIN sementara?',
      'PIN lama ${e.name} tidak berlaku lagi.',
      'Buat PIN',
    )) {
      return;
    }
    await _run((store, session) async {
      final pin = await store.auth.newPin(session, e.nrp);
      if (!mounted) return;
      await _showPin(context, e, pin);
      e.resetAt = null;
      widget.onChanged();
    });
  }

  Future<void> _toggle() async {
    final e = widget.employee;
    final off = e.active;
    if (!await _confirm(
      off ? 'Nonaktifkan ${e.name}?' : 'Aktifkan ${e.name}?',
      off
          ? 'Semua HP ${e.name} otomatis keluar saat online, dan manual yang tersimpan di HP-nya dihapus.'
          : '${e.name} bisa masuk lagi dengan PIN-nya.',
      off ? 'Nonaktifkan' : 'Aktifkan',
      danger: off,
    )) {
      return;
    }
    await _run((store, session) async {
      await store.auth.setActive(session, e.nrp, !off);
      e.active = !off;
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final me = StoreScope.read(context).session?.nrp == e.nrp;
    TableRow row(String label, String value) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 16),
            child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ]);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                row('NRP', e.nrp),
                row('HP aktif', e.devices.isEmpty ? '-' : '${e.devices.length} (${e.devices.join(', ')})'),
                row('Terakhir online', _lastSeen(e.lastSeen)),
                row('nyel AI hari ini', e.admin ? '${e.aiToday} (admin, tanpa batas)' : '${e.aiToday} dari ${AppStore.aiDailyLimit} pertanyaan'),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _newPin,
              child: const Text('Buat PIN sementara'),
            ),
            if (!me) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                style: e.active ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger) : null,
                onPressed: _busy ? null : _toggle,
                child: Text(e.active ? 'Nonaktifkan' : 'Aktifkan lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
