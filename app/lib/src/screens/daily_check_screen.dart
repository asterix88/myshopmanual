import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// The daily check website (not ours): opened inside MyManual so mechanics
/// with an account log in once. Android's WebView keeps its cookies and
/// local storage between app starts, so the login stays until the site
/// ends it.
const dailyCheckUrl = 'https://heavy-equipment-inspection.vercel.app/dashboard';

Future<void> openDailyCheck(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DailyCheckScreen()));

/// Whether [uri] stays inside the WebView: web pages do; phone, mail,
/// WhatsApp, maps and app links go to the phone's own apps.
bool staysInDailyCheck(Uri uri) {
  if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob' || uri.scheme == 'javascript') return true;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  const external = ['wa.me', 'api.whatsapp.com', 'play.google.com', 'maps.google.com'];
  return !external.any((h) => uri.host == h || uri.host.endsWith('.$h'));
}

/// The "Semua Good" button shows from this many dropdowns on the page.
const minDropdownsForGood = 3;

/// Tells the app how many dropdowns the page has, again whenever the page
/// changes (the site switches pages without reloading).
const watchDropdownsJs = '''
(function(){
  if (window.__mmWatch) { window.__mmWatch(); return; }
  var last = -1;
  window.__mmWatch = function(){
    var n = document.querySelectorAll('button[role="combobox"]').length;
    if (n !== last) { last = n; MyManual.postMessage('combo:' + n); }
  };
  var t;
  new MutationObserver(function(){ clearTimeout(t); t = setTimeout(window.__mmWatch, 300); })
    .observe(document.documentElement, {childList: true, subtree: true});
  window.__mmWatch();
})();
''';

/// Anas's setGood bookmarklet: opens each dropdown and picks "Good"; a
/// dropdown without "Good" is closed and skipped. Reports 'good:set:skipped'.
const setAllGoodJs = '''
(async function(){
  const delay = ms => new Promise(r => setTimeout(r, ms));
  let s = 0, d = 0;
  for (const t of document.querySelectorAll('button[role="combobox"]')) {
    t.click();
    await delay(40);
    const o = Array.from(document.querySelectorAll('[role="option"]')).find(x => x.textContent.includes('Good'));
    if (o) { o.click(); s++; } else { t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true})); d++; }
    await delay(40);
  }
  MyManual.postMessage('good:' + s + ':' + d);
})();
''';

class DailyCheckScreen extends StatefulWidget {
  const DailyCheckScreen({super.key});

  @override
  State<DailyCheckScreen> createState() => _DailyCheckScreenState();
}

class _DailyCheckScreenState extends State<DailyCheckScreen> {
  late final WebViewController _web;
  double _progress = 0;
  bool _failed = false;
  bool _canGoBack = false;

