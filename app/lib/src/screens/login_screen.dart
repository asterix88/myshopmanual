import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../diagnostics.dart';
import 'shell.dart';
import '../theme.dart';

/// Digits in a PIN (the server checks the same).
const pinLength = 4;

/// Behind the logo on the login screen.
Color get _headerColor => AppColors.dark ? AppColors.navyDark : const Color(0xFF1E3A64);

/// First screen until an employee logs in with NRP and PIN (needs internet).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nrp = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _showPin = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nrp.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_nrp.text.trim().isEmpty || _pin.text.length != pinLength) {
      setState(() => _error = 'Isi NRP dan PIN.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = StoreScope.read(context);
    try {
      final result = await store.auth.login(_nrp.text, _pin.text, await store.deviceInfo());
      if (!mounted) return;
      switch (result) {
        case LoggedIn(:final session):
          await store.signIn(session);
        case ChoosePin(:final setupToken, :final name):
          setState(() => _busy = false);
          final session = await Navigator.of(context).push<Session>(
            MaterialPageRoute(builder: (_) => ChoosePinScreen(setupToken: setupToken, name: name)),
          );
          if (session != null) await store.signIn(session);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.code == 'pin') _pin.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgot() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ForgotPinScreen(nrp: _nrp.text)));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: _headerColor),
      child: Scaffold(
        backgroundColor: _headerColor,
        body: Column(
          children: [
            const SafeArea(bottom: false, child: _Header()),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: SafeArea(
                  top: false,
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                              child: _form(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
        Text('Masuk', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 20),
        const _FieldLabel('NRP'),
        TextField(
          key: const Key('login-nrp'),
          controller: _nrp,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onSubmitted: (_) => _pinFocus.requestFocus(),
          decoration: _inputDecoration().copyWith(
            prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21),
          ),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 18),
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
        PinBoxes(
          key: const Key('login-pin'),
          controller: _pin,
          focusNode: _pinFocus,
          obscure: !_showPin,
          error: _error != null && _pin.text.isEmpty,
          onCompleted: () {
            if (_nrp.text.trim().isNotEmpty) _login();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          ErrorBox(_error!),
        ],
        const SizedBox(height: 24),
        _WideButton(key: const Key('login-submit'), label: 'Masuk', busy: _busy, onPressed: _login),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            key: const Key('login-forgot'),
            onPressed: _busy ? null : _forgot,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            child: const Text('Lupa PIN?'),
          ),
        ),
        const Spacer(),
        const SizedBox(height: 16),
        Text(versionLabel, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ],
    );
  }
}

/// Logo and name on the navy band above the form.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 34),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Image.asset('assets/images/logo.png', width: 60, height: 60),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'My', style: TextStyle(color: Colors.white)),
              TextSpan(text: 'Manual', style: TextStyle(color: AppColors.orange)),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ],
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: _sent ? _done() : _form(),
              ),
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
        Text('Lupa PIN', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
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
          decoration: _inputDecoration(error: _error != null).copyWith(
            prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21),
          ),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          ErrorBox(_error!),
        ],
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
              PinBoxes(
                key: const Key('pin-repeat'),
                controller: _repeat,
                focusNode: _repeatFocus,
                onCompleted: _save,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ErrorBox(_error!),
              ],
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
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscure;

  /// Red boxes, after a wrong PIN.
  final bool error;
  final VoidCallback? onCompleted;

  @override
  State<PinBoxes> createState() => _PinBoxesState();
}

class _PinBoxesState extends State<PinBoxes> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

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
    return Container(
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
              : Text(text[i], style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      onTap: _focus.requestFocus,
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(pinLength)],
                onChanged: (v) {
                  if (v.length == pinLength) widget.onCompleted?.call();
                },
              ),
            ),
          ),
        ],
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
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(label),
      ),
    );
  }
}
