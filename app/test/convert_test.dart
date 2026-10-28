import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/convert_screen.dart';
import 'package:mymanual/src/screens/home_screen.dart';
import 'package:mymanual/src/screens/search_screen.dart';
import 'package:mymanual/src/screens/unit_tabs.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/units.dart';

import 'shell_test.dart' show shownOpacity;
import 'store_test.dart' show fixtureServer;

String convert(UnitKind kind, double value, String from, String to) =>
    formatValue(convertUnit(value, kind.unit(from), kind.unit(to)));

void main() {
  test('pressure and torque match the manuals', () {
    expect(convert(pressure, 4980, 'psi', 'kg/cm²'), '350.1');
    expect(convert(pressure, 4980, 'psi', 'MPa'), '34.34');
    expect(convert(pressure, 1, 'psi', 'kg/cm²'), '0.07031');
    expect(convert(pressure, 1, 'bar', 'kg/cm²'), '1.02');
    expect(convert(pressure, 34.3, 'MPa', 'kg/cm²'), '349.8');
    expect(convert(pressure, 1, 'kg/cm²', 'psi'), '14.22');
    expect(convert(pressure, 1, 'atm', 'kPa'), '101.3');
    expect(convert(torque, 98, 'N·m', 'kgf·m'), '9.993');
    expect(convert(torque, 98, 'N·m', 'lb·ft'), '72.28');
    expect(convert(torque, 10, 'N·m', 'lb·in'), '88.51');
    expect(convert(torque, 10, 'kgf·m', 'kgf·cm'), '1000');
  });

  test('numbers are read with a dot or a comma and shown like the manuals', () {
    expect(parseNumber('34,3'), 34.3);
    expect(parseNumber(' 4 980 '), 4980);
    expect(parseNumber(''), isNull);
    expect(parseNumber('abc'), isNull);
    expect(formatValue(null), '–');
    expect(formatValue(1), '1');
    expect(formatValue(34336), '34 336');
    expect(formatValue(257540.4), '257 540');
  });

  test('a row title loses the unit after its colon', () {
    expect(rowTitle('STANDARD VALUE TABLE FOR ENGINE: PC210-10M0'), 'STANDARD VALUE TABLE FOR ENGINE');
    expect(rowTitle('Standard value table: PC210-10M0, PC210LC-10M0'), 'Standard value table');
    expect(rowTitle('Table of fuel, coolant and lubricants'), 'Table of fuel, coolant and lubricants');
    expect(rowTitle('Engine: oil pressure'), 'Engine: oil pressure');
  });

  test('Home greets by the time of day and the first name', () {
    expect(greeting('AHMAD ANAS SUKUMA', DateTime(2026, 10, 27, 12)), 'Selamat siang, Ahmad');
    expect(greeting('budi', DateTime(2026, 10, 27, 7)), 'Selamat pagi, Budi');
    expect(greeting(null, DateTime(2026, 10, 27, 16)), 'Selamat sore');
    expect(greeting('Anas', DateTime(2026, 10, 27, 21)), 'Selamat malam, Anas');
  });

  testWidgets('Konversi opens from Home, converts as the number is typed and remembers the units', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('convert');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tool-convert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-convert')));
    await tester.pumpAndSettle();
    expect(find.byType(ConvertScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('convert-input')), '4980');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('convert-result'))).data, '350.1');
    expect(find.text('34.34'), findsOneWidget);

    // The unit on the right of the Ke card picks another unit.
    await tester.tap(find.byKey(const Key('convert-to')));
    await tester.pump();
    await tester.tap(find.text('bar').last);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('convert-result'))).data, '343.4');

    await tester.tap(find.text('Torsi'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('convert-input')), '98');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('convert-result'))).data, '9.993');
    expect(find.text('lb·ft'), findsOneWidget);
    expect(store.lastConvert, (kind: 'torsi', from: 'N·m', to: 'kgf·m'));

    await tester.pageBack();
    await tester.pumpAndSettle();
    root.deleteSync(recursive: true);
  });

  testWidgets('the search box on Home opens Cari', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('convert');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-search')));
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, SearchScreen), 1);
    expect(shownOpacity(tester, HomeScreen), 0);
    root.deleteSync(recursive: true);
  });
}
