import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/unit_screen.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/theme.dart';

import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

void main() {
  for (final dark in [false, true]) {
    testWidgets('save icon shot dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mymanual/downloads'),
        (call) async => call.method == 'supported' ? true : (call.method == 'exists' ? false : null),
      );
      late AppStore store;
      await tester.runAsync(() async {
        await loadFonts();
        store = await AppStore.open(root: Directory.systemTemp.createTempSync('s'), client: fixtureServer());
        await store.setServerUrl('https://example.test');
        await store.download(store.catalog.files.single, unitName: 'TEST1-1');
      });
      AppColors.dark = dark;
      final file = store.catalog.files.single;
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            theme: buildTheme(dark: dark),
            home: UnitScreen(unitId: file.unitId),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tag = dark ? 'gelap' : 'terang';
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/save_card_$tag.png'));
      await tester.tap(find.byTooltip('Simpan file'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/save_dialog_$tag.png'));
      AppColors.dark = false;
    });
  }
}
