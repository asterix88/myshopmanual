part of '../chat_screen.dart';

// Mode belajar: the switch, the colors and the tutor's own bubbles.

/// The chat's colors in the normal mode and in mode belajar. [lerp] blends
/// them while the switch moves, so the screen changes color smoothly.
class _ChatPalette {
  const _ChatPalette({
    required this.bar,
    required this.title,
    required this.subtitle,
    required this.barIcon,
    required this.background,
    required this.surface,
    required this.field,
    required this.userBubble,
  });

  factory _ChatPalette.of({required bool learning}) => learning
      ? _ChatPalette(
          bar: AppColors.learningBar,
          title: Colors.white,
          subtitle: AppColors.learningBarMuted,
          barIcon: Colors.white,
          background: AppColors.learningBackground,
          surface: AppColors.learningSurface,
          field: AppColors.learningField,
          userBubble: AppColors.learningUserBubble,
        )
      : _ChatPalette(
          bar: AppColors.surface,
          title: AppColors.navy,
          subtitle: AppColors.muted,
          barIcon: AppColors.ink,
          background: AppColors.background,
          surface: AppColors.surface,
          field: AppColors.field,
          userBubble: AppColors.navyFill,
        );

  /// [t] 0 is the normal mode, 1 is mode belajar.
  factory _ChatPalette.lerp(double t) {
    final a = _ChatPalette.of(learning: false);
    final b = _ChatPalette.of(learning: true);
    Color mix(Color Function(_ChatPalette p) pick) => Color.lerp(pick(a), pick(b), t)!;
    return _ChatPalette(
      bar: mix((p) => p.bar),
      title: mix((p) => p.title),
      subtitle: mix((p) => p.subtitle),
      barIcon: mix((p) => p.barIcon),
      background: mix((p) => p.background),
      surface: mix((p) => p.surface),
      field: mix((p) => p.field),
      userBubble: mix((p) => p.userBubble),
    );
  }

  final Color bar;
  final Color title;
  final Color subtitle;
  final Color barIcon;
  final Color background;

  /// Answer cards and the input bar.
  final Color surface;
  final Color field;
  final Color userBubble;
}

/// The app logo at the top left. It turns once when mode belajar is
/// switched: clockwise on (like tightening a bolt), anticlockwise off. In
/// mode belajar it sits on a white disc so it shows on the navy bar.
class _SpinningLogo extends StatefulWidget {
  const _SpinningLogo({required this.learning});

  final bool learning;

  @override
  State<_SpinningLogo> createState() => _SpinningLogoState();
}

class _SpinningLogoState extends State<_SpinningLogo> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_SpinningLogo old) {
    super.didUpdateWidget(old);
    if (old.learning != widget.learning) _turn.forward(from: 0);
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.learning ? 1.0 : -1.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.learning ? Colors.white : Colors.white.withAlpha(0),
      ),
      alignment: Alignment.center,
      child: RotationTransition(
        turns: Tween(begin: 0.0, end: direction).animate(CurvedAnimation(parent: _turn, curve: Curves.easeInOutCubic)),
        // In dark mode the logo goes without its white tile; mode belajar
        // keeps it on its white circle.
        child: AppColors.dark && !widget.learning
            ? const LogoMark(size: 42, nutColor: Color(0xFFE8EAED))
            : Image.asset('assets/images/logo.png', width: widget.learning ? 34 : 42, height: widget.learning ? 34 : 42),
      ),
    );
  }
}

/// The on/off switch of mode belajar in the app bar.
class _LearningSwitch extends StatelessWidget {
  const _LearningSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mode belajar',
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.orange,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.border,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

/// "Socratic style tutor aktif" across the chat with the time, like the date
/// lines of a chat app.
class _LearningDivider extends StatelessWidget {
  const _LearningDivider({super.key, required this.entry});

  final ChatEntry entry;

  static String _time(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
    final clock = '${at.hour.toString().padLeft(2, '0')}.${at.minute.toString().padLeft(2, '0')}';
    final when = switch (days) {
      0 => 'Hari ini',
      1 => 'Kemarin',
      _ => '${at.day} ${_months[at.month - 1]} ${at.year}',
    };
    return '$when $clock';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  @override
  Widget build(BuildContext context) {
    final on = entry.kind == EntryKind.learningOn;
    final line = Expanded(child: Divider(color: on ? AppColors.learningLine : AppColors.border));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Text(
                  on ? 'Socratic style tutor aktif' : 'Socratic style tutor tidak aktif',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? AppColors.learningInk : AppColors.muted,
                  ),
                ),
                if (entry.at case final at?)
                  Text(_time(at), style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// The tutor's closing question, apart from the text above it.
class _TutorQuestion extends StatelessWidget {
  const _TutorQuestion(this.question);

  final String question;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.learningField, borderRadius: BorderRadius.circular(12)),
      child: Text(
        question,
        style: TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.learningInk),
      ),
    );
  }
}

/// A tutor reply split into its text and its closing question (the last
/// line when it ends with "?"); the question is null when there is none.
({String text, String? question}) splitTutorQuestion(String reply) {
  final lines = reply.trimRight().split('\n');
  final last = lines.last.trim();
  final question = last.replaceAll('**', '').trim();
  if (!question.endsWith('?') || RegExp(r'^([-•*]|\d{1,2}[.)])\s').hasMatch(last)) {
    return (text: reply, question: null);
  }
  return (text: lines.take(lines.length - 1).join('\n').trim(), question: question);
}

/// The Petunjuk button above the input, once for each tutor question.
class _HintButton extends StatelessWidget {
  const _HintButton({required this.used, required this.onPressed});

  final bool used;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: used ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: AppColors.border),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
          minimumSize: const Size(0, 36),
        ),
        icon: const AppIcon(AppGlyph.hint, size: 18),
        label: Text(used ? 'Petunjuk terpakai' : 'Petunjuk'),
      ),
    );
  }
}

/// "Perlu jawaban lengkapnya?" with its two answers.
class _OfferActions extends StatelessWidget {
  const _OfferActions({required this.onExplain, required this.onTryAgain});

  final VoidCallback? onExplain;
  final VoidCallback? onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: onExplain,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navyFill,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
            minimumSize: const Size(0, 36),
          ),
          child: const Text('Ya, jelaskan'),
        ),
        OutlinedButton(
          onPressed: onTryAgain,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            side: BorderSide(color: AppColors.border),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            minimumSize: const Size(0, 36),
          ),
          child: const Text('Coba lagi'),
        ),
      ],
    );
  }
}
