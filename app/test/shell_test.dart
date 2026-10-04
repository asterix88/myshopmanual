import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/search_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

double shownOpacity(WidgetTester tester, Type screen) => tester
    .renderObject<RenderAnimatedOpacity>(
        find.ancestor(of: find.byType(screen), matching: find.byType(AnimatedOpacity)))
    .opacity
    .value;

void main() {
  testWidgets('leaving a tab fades it out, so the chosen tab shows', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('shell');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tanya AI').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, ChatScreen), 1);

    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, ChatScreen), 0);

    await tester.tap(find.text('Cari').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, SearchScreen), 0);
    root.deleteSync(recursive: true);
  });
}
