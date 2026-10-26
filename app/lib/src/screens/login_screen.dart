import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth.dart';
import '../diagnostics.dart';
import 'shell.dart';
import '../theme.dart';

/// First screen until an employee logs in with NRP and PIN (needs internet).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nrp = TextEditingController();
  final _pin = TextEditingController();
  bool _showPin = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nrp.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_nrp.text.trim().isEmpty || _pin.text.trim().isEmpty) {
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
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/images/logo.png', width: 96, height: 96)),
                  const SizedBox(height: 10),
                  const _Brand(),
                  const SizedBox(height: 28),
                  const _FieldLabel('NRP'),
                  TextField(
                    key: const Key('login-nrp'),
                    controller: _nrp,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: _inputDecoration(error: _error != null),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('PIN'),
                  TextField(
                    key: const Key('login-pin'),
                    controller: _pin,
                    obscureText: !_showPin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(pinLength)],
                    onSubmitted: (_) => _login(),
                    decoration: _inputDecoration(error: _error != null).copyWith(
                      suffixIcon: IconButton(
                        key: const Key('login-show-pin'),
                        tooltip: _showPin ? 'Sembunyikan PIN' : 'Lihat PIN',
                        onPressed: () => setState(() => _showPin = !_showPin),
                        icon: Icon(
                          _showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 16, letterSpacing: 4),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ErrorBox(_error!),
                  ],
                  const SizedBox(height: 22),
                  _OrangeButton(label: 'Masuk', busy: _busy, onPressed: _login),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            versionLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}

/// Digits in a PIN (the server checks the same).
const pinLength = 4;

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
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, shape: const Border()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Halo, ${widget.name}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                'Buat PIN baru Anda',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              const _FieldLabel('PIN BARU'),
              PinBoxes(
                key: const Key('pin-new'),
                controller: _pin,
                autofocus: true,
                onCompleted: () => _repeatFocus.requestFocus(),
              ),
              const SizedBox(height: 20),
              const _FieldLabel('ULANGI PIN BARU'),
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
              _OrangeButton(label: 'Simpan PIN', busy: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six boxes showing a dot per digit typed; the typing goes to a hidden
/// text field so the phone's number keyboard and paste work as usual.
class PinBoxes extends StatefulWidget {
  const PinBoxes({super.key, required this.controller, this.focusNode, this.autofocus = false, this.onCompleted});

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
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

  @override
  Widget build(BuildContext context) {
    final length = widget.controller.text.length;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pinLength; i++)
                Container(
                  width: 44,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      width: 1.5,
                      color: i < length || (_focus.hasFocus && i == length) ? AppColors.navy : AppColors.border,
                    ),
                  ),
                  child: i < length
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                        )
                      : null,
                ),
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'My', style: TextStyle(color: AppColors.navy)),
        TextSpan(text: 'Manual', style: TextStyle(color: AppColors.orange)),
      ]),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.muted),
      ),
    );
  }
}

InputDecoration _inputDecoration({required bool error}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1.5),
      );
  return InputDecoration(
    filled: true,
    fillColor: AppColors.surface,
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.danger)),
    );
  }
}

class _OrangeButton extends StatelessWidget {
  const _OrangeButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
