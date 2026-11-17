/// The Ambil tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../../widgets/rise.dart';
import 'form_widgets.dart';
import 'widgets.dart';

/// Ambil: takes stock out (ambil_barang).
class TakeForm extends StatefulWidget {
  const TakeForm({super.key, required this.cetok, required this.choice});

  final Cetok cetok;
  final ValueNotifier<CetokPart?> choice;

  @override
  State<TakeForm> createState() => _TakeFormState();
}

class _TakeFormState extends State<TakeForm> {
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.choice.addListener(_picked);
    widget.cetok.addListener(_syncName);
  }

  @override
  void dispose() {
    widget.choice.removeListener(_picked);
    widget.cetok.removeListener(_syncName);
    for (final c in [_qty, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _picked() => setState(() => _qty.text = '1');

  void _syncName() => fillName(_name, widget.cetok);

  Future<void> _save(CetokPart part, int qty) async {
    final note = _note.text.trim().toUpperCase();
    final ok = await confirmSheet(
      context,
      title: 'Ambil $qty pcs?',
      rows: [
        ('Part', '${part.pn} ${part.desc}'),
        ('Dari', fromText(part)),
        ('Sisa stok', '${part.qty} → ${part.qty - qty} pcs'),
        ('Keperluan', note),
      ],
      yes: 'Ya, ambil',
      color: AppColors.orange,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.take(part, qty: qty, note: _note.text, name: _name.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showToast(context, 'Tersimpan: ambil $qty pcs ${part.pn}');
      _note.clear();
      widget.choice.value = null;
    } on CetokException catch (e) {
      if (mounted) showToast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final part = latestPart(cetok, widget.choice.value);
    final qty = qtyOf(_qty);
    final label = part == null
        ? 'Pilih part'
        : qty <= 0
            ? 'Isi jumlah'
            : qty > part.qty
                ? 'Stok tidak cukup'
                : _note.text.trim().isEmpty
                    ? 'Isi keperluan'
                    : _name.text.trim().isEmpty
                        ? 'Isi nama pengambil'
                        : 'Ambil $qty pcs';
    final ready = label.startsWith('Ambil ');
    void changed() => setState(() {});
    return FormPage(
      fields: [
        const FormLabel('PART'),
        PartSlot(cetok: cetok, part: part, choice: widget.choice),
        if (part != null)
          Rise(
            key: ValueKey('take-${part.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                const FormLabel('JUMLAH'),
                QtyStepper(controller: _qty, max: part.qty, onChanged: changed),
                const SizedBox(height: 6),
                Text(
                  qty > 0 && qty <= part.qty ? 'Sisa stok ${part.qty} → ${part.qty - qty} pcs' : 'Stok ${part.qty} pcs',
                  style: TextStyle(fontSize: 12, color: qty > part.qty ? AppColors.danger : AppColors.muted),
                ),
                const SizedBox(height: 18),
                const FormLabel('KEPERLUAN'),
                CetokField(controller: _note, hint: 'cth: PERBAIKAN UNIT E5138', onChanged: changed),
                if (cetok.recentNotes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Terakhir', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        for (final n in cetok.recentNotes)
                          CetokChip(
                            label: n,
                            small: true,
                            selected: _note.text.trim().toUpperCase() == n,
                            onTap: () {
                              _note.text = n;
                              changed();
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                const FormLabel('NAMA PENGAMBIL'),
                CetokField(controller: _name, hint: 'Nama kamu', onChanged: changed),
              ],
            ),
          ),
      ],
      cta: FormCta(
        key: const Key('cetok-take-cta'),
        label: label,
        color: AppColors.orange,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(part!, qty),
      ),
    );
  }
}
