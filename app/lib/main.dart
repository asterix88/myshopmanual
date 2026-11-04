import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide KeepAlive;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/diagnostics.dart';
import 'src/keep_alive.dart';
import 'src/screens/intro_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/unit_screen.dart';
import 'src/screens/shell.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/updates_screen.dart';
import 'src/store.dart';
import 'src/theme.dart';
import 'src/update_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await Diagnostics.start();
  await _clearOldPdfCache();
  final store = await AppStore.open()..autoFetchAiIndexes = true;
  // The opening animation only after a day or more away; a quick return
  // goes straight to Home behind the Android launch screen.
  final splash = store.wantsSplash(DateTime.now());
  store.markActive();
  // The opening animation waits until the notification permission question
  // (Android 13+, first start) is answered, so the dialog does not cover it.
  final permission = Completer<void>();
  runApp(MyManualApp(store: store, requireLogin: true, splash: splash, intro: true, splashReady: permission.future));
  // Tapping an update notification opens the update list.
  unawaited(startUpdateNotifications(
    onOpenUpdates: () => _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => UpdatesScreen()),
    ),
    onPermissionAnswered: permission.complete,
  ));
  // Tapping the download notification shows the manual being downloaded.
  unawaited(KeepAlive.listen(() {
    final key = store.downloads.keys.firstOrNull;
    final file = key == null ? null : store.fileByKey(key);
    if (file == null) return;
    _navigator.currentState?.push(MaterialPageRoute(
      builder: (_) => UnitScreen(unitId: file.unitId, folder: file.folder, focus: file.key),
    ));
  }));
  // Check the server in the background; the app works offline meanwhile.
  store.refresh();
}

/// Before this version the AI and the PDF viewer could write the same cache
/// file of a manual read online at once, which left broken pieces in it
/// (blank pages). The cache is only a copy of the server, so it is emptied
/// once.
Future<void> _clearOldPdfCache() async {
  try {
    final marker = File('${(await getApplicationSupportDirectory()).path}/pdf-cache-cleared-1');
    if (marker.existsSync()) return;
    final cache = Directory('${Pdfrx.cacheDirectoryPath}/pdfrx.cache');
    if (cache.existsSync()) await cache.delete(recursive: true);
    await marker.writeAsString('');
    Diagnostics.log('pdf cache cleared');
  } on Object catch (e) {
    Diagnostics.log('pdf cache not cleared: $e');
  }
}

/// Replaced when the app switches light/dark or someone logs in or out, so
/// the new app starts fresh.
var _navigator = GlobalKey<NavigatorState>();
String? _navigatorLook;

class MyManualApp extends StatefulWidget {
  const MyManualApp({
    super.key,
    required this.store,
    this.requireLogin = false,
    this.splash = false,
    this.intro = false,
    this.splashReady,
  });

  final AppStore store;

  /// Only employees who logged in with their NRP get past the login screen
  /// (always in the real app; tests start logged in).
  final bool requireLogin;

  /// Start with the opening animation.
  final bool splash;

  /// The opening animation holds its first frame until this completes.
  final Future<void>? splashReady;

  /// Show the introduction pages after the first login (the real app; tests
  /// go straight to Home).
  final bool intro;

  @override
  State<MyManualApp> createState() => _MyManualAppState();
}

class _MyManualAppState extends State<MyManualApp> with WidgetsBindingObserver {
  late bool _splashing = widget.splash;

  /// Home slides in once, after the opening animation or the introduction.
  bool _homeEntrance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone switched between light and dark.
  @override
  void didChangePlatformBrightness() => setState(() {});

  /// Back after a long time in the background: the login may have run out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.checkSessionExpiry();
    if (state == AppLifecycleState.paused) {
      widget.store.markActive();
      unawaited(widget.store.usage.send());
    }
  }

  bool _takeEntrance() {
    final entrance = _homeEntrance;
    _homeEntrance = false;
    return entrance;
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return StoreScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final dark = switch (store.themeMode) {
            'dark' => true,
            'light' => false,
            _ => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
          };
          final showLogin = widget.requireLogin && !store.loggedIn;
          final showIntro = widget.intro && store.loggedIn && !store.introSeen;
          if (showIntro) _homeEntrance = true;
          final phase = _splashing
              ? 'splash'
              : showLogin
                  ? 'login'
                  : showIntro
                      ? 'intro'
                      : 'home';
          // Screens read AppColors directly, so switching rebuilds the app;
          // so does each step from the opening animation to Home.
          final look = '$dark $phase';
          if (_navigatorLook != look) {
            if (_navigatorLook != null) _navigator = GlobalKey<NavigatorState>();
            _navigatorLook = look;
          }
          return MaterialApp(
            key: ValueKey(look),
            title: 'MyManual',
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(dark: dark),
            home: switch (phase) {
              'splash' => SplashScreen(
                  ready: widget.splashReady,
                  onDone: () => setState(() {
                    _splashing = false;
                    _homeEntrance = true;
                  }),
                ),
              'login' => const LoginScreen(),
              'intro' => const IntroScreen(),
              _ => HomeShell(entrance: _takeEntrance()),
            },
          );
        },
      ),
    );
  }
}
