// Bottom bar hiding on scroll, as PNG frames:
//   flutter test tool/navbar_shot_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/store.dart';

import '../test/specs_test.dart' show catalogWithSpec;
import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets('bar hides on scroll', (tester) async {
    tester.view.physicalSize = const Size(1080, 1700);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      final root = Directory.systemTemp.createTempSync('shots');
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalogWithSpec()));
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
      store.setLastRead(store.catalog.files.single.key, 2, section: 'x');
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    var n = 0;
    Future<void> shot() =>
        expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/nav_${(n++).toString().padLeft(2, '0')}.png'));
    final list = find.byType(Scrollable).first;
    await shot();
    // Scroll down slowly: the bar slides away.
    final g = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 40));
      await shot();
    }
    await g.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await shot();
    }
    await tester.pumpAndSettle();
    await shot();
    // Scroll up a little: it comes back.
    final g2 = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 3; i++) {
      await g2.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 40));
      await shot();
    }
    await g2.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await shot();
    }
    await tester.pumpAndSettle();
    await shot();
  });
}
