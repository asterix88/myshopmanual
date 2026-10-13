import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/theme.dart';

import '../test/store_test.dart' show fixtureServer;
import 'screenshot_test.dart' show loadFonts;

/// The note under answers that are partly general knowledge, and the
/// "Jawaban salah" report dialog.
void main() {
  testWidgets('answer footer and report shots', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    await tester.runAsync(() async {
      await loadFonts();
      store = await AppStore.open(root: Directory.systemTemp.createTempSync('shots'), client: fixtureServer());
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
                    'Secara umum, filter cepat tersumbat bila oli terkontaminasi, jadi cek juga kondisi oli.',
              },
            };
      return http.Response(jsonEncode(reply), 200);
    });
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(theme: buildTheme(dark: false), home: ChatScreen(client: worker)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lampu filter oli hidrolik menyala?');
    await tester.tap(find.byTooltip('Kirim'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/r1_answer.png'));
    await tester.tap(find.byTooltip('Jawaban salah'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Nilai standarnya ada di tabel E-3');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/r2_report.png'));
  });
}
