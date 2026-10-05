import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/models.dart';
import 'package:mymanual/src/screens/machine_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureCatalog, fixtureServer;

void main() {
  test('a title starting with PB is a partsbook', () {
    expect(DocType.of('other', 'PB PC1250SP-11 SN J20001'), DocType.partsbook);
    expect(DocType.of('other', 'HYD SCHEMATIC PC1250-8'), DocType.other);
    expect(DocType.of('omm', 'PB something'), DocType.omm);
  });

  testWidgets('unit rows fill the page and skip the empty-phone note', (tester) async {
    final catalog = fixtureCatalog();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    catalog['units'] = [
      for (final id in ['PC1250-11', 'PC2000-11R', 'PC210', 'PC500']) {...unit, 'id': id, 'name': id},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('machine');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
    });
    await tester.pumpWidget(StoreScope(
      store: store,
      child: const MaterialApp(home: MachineScreen(machine: Machine.excavator)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(UnitRow), findsNWidgets(4));
    expect(find.textContaining('belum ada file'), findsNothing);
    expect(find.text('PC1250'), findsOneWidget);
    // The last row ends near the bottom of the page instead of leaving space.
    final body = tester.getRect(find.byType(ListView));
    final last = tester.getRect(find.byType(UnitRow).last);
    expect(body.bottom - last.bottom, lessThan(4));
  });
}
