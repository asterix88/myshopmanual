part of '../login_screen.dart';

// Lupa PIN: asking an admin for a new PIN.

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
  int _shakes = 0;

  @override
  void dispose() {
    _nrp.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_nrp.text.trim().isEmpty) {
      setState(() => _error = 'Isi NRP');
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
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.code == 'unknown') _shakes++;
        });
        if (e.code == 'unknown') unawaited(buzzError());
      }
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
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text('Admin akan membuatkan PIN sementara', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 28),
        const _FieldLabel('NRP'),
        Shake(
          shakes: _shakes,
          child: TextField(
            key: const Key('forgot-nrp'),
            controller: _nrp,
            autofocus: _nrp.text.isEmpty,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onSubmitted: (_) => _send(),
            decoration: _inputDecoration(error: _error != null).copyWith(
              hintText: nrpHint,
              hintStyle: nrpHintStyle,
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.muted, size: 21),
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
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
          'Minta PIN sementara ke admin',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
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
