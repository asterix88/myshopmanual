import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/update_notifications.dart';

import 'store_test.dart' show fixtureCatalog, fixtureServer;

void main() {
  test('a manual added on the server is announced once, in the background', () async {
    final root = Directory.systemTemp.createTempSync('notify');
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    store.dispose();

    // Nothing new yet.
    expect(await updatesToAnnounce(root: root, client: fixtureServer()), isEmpty);

    final catalog = fixtureCatalog();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    final file = (unit['files'] as List).single as Map<String, dynamic>;
    unit['files'] = [file, {...file, 'id': 'SM_Test_Unit', 'title': 'SM Test Unit'}];

    final news = await updatesToAnnounce(root: root, client: fixtureServer(catalog: catalog));
    expect(news.map((u) => u.file.title), ['SM Test Unit']);
    expect(updateMessage(news), ('Ada update manual', 'Baru: SM Test Unit (TEST1-1)'));
    // Already announced: no second notification for the same change.
    expect(await updatesToAnnounce(root: root, client: fixtureServer(catalog: catalog)), isEmpty);
  });
}
