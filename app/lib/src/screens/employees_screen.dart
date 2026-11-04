import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'home_screen.dart' show titleCase;
import 'shell.dart';

enum _Filter { all, active, fresh, off }

const _filterLabels = {
  _Filter.all: 'Semua',
  _Filter.active: 'Aktif',
  _Filter.fresh: 'Belum login',
  _Filter.off: 'Nonaktif',
};

/// "BUDI SANTOSO" -> "Budi Santoso" (karyawan.xlsx has names in capitals).
String personName(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();

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

  /// A section ("s:WHEEL") or department ("d:PLANT") picked; null = all.
  String? _group;

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

  bool _found(Employee e) => _inGroup(e, _group) && _typed(e);

  bool _typed(Employee e) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || e.name.toLowerCase().contains(q) || e.nrp.toLowerCase().contains(q);
  }

  static bool _inGroup(Employee e, String? group) => switch (group) {
        null => true,
        final g when g.startsWith('s:') => e.sections.contains(g.substring(2)),
        final g => e.department == g.substring(2),
      };

  static bool _inFilter(Employee e, _Filter filter) => switch (filter) {
        _Filter.all => true,
        _Filter.active => e.active && !e.isNew,
        _Filter.fresh => e.active && e.isNew,
        _Filter.off => !e.active,
      };

  /// Sections (and departments, when there is more than one) to pick.
  List<(String, String)> _groups(List<Employee> employees) {
    final sections = {for (final e in employees) ...e.sections}.toList()..sort();
    final departments = {for (final e in employees) if (e.department.isNotEmpty) e.department}.toList()..sort();
    return [
      if (sections.length > 1) for (final s in sections) ('s:$s', titleCase(s)),
      if (departments.length > 1) for (final d in departments) ('d:$d', titleCase(d)),
    ];
  }

  String? _groupLabel(List<Employee> employees) {
    for (final (key, label) in _groups(employees)) {
      if (key == _group) return label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final employees = _employees;
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola karyawan'), shape: Border(bottom: BorderSide(color: AppColors.line))),
      body: employees == null
          ? Center(
              child: _error == null
                  ? const ExcavatorLoader(label: 'Memuat…')
                  : EmptyState(
                      icon: Icons.cloud_off,
                      title: _error!,
                      action: OutlinedButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _load();
                        },
                        child: const Text('Coba lagi'),
                      ),
                    ),
            )
          : RefreshIndicator(onRefresh: _load, child: _list(employees)),
    );
  }

  Widget _list(List<Employee> employees) {
    final shown = employees.where(_matches).toList();
    final groups = _groups(employees);
    final filtered = _filter != _Filter.all || _group != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
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
        _StatusBar(
          counts: {for (final f in _Filter.values) f: employees.where((e) => _inFilter(e, f) && _found(e)).length},
          selected: _filter,
          onPick: (f) => setState(() => _filter = f),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (key, label) in [(null, 'Semua'), ...groups]) ...[
                  if (key != null) const SizedBox(width: 6),
                  _Chip(
                    label: key == null
                        ? label
                        : '$label ${employees.where((e) => _inGroup(e, key) && _typed(e) && _inFilter(e, _filter)).length}',
                    selected: _group == key,
                    onTap: () => setState(() => _group = key),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!filtered && _query.trim().isEmpty) ..._requests(employees),
        if (filtered)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 0, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _caption(shown.length, employees),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted),
                  ),
                ),
                TextButton.icon(
                  onPressed: shown.isEmpty ? null : () => _copy(shown),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Salin daftar'),
                ),
              ],
            ),
          ),
        if (shown.isEmpty)
          const EmptyState(icon: Icons.person_search, title: 'Tidak ditemukan')
        else
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
                  _EmployeeRow(employee: shown[i], onTap: () => _open(shown[i])),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// "61 BELUM LOGIN · TRACK"
  String _caption(int count, List<Employee> employees) => [
        '$count ${_filter == _Filter.all ? 'karyawan' : _filterLabels[_filter]!}',
        ?_groupLabel(employees),
      ].join(' · ').toUpperCase();

  /// The list shown, as text for WhatsApp.
  Future<void> _copy(List<Employee> shown) async {
    final employees = _employees ?? const [];
    final title = [_filterLabels[_filter]!, ?_groupLabel(employees)].join(' · ');
    final lines = [for (var i = 0; i < shown.length; i++) '${i + 1}. ${personName(shown[i].name)} (${shown[i].nrp})'];
    await Clipboard.setData(ClipboardData(text: '$title\n${lines.join('\n')}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${shown.length} nama disalin')));
  }

  /// Employees who tapped Lupa PIN, newest first.
  List<Widget> _requests(List<Employee> employees) {
    final asked = [for (final e in employees) if (e.resetAt != null && e.active) e]
      ..sort((a, b) => b.resetAt!.compareTo(a.resetAt!));
    return [
      for (final e in asked) ...[
        _ResetRequest(
          key: ValueKey('reset-${e.nrp}'),
          employee: e,
          onDone: () => setState(() => e.resetAt = null),
        ),
        const SizedBox(height: 10),
      ],
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

/// Semua / Aktif / Belum login / Nonaktif, each with its count.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.counts, required this.selected, required this.onPick});

  final Map<_Filter, int> counts;
  final _Filter selected;
  final ValueChanged<_Filter> onPick;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final f in _Filter.values) ...[
            if (f != _Filter.all) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: f == selected ? AppColors.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('status-${f.name}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onPick(f),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Text(
                          '${counts[f]}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: f == selected ? Colors.white : AppColors.ink,
                          ),
                        ),
                        Text(
                          _filterLabels[f]!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: f == selected ? Colors.white : AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navySoft : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? AppColors.navy : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded square with someone's initials.
class _Initials extends StatelessWidget {
  const _Initials(this.name, {this.size = 36});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(size > 40 ? 12 : 10)),
      child: Text(
        _initials(name),
        style: TextStyle(fontSize: size > 40 ? 15 : 12, fontWeight: FontWeight.w600, color: AppColors.navy),
      ),
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
          Text('${personName(e.name)} · ${e.nrp}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pin));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN disalin')));
            }
          },
          child: const Text('Salin'),
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
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.orangeText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Minta reset PIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  '${personName(e.name)} · ${_when(e.resetAt!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abaikan',
            onPressed: _busy
                ? null
                : () => _run((store, session) async {
                      await store.auth.dismissReset(session, e.nrp);
                      widget.onDone();
                    }),
            icon: Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
          ),
          FilledButton(
            key: Key('reset-pin-${e.nrp}'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _busy
                ? null
                : () => _run((store, session) async {
                      final pin = await store.auth.newPin(session, e.nrp);
                      if (!context.mounted) return;
                      await _showPin(context, e, pin);
                      widget.onDone();
                    }),
            child: const Text('Buat PIN'),
          ),
        ],
      ),
    );
  }
}

