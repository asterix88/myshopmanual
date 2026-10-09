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

/// Shows in the workflow log how far the test got, so a hang can be placed.
final _start = DateTime.now();
// ignore: avoid_print
void step(String text) => print('[step ${DateTime.now().difference(_start).inSeconds}s] $text');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ExcavatorLoader.animate = false;

  testWidgets('a downloaded manual is saved to Download once and stays saved', (tester) async {
    final root = Directory('${(await getTemporaryDirectory()).path}/it-${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    step('open store');
    final store = await AppStore.open(root: root, client: fixtureServer());
    step('load catalog');
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;
    step('download manual');
    // Also starts the keep-alive service with its notification.
    await store.download(file, unitName: 'TEST1-1');
    expect(store.isDownloaded(file.key), isTrue);

    step('show unit page');
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: UnitScreen(unitId: file.unitId))));
    await pumpUntil(tester, find.text('Simpan ke Download'));

    step('tap Simpan ke Download');
    await tester.tap(find.text('Simpan ke Download'));
    await pumpUntil(tester, find.text('Simpan ke folder Download?'));
    expect(find.text('Download/MyManual/'), findsOneWidget);
    step('confirm');
    await tester.tap(find.text('Simpan'));

    await pumpUntil(tester, find.textContaining('Tersimpan di Download/MyManual/'));
    step('saved');
    // The message closes by itself after 2 seconds.
    await wait(tester, const Duration(seconds: 4));
    expect(find.textContaining('Tersimpan di Download/MyManual/'), findsNothing);
    expect(find.text('Simpan ke Download'), findsNothing);

    step('leave and come back');
    // Leaving the app and coming back checks the Download folder again:
    // the copy is there, so the button stays hidden (bug seen on 9 Oct).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await wait(tester, const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(tester, const Duration(seconds: 3));
    expect(find.text('Simpan ke Download'), findsNothing);
    step('done');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
