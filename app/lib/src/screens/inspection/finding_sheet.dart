part of '../inspection_screen.dart';

// One finding's detail sheet, where Action is filled in to close it.

/// White sheet with rounded top and a grab handle.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.onDragDown});

  final Widget child;
  final VoidCallback? onDragDown;

  @override
  Widget build(BuildContext context) {
    final handle = Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Center(
        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) (onDragDown ?? () => Navigator.of(context).maybePop())();
            },
            child: handle,
          ),
          child,
        ],
      ),
    );
  }
}

class _Saved {
  const _Saved(this.action, this.sent);

  final String action;
  final bool sent;
}

/// A finding's details and its ACTION; saving it makes the finding CLOSE.
class _FindingSheet extends StatefulWidget {
  const _FindingSheet({required this.row, required this.inspection});

  final InspectionRow row;
  final Inspection inspection;

  @override
  State<_FindingSheet> createState() => _FindingSheetState();
}

class _FindingSheetState extends State<_FindingSheet> {
  late final _action = TextEditingController(text: widget.row.action);
  bool _saving = false;

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  bool get _dirty => _action.text.trim() != widget.row.action.trim();

  Future<void> _close() async {
    if (_dirty) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Buang isian Action?'),
          content: const Text('Tulisan yang belum disimpan akan hilang'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut isi')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buang')),
          ],
        ),
      );
      if (drop != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final text = _action.text.trim().toUpperCase();
    setState(() => _saving = true);
    try {
      final sent = await widget.inspection.setAction(widget.row, text);
      if (mounted) Navigator.of(context).pop(_Saved(text, sent));
    } on InspectionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final age = r.ageOn(DateTime.now());
    final found = [r.date, if (r.hm.isNotEmpty) 'HM ${r.hm}', if (age != null) '$age hari'].join(' · ');
    final canSave = !_saving && _dirty && (r.closed || _action.text.trim().isNotEmpty);
    Widget info(String label, String value, {bool first = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: AppColors.divider))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted))),
              Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.ink))),
            ],
          ),
        );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: _SheetFrame(
          onDragDown: _close,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + (keyboard > 0 ? 0 : MediaQuery.paddingOf(context).bottom)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.unit} · ${r.model}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                    StatusPill(closed: r.closed),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.problem, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink)),
                const SizedBox(height: 12),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: keyboard > 0
                      ? Text(
                          '${_who(r)} / ${r.leader} · ${r.date}',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        )
                      : Container(
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              info('Inspector', r.inspector, first: true),
                              info('Leader', r.leader),
                              info('Ditemukan', found),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('inspection-action'),
                  controller: _action,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_Upper()],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Cth: done, replace saat service',
                    hintStyle: TextStyle(color: AppColors.faint, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    key: const Key('inspection-save-action'),
                    onPressed: canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(r.closed ? 'Simpan perubahan' : 'Simpan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
