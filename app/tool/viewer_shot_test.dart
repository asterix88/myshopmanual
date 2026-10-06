// Renders the spec page viewer for a visual check (not run in CI).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/unit_tabs.dart';
import 'package:mymanual/src/store.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/specs_test.dart' show catalogWithSpec;
import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets('spec viewer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      final root = Directory.systemTemp.createTempSync('shots');
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalogWithSpec()));
      await store.setServerUrl('https://example.test');
      await store.fetchSpecPacks();
      store.setThemeMode(Platform.environment['SHOTS_THEME'] ?? 'light');
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spek').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard tightening torque table'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SpecViewerScreen), findsOneWidget);
    final prefix = Platform.environment['SHOTS_THEME'] == 'dark' ? 'd_' : '';
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}8_spec_viewer.png'));
  });
}
