import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/remote_pdf.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('remote-pdf'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const bs = RemotePdf.blockSize;
  final source = Uint8List.fromList([for (var i = 0; i < bs * 10 + 123; i++) i * 7 % 251]);

  RemotePdf open(List<(int, int)> requests, {String name = 'm'}) => RemotePdf(
        size: source.length,
        dir: Directory('${tmp.path}/u/$name'),
        fetch: (start, end) async {
          requests.add((start, end));
          return Uint8List.sublistView(source, start, end);
        },
      );

  Future<Uint8List> read(RemotePdf pdf, int position, int length) async {
    final buffer = Uint8List(length);
    final n = await pdf.read(buffer, position, length);
    return Uint8List.sublistView(buffer, 0, n);
  }

  test('reads across pieces, fetching a few missing ones per request', () async {
    final requests = <(int, int)>[];
    final pdf = open(requests);
    expect(await read(pdf, bs - 10, 30), source.sublist(bs - 10, bs + 20));
    // The missing piece and the 3 after it, in one request.
    expect(requests, [(0, 4 * bs)]);
    expect(await read(pdf, 3 * bs + 5, 10), source.sublist(3 * bs + 5, 3 * bs + 15));
    expect(requests, hasLength(1));
    // The end of the file: the last piece is short.
    expect(await read(pdf, source.length - 50, 100), source.sublist(source.length - 50));
    expect(requests.last, (10 * bs, source.length));
  });

  test('pieces read once come back from the phone without the server', () async {
    final first = <(int, int)>[];
    await read(open(first), 9 * bs, 40);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = <(int, int)>[];
    expect(await read(open(again), 9 * bs, 40), source.sublist(9 * bs, 9 * bs + 40));
    expect(again, isEmpty);
  });

  test('prune drops the manual read longest ago', () async {
    await read(open([], name: 'old'), 0, 10);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await read(open([], name: 'new'), 0, 10);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await RemotePdf.prune(tmp, maxBytes: 5 * bs);
    expect(Directory('${tmp.path}/u/old').existsSync(), isFalse);
    expect(Directory('${tmp.path}/u/new').existsSync(), isTrue);
  });
}
