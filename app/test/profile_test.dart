import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/screens/home_screen.dart';
import 'package:mymanual/src/screens/profile_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

void main() {
  test('initials take the first letters of the first two words', () {
    expect(initials('anas aji sukuma'), 'AA');
    expect(initials('Budi'), 'B');
    expect(initials('  '), '?');
  });

  testWidgets('the person icon opens Profil with Saweria and Keluar', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('profile');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.signIn(testSession(), refreshNow: false);
    });
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: HomeScreen(onOpenSearch: () {}))));
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('21045678'), findsOneWidget);
    expect(find.text('Mekanik'), findsOneWidget);
    expect(find.byKey(const Key('saweria')), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari akun?'), findsOneWidget);
  });
}
