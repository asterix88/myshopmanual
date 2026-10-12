// Renders the viewer's nyel AI button and the chat it opens (not run in CI).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/viewer_screen.dart';
import 'package:mymanual/src/store.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets('viewer nyel AI button', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      store = await AppStore.open(root: Directory.systemTemp.createTempSync('shots'), client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pump();
    openViewer(tester.element(find.byType(Scaffold).first), store.catalog.files.single, page: 2);
    await settle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/a1_viewer_ai.png'));
    await tester.tap(find.byKey(const Key('viewer-ai')));
    await settle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/a2_chat_page.png'));
  });
}
