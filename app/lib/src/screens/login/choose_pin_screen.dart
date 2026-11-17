part of '../login_screen.dart';

// Choosing a new PIN after the first login or a reset.

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
  void initState() {
    super.initState();
    _pin.addListener(_changed);
    _repeat.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final match = _pin.text.length == pinLength && _pin.text == _repeat.text;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(gradient: headerGradient),
              padding: EdgeInsets.fromLTRB(8, top + 4, 20, 52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BackButton(color: Colors.white),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: const LogoMark(size: 36),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Buat PIN',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              Text(
                                'Halo, ${widget.name}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFFC9D3E3)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // The white sheet overlaps the navy header's bottom edge.
            Transform.translate(
              offset: const Offset(0, -28),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('PIN baru'),
                    PinBoxes(
                      key: const Key('pin-new'),
                      controller: _pin,
                      autofocus: true,
                      onCompleted: _repeatFocus.requestFocus,
                    ),
                    const SizedBox(height: 20),
                    const _FieldLabel('Ulangi PIN'),
                    PinBoxes(key: const Key('pin-repeat'), controller: _repeat, focusNode: _repeatFocus, onCompleted: _save),
                    if (match) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: AppColors.green),
                          const SizedBox(width: 6),
                          Text(
                            'PIN cocok',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.green),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[const SizedBox(height: 16), ErrorBox(_error!)],
                    const SizedBox(height: 32),
                    _WideButton(label: 'Simpan PIN', busy: _busy, onPressed: _save),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
