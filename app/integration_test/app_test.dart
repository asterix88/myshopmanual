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
import 'package:mymanual/src/screens/viewer_screen.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/widgets/excavator_loader.dart';
import 'package:path_provider/path_provider.dart';

import 'fixtures.g.dart';

/// The tiny test manual, served like the R2 bucket would.
MockClient fixtureServer() => MockClient((request) async {
      final data = fixtureFiles[request.url.path.replaceFirst(RegExp(r'^/'), '')];
      if (data == null) return http.Response('not found', 404);
      final bytes = base64Decode(data);
      // Reading a manual online asks for pieces of it.
      final range = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(request.headers['Range'] ?? '');
      if (range == null) return http.Response.bytes(bytes, 200);
      final start = int.parse(range[1]!);
      final end = (int.parse(range[2]!) + 1).clamp(start, bytes.length);
      return http.Response.bytes(bytes.sublist(start, end), 206);
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
    await pumpUntil(tester, find.byTooltip('Simpan file'));

    step('tap save icon');
    await tester.tap(find.byTooltip('Simpan file'));
    await pumpUntil(tester, find.text('Simpan file?'));
    expect(find.text('File disimpan di folder /Download/MyManual'), findsOneWidget);
    step('confirm');
    await tester.tap(find.text('Ya'));

    await pumpUntil(tester, find.textContaining('Tersimpan di Download/MyManual/'));
    step('saved');
    // The message closes by itself after 2 seconds.
    await wait(tester, const Duration(seconds: 4));
    expect(find.textContaining('Tersimpan di Download/MyManual/'), findsNothing);
    expect(find.byTooltip('Simpan file'), findsNothing);

    step('leave and come back');
    // Leaving the app and coming back checks the Download folder again:
    // the copy is there, so the button stays hidden (bug seen on 9 Oct).
    // No frames are drawn while paused, so wait without pumping there.
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await wait(tester, const Duration(seconds: 3));
    expect(find.byTooltip('Simpan file'), findsNothing);
    step('done');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('search in a manual starts on the search key and steps with the pill', (tester) async {
    final root = Directory('${(await getTemporaryDirectory()).path}/it-${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;
    await store.download(file, unitName: 'TEST1-1');

    step('open viewer');
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: ViewerScreen(fileKey: file.key))));
    await pumpUntil(tester, find.text(' / 4'));
    await tester.tap(find.byTooltip('Cari di file ini'));
    await tester.pump();

    step('type without searching');
    await tester.enterText(find.byKey(const Key('viewer-search')), 'hydraulic oil filter');
    await wait(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('match-pill')), findsNothing);

    step('press search');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(tester, find.byKey(const Key('match-pill')));
    // Page 2 has the words twice, page 3 once.
    await pumpUntil(tester, find.text('1/3'));

    step('next and previous');
    await tester.tap(find.byTooltip('Hasil berikutnya'));
    await pumpUntil(tester, find.text('2/3'));
    await tester.tap(find.byTooltip('Hasil sebelumnya'));
    await tester.tap(find.byTooltip('Hasil sebelumnya'));
    await pumpUntil(tester, find.text('3/3'));

    step('no match');
    // Tapping the pill closed the keyboard, and on a device the text input
    // does not reconnect reliably, so submit through the field itself.
    final field = find.byKey(const Key('viewer-search'));
    await tester.enterText(field, 'zzzz');
    await tester.pump();
    tester.widget<TextField>(field).onSubmitted!('zzzz');
    await pumpUntil(tester, find.text('tidak ada'));
    expect(find.byKey(const Key('match-pill')), findsNothing);
    step('done');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('a manual read online shows its pages, bookmarks and search', (tester) async {
    final root = Directory('${(await getTemporaryDirectory()).path}/it-${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;
    expect(store.isDownloaded(file.key), isFalse);

    step('open online');
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: ViewerScreen(fileKey: file.key))));
    await pumpUntil(tester, find.text(' / 4'));

    step('bookmarks from the index');
    await tester.tap(find.byTooltip('Penanda'));
    await pumpUntil(tester, find.text('Operation'));
    expect(find.text('Maintenance'), findsOneWidget);
    await tester.tap(find.text('Maintenance'));
    await wait(tester, const Duration(seconds: 1));

    step('search');
    await tester.tap(find.byTooltip('Cari di file ini'));
    await tester.pump();
    final field = find.byKey(const Key('viewer-search'));
    await tester.enterText(field, 'hydraulic oil filter');
    await tester.pump();
    tester.widget<TextField>(field).onSubmitted!('hydraulic oil filter');
    await pumpUntil(tester, find.text('1/3'));
    await tester.tap(find.byTooltip('Hasil berikutnya'));
    await pumpUntil(tester, find.text('2/3'));
    step('done');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
