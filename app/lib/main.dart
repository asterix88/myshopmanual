import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/diagnostics.dart';
import 'src/screens/shell.dart';
import 'src/store.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await Diagnostics.start();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
  ));
  final store = await AppStore.open()..autoFetchAiIndexes = true;
  runApp(MyManualApp(store: store));
  // Check the server in the background; the app works offline meanwhile.
  store.refresh();
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
