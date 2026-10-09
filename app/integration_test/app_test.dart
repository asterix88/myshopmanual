// Runs on an Android emulator (GitHub workflow "Android emulator tests"),
// so the Android parts of the app (MediaStore copy, notifications, the
// download keep-alive service) run for real, which `flutter test` can't do.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/unit_screen.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/widgets/excavator_loader.dart';
import 'package:path_provider/path_provider.dart';

import 'fixtures.g.dart';

/// The tiny test manual, served like the R2 bucket would.
MockClient fixtureServer() => MockClient((request) async {
      final data = fixtureFiles[request.url.path.replaceFirst(RegExp(r'^/'), '')];
      return data == null ? http.Response('not found', 404) : http.Response.bytes(base64Decode(data), 200);
    });

/// Pumps until [finder] matches, or fails after [timeout].
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('Not shown in time: $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Lets real platform work (copying, MediaStore queries) finish.
Future<void> wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ExcavatorLoader.animate = false;

  testWidgets('a downloaded manual is saved to Download once and stays saved', (tester) async {
    final root = Directory('${(await getTemporaryDirectory()).path}/it-${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;
    // Also starts the keep-alive service with its notification.
    await store.download(file, unitName: 'TEST1-1');
    expect(store.isDownloaded(file.key), isTrue);

    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: UnitScreen(unitId: file.unitId))));
    await pumpUntil(tester, find.text('Simpan ke Download'));

    await tester.tap(find.text('Simpan ke Download'));
    await pumpUntil(tester, find.text('Simpan ke folder Download?'));
    expect(find.text('Download/MyManual/'), findsOneWidget);
    await tester.tap(find.text('Simpan'));

    await pumpUntil(tester, find.textContaining('Tersimpan di Download/MyManual/'));
    // The message closes by itself after 2 seconds.
    await wait(tester, const Duration(seconds: 4));
    expect(find.textContaining('Tersimpan di Download/MyManual/'), findsNothing);
    expect(find.text('Simpan ke Download'), findsNothing);

    // Leaving the app and coming back checks the Download folder again:
    // the copy is there, so the button stays hidden (bug seen on 9 Oct).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await wait(tester, const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(tester, const Duration(seconds: 3));
    expect(find.text('Simpan ke Download'), findsNothing);
  });
}
