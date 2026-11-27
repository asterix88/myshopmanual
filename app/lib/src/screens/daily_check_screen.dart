import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// The daily check website (not ours): opened inside MyManual so mechanics
/// with an account log in once. The WebView keeps its cookies and local
/// storage between app starts, so the login stays until the site ends it.
const dailyCheckUrl = 'https://heavy-equipment-inspection.vercel.app/dashboard';

Future<void> openDailyCheck(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DailyCheckScreen()));

/// Whether [uri] stays inside the WebView: pages of the daily check site
/// (and its sign-in pages on other https hosts). Phone, mail, WhatsApp and
/// app links go to the phone's own apps.
bool staysInDailyCheck(Uri uri) {
  if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob' || uri.scheme == 'javascript') return true;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  const external = ['wa.me', 'api.whatsapp.com', 'play.google.com', 'maps.google.com'];
  return !external.any((h) => uri.host == h || uri.host.endsWith('.$h'));
}

class DailyCheckScreen extends StatefulWidget {
  const DailyCheckScreen({super.key});

  @override
  State<DailyCheckScreen> createState() => _DailyCheckScreenState();
}

class _DailyCheckScreenState extends State<DailyCheckScreen> {
  InAppWebViewController? _web;
  double _progress = 0;
  bool _failed = false;
  bool _canGoBack = false;

  static final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    cacheEnabled: true,
    thirdPartyCookiesEnabled: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    allowFileAccess: false,
    mediaPlaybackRequiresUserGesture: true,
    supportZoom: false,
    builtInZoomControls: false,
    // The site's own pinch zoom stays off: it is made for phones.
    useWideViewPort: true,
    loadWithOverviewMode: true,
  );

  Future<void> _openOutside(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan tidak dapat dibuka')));
    }
  }

  Future<void> _updateBack() async {
    final can = await _web?.canGoBack() ?? false;
    if (mounted && can != _canGoBack) setState(() => _canGoBack = can);
  }

  void _retry() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    final web = _web;
    if (web == null) return;
    unawaited(web.getUrl().then((url) {
      final last = url?.toString();
      return web.loadUrl(
        urlRequest: URLRequest(url: WebUri(last == null || last.startsWith('about:') ? dailyCheckUrl : last)),
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final loading = _progress < 1 && !_failed;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_web?.goBack().then((_) => _updateBack()));
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.navyFill,
            foregroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            title: const Text('Daily Check', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            actions: [
              IconButton(
                key: const Key('daily-check-reload'),
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh),
                onPressed: _failed ? _retry : () => _web?.reload(),
              ),
              PopupMenuButton<String>(
                tooltip: 'Menu',
                onSelected: (v) async {
                  if (v == 'browser') {
                    final url = await _web?.getUrl();
                    await _openOutside(Uri.parse(url?.toString() ?? dailyCheckUrl));
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
          body: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(dailyCheckUrl)),
                initialSettings: _settings,
                onWebViewCreated: (c) => _web = c,
                onProgressChanged: (_, p) {
                  if (mounted) setState(() => _progress = p / 100);
                },
                onLoadStop: (_, _) => _updateBack(),
                onUpdateVisitedHistory: (_, _, _) => _updateBack(),
                shouldOverrideUrlLoading: (_, action) async {
                  final uri = action.request.url;
                  if (uri == null || staysInDailyCheck(uri)) return NavigationActionPolicy.ALLOW;
                  unawaited(_openOutside(uri));
                  return NavigationActionPolicy.CANCEL;
                },
                // Links that open a new window (target="_blank").
                onCreateWindow: (_, action) async {
                  final uri = action.request.url;
                  if (uri == null) return false;
                  if (staysInDailyCheck(uri)) {
                    await _web?.loadUrl(urlRequest: URLRequest(url: uri));
                  } else {
                    unawaited(_openOutside(uri));
                  }
                  return false;
                },
                // Reports and exports: the phone's browser saves them.
                onDownloadStartRequest: (_, request) => _openOutside(request.url),
                onReceivedError: (_, request, error) {
                  if ((request.isForMainFrame ?? true) && error.type != WebResourceErrorType.CANCELLED) {
                    setState(() => _failed = true);
                  }
                },
              ),
              if (_failed)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.background,
                    child: Center(
                      child: EmptyState(
                        key: const Key('daily-check-offline'),
                        icon: Icons.cloud_off,
                        title: 'Daily Check tidak dapat dibuka',
                        message: 'Periksa koneksi internet, lalu coba lagi.',
                        action: TextButton(onPressed: _retry, child: const Text('Coba lagi')),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
