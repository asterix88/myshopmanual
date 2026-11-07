import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../page_image.dart';
import '../quiz.dart';
import '../quiz_edit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

/// "Atur gambar": the admin edits the picture of a question on its page.
/// Potong chooses the part shown; Label moves, merges, splits, renames and
/// deletes the letter boxes of a labelled photo, picks the one asked, and
/// covers or uncovers words; Pratinjau shows the picture as the mechanic
/// sees it. Two fingers zoom and move the page. It opens on the last saved
/// edit, or the automatic choice.
class QuizCropScreen extends StatefulWidget {
  const QuizCropScreen({super.key, required this.api, required this.file, required this.question, this.page});

  final QuizApi api;
  final ManualFile file;
  final QuizQuestion question;

  /// The drawn page, for tests; drawn from the manual when null.
  final Future<QuizPage> Function()? page;

  @override
  State<QuizCropScreen> createState() => _QuizCropScreenState();
}

enum _Tool { crop, label, preview }

enum _Grip { move, topLeft, topRight, bottomLeft, bottomRight, resize, pan }

/// What a tap on the picture does next.
enum _Mode { normal, merge, pickAnswer }

class _QuizCropScreenState extends State<QuizCropScreen> {
  QuizPage? _page;
  Object? _error;
  late QuizEdit _edit;
  late QuizEdit _auto;
  late QuizEdit _saved;
  final _undo = <QuizEdit>[];
  final _redo = <QuizEdit>[];
  _Tool _tool = _Tool.crop;
  _Mode _mode = _Mode.normal;

  /// The selected label (cover == false) or white box (cover == true).
  ({bool cover, int index})? _sel;
  bool _sizeShown = false;
  bool _saving = false;
  Future<Uint8List>? _preview;

  // Zoom and the gesture in progress.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  Offset _startFocal = Offset.zero;
  _Grip? _grip;
  QuizEdit? _before;

  /// Where the page sits in the stage: top left and pixels on screen per
  /// page pixel, before zoom.
  Offset _origin = Offset.zero;
  double _fit = 1;
  Size _stage = Size.zero;

  String? get _target => widget.question.pictureTarget;

  @override
  void initState() {
    super.initState();
    _draw();
  }

