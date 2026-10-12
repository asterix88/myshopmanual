import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/viewer_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

/// The viewer screen must build before the PDF has loaded: pdfrx throws if
/// a text searcher is created while the document is not ready yet, which
/// showed as a blank grey screen on the phone.
void main() {
  for (final downloaded in [true, false]) {
    testWidgets('viewer opens a ${downloaded ? 'downloaded' : 'online'} manual', (tester) async {
      late AppStore store;
      await tester.runAsync(() async {
        store = await AppStore.open(root: Directory.systemTemp.createTempSync('viewer'), client: fixtureServer());
        await store.setServerUrl('https://example.test');
        if (downloaded) await store.download(store.catalog.files.single, unitName: 'TEST1-1');
      });
      await tester.pumpWidget(MyManualApp(store: store));
      await tester.pump();
      openViewer(tester.element(find.byType(Scaffold).first), store.catalog.files.single);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(ViewerScreen), findsOneWidget);
      expect(find.text('OMM Test Unit'), findsOneWidget);
    });
  }

  testWidgets('the round nyel AI button opens the chat about the page, back returns to it', (tester) async {
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: Directory.systemTemp.createTempSync('viewer'), client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pump();
    openViewer(tester.element(find.byType(Scaffold).first), store.catalog.files.single, page: 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('viewer-ai')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Halaman 1'), findsOneWidget);
    expect(find.text('Terjemahkan halaman ini'), findsOneWidget);

    // Taking the page off leaves a plain chat.
    await tester.tap(find.byTooltip('Lepas halaman'));
    await tester.pump();
    expect(find.text('Halaman 1'), findsNothing);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(ViewerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
