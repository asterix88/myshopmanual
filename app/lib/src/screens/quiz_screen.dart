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
              if (q.type == 'gambar' && q.image != null) ...[
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

class _RecallTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      message: 'Soal ulangan: dulu salah atau sudah waktunya diulang',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
        decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppGlyph.refresh, size: 12, color: AppColors.orangeText),
            const SizedBox(width: 4),
            Text('Recall', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.orangeText)),
          ],
        ),
      ),
    );
  }
}

enum _OptState { idle, picked, right, wrong, dim }

/// An answer: at least 56 px high and tappable all over (gloves).
class _Option extends StatelessWidget {
  const _Option({required this.letter, required this.text, required this.state, this.onTap});

  final String letter;
  final String text;
  final _OptState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (border, fill, badge, badgeText) = switch (state) {
      _OptState.idle => (AppColors.border, AppColors.surface, AppColors.background, AppColors.inkSoft),
      _OptState.picked => (AppColors.navy, AppColors.navySoft, AppColors.navy, Colors.white),
      _OptState.right => (AppColors.green, AppColors.greenSoft, AppColors.green, Colors.white),
      _OptState.wrong => (AppColors.danger, AppColors.danger.withValues(alpha: .08), AppColors.danger, Colors.white),
      _OptState.dim => (AppColors.line, AppColors.surface, AppColors.background, AppColors.faint),
    };
    return Semantics(
      button: true,
      selected: state == _OptState.picked,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: state == _OptState.idle || state == _OptState.dim ? 1 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                    child: Center(
                      child: switch (state) {
                        _OptState.right => const AppIcon(AppGlyph.check, size: 16, color: Colors.white),
                        _OptState.wrong => const AppIcon(AppGlyph.cross, size: 16, color: Colors.white),
                        _ => Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: badgeText)),
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: state == _OptState.dim ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.glyph, required this.label, required this.onTap});

  final AppGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.navy;
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 40),
        foregroundColor: color,
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(glyph, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _QuizSkeleton extends StatelessWidget {
  const _QuizSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat soal',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 96, height: 22, radius: 6)),
          SizedBox(height: 16),
          SkeletonBox(height: 18),
          SizedBox(height: 8),
          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .7, child: SkeletonBox(height: 18)),
          SizedBox(height: 22),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 14),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.unit, required this.onRetry});

  final Object error;
  final String? unit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final code = error is AuthException ? (error as AuthException).code : '';
    final (title, message) = switch (code) {
      'done' => ('Quiz harian sudah selesai', 'Coba Quiz per unit'),
      'empty' => ('Belum ada soal', 'Soal untuk ${unit ?? 'section-mu'} sedang disiapkan'),
      'network' => ('Gagal memuat soal', 'Periksa koneksi internet.'),
      _ => ('Gagal memuat soal', error is AuthException ? (error as AuthException).message : '$error'),
    };
    final retry = code == 'network' || code == 'server' || code == '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(code == 'network' ? AppGlyph.cloudOff : AppGlyph.quiz, size: 36, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 20),
            if (retry)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const AppIcon(AppGlyph.refresh, size: 18, color: Colors.white),
                label: const Text('Coba lagi'),
              )
            else if (code == 'done' || (code == 'empty' && unit == null))
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const QuizUnitsScreen()),
                ),
                child: const Text('Quiz per unit'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.message, required this.children});

  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// After the last question: right answers, XP, rank, streak.
class QuizSummaryScreen extends StatelessWidget {
  const QuizSummaryScreen({
    super.key,
    required this.daily,
    required this.unit,
    required this.questions,
    required this.first,
    required this.chosen,
    required this.result,
    required this.offline,
    required this.xpWithoutBonus,
    required this.minutes,
  });

  final bool daily;
  final String? unit;
  final List<QuizQuestion> questions;
  final Map<String, bool> first;
  final Map<String, int> chosen;

