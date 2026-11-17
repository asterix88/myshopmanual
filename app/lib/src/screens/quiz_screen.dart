/// Playing a quiz. This file holds the quiz bar and the play page; the other
/// quiz pages and pieces are part files under `quiz/`:
///
/// - `play_widgets.dart`    options, tags, skeleton, error view, sheets
/// - `summary_screen.dart`  score after a quiz
/// - `review_screen.dart`   looking back at the answers
/// - `picture.dart`         a question's picture and its zoom
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth.dart';
import '../quiz.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/quiz_widgets.dart';
import 'quiz_hub_screen.dart';
import 'shell.dart';
import 'viewer_screen.dart';

part 'quiz/picture.dart';
part 'quiz/play_widgets.dart';
part 'quiz/review_screen.dart';
part 'quiz/summary_screen.dart';

/// The navy bar on Quiz screens: X (or back), title, something on the right.
class QuizBar extends StatelessWidget implements PreferredSizeWidget {
  const QuizBar({super.key, required this.title, this.close = false, this.onLeading, this.trailing, this.bottom});

  final String title;
  final bool close;
  final VoidCallback? onLeading;
  final Widget? trailing;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      titleTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
      leading: IconButton(
        tooltip: close ? 'Tutup' : 'Kembali',
        onPressed: onLeading ?? () => Navigator.maybePop(context),
        icon: close ? const AppIcon(AppGlyph.close, color: Colors.white, size: 22) : const BackButtonIcon(),
      ),
      title: Text(title),
      actions: [if (trailing != null) Padding(padding: const EdgeInsets.only(right: 16), child: trailing)],
      bottom: bottom,
    );
  }
}

/// One set of 10 questions: Quiz harian ([unit] null) or Quiz per unit.
/// Choose an answer, Periksa, read why, Lanjut. Wrong answers come back at
/// the end of the set ("Ulangan").
class QuizPlayScreen extends StatefulWidget {
  const QuizPlayScreen({super.key, this.unit, this.client});

  final String? unit;
  final http.Client? client;

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final QuizApi _api = QuizApi(StoreScope.read(context), _client);

  QuizSession? _session;
  Object? _error;

  /// The questions in the order shown: the set, then the ones answered wrong.
  final _queue = <QuizQuestion>[];
  int _i = 0;
  int? _picked;
  bool _checked = false;
  AnswerResult? _result;
  bool _sent = false;
  late DateTime _shownAt;

  /// First answers: question id -> right or wrong.
  final _first = <String, bool>{};
  final _chosen = <String, int>{};
  int _xp = 0;
  final _started = DateTime.now();

