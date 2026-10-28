import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'login_screen.dart';
import 'shell.dart';

/// Height of the navy picture band on the introduction pages; the login
/// header grows to it so the two screens join up.
double introArtHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return MediaQuery.paddingOf(context).top + (size.height * 0.47).clamp(300.0, 420.0);
}

/// Four pages shown once, after the first login: manuals, search, nyel AI,
/// and the Standar and Servis tabs. "Lewati" or "Mulai" goes to Home.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _count = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _count - 1) {
      StoreScope.read(context).finishIntro();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = StoreScope.of(context).session?.name.trim().split(RegExp(r'\s+')).first ?? '';
    final last = _page == _count - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _Slide(
                  current: _page == 0,
                  greeting: name.isEmpty ? null : 'Halo, $name',
                  title: 'Semua manual, satu genggaman',
                  body:
                      'Shop Manual, OMM, dan Partsbook tersusun per unit. '
                      'Baca online atau unduh, akses kapan pun tanpa sinyal.',
                  picture: 'assets/units/pc2000.png',
                  art: const _ManualsCard(),
                ),
                _Slide(
                  current: _page == 1,
                  title: 'Temukan dalam hitungan detik',
                  body: 'Cari part number, kode error, atau istilah teknis di seluruh manual sekaligus.',
                  art: _SearchCard(play: _page == 1),
                ),
                _Slide(
                  current: _page == 2,
                  title: 'nyel AI, rekan diskusi teknis',
                  body: 'Uraikan gejala kerusakan, dapatkan arah pemeriksaan beserta halaman rujukannya.',
                  art: const _ChatArt(),
                ),
                _Slide(
                  current: _page == 3,
                  title: 'Nilai standar tanpa membuka ribuan halaman',
                  body:
                      'Torsi baut, kapasitas oli, nilai standar, dan servis per HM, '
                      'tersusun per unit dan siap dibuka offline.',
                  picture: 'assets/units/d375.png',
                  art: const _TorqueCard(),
                ),
              ],
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              right: 16,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  key: const Key('intro-skip'),
                  onPressed: last ? null : () => StoreScope.read(context).finishIntro(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Lewati', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.paddingOf(context).bottom + 28,
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.orange : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    width: last ? 150 : 52,
                    height: 52,
                    decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(26)),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: const Key('intro-next'),
                        borderRadius: BorderRadius.circular(26),
                        onTap: _next,
                        child: Center(
                          child: last
                              ? const Text(
                                  'Mulai',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_forward_rounded, color: Colors.white, semanticLabel: 'Lanjut'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page: the navy band with a picture and a sample of the app, then the
/// title and a line of text. The parts arrive in turn when the page shows.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.current,
    required this.title,
    required this.body,
    required this.art,
    this.greeting,
    this.picture,
  });

  final bool current;
  final String title;
  final String body;
  final Widget art;
  final String? greeting;
  final String? picture;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: introArtHeight(context),
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.only(top: top + 30, bottom: 18),
          decoration: BoxDecoration(
            gradient: headerGradient,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (picture case final picture?)
                Flexible(
                  child: _Arrive(
                    play: current,
                    dx: 40,
                    child: Image.asset(picture, height: 150, fit: BoxFit.contain),
                  ),
                ),
              // Short phones shrink the card instead of cutting it off.
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Transform.translate(
                    offset: Offset(0, picture == null ? 0 : -20),
                    child: _Arrive(play: current, dy: 16, delay: 0.1, child: art),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (greeting case final greeting?)
                  _Arrive(
                    play: current,
                    dy: 10,
                    delay: 0.25,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        greeting.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  ),
                _Arrive(
                  play: current,
                  dy: 10,
                  delay: 0.3,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 23,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark ? AppColors.ink : AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Arrive(
                  play: current,
                  dy: 10,
                  delay: 0.38,
                  child: Text(body, style: TextStyle(fontSize: 14, height: 1.55, color: AppColors.muted)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades [child] in from a small offset whenever [play] turns on.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.play, required this.child, this.dx = 0, this.dy = 0, this.delay = 0});

  final bool play;
  final Widget child;
  final double dx;
  final double dy;

  /// Fraction of the 0.7 s before this part starts.
  final double delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: play ? 1 : 0),
      duration: Duration(milliseconds: play ? 700 : 0),
      curve: Interval(delay, (delay + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(dx * (1 - t), dy * (1 - t)), child: child),
      ),
    );
  }
}