String _lastSeen(DateTime? t) {
  if (t == null) return 'belum pernah';
  final days = DateTime.now().difference(t).inDays;
  if (days == 0) return 'Hari ini';
  if (days == 1) return 'Kemarin';
  return '$days hari lalu';
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.onTap});

  final Employee employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final meta = [
      e.nrp,
      e.sections.map(titleCase).join(', '),
      if (e.active && e.devices.isNotEmpty) '${e.devices.length} HP',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            _Initials(e.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    personName(e.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: e.active ? AppColors.ink : AppColors.faint,
                    ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Status(e),
          ],
        ),
      ),
    );
  }
}

/// Right side of a row: a tag for admin / belum login / nonaktif, or when
/// an active employee was last online.
class _Status extends StatelessWidget {
  const _Status(this.e, {this.long = false});

  final Employee e;

  /// In the detail sheet: "Aktif" instead of the last-online time.
  final bool long;

  @override
  Widget build(BuildContext context) {
    if (!e.active) return Pill('Nonaktif', background: AppColors.danger.withValues(alpha: 0.12), foreground: AppColors.danger);
    if (e.isNew) return Pill('Belum login', background: AppColors.greySoft, foreground: AppColors.muted);
    if (e.admin) return Pill('Admin', background: AppColors.navySoft, foreground: AppColors.navy);
    if (long) return Pill('Aktif', background: AppColors.greenSoft, foreground: AppColors.green);
    return Text(_lastSeen(e.lastSeen), style: TextStyle(fontSize: 12, color: AppColors.muted));
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
    if (!await _confirm('Buat PIN sementara?', 'PIN lama tidak berlaku.', 'Buat PIN')) return;
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
    final name = personName(e.name);
    if (!await _confirm(off ? 'Nonaktifkan?' : 'Aktifkan?', name, off ? 'Nonaktifkan' : 'Aktifkan', danger: off)) {
      return;
    }
    await _run((store, session) async {
      await store.auth.setActive(session, e.nrp, !off);
      e.active = !off;
      widget.onChanged();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(off ? '$name dinonaktifkan' : '$name aktif lagi')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final me = StoreScope.read(context).session?.nrp == e.nrp;
    Widget row(String label, String value, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
    final pinButton = FilledButton(
      onPressed: _busy ? null : _newPin,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
      child: const Text('Buat PIN sementara'),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Initials(e.name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName(e.name),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.navy),
                      ),
                      Text('NRP ${e.nrp}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                _Status(e, long: true),
              ],
            ),
            if (e.sections.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in e.sections)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        titleCase(s),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.navy),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  row('Terakhir online', _lastSeen(e.lastSeen)),
                  row('HP', e.devices.isEmpty ? '-' : e.devices.join(' · ')),
                  row('Versi app', e.app.isEmpty ? '-' : e.app),
                  row(
                    'nyel AI hari ini',
                    e.admin ? 'tanpa batas' : '${e.aiToday} dari ${AppStore.aiDailyLimit}',
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (me)
              pinButton
            else
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        foregroundColor: e.active ? AppColors.danger : AppColors.navy,
                      ),
                      onPressed: _busy ? null : _toggle,
                      child: Text(e.active ? 'Nonaktifkan' : 'Aktifkan lagi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: pinButton),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
