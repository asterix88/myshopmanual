import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../diagnostics.dart';
import '../haptics.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/logo_mark.dart';
import 'intro_screen.dart';
import 'shell.dart';
import '../theme.dart';

/// Digits in a PIN (the server checks the same).
const pinLength = 4;

/// Navy band behind the logo on the login screen and the introduction.
LinearGradient get headerGradient => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: AppColors.dark ? const [Color(0xFF0E1A2C), Color(0xFF1A2F4F)] : const [Color(0xFF1E3A64), Color(0xFF2C5791)],
);

/// First screen until an employee logs in with NRP and PIN (needs internet).
/// The header drops in, the PC210 drives into it and the fields follow one
/// by one; a wrong PIN shakes the boxes; after a good one the header grows
/// into the introduction's and the PC210 drives off.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _nrp = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _showPin = false;
  bool _busy = false;
  bool _done = false;
  String? _nrpError;
  String? _error;
  int _shakes = 0;

  /// Arrival of the header, picture and fields.
  late final _arrive = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  /// Hand-over to the introduction after a good login.
  late final _leave = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _arrive.value = 1;
  }

  @override
  void dispose() {
    _nrp.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    _arrive.dispose();
    _leave.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || _done) return;
    final nrpMissing = _nrp.text.trim().isEmpty;
    final pinShort = _pin.text.length != pinLength;
    if (nrpMissing || pinShort) {
      setState(() {
        _nrpError = nrpMissing ? 'Isi NRP.' : null;
        _error = pinShort ? 'PIN $pinLength angka.' : null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _nrpError = null;
    });
    final store = StoreScope.read(context);
    try {
      final result = await store.auth.login(_nrp.text, _pin.text, await store.deviceInfo());
      if (!mounted) return;
      switch (result) {
        case LoggedIn(:final session):
          await _handOver(() => store.signIn(session));
        case ChoosePin(:final setupToken, :final name):
          setState(() => _busy = false);
          final session = await Navigator.of(context).push<Session>(
            MaterialPageRoute(
              builder: (_) => ChoosePinScreen(setupToken: setupToken, name: name),
            ),
          );
          if (session != null) await store.signIn(session);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          // An NRP that is not on the employee list shows under the NRP.
          if (e.code == 'unknown') {
            _nrpError = e.message;
          } else {
            _error = e.message;
          }
          if (e.code == 'pin') {
            _pin.clear();
            _shakes++;
          }
        });
        if (e.code == 'pin' || e.code == 'unknown') unawaited(buzzError());
        if (e.code == 'pin') _pinFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A green tick, then the header grows and the form fades before [signIn]
  /// swaps to the introduction (or Home).
  Future<void> _handOver(Future<void> Function() signIn) async {
    setState(() {
      _busy = false;
      _done = true;
    });
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await _leave.forward();
    await signIn();
  }

  void _forgot() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ForgotPinScreen(nrp: _nrp.text)));
  }

  /// Fades and lifts the nth part of the form in during the arrival, and
  /// out again during the hand-over.
  Widget _part(int n, Widget child) {
    final start = (0.32 + n * 0.055).clamp(0.0, 0.8);
    final t = CurvedAnimation(
      parent: _arrive,
      curve: Interval(start, (start + 0.35).clamp(0.0, 1.0), curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([t, _leave]),
      child: child,
      builder: (context, child) {
        final out = Curves.easeIn.transform((_leave.value * 2).clamp(0.0, 1.0));
        return Opacity(
          opacity: (t.value * (1 - out)).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 10 * (1 - t.value) + 16 * out), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final screen = MediaQuery.sizeOf(context).height;
    // Taller phones get a taller header, so the form is not left high up.
    final headerHeight = top + (screen * 0.27).clamp(172.0, 230.0);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final growTo = introArtHeight(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            Column(
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_arrive, _leave]),
                  builder: (context, _) {
                    final drop = Curves.easeOutCubic.transform((_arrive.value / 0.45).clamp(0.0, 1.0));
                    final grow = Curves.easeInOutCubic.transform(_leave.value);
                    final height = headerHeight + (growTo - headerHeight) * grow;
                    return Transform.translate(
                      offset: Offset(0, -height * (1 - drop)),
                      child: SizedBox(
                        height: height,
                        child: _Header(fade: grow),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    bottom: keyboard,
                    // The form in the middle of the space below the header.
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 12), child: _form()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!keyboard)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FadeTransition(
                        opacity: ReverseAnimation(_leave),
                        child: Text(versionLabel, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ),
                    ),
                  ),
              ],
            ),
            // The PC210 drives into the header from the right and off again.
            AnimatedBuilder(
              animation: Listenable.merge([_arrive, _leave]),
              builder: (context, child) {
                final inT = Curves.easeOutCubic.transform(((_arrive.value - 0.25) / 0.6).clamp(0.0, 1.0));
                final outT = Curves.easeInCubic.transform(_leave.value);
                return Positioned(
                  top: headerHeight - 134,
                  right: -12 - 90 * (1 - inT) - 380 * outT,
                  child: Opacity(opacity: inT, child: child),
                );
              },
              child: IgnorePointer(child: Image.asset('assets/units/pc210.png', width: screen < 640 ? 170 : 200)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    var n = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _part(
          n++,
          Text(
            'Selamat datang',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.dark ? AppColors.ink : AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 2),
        _part(n++, Text('Masuk dengan NRP dan PIN Anda', style: TextStyle(fontSize: 13.5, color: AppColors.muted))),
        const SizedBox(height: 22),
        _part(n++, const _FieldLabel('NRP')),
        _part(
          n++,
          TextField(
            key: const Key('login-nrp'),
            controller: _nrp,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onChanged: (_) {
              if (_nrpError != null) setState(() => _nrpError = null);
            },
            onSubmitted: (_) => _pinFocus.requestFocus(),
            decoration: _inputDecoration(error: _nrpError != null).copyWith(
              hintText: 'Contoh 12345678',
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21),
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        _InlineError(_nrpError),
        const SizedBox(height: 10),
        _part(
          n++,
          Row(
            children: [
              const Expanded(child: _FieldLabel('PIN')),
              Tooltip(
                message: _showPin ? 'Sembunyikan PIN' : 'Lihat PIN',
                child: TextButton.icon(
                  key: const Key('login-show-pin'),
                  onPressed: () => setState(() => _showPin = !_showPin),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                  icon: Icon(_showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 17),
                  label: Text(_showPin ? 'Sembunyikan' : 'Lihat'),
                ),
              ),
            ],
          ),
        ),
        _part(
          n++,
          PinBoxes(
            key: const Key('login-pin'),
            controller: _pin,
            focusNode: _pinFocus,
            obscure: !_showPin,
            error: _error != null && _pin.text.isEmpty,
            shakes: _shakes,
            onCompleted: () {
              if (_error != null) setState(() => _error = null);
              if (_nrp.text.trim().isNotEmpty) _login();
            },
          ),
        ),
        _InlineError(_error),
        const SizedBox(height: 18),
        _part(
          n++,
          _MorphButton(key: const Key('login-submit'), label: 'Masuk', busy: _busy, done: _done, onPressed: _login),
        ),
        const SizedBox(height: 6),
        _part(
          n++,
          Center(
            child: TextButton(
              key: const Key('login-forgot'),
              onPressed: _busy || _done ? null : _forgot,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              child: const Text('Lupa PIN?'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Navy band with the logo, name and tagline; a faint torque arrow turns
/// slowly in the corner. [fade] hides the text while the band grows into
/// the introduction's.
class _Header extends StatefulWidget {
  const _Header({required this.fade});

  final double fade;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 26));

  @override
  void initState() {
    super.initState();
    // Loops forever, so not in widget tests (pumpAndSettle would wait).
    if (ExcavatorLoader.animate) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -90,
            bottom: -130,
            child: RotationTransition(
              turns: _spin,
              child: const Opacity(opacity: 0.07, child: _WhiteArc(size: 260)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, top + 28, 24, 0),
            child: Opacity(
              opacity: 1 - widget.fade.clamp(0.0, 1.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: const LogoMark(size: 30),
                      ),
                      const SizedBox(width: 9),
                      Text.rich(
                        TextSpan(
                          text: 'My',
                          children: [
                            TextSpan(
                              text: 'Manual',
                              style: TextStyle(color: AppColors.orange),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(
                    width: 150,
                    child: Text(
                      'Shop manual dalam genggaman',
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xB8FFFFFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo's arrow alone, in white, for backgrounds.
class _WhiteArc extends StatelessWidget {
  const _WhiteArc({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: LogoMark(size: size, nutScale: 0),
    );
  }
}

/// A red line under a field, sliding in when it appears.
class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -6 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 2),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The orange button that shrinks to a spinner while logging in and turns
/// into a green tick when it worked.
class _MorphButton extends StatelessWidget {
  const _MorphButton({super.key, required this.label, required this.busy, required this.done, required this.onPressed});

  final String label;
  final bool busy;
  final bool done;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final round = busy || done;
    // The form is at most 420 wide with 24 on each side.
    final wide = math.min(MediaQuery.sizeOf(context).width, 420.0) - 48;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: round ? 52 : wide,
        height: 52,
        decoration: BoxDecoration(
          color: done ? AppColors.green : AppColors.orange,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: round ? null : onPressed,
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 28)
                  : busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Lupa PIN": asks an admin for a temporary PIN for this NRP.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, this.nrp = ''});

  final String nrp;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  late final _nrp = TextEditingController(text: widget.nrp.trim());
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _nrp.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_nrp.text.trim().isEmpty) {
      setState(() => _error = 'Isi NRP.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await StoreScope.read(context).auth.forgotPin(_nrp.text);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, shape: const Border()),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(padding: const EdgeInsets.fromLTRB(24, 4, 24, 24), child: _sent ? _done() : _form()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lupa PIN',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text('Admin akan membuatkan PIN sementara.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
        const SizedBox(height: 28),
        const _FieldLabel('NRP'),
        TextField(
          key: const Key('forgot-nrp'),
          controller: _nrp,
          autofocus: _nrp.text.isEmpty,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onSubmitted: (_) => _send(),
          decoration: _inputDecoration(error: _error != null)
              .copyWith(prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21)),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        if (_error != null) ...[const SizedBox(height: 14), ErrorBox(_error!)],
        const Spacer(),
        const SizedBox(height: 24),
        _WideButton(key: const Key('forgot-send'), label: 'Kirim permintaan', busy: _busy, onPressed: _send),
      ],
    );
  }

  Widget _done() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 46, color: AppColors.green),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Permintaan terkirim',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'Minta PIN sementara ke admin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const Spacer(),
        _WideButton(
          label: 'Kembali ke Masuk',
          busy: false,
          color: AppColors.navy,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// After the first login with the starting PIN: the employee picks their own.
class ChoosePinScreen extends StatefulWidget {
  const ChoosePinScreen({super.key, required this.setupToken, required this.name});

  final String setupToken;
  final String name;

  @override
  State<ChoosePinScreen> createState() => _ChoosePinScreenState();
}

class _ChoosePinScreenState extends State<ChoosePinScreen> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  final _repeatFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    _repeatFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_pin.text.length != pinLength) {
      setState(() => _error = 'PIN harus $pinLength angka.');
      return;
    }
    if (_pin.text != _repeat.text) {
      setState(() => _error = 'Kedua PIN tidak sama.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = StoreScope.read(context);
    try {
      final session = await store.auth.choosePin(widget.setupToken, _pin.text, await store.deviceInfo());
      if (mounted) Navigator.of(context).pop(session);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, shape: const Border()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Halo, ${widget.name}',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              Text('Buat PIN baru Anda', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              const SizedBox(height: 28),
              const _FieldLabel('PIN baru'),
              PinBoxes(
                key: const Key('pin-new'),
                controller: _pin,
                autofocus: true,
                onCompleted: () => _repeatFocus.requestFocus(),
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Ulangi PIN baru'),
              PinBoxes(key: const Key('pin-repeat'), controller: _repeat, focusNode: _repeatFocus, onCompleted: _save),
              if (_error != null) ...[const SizedBox(height: 16), ErrorBox(_error!)],
              const SizedBox(height: 32),
              _WideButton(label: 'Simpan PIN', busy: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// One box per PIN digit, showing a dot (or the digit when [obscure] is
/// off); the typing goes to a hidden text field so the phone's number
/// keyboard and paste work as usual, and it takes no more than [pinLength].
class PinBoxes extends StatefulWidget {
  const PinBoxes({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.obscure = true,
    this.error = false,
    this.shakes = 0,
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscure;

  /// Red boxes, after a wrong PIN.
  final bool error;

  /// Counts wrong PINs: each new one shakes the row (swinging less each
  /// time, like a head shake) and pulses the boxes one after another.
  final int shakes;
  final VoidCallback? onCompleted;

  @override
  State<PinBoxes> createState() => _PinBoxesState();
}

class _PinBoxesState extends State<PinBoxes> with SingleTickerProviderStateMixin {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(PinBoxes old) {
    super.didUpdateWidget(old);
    if (widget.shakes != old.shakes) _shake.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Widget _box(int i, String text) {
    final filled = i < text.length;
    final current = _focus.hasFocus && i == text.length;
    final Color border;
    if (widget.error) {
      border = AppColors.danger;
    } else if (current) {
      border = AppColors.orange;
    } else if (filled) {
      border = AppColors.navy;
    } else {
      border = AppColors.border;
    }
    final box = Container(
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.error
            ? AppColors.danger.withValues(alpha: AppColors.dark ? 0.14 : 0.06)
            : filled || current
            ? AppColors.surface
            : AppColors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: current ? 2 : 1.5, color: border),
      ),
      child: !filled
          ? null
          : widget.obscure
          ? Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
            )
          : Text(
              text[i],
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
    );
    // Each box swells a little in turn while the row shakes.
    return AnimatedBuilder(
      animation: _shake,
      child: box,
      builder: (context, child) {
        final t = ((_shake.value - i * 0.08) / 0.6).clamp(0.0, 1.0);
        return Transform.scale(scale: 1 + 0.07 * math.sin(t * math.pi), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          // Swings of 11 px that die away.
          final dx = t == 0 || t == 1 ? 0.0 : 11 * (1 - t) * math.sin(t * math.pi * 6);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < pinLength; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _box(i, text)),
                ],
              ],
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(pinLength),
                  ],
                  onChanged: (v) {
                    if (v.length == pinLength) widget.onCompleted?.call();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.muted),
      ),
    );
  }
}

InputDecoration _inputDecoration({bool error = false}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: 1.5),
  );
  return InputDecoration(
    filled: true,
    fillColor: AppColors.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: border(error ? AppColors.danger : AppColors.border),
    focusedBorder: border(error ? AppColors.danger : AppColors.navy),
  );
}

/// A red note under the fields saying what went wrong.
class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: AppColors.dark ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 19, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({super.key, required this.label, required this.busy, required this.onPressed, this.color});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  /// Orange unless given.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
