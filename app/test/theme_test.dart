import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

void main() {
  test('the app starts light unless the user picked another look', () async {
    final fresh = await AppStore.open(root: Directory.systemTemp.createTempSync('theme'), client: fixtureServer());
    expect(fresh.themeMode, 'light');

    // Older versions saved 'system' without the user choosing it.
    final old = Directory.systemTemp.createTempSync('theme');
    File('${old.path}/state.json').writeAsStringSync(jsonEncode({'theme': 'system'}));
    expect((await AppStore.open(root: old, client: fixtureServer())).themeMode, 'light');

    final picked = Directory.systemTemp.createTempSync('theme');
    File('${picked.path}/state.json').writeAsStringSync(jsonEncode({'theme': 'dark', 'theme_chosen': true}));
    expect((await AppStore.open(root: picked, client: fixtureServer())).themeMode, 'dark');
  });
}
