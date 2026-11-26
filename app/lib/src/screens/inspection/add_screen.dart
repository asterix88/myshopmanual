part of '../inspection_screen.dart';

// '+ Temuan': adding new findings.

/// "+ Temuan": new findings of one unit, one sheet row per problem.
class AddInspectionScreen extends StatefulWidget {
  const AddInspectionScreen({super.key, required this.section});

  final String section;

  @override
  State<AddInspectionScreen> createState() => _AddInspectionScreenState();
}

class _AddInspectionScreenState extends State<AddInspectionScreen> {
  final _unit = TextEditingController();
  final _model = TextEditingController();
  final _hm = TextEditingController();
  final _leader = TextEditingController();
  final _problems = [TextEditingController()];
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_unit, _model, _hm, _leader, ..._problems]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _touched =>
      [_unit, _model, _hm, _leader, ..._problems].any((c) => c.text.trim().isNotEmpty);

  Future<bool> _confirmLeave() async {
    if (!_touched) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buang temuan ini?'),
        content: const Text('Isian yang belum disimpan akan hilang'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut isi')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buang')),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(Inspection data, String model) async {
    setState(() => _saving = true);
    final problems = [for (final c in _problems) c.text.trim()];
    final unit = _unit.text.trim().toUpperCase();
    try {
      final sent = await data.add(
        section: widget.section,
        unit: data.popIndex[inspectionUnitKey(unit)]?.unit ?? unit,
        model: model,
        hm: _hm.text,
        date: _date,
        leader: _leader.text,
        problems: problems,
      );
      if (!mounted) return;
      Navigator.of(context).pop('${problems.length} temuan baru · $unit${sent ? '' : ' · belum terkirim'}');
    } on InspectionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.faint, fontSize: 14),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
      );

  Widget _note(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: color ?? AppColors.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final data = store.inspection;
    final section = widget.section;
    final tab = data.tabs[section];
    final key = inspectionUnitKey(_unit.text);
    final hit = key.isEmpty ? null : data.popIndex[key];
    final other = hit != null && hit.section.isNotEmpty && hit.section != section ? hit.section : '';
    final locked = hit != null && other.isEmpty;
    final hits = key.isEmpty || hit != null
        ? const <PopUnit>[]
        : [for (final u in data.pop) if (u.section == section && inspectionUnitKey(u.unit).contains(key)) u].take(5).toList();
    final unknown = key.isNotEmpty && hit == null && hits.isEmpty;
    final model = locked ? hit.model : _model.text.trim().toUpperCase();
    final last = key.isEmpty ? null : lastHm(tab, hit?.unit ?? _unit.text);
    final inspector = data.inspector.isNotEmpty
        ? data.inspector
        : (store.session?.name ?? '').trim().toUpperCase().split(RegExp(r'\s+')).first;
    final leaders = tab?.leaders ?? const <String>[];
    final hmOk = RegExp(r'^\d+([.,]\d+)?$').hasMatch(_hm.text.trim());
    final filled = _problems.every((c) => c.text.trim().isNotEmpty);
    final ok = !_saving && key.isNotEmpty && other.isEmpty && model.isNotEmpty && hmOk && _leader.text.trim().isNotEmpty && filled;
    void changed(_) => setState(() {});

    Widget card(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        );

    return PopScope(
      canPop: !_touched || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Temuan baru'),
              Text(
                'Masuk ke sheet Inspection ${sectionLabel(section)} Open 2026',
                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            card([
              _label('CODE UNIT'),
              TextField(
                key: const Key('add-unit'),
                controller: _unit,
                inputFormatters: [_Upper()],
                textCapitalization: TextCapitalization.characters,
                onChanged: changed,
                decoration: _box('Cth: ${unitExamples[section] ?? ''}'),
              ),
              if (hits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final u in hits)
                        ActionChip(
                          key: Key('unit-hit-${u.unit}'),
                          label: Text('${u.unit} · ${u.model}', style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() {
                            _unit.text = u.unit;
                            _unit.selection = TextSelection.collapsed(offset: u.unit.length);
                          }),
                        ),
                    ],
                  ),
                ),
              if (unknown) _note('Belum ada di POP UNIT, isi model unit manual', color: AppColors.amber),
              if (other.isNotEmpty) _note('Unit ini milik section ${sectionLabel(other)}', color: AppColors.danger),
              const SizedBox(height: 14),
              _label('MODEL UNIT'),
              locked
                  ? Container(
                      key: const Key('add-model-locked'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(hit.model, style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
                    )
                  : TextField(
                      key: const Key('add-model'),
                      controller: _model,
                      inputFormatters: [_Upper()],
                      textCapitalization: TextCapitalization.characters,
                      onChanged: changed,
                      decoration: _box(key.isEmpty ? 'Terisi otomatis dari POP UNIT' : 'Cth: PC210-10M0'),
                    ),
              if (locked) _note('Terisi dari POP UNIT'),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('HM'),
                        TextField(
                          key: const Key('add-hm'),
                          controller: _hm,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: changed,
                          decoration: _box(last ?? 'Cth: 10615'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('DATE'),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: _box(''),
                            child: Row(
                              children: [
                                Expanded(child: Text(sheetDate(_date), style: const TextStyle(fontSize: 14))),
                                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (last != null) _note('HM terakhir di sheet: $last'),
            ]),
            card([
              _label('NAME INSPECTOR'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
                child: Text(inspector, style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
              ),
              const SizedBox(height: 14),
              _label('NAME LEADER'),
              TextField(
                key: const Key('add-leader'),
                controller: _leader,
                inputFormatters: [_Upper()],
                textCapitalization: TextCapitalization.characters,
                onChanged: changed,
                decoration: _box(leaders.isEmpty ? 'Nama group leader' : 'Cth: ${leaders.first}'),
              ),
              if (leaders.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in leaders)
                        ChoiceChip(
                          key: Key('leader-$l'),
                          label: Text(l, style: const TextStyle(fontSize: 12)),
                          selected: _leader.text.trim() == l,
                          onSelected: (_) => setState(() {
                            _leader.text = l;
                            _leader.selection = TextSelection.collapsed(offset: l.length);
                          }),
                        ),
                    ],
                  ),
                ),
            ]),
            for (var i = 0; i < _problems.length; i++)
              card([
                Row(
                  children: [
                    Expanded(child: _label('PROBLEM')),
                    if (_problems.length > 1)
                      GestureDetector(
                        onTap: () => setState(() => _problems.removeAt(i).dispose()),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('Hapus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
                        ),
                      ),
                  ],
                ),
                TextField(
                  key: Key('add-problem-$i'),
                  controller: _problems[i],
                  minLines: 2,
                  maxLines: 4,
                  inputFormatters: [_Upper()],
                  textCapitalization: TextCapitalization.characters,
                  onChanged: changed,
                  decoration: _box('Cth: hose ppc fatigue'),
                ),
              ]),
            OutlinedButton.icon(
              key: const Key('add-more-problem'),
              onPressed: () => setState(() => _problems.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah problem di unit ini'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('add-save'),
                onPressed: ok ? () => _save(data, model) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text('Simpan ${_problems.length} temuan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