  /// Dropdowns on the page; the "Semua Good" button shows on the
  /// inspection form (many dropdowns), not on the dashboard.
  int _dropdowns = 0;
  bool _settingGood = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('MyManual', onMessageReceived: _onPageMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageFinished: (_) {
            unawaited(_updateBack());
            unawaited(_web.runJavaScript(watchDropdownsJs).catchError((_) {}));
          },
          onUrlChange: (_) => _updateBack(),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || staysInDailyCheck(uri)) return NavigationDecision.navigate;
            unawaited(_openOutside(uri));
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? true) && mounted) setState(() => _failed = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(dailyCheckUrl));
    final android = _web.platform;
    if (android is AndroidWebViewController) {
      unawaited(android.setOnShowFileSelector(_pickFiles));
      unawaited(android.setMediaPlaybackRequiresUserGesture(true));
    }
  }

  /// A photo field on the site: take one with the camera or pick from the
  /// gallery. Returns file URIs, or none when cancelled.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final picker = ImagePicker();
    final multiple = params.mode == FileSelectorMode.openMultiple;
    final source = params.isCaptureEnabled
        ? ImageSource.camera
        : await showModalBottomSheet<ImageSource>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Kamera'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Galeri'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
    if (source == null) return [];
    try {
      final List<XFile> files;
      if (source == ImageSource.camera) {
        final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
        files = f == null ? [] : [f];
      } else if (multiple) {
        files = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1920);
      } else {
        final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920);
        files = f == null ? [] : [f];
      }
      return [for (final f in files) Uri.file(f.path).toString()];
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto tidak dapat diambil')));
      }
      return [];
    }
  }

  void _onPageMessage(JavaScriptMessage message) {
    final parts = message.message.split(':');
    if (!mounted) return;
    if (parts.first == 'combo' && parts.length == 2) {
      setState(() => _dropdowns = int.tryParse(parts[1]) ?? 0);
    } else if (parts.first == 'good' && parts.length == 3) {
      setState(() => _settingGood = false);
      final skipped = int.tryParse(parts[2]) ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parts[1]} kolom diisi Good${skipped > 0 ? ', $skipped dilewati' : ''}')),
      );
    }
  }

  Future<void> _setAllGood() async {
    setState(() => _settingGood = true);
    try {
      await _web.runJavaScript(setAllGoodJs);
    } catch (_) {
      if (mounted) setState(() => _settingGood = false);
    }
  }

  Future<void> _openOutside(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan tidak dapat dibuka')));
    }
  }

  Future<void> _updateBack() async {
    final can = await _web.canGoBack();
    if (mounted && can != _canGoBack) setState(() => _canGoBack = can);
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    final last = await _web.currentUrl();
    await _web.loadRequest(Uri.parse(last == null || last.startsWith('about:') ? dailyCheckUrl : last));
  }

  @override
  Widget build(BuildContext context) {
    final loading = _progress < 1 && !_failed;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_web.goBack().then((_) => _updateBack()));
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.navyFill,
            foregroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            title: const Text(
              'Daily Check',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            actions: [
              IconButton(
                key: const Key('daily-check-reload'),
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh),
                onPressed: _failed ? _retry : _web.reload,
              ),
              PopupMenuButton<String>(
                tooltip: 'Menu',
                onSelected: (v) async {
                  if (v == 'browser') {
                    final url = await _web.currentUrl();
                    await _openOutside(Uri.parse(url ?? dailyCheckUrl));
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'browser', child: Text('Buka di browser'))],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: SizedBox(
                height: 2,
                child: loading
                    ? LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        backgroundColor: Colors.transparent,
                        color: AppColors.orange,
                        minHeight: 2,
                      )
                    : null,
              ),
            ),
          ),
          floatingActionButton:
              _failed || _dropdowns < minDropdownsForGood || MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : FloatingActionButton(
                  key: const Key('daily-check-good'),
                  tooltip: 'Isi semua Good',
                  shape: const CircleBorder(),
                  onPressed: _settingGood ? null : _setAllGood,
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  child: _settingGood
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.bolt, size: 30),
                ),
          body: _failed
              ? Center(
                  child: EmptyState(
                    key: const Key('daily-check-offline'),
                    icon: Icons.cloud_off,
                    title: 'Daily Check tidak dapat dibuka',
                    message: 'Periksa koneksi internet, lalu coba lagi',
                    action: TextButton(onPressed: _retry, child: const Text('Coba lagi')),
                  ),
                )
              : WebViewWidget.fromPlatformCreationParams(
                  // Hybrid composition: Android draws the page itself, so
                  // scrolling and typing are as smooth as in Chrome (the
                  // default texture mode lags on many phones).
                  params: _web.platform is AndroidWebViewController
                      ? AndroidWebViewWidgetCreationParams(
                          controller: _web.platform,
                          displayWithHybridComposition: true,
                        )
                      : PlatformWebViewWidgetCreationParams(controller: _web.platform),
                ),
        ),
      ),
    );
  }
}
