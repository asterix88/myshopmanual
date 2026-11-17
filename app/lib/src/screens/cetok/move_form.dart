/// The Transfer tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../../widgets/rise.dart';
import 'form_widgets.dart';
import 'style.dart';

/// Transfer: moves stock to another location and/or status (transfer_stok).
class MoveForm extends StatefulWidget {
  const MoveForm({super.key, required this.cetok, required this.choice});

  final Cetok cetok;
  final ValueNotifier<CetokPart?> choice;

  @override
  State<MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends State<MoveForm> {
  final _qty = TextEditingController(text: '1');
  final _location = TextEditingController();
  late String _status = widget.choice.value?.status ?? 'RFU';
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
    for (final c in [_qty, _location, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncName() => fillName(_name, widget.cetok);

  void _picked() => setState(() {
        _qty.text = '1';
        _location.clear();
        _status = widget.choice.value?.status ?? 'RFU';
      });

  Future<void> _save(CetokPart part, int qty) async {
    final location = _location.text.trim().toUpperCase();
    final ok = await confirmSheet(
      context,
      title: 'Transfer $qty pcs?',
      rows: [
        ('Part', '${part.pn} ${part.desc}'),
        ('Dari', fromText(part)),
        ('Ke', '$location ($_status)'),
        ('Sisa di asal', '${part.qty - qty} pcs'),
      ],
      yes: 'Ya, transfer',
      color: cetokNavy,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.move(part, qty: qty, location: location, status: _status, note: _note.text, name: _name.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showToast(context, '$qty pcs ${part.pn} dipindah ke $location ($_status)');
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
    final location = _location.text.trim();
    final label = part == null
        ? 'Pilih part'
        : qty <= 0
            ? 'Isi jumlah'
            : qty > part.qty
                ? 'Stok tidak cukup'
                : location.isEmpty
                    ? 'Isi lokasi tujuan'
                    : location.toLowerCase() == part.loc.toLowerCase() && _status == (part.status ?? '')
                        ? 'Tujuan sama dengan asal'
                        : _name.text.trim().isEmpty
                            ? 'Isi nama'
                            : 'Transfer $qty pcs';
    final ready = label.startsWith('Transfer ');
    void changed() => setState(() {});
    return FormPage(
      fields: [
        const FormLabel('PART'),
        PartSlot(cetok: cetok, part: part, choice: widget.choice),
        if (part != null)
          Rise(
            key: ValueKey('move-${part.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                const FormLabel('JUMLAH'),
                Row(
                  children: [
                    Expanded(child: QtyStepper(controller: _qty, max: part.qty, onChanged: changed)),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: BorderSide(color: AppColors.border, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _qty.text = '${part.qty}';
                          changed();
                        },
                        child: const Text('Semua'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const FormLabel('DARI → KE'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.navy, width: 2.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dari', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                Text(fromText(part),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: 2, height: 16, color: AppColors.border),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Text('Ke', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CetokField(
                        key: const Key('cetok-move-location'),
                        controller: _location,
                        hint: 'Ketik atau pilih lokasi',
                        onChanged: changed,
                      ),
                      LocationChips(cetok: cetok, controller: _location, onChanged: changed, except: part.loc),
                      const SizedBox(height: 12),
                      StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const FormLabel('KETERANGAN (OPSIONAL)'),
                CetokField(controller: _note, hint: 'cth: PINDAH KE GUDANG', onChanged: changed),
                const SizedBox(height: 18),
                const FormLabel('NAMA'),
                CetokField(controller: _name, hint: 'Nama kamu', onChanged: changed),
              ],
            ),
          ),
      ],
      cta: FormCta(
        key: const Key('cetok-move-cta'),
        label: label,
        color: cetokNavy,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(part!, qty),
      ),
    );
  }
}
