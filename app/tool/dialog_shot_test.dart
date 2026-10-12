import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/store.dart';

import '../test/store_test.dart' show fixtureServer, testSession;
import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets('dialog shots', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      store = await AppStore.open(root: Directory.systemTemp.createTempSync('shots'), client: fixtureServer());
      await store.signIn(testSession(admin: true), refreshNow: false);
    });
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true));
    for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    for (final (item, name) in [('Tampilan (terang / gelap)', 'd1_theme'), ('Data Cetok Online', 'd2_cetok')]) {
      await tester.tap(find.byTooltip('Lainnya'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text(item));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
      await tester.tapAt(const Offset(5, 5));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  });
}