  Future<void> _draw() async {
    try {
      final page = await (widget.page?.call() ??
          renderQuizPage(StoreScope.read(context), widget.file, widget.question.page));
      if (!mounted) {
        page.dispose();
        return;
      }
      final auto = QuizEdit.auto(page, _target, labelled: widget.question.prompt.contains('[X]'));
      final saved =
          QuizEdit.fromJson(QuizApi.savedEdit(widget.question.id) ?? widget.question.imageEdit, page.scale) ?? auto;
      setState(() {
        _page = page;
        _auto = auto;
        _saved = saved;
        _edit = saved;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _page?.dispose();
    super.dispose();
  }

  bool get _dirty => _page != null && !_edit.same(_saved);

  /// Makes [next] the edit, undoable.
  void _change(QuizEdit next, {({bool cover, int index})? select}) {
    if (next.same(_edit)) return;
    setState(() {
      _undo.add(_edit);
      if (_undo.length > 50) _undo.removeAt(0);
      _redo.clear();
      _edit = next;
      _sel = select;
      _preview = null;
    });
  }

  void _undoOne() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_edit);
      _edit = _undo.removeLast();
      _sel = null;
      _mode = _Mode.normal;
      _preview = null;
    });
  }

  void _redoOne() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_edit);
      _edit = _redo.removeLast();
      _sel = null;
      _mode = _Mode.normal;
      _preview = null;
    });
  }

  Future<void> _save() async {
    final page = _page;
    if (page == null) return;
    if (_edit.labels.isNotEmpty && _edit.ask == null) {
      showError(context, Exception('Tunjuk dulu label jawabannya: Label, lalu Ganti.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveImageEdit(widget.question.id, _edit.toJson(page.scale));
      await widget.api.uploadImage(widget.question.id, await _edit.png(page), letter: _edit.letter);
      _saved = _edit;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  Future<void> _leave() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: const Text('Editan gambar ini belum disimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut edit')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      setState(() => _saved = _edit);
      Navigator.pop(context);
    }
  }

  // ---- Picture coordinates ----

  double get _k => _fit * _zoom;

  Offset _toPage(Offset local) => (local - _origin - _pan) / _k;

  /// A point in the middle of what is on screen, in page pixels.
  Offset get _visibleCenter => _toPage(Offset(_stage.width / 2, _stage.height / 2));

  // ---- Gestures ----

  void _scaleStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startPan = _pan;
    _startFocal = d.localFocalPoint;
    _before = _edit;
    _grip = null;
    if (d.pointerCount > 1 || _tool == _Tool.preview) return;
    final p = _toPage(d.localFocalPoint);
    final reach = 28 / _k;
    if (_tool == _Tool.crop) {
      _grip = _cropGrip(p, reach) ?? (_zoom > 1 ? _Grip.pan : null);
      return;
    }
    final box = _selectedBox();
    if (box != null && _mode == _Mode.normal) {
      if ((box.bottomRight - p).distance <= reach) {
        _grip = _Grip.resize;
      } else if (box.inflate(6 / _k).contains(p)) {
        _grip = _Grip.move;
      }
    }
    _grip ??= _zoom > 1 ? _Grip.pan : null;
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      // Two fingers: zoom around the fingers, and move with them.
      _grip = null;
      final zoom = (_startZoom * d.scale).clamp(1.0, 6.0);
      final at = (_startFocal - _origin - _startPan) / (_fit * _startZoom);
      setState(() {
        _zoom = zoom;
        _pan = zoom == 1 ? Offset.zero : d.localFocalPoint - _origin - at * _fit * zoom;
      });
      return;
    }
    final grip = _grip;
    if (grip == null) return;
    if (grip == _Grip.pan) {
      setState(() => _pan += d.focalPointDelta);
      return;
    }
    final delta = d.focalPointDelta / _k;
    setState(() {
      _edit = _tool == _Tool.crop ? _edit.copyWith(crop: _dragCrop(grip, delta)) : _dragSelected(grip, delta);
      _preview = null;
    });
  }

  void _scaleEnd(ScaleEndDetails d) {
    final before = _before;
    if (before != null && !before.same(_edit)) {
      setState(() {
        _undo.add(before);
        if (_undo.length > 50) _undo.removeAt(0);
        _redo.clear();
      });
    }
    _before = null;
    _grip = null;
  }

  void _tap(TapUpDetails d) {
    if (_tool != _Tool.label) return;
    final p = _toPage(d.localPosition);
    final label = _labelAt(p);
    switch (_mode) {
      case _Mode.merge:
        final sel = _sel;
        if (label != null && sel != null && !sel.cover && label != sel.index) {
          final merged = _edit.merge(sel.index, label);
          _change(merged, select: (cover: false, index: math.min(sel.index, label)));
          setState(() => _mode = _Mode.normal);
        }
      case _Mode.pickAnswer:
        if (label != null) {
          _change(_edit.copyWith(ask: () => label), select: (cover: false, index: label));
          setState(() => _mode = _Mode.normal);
        }
      case _Mode.normal:
        final cover = label == null ? _coverAt(p) : null;
        setState(() {
          _sel = label != null
              ? (cover: false, index: label)
              : cover != null
                  ? (cover: true, index: cover)
                  : null;
        });
    }
  }

  int? _labelAt(Offset p) {
    final slop = 8 / _k;
    for (final i in _edit.order.reversed) {
      if (_edit.markBox(i).inflate(slop).contains(p)) return i;
    }
    return null;
  }

  int? _coverAt(Offset p) {
    for (var i = _edit.covers.length - 1; i >= 0; i--) {
      if (_edit.covers[i].inflate(4 / _k).contains(p)) return i;
    }
    return null;
  }

  Rect? _selectedBox() {
    final sel = _sel;
    if (sel == null) return null;
    if (sel.cover) return sel.index < _edit.covers.length ? _edit.covers[sel.index] : null;
    return sel.index < _edit.labels.length ? _edit.markBox(sel.index) : null;
  }

  _Grip? _cropGrip(Offset p, double reach) {
    final r = _edit.crop;
    final corners = {
      _Grip.topLeft: r.topLeft,
      _Grip.topRight: r.topRight,
      _Grip.bottomLeft: r.bottomLeft,
      _Grip.bottomRight: r.bottomRight,
    };
    for (final MapEntry(key: grip, value: c) in corners.entries) {
      if ((c - p).distance <= reach) return grip;
    }
    return r.contains(p) ? _Grip.move : null;
  }

  Rect _dragCrop(_Grip grip, Offset d) {
    final page = _page!;
    var r = _edit.crop;
    final w = page.width.toDouble();
    final h = page.height.toDouble();
    final least = math.max(w, h) * 0.06;
    return switch (grip) {
      _Grip.move => r.shift(Offset(d.dx.clamp(-r.left, w - r.right), d.dy.clamp(-r.top, h - r.bottom))),
      _Grip.topLeft => Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - least), (r.top + d.dy).clamp(0, r.bottom - least),
          r.right, r.bottom),
      _Grip.topRight => Rect.fromLTRB(r.left, (r.top + d.dy).clamp(0, r.bottom - least),
          (r.right + d.dx).clamp(r.left + least, w), r.bottom),
      _Grip.bottomLeft => Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - least), r.top, r.right,
          (r.bottom + d.dy).clamp(r.top + least, h)),
      _Grip.bottomRight => Rect.fromLTRB(r.left, r.top, (r.right + d.dx).clamp(r.left + least, w),
          (r.bottom + d.dy).clamp(r.top + least, h)),
      _ => r,
    };
  }

  /// The selected label or white box moved or resized by [d].
  QuizEdit _dragSelected(_Grip grip, Offset d) {
    final sel = _sel;
    if (sel == null) return _edit;
    Rect resized(Rect r) =>
        Rect.fromLTRB(r.left, r.top, math.max(r.left + 8, r.right + d.dx), math.max(r.top + 8, r.bottom + d.dy));
    if (sel.cover) {
      final covers = [..._edit.covers];
      covers[sel.index] = grip == _Grip.resize ? resized(covers[sel.index]) : covers[sel.index].shift(d);
      return _edit.copyWith(covers: covers);
    }
    final labels = [..._edit.labels];
    final l = labels[sel.index];
    labels[sel.index] = grip == _Grip.resize ? QuizLabel(resized(l.box), l.text, l.words) : l.moved(d);
    return _edit.copyWith(labels: labels);
  }

  // ---- Label actions ----

  Future<String?> _askText(String title, String text) {
    final controller = TextEditingController(text: text);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Teks di gambar'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Pakai')),
        ],
      ),
    );
  }

  Future<void> _rename(int i) async {
    final l = _edit.labels[i];
    final text = await _askText('Label ${_edit.letterOf(i) ?? ''}', l.text);
    if (text == null || !mounted) return;
    final labels = [..._edit.labels]..[i] = QuizLabel(l.box, text, l.words);
    _change(_edit.copyWith(labels: labels), select: (cover: false, index: i));
  }

  Future<void> _addLabel() async {
    final side = _edit.side;
    final box = Rect.fromCenter(center: _visibleCenter, width: side * 3, height: side * 1.2);
    final text = await _askText('Label baru', '');
    if (text == null || !mounted) return;
    final labels = [..._edit.labels, QuizLabel(box, text)];
    _change(_edit.copyWith(labels: labels), select: (cover: false, index: labels.length - 1));
  }

  void _addCover() {
    final side = _edit.side;
    final covers = [..._edit.covers, Rect.fromCenter(center: _visibleCenter, width: side * 4, height: side * 1.5)];
    _change(_edit.copyWith(covers: covers), select: (cover: true, index: covers.length - 1));
  }

  void _setTool(_Tool tool) {
    setState(() {
      _tool = tool;
      _mode = _Mode.normal;
      _sel = null;
      if (tool == _Tool.preview) _preview ??= _edit.png(_page!);
    });
  }

  // ---- Screen ----

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final landscape = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final body = page == null
        ? Center(
            child: _error == null
                ? const ExcavatorLoader()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Halaman tidak bisa digambar. Coba lagi saat ada sinyal.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
          )
        : landscape
            ? Row(children: [
                Expanded(child: _stageView(page, landscape)),
                SizedBox(
                  width: 300,
                  child: ColoredBox(color: AppColors.surface, child: SingleChildScrollView(child: _panel())),
                ),
              ])
            : Column(children: [Expanded(child: _stageView(page, landscape)), _panel()]);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.viewerBackground,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Atur gambar'),
              Text('${widget.file.title} · hal. ${widget.question.page}',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: [
            IconButton(
                tooltip: 'Batal', onPressed: _undo.isEmpty || _saving ? null : _undoOne, icon: const Icon(Icons.undo)),
            IconButton(
                tooltip: 'Ulang', onPressed: _redo.isEmpty || _saving ? null : _redoOne, icon: const Icon(Icons.redo)),
          ],
        ),
        body: SafeArea(top: false, child: body),
      ),
    );
  }

  Widget _stageView(QuizPage page, bool landscape) {
    if (_tool == _Tool.preview) return _previewView();
    return LayoutBuilder(builder: (context, box) {
      const pad = 12.0;
      _stage = box.biggest;
      _fit = math.min((box.maxWidth - 2 * pad) / page.width, (box.maxHeight - 2 * pad) / page.height);
      final shown = Size(page.width * _fit, page.height * _fit);
      _origin = Offset((box.maxWidth - shown.width) / 2, landscape ? (box.maxHeight - shown.height) / 2 : pad);
      final banner = switch (_mode) {
        _Mode.merge => 'Ketuk label kedua untuk digabung',
        _Mode.pickAnswer => 'Ketuk label untuk: ${_target ?? 'jawaban'}',
        _Mode.normal => null,
      };
      return ClipRect(
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _scaleStart,
              onScaleUpdate: _scaleUpdate,
              onScaleEnd: _scaleEnd,
              onTapUp: _tap,
              child: CustomPaint(
                painter: _EditPainter(
                  page: page,
                  edit: _edit,
                  origin: _origin + _pan,
                  k: _k,
                  tool: _tool,
                  selected: _selectedBox(),
                  navy: AppColors.navy,
                  orange: AppColors.orange,
                ),
              ),
            ),
          ),
          if (banner != null)
            Positioned(
              left: 12,
              right: 12,
              top: 10,
              child: Material(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(children: [
                    Expanded(child: Text(banner, style: const TextStyle(color: Colors.white, fontSize: 13))),
                    TextButton(
                      onPressed: () => setState(() => _mode = _Mode.normal),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Batal'),
                    ),
                  ]),
                ),
              ),
            ),
          if (_zoom > 1.01)
            Positioned(
              right: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(999)),
                child: Text('${_zoom.toStringAsFixed(1)}×', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
        ]),
      );
    });
  }

  /// The question as the mechanic sees it.
  Widget _previewView() {
    final q = widget.question;
    final letter = _edit.letter;
    var prompt = q.prompt;
    if (letter != null) {
      prompt = prompt.contains('[X]')
          ? prompt.replaceAll('[X]', letter)
          : prompt.replaceFirst(RegExp(r'bertanda [A-Z]\b'), 'bertanda $letter');
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      FutureBuilder<Uint8List>(
        future: _preview,
        builder: (context, snap) {
          final png = snap.data;
          if (snap.hasError) {
            return Text('Gambar tidak bisa dibuat.', style: TextStyle(color: AppColors.muted));
          }
          if (png == null) return const SizedBox(height: 160, child: Center(child: ExcavatorLoader()));
          return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(png, fit: BoxFit.contain));
        },
      ),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(prompt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.4)),
          for (final c in q.choices)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(c, style: TextStyle(fontSize: 13, color: AppColors.ink)),
            ),
        ]),
      ),
    ]);
  }

  Widget _panel() {
    final busy = _saving || _page == null;
    final sel = _sel;
    final children = <Widget>[
      _ToolTabs(tool: _tool, onTool: busy ? null : _setTool),
      const SizedBox(height: 10),
    ];
    switch (_tool) {
      case _Tool.crop:
        children.addAll([
          Text('Geser kotak atau sudutnya · dua jari untuk zoom',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 4),
          _ActionBar([
            _act(Icons.rotate_90_degrees_cw_outlined, 'Putar 90°',
                busy ? null : () => _change(_edit.copyWith(turns: (_edit.turns + 1) % 4))),
          ]),
        ]);
      case _Tool.label:
        if (_edit.labels.isNotEmpty || _target != null && calloutOf(widget.question.prompt) == null) {
          children.add(_AnswerCard(
            letter: _edit.letter,
            text: _target ?? '',
            onChange: busy || _edit.labels.isEmpty ? null : () => setState(() => _mode = _Mode.pickAnswer),
          ));
        }
        if (sel != null && !sel.cover && sel.index < _edit.labels.length) {
          final i = sel.index;
          final l = _edit.labels[i];
          children.addAll([
            _SelectedRow(
              title: '${_edit.letterOf(i) ?? '-'} · ${l.text.isEmpty ? 'Tanpa teks' : l.text}',
              onSize: () => setState(() => _sizeShown = !_sizeShown),
            ),
            _ActionBar([
              _act(Icons.text_fields, 'Teks', busy ? null : () => _rename(i)),
              _act(Icons.merge_type, 'Gabung', busy || _edit.labels.length < 2 ? null : () => setState(() => _mode = _Mode.merge)),
              _act(Icons.call_split, 'Pisah',
                  busy || quizSplitWords(l.words).length < 2 ? null : () => _change(_edit.split(i, _target), select: (cover: false, index: i))),
              _act(Icons.delete_outline, 'Hapus', busy ? null : () => _change(_edit.removeLabel(i)), danger: true),
            ]),
          ]);
        } else if (sel != null && sel.cover) {
          children.addAll([
            const _SelectedRow(title: 'Tutup teks'),
            _ActionBar([
              _act(Icons.delete_outline, 'Buka tutup',
                  busy ? null : () => _change(_edit.copyWith(covers: [..._edit.covers]..removeAt(sel.index))),
                  danger: true),
            ]),
          ]);
        } else {
          children.addAll([
            Text('Ketuk huruf atau kotak putih untuk memilih.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            _ActionBar([
              _act(Icons.add, 'Label', busy ? null : _addLabel),
              _act(Icons.rectangle_outlined, 'Tutup teks', busy ? null : _addCover),
              if (_edit.labels.isNotEmpty)
                _act(Icons.format_size, 'Ukuran huruf', () => setState(() => _sizeShown = !_sizeShown)),
            ]),
          ]);
        }
        if (_sizeShown && _edit.labels.isNotEmpty) {
          children.add(Row(children: [
            Text('Ukuran huruf', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            Expanded(
              child: Slider(
                value: _edit.size,
                min: 0.6,
                max: 1.8,
                onChangeStart: (_) => _before = _edit,
                onChanged: (v) => setState(() {
                  _edit = _edit.copyWith(size: v);
                  _preview = null;
                }),
                onChangeEnd: (_) => _scaleEnd(ScaleEndDetails()),
              ),
            ),
          ]));
        }
      case _Tool.preview:
        break;
    }
    children.addAll([
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy || _edit.same(_auto) ? null : () => _change(_auto),
            child: const Text('Otomatis'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : _save,
            child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
          ),
        ),
      ]),
    ]);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _ToolTabs extends StatelessWidget {
  const _ToolTabs({required this.tool, required this.onTool});

  final _Tool tool;
  final ValueChanged<_Tool>? onTool;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (_Tool.crop, Icons.crop, 'Potong'),
      (_Tool.label, Icons.label_outline, 'Label'),
      (_Tool.preview, Icons.visibility_outlined, 'Pratinjau'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final (t, icon, label) in tabs)
          Expanded(
            child: GestureDetector(
              onTap: onTool == null ? null : () => onTool!(t),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: t == tool ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: t == tool ? const [BoxShadow(color: Color(0x14101828), blurRadius: 4, offset: Offset(0, 1))] : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 18, color: t == tool ? AppColors.navy : AppColors.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: t == tool ? FontWeight.w600 : FontWeight.w500,
                          color: t == tool ? AppColors.navy : AppColors.muted,
                        )),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The answer the question asks about and its letter on the picture.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.letter, required this.text, required this.onChange});

  final String? letter;
  final String text;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.orange, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(letter ?? '?', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(letter == null ? 'Jawaban · belum ditunjuk' : 'Jawaban',
                style: TextStyle(fontSize: 12, color: letter == null ? AppColors.danger : AppColors.muted)),
            Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ]),
        ),
        TextButton(onPressed: onChange, child: const Text('Ganti')),
      ]),
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({required this.title, this.onSize});

  final String title;
  final VoidCallback? onSize;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ),
      if (onSize != null) TextButton(onPressed: onSize, child: const Text('Ukuran huruf')),
    ]);
  }
}

