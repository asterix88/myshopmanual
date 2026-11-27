/// Login with NRP and PIN. This file holds the login page itself; the
/// other login pages and pieces are part files under `login/` (they share
/// this file's private widgets):
///
/// - `header.dart`             navy header with the logo
/// - `forgot_pin_screen.dart`  Lupa PIN
/// - `choose_pin_screen.dart`  choosing a new PIN
/// - `pin_boxes.dart`          the PIN boxes and the wrong-PIN shake
/// - `widgets.dart`            labels, fields, error box, buttons
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../diagnostics.dart';
import '../haptics.dart';
import '../theme.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/logo_mark.dart';
import 'intro_screen.dart';
import 'shell.dart';

part 'login/choose_pin_screen.dart';
part 'login/forgot_pin_screen.dart';
part 'login/header.dart';
part 'login/pin_boxes.dart';
part 'login/widgets.dart';

/// Digits in a PIN (the server checks the same).
const pinLength = 4;

/// Example in the empty NRP field: small and faint, so it does not read
/// as an NRP already typed.
const nrpHint = 'Cth: 25002476';
TextStyle get nrpHintStyle => TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.faint);

/// Navy band behind the logo on the login screen and the introduction.
LinearGradient get headerGradient => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: AppColors.dark ? const [Color(0xFF0E1A2C), Color(0xFF1A2F4F)] : const [AppColors.header, Color(0xFF2C5791)],
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
        _nrpError = nrpMissing ? 'Isi NRP' : null;
        _error = pinShort ? 'PIN $pinLength angka' : null;
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
          // A refused PIN or NRP: the PIN is typed again.
          if (e.code == 'pin' || e.code == 'unknown') _pin.clear();
          if (e.code == 'pin') _shakes++;
        });
        if (e.code == 'pin') _pinFocus.requestFocus();
        if (e.code == 'pin' || e.code == 'unknown') unawaited(buzzError());
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
    unawaited(HapticFeedback.lightImpact());
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
    final machineWidth = screen < 640 ? 170.0 : 200.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // While the keyboard is open the header folds into a slim bar (k
        // goes to 1), so "Selamat datang", NRP and PIN stay in view.
        body: TweenAnimationBuilder<double>(
          tween: Tween(end: keyboard ? 1 : 0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, k, _) => _layout(
            k: k,
            keyboard: keyboard,
            headerHeight: headerHeight + (top + _barHeight - headerHeight) * k,
            growTo: growTo,
            machineWidth: machineWidth + (_barMachineWidth - machineWidth) * k,
          ),
        ),
      ),
    );
  }

  /// The slim header bar under the status bar, and the PC210 in it.
  static const _barHeight = 68.0;
  static const _barMachineWidth = 92.0;

  Widget _layout({
    required double k,
    required bool keyboard,
    required double headerHeight,
    required double growTo,
    required double machineWidth,
  }) {
    return Stack(
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
                    child: _Header(fade: grow, compact: k),
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
                      child: Align(
                        alignment: Alignment.lerp(Alignment.center, Alignment.topCenter, k)!,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                            child: _form(keyboard: keyboard),
                          ),
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
                    child: Text(versionLabel, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
              // Its tracks rest on the header's bottom edge.
              top: headerHeight - machineWidth * 0.67,
              right: -12 + 26 * k - 90 * (1 - inT) - 380 * outT,
              child: Opacity(opacity: inT, child: child),
            );
          },
          child: IgnorePointer(child: Image.asset('assets/units/pc210.png', width: machineWidth)),
        ),
      ],
    );
  }

  Widget _form({bool keyboard = false}) {
    var n = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _part(
          n++,
          Text(
            'Selamat datang',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.dark ? AppColors.ink : AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 2),
        _part(n++, Text('Masuk dengan NRP dan PIN kamu', style: TextStyle(fontSize: 13, color: AppColors.muted))),
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
            // PIN typed first: the keyboard's Next logs in, as the button is hidden.
            onSubmitted: (_) => _pin.text.length == pinLength ? _login() : _pinFocus.requestFocus(),
            decoration: _inputDecoration(error: _nrpError != null).copyWith(
              hintText: nrpHint,
              hintStyle: nrpHintStyle,
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21),
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
                    textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
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
        // The PIN logs in by itself on its last digit, so while the keyboard
        // is open the button and Lupa PIN make room for the fields.
        if (!keyboard) ...[
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
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: const Text('Lupa PIN?'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
