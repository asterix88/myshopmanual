// Renders the main screens to PNG files for a visual check:
//   flutter test tool/screenshot_test.dart --update-goldens
// Output goes to tool/screenshots/ (not committed, not run in CI).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/theme.dart';
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
  // SHOTS_THEME=dark renders the dark versions (file names start with d_).
  final themeMode = Platform.environment['SHOTS_THEME'] ?? 'light';
  final prefix = themeMode == 'dark' ? 'd_' : '';
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
      store.setThemeMode(themeMode);
    });

    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}1_home.png'));

    await tester.tap(find.text('EXCAVATOR'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}1b_excavator.png'));
    await tester.tap(find.text('TEST1-1'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}2_unit.png'));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}3_edit.png'));
    await tester.tap(find.byTooltip('Selesai edit'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'hydraulic oil filter');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}4_search.png'));

    await tester.tap(find.text('Tanya AI').last);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}5_chat.png'));

    // A manual not on the phone: read online or download.
    await tester.runAsync(() => store.deleteManuals([store.catalog.files.single.key]));
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXCAVATOR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST1-1'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}6_unit_online.png'));
  });

  testWidgets('chat answer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      final root = Directory.systemTemp.createTempSync('shots');
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    var round = 0;
    final worker = MockClient((_) async {
      round++;
      final reply = round == 1
          ? {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'c1',
                    'type': 'function',
                    'function': {
                      'name': 'search_manuals',
                      'arguments': jsonEncode({'query': 'hydraulic oil filter clogging', 'unit': ''}),
                    },
                  },
                ],
              },
            }
          : {
              'message': {
                'role': 'assistant',
                'content': 'Lampu hydraulic oil filter clogging menandakan filter oli hidrolik tersumbat [S1].\n\n'
                    'Langkah:\n1. Matikan engine.\n2. Ganti element hydraulic oil filter [S2].',
              },
            };
      return http.Response(jsonEncode(reply), 200);
    });
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(theme: buildTheme(dark: themeMode == 'dark'), home: ChatScreen(client: worker)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lampu filter oli hidrolik menyala, apa yang harus dilakukan?');
    await tester.tap(find.byTooltip('Kirim'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/${prefix}7_chat_answer.png'));
  });
}
