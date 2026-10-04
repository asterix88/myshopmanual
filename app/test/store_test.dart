import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/models.dart';
import 'package:mymanual/src/search.dart';
import 'package:mymanual/src/store.dart';

/// test/fixtures holds a tiny manual built by tools/build_packages.py.
final fixtures = Directory('test/fixtures');

Map<String, dynamic> fixtureCatalog() =>
    jsonDecode(File('${fixtures.path}/catalog.json').readAsStringSync()) as Map<String, dynamic>;

/// Serves files from test/fixtures like the R2 bucket would.
MockClient fixtureServer({Map<String, dynamic>? catalog, Set<String>? corrupt}) {
  return MockClient((request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^/'), '');
    if (path == 'catalog.json') {
      return http.Response(jsonEncode(catalog ?? fixtureCatalog()), 200);
    }
    final file = File('${fixtures.path}/$path');
    if (!file.existsSync()) return http.Response('not found', 404);
    final bytes = file.readAsBytesSync();
    if (corrupt?.contains(path) ?? false) bytes[0] ^= 0xff;
    return http.Response.bytes(bytes, 200);
  });
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('mymanual'));
  tearDown(() => root.deleteSync(recursive: true));

  group('catalog', () {
    test('parses the pipeline output', () {
      final catalog = Catalog.fromJson(fixtureCatalog());
      final unit = catalog.units.single;
      expect(unit.name, 'TEST1-1');
      expect(unit.kind, 'Excavator');
      final file = unit.files.single;
      expect(file.key, 'TEST1/OMM_Test_Unit');
      expect(file.type, DocType.omm);
      expect(file.pages, 4);
      expect(file.updatedAt, isNotNull);
    });
  });

  group('machine folders', () {
    Unit unit(String id, [String kind = '']) => Unit(id: id, name: id, kind: kind, files: const []);

    test('model codes sort into excavator and bulldozer', () {
      for (final id in ['PC2000-11', 'PC1250-11', 'CAT395', 'PC500-10', 'PC210']) {
        expect(unit(id).machine, Machine.excavator, reason: id);
      }
      for (final id in ['D375', 'D155', 'D85']) {
        expect(unit(id).machine, Machine.bulldozer, reason: id);
      }
      expect(unit('GD825').machine, Machine.other);
    });

    test('kind from unit.json wins over the model code', () {
      expect(unit('CATD9', 'Bulldozer').machine, Machine.bulldozer);
      expect(unit('X1', 'Excavator').machine, Machine.excavator);
    });
  });

  group('updates', () {
    final catalog = Catalog.fromJson(fixtureCatalog());
    final file = catalog.files.single;

    test('a file not seen before is new; once seen it is not', () {
      expect(computeUpdates(remote: catalog, local: {}, seenKeys: {}).single.kind, UpdateKind.added);
      expect(computeUpdates(remote: catalog, local: {}, seenKeys: {file.key}), isEmpty);
    });

    test('a downloaded file with a different hash has a new version', () {
      final old = ManualFile.fromJson(file.unitId, {
        ...file.toJson(),
        'pdf': {...file.pdf.toJson(), 'sha256': 'old'},
      });
      final updates = computeUpdates(
        remote: catalog,
        local: {file.key: LocalManual(file: old, unitName: 'TEST1-1')},
        seenKeys: {file.key},
      );
      expect(updates.single.kind, UpdateKind.newVersion);
    });

    test('a downloaded file missing from the server is withdrawn', () {
      final updates = computeUpdates(
        remote: Catalog.empty,
        local: {file.key: LocalManual(file: file, unitName: 'TEST1-1')},
        seenKeys: {},
      );
      expect(updates.single.kind, UpdateKind.withdrawn);
    });
  });

  group('search', () {
    final index = '${fixtures.path}/units/TEST1/OMM_Test_Unit.sqlite';

    test('builds an FTS query with a prefix on the last word', () {
      expect(toFtsQuery('hydraulic oil fil'), '"hydraulic" "oil" "fil"*');
      expect(toFtsQuery('  "  '), '');
    });

    test('finds pages with their section and highlighted snippet', () {
      final result = searchIndexesSync({'k': index}, toFtsQuery('hydraulic oil filter'));
      expect(result.pageCounts['k'], 2);
      final best = result.hits.first;
      expect([2, 3], contains(best.page));
      expect(best.section, isNotNull);
      expect(best.snippet, contains(SearchHit.matchStart));
    });

    test('prefix search works while typing', () {
      final result = searchIndexesSync({'k': index}, toFtsQuery('track ten'));
      expect(result.hits.single.page, 4);
      expect(result.hits.single.section, 'Track tension');
    });

    test('reads the bookmarks', () {
      final toc = loadToc(index);
      expect(toc.map((e) => e.title), contains('Hydraulic oil filter clogging caution lamp'));
    });
  });

  group('store', () {
    test('refresh, download, search, delete, and reopen offline', () async {
      var store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      expect(store.online, isTrue);
      expect(store.units.single.name, 'TEST1-1');
      // First contact: existing manuals are not "new".
      expect(store.updates, isEmpty);

      final file = store.catalog.files.single;
      await store.download(file, unitName: 'TEST1-1');
      expect(store.isDownloaded(file.key), isTrue);
      expect(File(store.pdfPath(file)).existsSync(), isTrue);
      expect(store.searchableIndexes().keys, [file.key]);

      store.setLastRead(file.key, 3, section: 'Maintenance');
      store.toggleBookmark(file.key, 2);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Reopen without network: everything downloaded is still there.
      store.dispose();
      store = await AppStore.open(
        root: root,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      await store.refresh();
      expect(store.online, isFalse);
      expect(store.units.single.files.single.key, file.key);
      expect(store.lastRead?.page, 3);
      expect(store.isBookmarked(file.key, 2), isTrue);

      await store.deleteManuals([file.key]);
      expect(store.isDownloaded(file.key), isFalse);
      expect(File(store.pdfPath(file)).existsSync(), isFalse);
      expect(store.lastRead, isNull);
      store.dispose();
    });

    test('an install saved with the old r2.dev address moves to the default', () async {
      File('${root.path}/state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'server': 'https://pub-123.r2.dev'}));
      final store = await AppStore.open(root: root, client: fixtureServer());
      expect(store.serverUrl, defaultServerUrl);
      store.dispose();
    });

    test('a corrupted download is rejected and the bad file removed', () async {
      final store = await AppStore.open(
        root: root,
        client: fixtureServer(corrupt: {'units/TEST1/OMM_Test_Unit.pdf'}),
      );
      await store.setServerUrl('https://example.test');
      final file = store.catalog.files.single;
      await expectLater(store.download(file, unitName: 'TEST1-1'), throwsA(isA<FileSystemException>()));
      expect(store.isDownloaded(file.key), isFalse);
      expect(File('${store.pdfPath(file)}.part').existsSync(), isFalse);
      // The index arrived intact and is kept for the next try.
      expect(store.partialBytes(file), file.index.size);
      store.dispose();
    });

    test('an interrupted download continues where it stopped', () async {
      final pdfPath = 'units/TEST1/OMM_Test_Unit.pdf';
      final pdfBytes = File('${fixtures.path}/$pdfPath').readAsBytesSync();
      final ranges = <String?>[];
      var dropConnection = true;
      final client = MockClient.streaming((request, _) async {
        final path = request.url.path.replaceFirst(RegExp(r'^/'), '');
        if (path != pdfPath) {
          return fixtureServer().send(http.Request(request.method, request.url));
        }
        ranges.add(request.headers['Range']);
        if (dropConnection) {
          // Send half the PDF, then lose the connection.
          Stream<List<int>> body() async* {
            yield pdfBytes.sublist(0, pdfBytes.length ~/ 2);
            throw const SocketException('Network is unreachable');
          }
          return http.StreamedResponse(body(), 200);
        }
        final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['Range']!)!.group(1)!);
        return http.StreamedResponse(Stream.value(pdfBytes.sublist(from)), 206);
      });
      final store = await AppStore.open(root: root, client: client);
      await store.setServerUrl('https://example.test');
      final file = store.catalog.files.single;

      await expectLater(store.download(file, unitName: 'TEST1-1'), throwsA(isA<DownloadInterrupted>()));
      expect(store.isDownloaded(file.key), isFalse);
      expect(store.partialBytes(file), greaterThanOrEqualTo(pdfBytes.length ~/ 2));

      dropConnection = false;
      await store.download(file, unitName: 'TEST1-1');
      expect(ranges.last, 'bytes=${pdfBytes.length ~/ 2}-');
      expect(store.isDownloaded(file.key), isTrue);
      expect(File(store.pdfPath(file)).readAsBytesSync(), pdfBytes);
      expect(store.partialBytes(file), 0);
      store.dispose();
    });

    test('a manual added on the server later lights the bell', () async {
      final catalog = fixtureCatalog();
      var store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
      store.dispose();

      final unit = (catalog['units'] as List).single as Map<String, dynamic>;
      final extra = {...(unit['files'] as List).single as Map<String, dynamic>, 'id': 'Shop_Manual_New'};
      unit['files'] = [...unit['files'] as List, extra];
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.refresh();
      expect(store.updates.single.kind, UpdateKind.added);
      store.markUpdatesSeen();
      expect(store.updates, isEmpty);
      store.dispose();
    });
  });
}
