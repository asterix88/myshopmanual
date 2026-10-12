import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/login_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/store.dart';

import '../test/store_test.dart' show fixtureServer, testSession;
import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets('login shots', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    late AppStore store;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/login') {
        return http.Response(jsonEncode({'error': 'pin', 'message': 'PIN salah, sisa 3 kali coba.'}), 403);
      }
      if (request.url.path == '/admin/employees') {
        return http.Response(jsonEncode({'employees': [
          {'nrp': '21045678', 'name': 'Budi Santoso', 'admin': false, 'active': true, 'status': 'active', 'seen': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'devices': ['Samsung SM-A546E', 'Xiaomi Redmi Note 12'], 'ai_today': 4},
          {'nrp': '21039012', 'name': 'Andi Pratama', 'admin': false, 'active': true, 'status': 'active', 'seen': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3 * 86400, 'devices': ['Xiaomi Redmi Note 12'], 'ai_today': 0},
          {'nrp': '21051133', 'name': 'Rudi Hartono', 'admin': false, 'active': true, 'status': 'new', 'seen': 0, 'devices': [], 'ai_today': 0},
          {'nrp': '21000001', 'name': 'Anas', 'admin': true, 'active': true, 'status': 'active', 'seen': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'devices': ['Samsung SM-S918B'], 'ai_today': 12},
          {'nrp': '21018820', 'name': 'Joko Susilo', 'admin': false, 'active': false, 'status': 'active', 'seen': 0, 'devices': [], 'ai_today': 0},
        ]}), 200);
      }
      return fixtureServer().send(http.Request(request.method, request.url)).then(http.Response.fromStream);
    });
    await tester.runAsync(() async {
      await loadFonts();
      store = await AppStore.open(root: Directory.systemTemp.createTempSync('shots'), client: client);
    });
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-nrp')), '21045678');
    await tester.enterText(find.byKey(const Key('login-pin')), '123456');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/l1_login.png'));

    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(
      theme: ThemeData(fontFamily: 'Poppins', useMaterial3: true),
      home: const ChoosePinScreen(setupToken: 's', name: 'Budi Santoso'),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('pin-new')), matching: find.byType(TextField)), '123456');
    await tester.enterText(find.descendant(of: find.byKey(const Key('pin-repeat')), matching: find.byType(TextField)), '123');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/l2_pin.png'));

    await tester.runAsync(() => store.signIn(testSession(admin: true), refreshNow: true));
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/l3_menu.png'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Kelola karyawan'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/l4_admin.png'));
    await tester.tap(find.text('Budi Santoso'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/l5_sheet.png'));
  });
}