typedef _Act = (IconData icon, String label, VoidCallback? onTap, {bool danger});

_Act _act(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => (icon, label, onTap, danger: danger);

/// Actions as 48 dp buttons with their names.
class _ActionBar extends StatelessWidget {
  const _ActionBar(this.actions);

  final List<_Act> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (final (icon, label, onTap, danger: danger) in actions)
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Opacity(
                  opacity: onTap == null ? 0.4 : 1,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 22, color: danger ? AppColors.danger : AppColors.navy),
                    const SizedBox(height: 2),
                    Text(label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: danger ? AppColors.danger : AppColors.ink)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The page with its white boxes and letters, the crop box, and the
/// selected item's outline and resize handle.
class _EditPainter extends CustomPainter {
  _EditPainter({
    required this.page,
    required this.edit,
    required this.origin,
    required this.k,
    required this.tool,
    required this.selected,
    required this.navy,
    required this.orange,
  });

  final QuizPage page;
  final QuizEdit edit;
  final Offset origin;
  final double k;
  final _Tool tool;
  final Rect? selected;
  final Color navy;
  final Color orange;

  Rect _screen(Rect r) => Rect.fromLTRB(r.left * k + origin.dx, r.top * k + origin.dy, r.right * k + origin.dx, r.bottom * k + origin.dy);

  @override
  void paint(Canvas canvas, Size size) {
    final pageRect = _screen(Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()));
    canvas.drawImageRect(page.image, Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()), pageRect,
        Paint()..filterQuality = FilterQuality.medium);
    final white = Paint()..color = Colors.white;
    for (final c in edit.covers) {
      canvas.drawRect(_screen(c), white);
    }
    if (tool == _Tool.label) {
      final dash = Paint()
        ..color = navy.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final c in edit.covers) {
        canvas.drawRect(_screen(c), dash);
      }
    }
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(k);
    paintQuizMarks(canvas, edit.marks, 1, Offset.zero, side: edit.side);
    canvas.restore();

    final crop = _screen(edit.crop);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(pageRect)
      ..addRect(crop);
    canvas.drawPath(outside, Paint()..color = Color(tool == _Tool.crop ? 0x59000000 : 0x33000000));
    if (tool == _Tool.crop) {
      canvas.drawRect(crop, Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      final grip = Paint()..color = navy;
      final ring = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final c in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
        canvas.drawCircle(c, 8, grip);
        canvas.drawCircle(c, 8, ring);
      }
    }
    final sel = selected;
    if (tool == _Tool.label && sel != null) {
      final r = _screen(sel).inflate(3);
      canvas.drawRect(r, Paint()
        ..color = orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      canvas.drawCircle(r.bottomRight, 7, Paint()..color = orange);
      canvas.drawCircle(r.bottomRight, 7, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_EditPainter old) =>
      old.edit != edit || old.origin != origin || old.k != k || old.tool != tool || old.selected != selected ||
      old.navy != navy || old.page != page;
}
