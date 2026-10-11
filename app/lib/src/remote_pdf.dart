import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'diagnostics.dart';

/// Reads a manual on the server for the PDF viewer, in small pieces.
///
/// pdfrx's own reader fetches 1 MB at a time, while a Shop Manual page is
/// mostly 30-100 KB, so a jump to a far page downloaded many times what it
/// needed and took 10-15 s on 4G. Here a piece is 64 KB, a few missing
/// pieces in a row come in one request, and every piece is kept on the
/// phone, so a page read once opens again at once.
class RemotePdf {
  RemotePdf({required this.size, required this.dir, required this.fetch}) {
    dir.createSync(recursive: true);
  }

  static const blockSize = 64 * 1024;

  /// Pieces fetched in one request: the missing one and the missing ones
  /// right after it, since PDFium mostly reads on from where it was.
  static const readAhead = 4;

  /// Pieces kept in memory (8 MB); the rest are read back from the phone.
  static const _memoryBlocks = 128;

  final int size;
  final Directory dir;

  /// Bytes [start] to [end] (exclusive) from the server.
  final Future<Uint8List> Function(int start, int end) fetch;

  // Insertion-ordered: the piece used longest ago is first.
  final _memory = <int, Uint8List>{};
  final _inFlight = <int, Future<Uint8List>>{};

  int get _blockCount => (size + blockSize - 1) ~/ blockSize;

  int _lengthOf(int id) => math.min(blockSize, size - id * blockSize);

  File _file(int id) => File(p.join(dir.path, '$id.b'));

  /// The read function PDFium calls (see PdfViewer.custom).
  Future<int> read(Uint8List buffer, int position, int length) async {
    var done = 0;
    while (done < length && position + done < size) {
      final at = position + done;
      final data = await _block(at ~/ blockSize);
      final offset = at % blockSize;
      final n = math.min(length - done, data.length - offset);
      buffer.setRange(done, done + n, data, offset);
      done += n;
    }
    return done;
  }

  Future<Uint8List> _block(int id) async {
    final hit = _memory.remove(id);
    if (hit != null) return _memory[id] = hit;
    final pending = _inFlight[id];
    if (pending != null) return pending;
    final file = _file(id);
    if (file.existsSync()) {
      final data = await file.readAsBytes();
      // A piece cut short (the app closed while writing it) is fetched again.
      if (data.length == _lengthOf(id)) {
        _remember(id, data);
        return data;
      }
    }
    var end = id + 1;
    while (end < _blockCount && end - id < readAhead && !_have(end)) {
      end++;
    }
    final run = _fetchRun(id, end);
    for (var b = id; b < end; b++) {
      // Only the first piece is awaited here; the others may never be asked
      // for, so their errors must not go unhandled.
      _inFlight[b] = run.then((blocks) => blocks[b - id])..ignore();
    }
    try {
      return (await run)[0];
    } finally {
      for (var b = id; b < end; b++) {
        _inFlight.remove(b);
      }
    }
  }

  bool _have(int id) => _memory.containsKey(id) || _inFlight.containsKey(id) || _file(id).existsSync();

  Future<List<Uint8List>> _fetchRun(int first, int end) async {
    final start = first * blockSize;
    final stop = math.min(end * blockSize, size);
    final watch = Stopwatch()..start();
    final data = await fetch(start, stop);
    if (watch.elapsedMilliseconds > 3000) {
      Diagnostics.log('pdf piece ${(stop - start) ~/ 1024} KB took ${watch.elapsedMilliseconds} ms');
    }
    final blocks = <Uint8List>[
      for (var b = first; b < end; b++)
        Uint8List.sublistView(data, (b - first) * blockSize, math.min((b - first + 1) * blockSize, data.length)),
    ];
    for (final (i, block) in blocks.indexed) {
      _remember(first + i, block);
      unawaited(_file(first + i).writeAsBytes(block).then((_) {}, onError: (Object e) {
        Diagnostics.log('pdf piece not saved: $e');
      }));
    }
    return blocks;
  }

  void _remember(int id, Uint8List data) {
    _memory[id] = data;
    while (_memory.length > _memoryBlocks) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// Deletes the pieces of the manuals read longest ago until those under
  /// [root] take at most [maxBytes]; [keep] (the manual open now) stays.
  static Future<void> prune(Directory root, {required int maxBytes, Directory? keep}) async {
    if (!await root.exists()) return;
    final dirs = <(Directory, DateTime, int)>[];
    var total = 0;
    await for (final unit in root.list()) {
      if (unit is! Directory) continue;
      await for (final manual in unit.list()) {
        if (manual is! Directory) continue;
        var bytes = 0;
        var newest = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final f in manual.list()) {
          if (f is! File) continue;
          final stat = await f.stat();
          bytes += stat.size;
          if (stat.modified.isAfter(newest)) newest = stat.modified;
        }
        total += bytes;
        dirs.add((manual, newest, bytes));
      }
    }
    dirs.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (manual, _, bytes) in dirs) {
      if (total <= maxBytes) break;
      if (keep != null && p.equals(manual.path, keep.path)) continue;
      await manual.delete(recursive: true);
      total -= bytes;
    }
  }
}