  /// null when the set could not be closed on the server (no signal).
  final FinishResult? result;
  final bool offline;
  final int xpWithoutBonus;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final right = result?.score ?? first.values.where((v) => v).length;
    final total = result?.total ?? questions.length;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: QuizBar(title: daily ? 'Quiz selesai' : 'Quiz $unit selesai', close: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Text('Jawaban benar', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$right', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    TextSpan(text: '/$total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.muted)),
                  ]),
                ),
                Text(minutes < 2 ? 'sekitar 1 menit' : '$minutes menit', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '+${result?.xp ?? xpWithoutBonus}',
                  label: 'XP',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(value: (result?.rank ?? 0) > 0 ? '${result!.rank}' : '-', label: 'Peringkat'),
              ),
            ],
          ),
          if (daily && result != null) ...[
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  StreakRing(streak: result!.streak, look: FlameLook.done),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Streak ${result!.streak} hari', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(
                          result!.freezeUsed ? 'Libur streak terpakai' : 'Quiz hari ini selesai',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (offline) ...[
            const SizedBox(height: 12),
            AppCard(
              color: AppColors.amberSoft,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  AppIcon(AppGlyph.cloudOff, size: 20, color: AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'XP dan streak dihitung saat ada sinyal',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => QuizReviewScreen(questions: questions, first: first, chosen: chosen),
            )),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const AppIcon(AppGlyph.list, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lihat ${questions.length} soal', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QuizHubScreen())),
            child: const Text('Selesai', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}

/// The questions of a set with the right answer and why; tap to open.
class QuizReviewScreen extends StatefulWidget {
  const QuizReviewScreen({super.key, required this.questions, required this.first, required this.chosen});

  final List<QuizQuestion> questions;
  final Map<String, bool> first;
  final Map<String, int> chosen;

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Soal sesi ini'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                for (final (i, q) in widget.questions.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => setState(() => _open = _open == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Mark(right: widget.first[q.id]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.prompt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  [?q.unit, widget.first[q.id] == false ? 'Diulang besok' : q.topicName].join(' · '),
                                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                                if (_open == i) ...[
                                  const SizedBox(height: 8),
                                  Text.rich(
                                    TextSpan(children: [
                                      const TextSpan(text: 'Jawaban: '),
                                      TextSpan(
                                        text: q.choices[q.answer.clamp(0, q.choices.length - 1)],
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ]),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(q.explain, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
                                  if (q.page > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('Manual hal. ${q.page}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.right});

  final bool? right;

  @override
  Widget build(BuildContext context) {
    final color = right == null ? AppColors.border : (right! ? AppColors.green : AppColors.danger);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: AppIcon(right == false ? AppGlyph.cross : AppGlyph.check, size: 14, color: Colors.white),
      ),
    );
  }
}

/// The picture of a "gambar" question: the manual's drawing with its numbers
/// and without its words. Tap to see it full screen and zoom in.
class QuizPicture extends StatefulWidget {
  const QuizPicture({super.key, required this.api, required this.questionId, this.height = 220});

  final QuizApi api;
  final String questionId;
  final double height;

  @override
  State<QuizPicture> createState() => _QuizPictureState();
}

class _QuizPictureState extends State<QuizPicture> {
  late Future<Uint8List> _bytes = widget.api.image(widget.questionId);

  @override
  void didUpdateWidget(QuizPicture old) {
    super.didUpdateWidget(old);
    if (old.questionId != widget.questionId) _bytes = widget.api.image(widget.questionId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        return Semantics(
          label: 'Gambar soal. Ketuk untuk perbesar.',
          button: bytes != null,
          child: GestureDetector(
            onTap: bytes == null
                ? (snap.hasError ? () => setState(() => _bytes = widget.api.image(widget.questionId)) : null)
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PictureZoom(bytes: bytes))),
            child: Container(
              height: widget.height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Stack(
                      children: [
                        Positioned.fill(child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium)),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xB31F2328), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Ketuk untuk perbesar', style: TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: snap.hasError
                          ? Text('Gagal dimuat. Ketuk lagi.',
                              style: TextStyle(fontSize: 12, color: AppColors.muted))
                          : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _PictureZoom extends StatelessWidget {
  const _PictureZoom({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const QuizBar(title: 'Gambar soal', close: true),
      body: InteractiveViewer(
        maxScale: 8,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}