/// White card on the navy band.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x47050F23), blurRadius: 26, offset: Offset(0, 10))],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12.5, color: AppColors.ink),
        child: child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.orange = false});

  final String text;
  final bool orange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: orange ? AppColors.orangeSoft : AppColors.greySoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: orange ? AppColors.orangeText : AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A unit with its manuals, one downloaded and one to download.
class _ManualsCard extends StatelessWidget {
  const _ManualsCard();

  Widget _row(String name, Widget pill, {bool orange = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: orange ? AppColors.orange : AppColors.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          pill,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PC2000',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
          Text('Excavator · 3 dokumen', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          _row('Shop Manual', const _Pill('Diunduh')),
          _row('Partsbook', const _Pill('Unduh', orange: true), orange: true),
        ],
      ),
    );
  }
}

/// The search box typing "fuel injector", with hits on several pages.
class _SearchCard extends StatefulWidget {
  const _SearchCard({required this.play});

  final bool play;

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
  static const _word = 'fuel injector';
  int _typed = 0;
  Timer? _timer;

  @override
  void didUpdateWidget(_SearchCard old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) {
      _typed = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 70), (t) {
        if (!mounted || _typed >= _word.length) return t.cancel();
        setState(() => _typed++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _hit(String before, String after, String page) {
    final mark = TextStyle(backgroundColor: AppColors.highlight, color: AppColors.ink);
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: before),
                  TextSpan(text: 'fuel injector', style: mark),
                  TextSpan(text: after),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _Pill(page),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Text(_word.substring(0, _typed), style: const TextStyle(fontSize: 13)),
                Container(width: 1.5, height: 15, color: AppColors.orange),
              ],
            ),
          ),
          _hit('Removal of ', '', 'hal. 412'),
          _hit('Testing ', '', 'hal. 1203'),
          _hit('', ' assembly', 'hal. 87'),
        ],
      ),
    );
  }
}

/// A question and nyel AI's answer pointing at a manual page.
class _ChatArt extends StatelessWidget {
  const _ChatArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: const Text(
              'Travel kiri lambat, kanan normal. Cek apa dulu?',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(5),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: const [BoxShadow(color: Color(0x47050F23), blurRadius: 26, offset: Offset(0, 10))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mulai dari tekanan travel motor kiri, lalu bandingkan dengan nilai standar di manual.',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Shop Manual PC210 · hal. 30-112',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.navy),
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

/// A piece of a Shop Manual page with its torque values marked, as the
/// viewer does. The numbers are examples and say so.
class _TorqueCard extends StatelessWidget {
  const _TorqueCard();

  Widget _line(String part, String value) {
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.6, color: AppColors.inkSoft);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$part\nTightening torque: '),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.w700, backgroundColor: AppColors.highlight, color: AppColors.ink),
            ),
          ],
        ),
        style: mono,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, {bool orange = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: orange ? AppColors.orangeSoft : AppColors.navySoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: orange ? AppColors.orangeText : AppColors.navy,
        ),
      ),
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Track roller',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
              Text('Installation · contoh', style: TextStyle(fontSize: 10.5, color: AppColors.faint)),
            ],
          ),
          const SizedBox(height: 2),
          _line('Roller mounting bolt', '824 ± 39 N·m'),
          _line('Plug (oil filler)', '59 ± 5 N·m'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [chip('Servis HM 500', orange: true), chip('psi → kg/cm²')]),
        ],
      ),
    );
  }
}
