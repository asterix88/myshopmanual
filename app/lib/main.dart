import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/diagnostics.dart';
import 'src/screens/shell.dart';
import 'src/store.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await Diagnostics.start();
  await _clearOldPdfCache();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
  ));
  final store = await AppStore.open()..autoFetchAiIndexes = true;
  runApp(MyManualApp(store: store));
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

class MyManualApp extends StatelessWidget {
  const MyManualApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'MyManual',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
