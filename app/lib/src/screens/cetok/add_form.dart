/// The Input tab.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cetok.dart';
import '../../theme.dart';
import 'form_widgets.dart';
import 'style.dart';
import 'widgets.dart';

/// Input: adds stock (input_barang). A part number already in stock fills
/// in its name and unit, so its quantity is added to that row.
class AddForm extends StatefulWidget {
  const AddForm({super.key, required this.cetok});

  final Cetok cetok;

  @override
  State<AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<AddForm> {
  late String _unit = widget.cetok.unitModels.first;
  final _pn = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _qty = TextEditingController(text: '1');
  String _status = 'RFU';
  final _remarks = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.cetok.addListener(_syncName);
  }

  void _syncName() => fillName(_name, widget.cetok);

  @override
  void dispose() {
    widget.cetok.removeListener(_syncName);
    for (final c in [_pn, _desc, _location, _qty, _remarks, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The stock row with exactly this part number, if any.
  CetokPart? get _known {
    final pn = _pn.text.trim().toUpperCase();
    if (pn.isEmpty) return null;
    for (final p in widget.cetok.parts) {
      if (p.pn.toUpperCase() == pn || p.numbers.any((n) => n.toUpperCase() == pn)) return p;
    }
    return null;
  }

  void _fillFrom(CetokPart p) {
    _desc.text = p.desc;
    if (widget.cetok.unitModels.contains(p.unit)) _unit = p.unit;
  }

  void _pnChanged() {
    final known = _known;
    setState(() {
      if (known != null) _fillFrom(known);
    });
  }

  Future<void> _save(int qty) async {
    final pn = _pn.text.trim().toUpperCase();
    final location = _location.text.trim().toUpperCase();
    final ok = await confirmSheet(
      context,
      title: 'Input $qty pcs?',
      rows: [
        ('Part', pn),
        ('Nama part', _desc.text.trim().toUpperCase()),
        ('Unit', _unit),
        ('Lokasi', '${location.isEmpty ? 'tanpa lokasi' : location} ($_status)'),
      ],
      yes: 'Ya, simpan',
      color: AppColors.green,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.add(
        unit: _unit,
        pn: _pn.text,
        desc: _desc.text,
        location: _location.text,
        qty: qty,
        status: _status,
        remarks: _remarks.text,
        name: _name.text,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      showToast(context, 'Tersimpan: $qty pcs $pn di $_unit ($_status)');
      setState(() {
        _pn.clear();
        _desc.clear();
        _location.clear();
        _qty.text = '1';
        _status = 'RFU';
        _remarks.clear();
      });
    } on CetokException catch (e) {
      if (mounted) showToast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final known = _known;
    final q = _pn.text.trim();
    final similar = known != null || q.length < 3
        ? const <CetokPart>[]
        : cetok.parts.where((p) => p.matches(q)).take(3).toList();
    final qty = qtyOf(_qty);
    final label = _pn.text.trim().isEmpty
        ? 'Isi part number'
        : _desc.text.trim().isEmpty
            ? 'Isi nama part'
            : qty <= 0
                ? 'Isi jumlah'
                : _name.text.trim().isEmpty
                    ? 'Isi nama penginput'
                    : 'Simpan $qty pcs';
    final ready = label.startsWith('Simpan ');
    void changed() => setState(() {});
    return FormPage(
      fields: [
        const FormLabel('UNIT'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in cetok.unitModels)
              CetokChip(label: u, selected: _unit == u, onTap: () => setState(() => _unit = u)),
          ],
        ),
        const SizedBox(height: 18),
        const FormLabel('PART NUMBER'),
        CetokField(key: const Key('cetok-add-pn'), controller: _pn, hint: 'cth: 07000-12010', onChanged: _pnChanged),
        AnimatedSize(
          duration: cetokMotion,
          curve: cetokCurve,
          alignment: Alignment.topCenter,
          child: known != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: AppColors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sudah ada: ${known.qty} pcs di ${known.loc.isEmpty ? '–' : known.loc}. Nama part diisi otomatis',
                          style: TextStyle(fontSize: 12, color: AppColors.green),
                        ),
                      ),
                    ],
                  ),
                )
              : similar.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          for (final p in similar)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(p.pn, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${p.desc} · ${p.unit} · ${p.qty} pcs'),
                              trailing: const Text('Pakai'),
                              onTap: () {
                                _pn.text = p.pn;
                                setState(() => _fillFrom(p));
                              },
                            ),
                        ],
                      ),
                    ),
        ),
        const SizedBox(height: 18),
        const FormLabel('NAMA PART'),
        CetokField(controller: _desc, hint: 'cth: O-RING', onChanged: changed),
        const SizedBox(height: 18),
        const FormLabel('LOKASI'),
        CetokField(controller: _location, hint: 'Ketik atau pilih lokasi', onChanged: changed),
        LocationChips(cetok: cetok, controller: _location, onChanged: changed),
        const SizedBox(height: 18),
        const FormLabel('JUMLAH'),
        QtyStepper(controller: _qty, onChanged: changed),
        const SizedBox(height: 18),
        const FormLabel('STATUS'),
        StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
        const SizedBox(height: 18),
        const FormLabel('KETERANGAN (OPSIONAL)'),
        CetokField(controller: _remarks, hint: 'cth: NEW, BEKAS UNIT E5138', onChanged: changed),
        const SizedBox(height: 18),
        const FormLabel('NAMA PENGINPUT'),
        CetokField(controller: _name, hint: 'Nama kamu', onChanged: changed),
      ],
      cta: FormCta(
        key: const Key('cetok-add-cta'),
        label: label,
        color: AppColors.green,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(qty),
      ),
    );
  }
}
