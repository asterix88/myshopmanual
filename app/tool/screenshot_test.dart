// Renders the main screens to PNG files for a visual check:
//   flutter test tool/screenshot_test.dart --update-goldens
// Output goes to tool/screenshots/ (not committed, not run in CI).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/store.dart';

import '../test/store_test.dart' show fixtureServer;

Future<void> loadFonts() async {
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
  }
  await poppins.load();
  final icons = FontLoader('MaterialIcons');
  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/sdk/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  icons.addFont(Future.value(ByteData.sublistView(iconFont.readAsBytesSync())));
  await icons.load();
}

void main() {
  testWidgets('screens', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      final root = Directory.systemTemp.createTempSync('shots');
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
      store.setLastRead(store.catalog.files.single.key, 2, section: 'Hydraulic oil filter clogging caution lamp');
    });

    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/1_home.png'));

    await tester.tap(find.text('EXCAVATOR'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/1b_excavator.png'));
    await tester.tap(find.text('TEST1-1'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/2_unit.png'));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/3_edit.png'));
    await tester.tap(find.byTooltip('Selesai edit'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hydraulic oil filter');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/4_search.png'));

    await tester.tap(find.text('Tanya AI').last);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/5_chat.png'));

    // A manual not on the phone: read online or download.
    await tester.runAsync(() => store.deleteManuals([store.catalog.files.single.key]));
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXCAVATOR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST1-1'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/6_unit_online.png'));
  });
}
