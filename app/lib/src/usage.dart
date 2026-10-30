import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// What this phone's user did, for the admins' "Statistik pemakaian": a
/// manual opened, a chapter read, a download, a search, a nyel AI question.
/// Kept in a file and sent to the server (POST /stats,
/// ai-worker/src/stats.ts) each time the app reaches it (AppStore.refresh),
/// so what was done offline arrives later; the server adds who it was from
/// the session.
class UsageLog {
  UsageLog({required this.path, required this.client, required this.endpoint, required this.enabled});

  final String path;

  /// Adds the session (SessionClient).
  final http.Client client;
  final Uri endpoint;

  /// Only logged-in phones send anything.
  final bool Function() enabled;

  /// Events not sent yet, oldest first; the oldest go when there are too
  /// many (a phone offline for weeks).
  static const maxKept = 3000;

  List<Map<String, dynamic>>? _queue;
  Future<void> _writing = Future.value();
  Future<void>? _sending;

  /// Searches already counted lately, so typing on does not count again.
  final Map<String, DateTime> _searched = {};

  Future<List<Map<String, dynamic>>> _load() async {
    if (_queue != null) return _queue!;
    var queue = <Map<String, dynamic>>[];
    try {
      final file = File(path);
      if (await file.exists()) {
        queue = [for (final e in jsonDecode(await file.readAsString()) as List) (e as Map).cast<String, dynamic>()];
      }
    } catch (e) {
      debugPrint('usage log unreadable: $e');
    }
    return _queue ??= queue;
  }

  Future<void> _write() => _writing = _writing.catchError((_) {}).then((_) async {
        final tmp = File('$path.tmp');
        await tmp.parent.create(recursive: true);
        await tmp.writeAsString(jsonEncode(_queue ?? const []));
        await tmp.rename(path);
      });

  Future<void> _adding = Future.value();

  /// Adds events one after another, so they stay in the order they happened
  /// while the file is still being read.
  Future<void> _add(Map<String, dynamic> event) {
    if (!enabled()) return Future.value();
    final entry = {'at': DateTime.now().millisecondsSinceEpoch, ...event};
    return _adding = _adding.catchError((_) {}).then((_) async {
      final queue = await _load();
      queue.add(entry);
      if (queue.length > maxKept) queue.removeRange(0, queue.length - maxKept);
      await _write().catchError((Object e) => debugPrint('usage log not saved: $e'));
    });
  }

  static Map<String, dynamic> _file(ManualFile f) => {'file': f.key, 'unit': f.unitId, 'title': f.title};

  void opened(ManualFile f) => unawaited(_add({'kind': 'open', ..._file(f)}));

  /// The top-level bookmark the reader stayed on.
  void chapter(ManualFile f, String title) => unawaited(_add({'kind': 'chapter', ..._file(f), 'q': title}));

  void downloaded(ManualFile f) => unawaited(_add({'kind': 'download', ..._file(f)}));

  /// A search on the Cari tab; [hits] 0 = found in no manual on the phone.
  void searched(String query, int hits) {
    final q = query.trim();
    if (q.length < 2) return;
    final key = q.toLowerCase();
    final now = DateTime.now();
    final last = _searched[key];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) return;
    _searched[key] = now;
    unawaited(_add({'kind': 'search', 'q': q, 'hits': hits}));
  }

  /// A nyel AI question that got an answer; [queries] are the searches the
  /// AI made, which give the statistics their topics.
  void asked({
    required String question,
    required String answer,
    required List<String> sources,
    required List<String> queries,
    String unit = '',
  }) =>
      unawaited(_add({
        'kind': 'ai',
        'q': question,
        'unit': unit,
        'extra': {'answer': answer, 'sources': sources, 'queries': queries},
      }));

  /// Sends what is waiting; quietly keeps it for later when offline.
  Future<void> send() => _sending ??= () async {
        try {
          if (!enabled()) return;
          final queue = await _load();
          while (queue.isNotEmpty) {
            final batch = queue.take(300).toList();
            final response = await client
                .post(endpoint, headers: {'content-type': 'application/json'}, body: jsonEncode({'events': batch}))
                .timeout(const Duration(seconds: 20));
            if (response.statusCode != 200) {
              debugPrint('usage log not sent: HTTP ${response.statusCode}');
              return;
            }
            queue.removeRange(0, batch.length);
            await _write();
          }
        } catch (e) {
          debugPrint('usage log not sent: $e');
        }
      }()
          .whenComplete(() => _sending = null);

  /// Logging out: what was not sent belongs to the one who logged out.
  Future<void> clear() async {
    _queue = [];
    await _write().catchError((_) {});
  }
}