  String get _title => widget.unit == null ? 'Quiz harian' : 'Quiz ${widget.unit}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _session = null;
    });
    try {
      final s = await _api.start(unit: widget.unit);
      if (!mounted) return;
      _queue
        ..clear()
        ..addAll(s.questions);
      for (final q in s.questions) {
        final a = s.answered[q.id];
        if (a != null) {
          _first[q.id] = a.correct;
          _chosen[q.id] = a.chosen;
        }
      }
      // A set continued: skip what was answered, the wrong ones come back.
      _i = s.questions.indexWhere((q) => !_first.containsKey(q.id));
      if (_i < 0) _i = s.questions.length;
      _queue.addAll(s.questions.where((q) => _first[q.id] == false));
      setState(() {
        _session = s;
        _shownAt = DateTime.now();
      });
      if (_i >= _queue.length) unawaited(_finish());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  QuizQuestion get _q => _queue[_i];
  bool get _inRetry => _session != null && _i >= _session!.questions.length;

  void _check() {
    if (_picked == null || _checked) return;
    final q = _q;
    final right = _picked == q.answer;
    unawaited(right ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact());
    final ms = DateTime.now().difference(_shownAt).inMilliseconds;
    setState(() {
      _checked = true;
      _result = null;
      _sent = false;
    });
    final firstTime = !_first.containsKey(q.id);
    if (firstTime) {
      _first[q.id] = right;
      _chosen[q.id] = _picked!;
      if (!right) _queue.add(q);
    }
    _api.answer(QuizAnswer(sessionId: _session!.id, questionId: q.id, chosen: _picked!, ms: ms)).then((r) {
      if (!mounted) return;
      if (r != null) _xp += r.xp;
      setState(() {
        _result = r;
        _sent = true;
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _sent = true);
    });
  }

  void _next() {
    if (_i + 1 >= _queue.length) {
      unawaited(_finish());
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _checked = false;
      _result = null;
      _shownAt = DateTime.now();
    });
  }

  Future<void> _finish() async {
    final session = _session!;
    FinishResult? result;
    Object? error;
    try {
      result = await _api.finish(session.id);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    QuizApi.changed.value++;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => QuizSummaryScreen(
        daily: widget.unit == null,
        unit: widget.unit,
        questions: session.questions,
        first: Map.of(_first),
        chosen: Map.of(_chosen),
        result: result,
        offline: error is AuthException && error.code == 'network',
        xpWithoutBonus: _xp,
        minutes: DateTime.now().difference(_started).inMinutes,
      ),
    ));
  }

  Future<void> _exit() async {
    if (_session == null || _first.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final leave = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => _Sheet(
        title: 'Keluar dari quiz?',
        message: widget.unit == null
            ? 'Jawaban tersimpan. Bisa dilanjutkan sampai 04.00.'
            : 'Jawaban tersimpan.',
        children: [
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjutkan quiz')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Keluar')),
        ],
      ),
    );
    if ((leave ?? false) && mounted) {
      QuizApi.changed.value++;
      Navigator.pop(context);
    }
  }

  Future<void> _report() async {
    const reasons = [
      'Jawaban kunci salah',
      'Lebih dari satu jawaban benar',
      'Soal tidak jelas',
      'Tidak sesuai unit di site saya',
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _Sheet(
        title: 'Laporkan soal',
        children: [
          for (final r in reasons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r, style: const TextStyle(fontSize: 14)),
              trailing: AppIcon(AppGlyph.flag, size: 18, color: AppColors.muted),
              onTap: () => Navigator.pop(context, r),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _api.report(_q.id, picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan terkirim')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _openManual() {
    final q = _q;
    final store = StoreScope.read(context);
    if (store.fileByKey(q.manualId) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manual ${q.manualId} tidak ada di daftar manual HP ini.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ViewerScreen(fileKey: q.manualId, initialPage: q.page)));
  }

  void _askAi() {
    final q = _q;
    final store = StoreScope.read(context);
    store.askAi('Jelaskan soal quiz ini: ${q.prompt}\nJawaban benar: ${q.choices[q.answer]}');
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return PopScope(
      canPop: session == null || _first.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: QuizBar(
          title: _title,
          close: true,
          onLeading: _exit,
          trailing: session == null || _i >= _queue.length
              ? null
              : Text(
                  _inRetry
                      ? 'Ulangan ${_i - session.questions.length + 1}/${_queue.length - session.questions.length}'
                      : '${_i + 1}/${session.questions.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: session == null ? 0 : (_inRetry ? 1 : _i / session.questions.length),
              minHeight: 4,
              backgroundColor: Colors.white24,
              color: AppColors.orange,
            ),
          ),
        ),
        body: switch ((session, _error)) {
          (_, final Object e) => _ErrorView(error: e, unit: widget.unit, onRetry: _load),
          (null, _) => const _QuizSkeleton(),
          _ when _i >= _queue.length => const _QuizSkeleton(),
          _ => _question(context),
        },
      ),
    );
  }

  Widget _question(BuildContext context) {
    final q = _q;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (q.unit != null) Pill(q.unit!, background: AppColors.navySoft, foreground: AppColors.navy),
                  Text(q.topicName, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (_inRetry)
                    Pill('Ulangan', background: AppColors.orangeSoft, foreground: AppColors.orangeText)
                  else if (q.review)
                    _RecallTag(),
                ],
              ),
              const SizedBox(height: 14),
              Text(q.prompt, style: const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w600)),
              if (q.image != null) ...[
                const SizedBox(height: 12),
                QuizPicture(api: _api, questionId: q.id),
              ],
              const SizedBox(height: 16),
              for (final (i, choice) in q.choices.indexed) ...[
                _Option(
                  letter: 'ABCD'[i.clamp(0, 3)],
                  text: choice,
                  state: !_checked
                      ? (_picked == i ? _OptState.picked : _OptState.idle)
                      : i == q.answer
                          ? _OptState.right
                          : i == _picked
                              ? _OptState.wrong
                              : _OptState.dim,
                  onTap: _checked ? null : () => setState(() => _picked = i),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        Material(
          color: AppColors.surface,
          elevation: 8,
          shadowColor: const Color(0x33101828),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
            child: _checked ? _feedback(q) : _checkButton(),
          ),
        ),
      ],
    );
  }

  Widget _checkButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _picked == null ? null : _check,
          child: const Text('Periksa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _feedback(QuizQuestion q) {
    final right = _picked == q.answer;
    final color = right ? AppColors.green : AppColors.danger;
    final firstWrong = !right && !_inRetry;
    final next = !right
        ? (firstWrong ? 'Diulang di akhir sesi dan besok' : 'Diulang besok')
        : _result == null
            ? (_sent ? 'Dikirim saat ada sinyal' : '')
            : _result!.nextDays <= 1
                ? 'Diulang besok'
                : 'Diulang ${_result!.nextDays} hari lagi';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: AppIcon(right ? AppGlyph.check : AppGlyph.cross, size: 14, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Text(right ? 'Benar' : 'Belum tepat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            const Spacer(),
            if ((_result?.xp ?? 0) > 0)
              Text('+${_result!.xp} XP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .22),
          child: SingleChildScrollView(
            child: Text(q.explain, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkSoft)),
          ),
        ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(next, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            if (q.page > 0) _LinkButton(glyph: AppGlyph.book, label: 'Manual hal. ${q.page}', onTap: _openManual),
            _LinkButton(glyph: AppGlyph.nyel, label: 'Tanya nyel AI', onTap: _askAi),
            const Spacer(),
            IconButton(
              tooltip: 'Laporkan soal',
              onPressed: _report,
              icon: AppIcon(AppGlyph.flag, size: 18, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _next,
            child: const Text('Lanjut', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
