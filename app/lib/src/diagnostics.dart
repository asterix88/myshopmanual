import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A small log of what the app was doing, kept on the phone so a force close
/// can be explained afterwards (menu ⋮ > Laporan masalah). Each line is
/// written straight to disk, so the last steps before a crash survive it.
class Diagnostics {
  Diagnostics._();

  static File? _file;
  static const _channel = MethodChannel('mymanual/diagnostics');
  static const _maxBytes = 64 * 1024;

  /// Starts the log and catches errors the app did not handle.
  static Future<void> start({Directory? dir}) async {
    dir ??= await getApplicationSupportDirectory();
    final file = File('${dir.path}/diagnostics.log');
    try {
      // Keep the newest half when the log grows too big.
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final text = file.readAsStringSync();
        file.writeAsStringSync(text.substring(text.length - _maxBytes ~/ 2));
      }
    } on FileSystemException {
      // A log that can't be trimmed is still worth appending to.
    }
    _file = file;
    log('app started');
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      log('ERROR ${details.exceptionAsString()}\n${details.stack ?? ''}');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('ERROR $error\n$stack');
      return false;
    };
  }

  /// Adds one line, with the time, to the log.
  static void log(String message) {
    final file = _file;
    if (file == null) return;
    final now = DateTime.now().toIso8601String().substring(0, 19);
    try {
      file.writeAsStringSync('$now $message\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // Logging must never break the app.
    }
  }

  /// Everything known about recent problems, as text to copy and send.
  static Future<String> report() async {
    final out = StringBuffer();
    try {
      final memory = (await _channel.invokeMapMethod<String, Object?>('memory')) ?? const {};
      out.writeln('RAM HP: ${memory['totalMb']} MB, tersedia ${memory['availMb']} MB, '
          'batas aplikasi ${memory['memoryClassMb']} MB');
      final exits = (await _channel.invokeListMethod<Map<Object?, Object?>>('exits')) ?? const [];
      out.writeln('\nBerhenti terakhir (terbaru dulu):');
      for (final e in exits) {
        final time = DateTime.fromMillisecondsSinceEpoch(e['time'] as int).toIso8601String().substring(0, 19);
        final pssMb = ((e['pssKb'] as int? ?? 0) / 1024).round();
        out.writeln('- $time ${e['reason']} (memori $pssMb MB) ${e['description'] ?? ''}');
      }
      if (exits.isEmpty) out.writeln('- (tidak tersedia di Android ini)');
    } on Object catch (e) {
      out.writeln('Info sistem tidak tersedia: $e');
    }
    out.writeln('\nCatatan aplikasi:');
    try {
      final lines = (_file?.readAsLinesSync() ?? const <String>[]);
      out.write(lines.skip(lines.length > 120 ? lines.length - 120 : 0).join('\n'));
    } on FileSystemException {
      out.write('(kosong)');
    }
    return out.toString();
  }

  @visibleForTesting
  static void reset() => _file = null;
}
