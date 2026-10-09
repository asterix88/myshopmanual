import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide KeepAlive;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/diagnostics.dart';
import 'src/keep_alive.dart';
import 'src/screens/unit_screen.dart';
import 'src/screens/shell.dart';
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
  runApp(MyManualApp(store: store));
  // Tapping an update notification opens the update list.
  unawaited(startUpdateNotifications(
    onOpenUpdates: () => _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => UpdatesScreen()),
    ),
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

/// Replaced when the app switches light/dark, so the new app starts fresh.
var _navigator = GlobalKey<NavigatorState>();
bool? _navigatorDark;

class MyManualApp extends StatefulWidget {
  const MyManualApp({super.key, required this.store});

  final AppStore store;

  @override
  State<MyManualApp> createState() => _MyManualAppState();
}

class _MyManualAppState extends State<MyManualApp> with WidgetsBindingObserver {
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
          // Screens read AppColors directly, so switching rebuilds the app.
          if (_navigatorDark != dark) {
            if (_navigatorDark != null) _navigator = GlobalKey<NavigatorState>();
            _navigatorDark = dark;
          }
          return MaterialApp(
            key: ValueKey(dark),
            title: 'MyManual',
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(dark: dark),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
