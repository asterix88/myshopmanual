/// Pieces shared by the Ambil, Transfer and Input forms: fields, labels,
/// the sticky button, the confirm sheet, the quantity stepper and the part
/// picker.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../../widgets/rise.dart';
import 'style.dart';
import 'widgets.dart';

const _upper = TextCapitalization.characters;

/// An upper-case text field.
class CetokField extends StatelessWidget {
  const CetokField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textCapitalization: _upper,
        onChanged: (_) => onChanged(),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
        decoration: cetokInput(hint),
      );
}

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.muted)),
      );
}

/// A form above a sticky button.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.fields, required this.cta});

  final List<Widget> fields;
  final Widget cta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: cta,
        ),
      ],
    );
  }
}

/// The form's button: grey with what is still missing, coloured with what it
/// will do once everything is filled in.
class FormCta extends StatelessWidget {
  const FormCta({super.key, required this.label, required this.color, required this.ready, required this.busy, required this.onPressed});

  final String label;
  final Color color;
  final bool ready;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = ready && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Pressable(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 52,
          decoration: BoxDecoration(
            color: ready ? color : AppColors.greySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          label,
                          key: ValueKey(label),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ready ? Colors.white : AppColors.muted,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> rows,
  required String yes,
  required Color color,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  for (final (k, v) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 96, child: Text(k, style: TextStyle(fontSize: 13, color: AppColors.muted))),
                          Expanded(
                            child: Text(v,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(sheet, false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(sheet, true),
                    child: Text(yes),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

void showToast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

int qtyOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

/// A whole-number quantity between − and +; it can also be typed.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.controller, required this.onChanged, this.max = 99999});

  final TextEditingController controller;
  final VoidCallback onChanged;
  final int max;

  void _step(int by) {
    final next = (qtyOf(controller) + by).clamp(1, max < 1 ? 1 : max);
    HapticFeedback.selectionClick();
    controller.text = '$next';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final qty = qtyOf(controller);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kurangi',
            onPressed: qty > 1 ? () => _step(-1) : null,
            icon: Icon(Icons.remove, color: AppColors.navy),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) => onChanged(),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
          IconButton(
            tooltip: 'Tambah',
            onPressed: qty < max ? () => _step(1) : null,
            icon: Icon(Icons.add, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

/// RFU / NOT RFU with a pill that slides to the chosen one.
class StatusChoice extends StatelessWidget {
  const StatusChoice({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = ['RFU', 'NOT RFU'];

  @override
  Widget build(BuildContext context) {
    final index = _options.indexOf(value).clamp(0, 1);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 4) / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: cetokMotion,
                curve: cetokCurve,
                left: index * (w + 4),
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [BoxShadow(color: Color(0x1F101828), blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    SizedBox(
                      width: w,
                      child: InkWell(
                        key: Key('status-${_options[i]}'),
                        borderRadius: BorderRadius.circular(9),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(_options[i]);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: cetokMotion,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: i == index ? statusColor(_options[i]) : AppColors.muted,
                            ),
                            child: Text(_options[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Location chips under a location field: the stock's locations.
class LocationChips extends StatelessWidget {
  const LocationChips({super.key, required this.cetok, required this.controller, required this.onChanged, this.except = ''});

  final Cetok cetok;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String except;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().toLowerCase();
    final options = [
      for (final l in cetok.locations)
        if (l.toLowerCase() != except.toLowerCase() && (typed.isEmpty || l.toLowerCase().contains(typed) || l.toLowerCase() == typed)) l,
    ].take(8);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in options)
            CetokChip(
              label: l,
              small: true,
              selected: l.toLowerCase() == typed,
              onTap: () {
                controller.text = l;
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

/// Finds a stock row by part number or name, the results right below.
class _PartPicker extends StatefulWidget {
  const _PartPicker({super.key, required this.cetok, required this.onPicked});

  final Cetok cetok;
  final ValueChanged<CetokPart> onPicked;

  @override
  State<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends State<_PartPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final found = q.isEmpty ? const <CetokPart>[] : widget.cetok.parts.where((p) => p.matches(q)).take(30).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CetokSearchBox(controller: _query, hint: 'Ketik part number atau nama part', onChanged: () => setState(() {})),
        const SizedBox(height: 10),
        if (q.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Ketik untuk mencari dari ${widget.cetok.parts.length} part',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          )
        else if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Tidak ada part yang cocok dengan "$q"', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          )
        else
          for (var i = 0; i < found.length; i++)
            Rise(
              key: ValueKey('pick-${found[i].id}'),
              delay: Rise.stagger(i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Opacity(
                  opacity: found[i].qty <= 0 ? 0.5 : 1,
                  child: PartCard(
                    part: found[i],
                    highlight: q,
                    onTap: found[i].qty <= 0
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            widget.onPicked(found[i]);
                          },
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _PickedPart extends StatelessWidget {
  const _PickedPart({super.key, required this.part, required this.onChange});

  final CetokPart part;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.pn, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(part.desc, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                const SizedBox(height: 4),
                Text(
                  [if (part.loc.isNotEmpty) part.loc, part.status ?? 'Tanpa status', part.unit].join(' · '),
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text('${part.qty}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: part.qty <= 0 ? AppColors.danger : AppColors.ink)),
              Text('stok', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          TextButton(onPressed: onChange, child: const Text('Ganti')),
        ],
      ),
    );
  }
}

/// The picker until a part is chosen, then the part with "Ganti".
class PartSlot extends StatelessWidget {
  const PartSlot({super.key, required this.cetok, required this.part, required this.choice});

  final Cetok cetok;
  final CetokPart? part;
  final ValueNotifier<CetokPart?> choice;

  @override
  Widget build(BuildContext context) {
    final p = part;
    return AnimatedSwitcher(
      duration: cetokMotion,
      switchInCurve: cetokCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: p == null
          ? _PartPicker(key: const ValueKey('picker'), cetok: cetok, onPicked: (picked) => choice.value = picked)
          : _PickedPart(key: ValueKey('picked-${p.id}'), part: p, onChange: () => choice.value = null),
    );
  }
}

/// The picked part as it is in the latest stock list.
CetokPart? latestPart(Cetok cetok, CetokPart? picked) {
  if (picked == null) return null;
  for (final p in cetok.parts) {
    if (p.id == picked.id) return p;
  }
  return picked;
}

/// Fills in the name last used once the saved stock list has been read.
void fillName(TextEditingController name, Cetok cetok) {
  if (name.text.isEmpty && cetok.name.isNotEmpty) name.text = cetok.name;
}

String fromText(CetokPart p) => '${p.loc.isEmpty ? '–' : p.loc} (${p.status ?? 'tanpa status'})';
