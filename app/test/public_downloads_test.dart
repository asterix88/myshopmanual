import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/public_downloads.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/unit_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

void main() {
  test('a manual title becomes a safe file name', () {
    expect(PublicDownloads.fileName('SM PC2000-11R SN30019 UP'), 'SM PC2000-11R SN30019 UP.pdf');
    expect(PublicDownloads.fileName('OMM D85/ESS:2  "new"'), 'OMM D85 ESS 2 new.pdf');
  });

  testWidgets('a downloaded manual can be saved to Download once', (tester) async {
    const channel = MethodChannel('mymanual/downloads');
    final saved = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final name = (call.arguments as Map?)?['name'];
      switch (call.method) {
        case 'supported':
          return true;
        case 'exists':
          return saved.contains(name);
        case 'free':
          return 18 * 1024 * 1024 * 1024;
        case 'save':
          saved.add(name as String);
          return null;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    late AppStore store;
    final root = Directory.systemTemp.createTempSync('save');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    final file = store.catalog.files.single;
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: UnitScreen(unitId: file.unitId)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simpan ke Download'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan ke folder Download?'), findsOneWidget);
    expect(find.text('Download/MyManual/'), findsOneWidget);
    expect(find.textContaining('ruang kosong di HP'), findsOneWidget);

    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    final name = PublicDownloads.fileName(file.title);
    expect(saved, [name]);
    expect(find.text('Tersimpan di Download/MyManual/$name'), findsOneWidget);
    expect(find.text('BUKA'), findsOneWidget);
    // The copy is there now, so the card no longer offers it.
    expect(find.text('Simpan ke Download'), findsNothing);
  });
}
