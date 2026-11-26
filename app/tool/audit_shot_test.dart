// Extra screens for the UI audit: flutter test tool/audit_shot_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/convert_screen.dart';
import 'package:mymanual/src/screens/login_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/updates_screen.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/theme.dart';

import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

void main() {
  final themeMode = Platform.environment['SHOTS_THEME'] ?? 'light';
  final prefix = themeMode == 'dark' ? 'd_' : '';
  final screens = <String, Widget Function()>{
    'a_convert': () => const ConvertScreen(),
    'a_updates': () => const UpdatesScreen(),
    'a_login': () => const LoginScreen(),
  };
  for (final e in screens.entries) {
    testWidgets(e.key, (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      late AppStore store;
      await tester.runAsync(() async {
        await loadFonts();
        final root = Directory.systemTemp.createTempSync('shots');
        store = await AppStore.open(root: root, client: fixtureServer());
        await store.setServerUrl('https://example.test');
        store.setThemeMode(themeMode);
      });
      await tester.pumpWidget(StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(dark: themeMode == 'dark'), home: e.value()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 500));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$prefix${e.key}.png'));
    });
  }
  testWidgets('a_menu', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      final root = Directory.systemTemp.createTempSync('shots');
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      store.setThemeMode(themeMode);
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}a_menu.png'));
  });
}
