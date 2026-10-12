import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/unit_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

void main() {
  testWidgets('Unduh semua downloads every manual of the unit after a confirm', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('all');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
    });
    final file = store.catalog.files.single;
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: UnitScreen(unitId: file.unitId)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unduh semua'));
    await tester.pumpAndSettle();
    expect(find.text('Unduh 1 file?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Unduh'));
    for (var i = 0; i < 100 && (store.downloadQueue.isNotEmpty || !store.isDownloaded(file.key)); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(store.isDownloaded(file.key), isTrue);
    await tester.pumpAndSettle();
    // Nothing left to download: the button goes away.
    expect(find.text('Unduh semua'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    root.deleteSync(recursive: true);
  });
}
