import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai.dart' show aiUrl;
import 'auth.dart';
import 'diagnostics.dart';

/// Automatic error reports. Problems are written to a small list on the
/// phone (errors-pending.json) and sent to our own server
/// (ai.mymanual.my.id/errors) the next time the phone is online and logged
/// in; admins see them in menu ⋮ > Laporan error. Two kinds of problems:
/// - "error": an error the app did not handle (from [Diagnostics]);
/// - Android closing the app: CRASH, CRASH_NATIVE, ANR (not responding),
///   INITIALIZATION_FAILURE, read at the next start, with the last lines of
///   the app's log before it.
/// The same problem is kept once with a count, at most [maxItems] problems
/// wait on the phone, and nothing is sent without a login.
class ErrorReports {
  ErrorReports._();

  static const maxItems = 30;
  static const _exitKinds = {'CRASH', 'CRASH_NATIVE', 'ANR', 'INITIALIZATION_FAILURE'};

  static File? _pending;
  static File? _state;
  static List<Map<String, dynamic>> _items = [];
  static Timer? _timer;
  static bool _sending = false;

  static Session? Function() _session = () => null;
  static Future<Session?> Function() _renew = () async => null;
  static http.Client Function() _client = http.Client.new;
  static Uri _endpoint = Uri.parse('$aiUrl/errors');

  /// Starts listening for errors, reads why Android closed the app last
  /// time, and sends what is waiting.
  static Future<void> start({
    required Directory dir,
    required Session? Function() session,
    required Future<Session?> Function() renew,
    @visibleForTesting http.Client Function()? client,
    @visibleForTesting Uri? endpoint,
    @visibleForTesting List<Map<Object?, Object?>>? exits,
    @visibleForTesting Duration delay = const Duration(seconds: 20),
  }) async {
    _session = session;
    _renew = renew;
    if (client != null) _client = client;
    if (endpoint != null) _endpoint = endpoint;
    _pending = File('${dir.path}/errors-pending.json');
    _state = File('${dir.path}/errors-state.json');
    _items = _load();
    Diagnostics.onError = (message, stack) => record('error', message, stack);
    await _readExits(exits ?? await Diagnostics.exits());
    if (_items.isNotEmpty) _schedule(delay);
  }

  /// The problems waiting to be sent.
  static List<Map<String, dynamic>> get pending => List.unmodifiable(_items);

  /// Keeps one problem; the same one again only counts up.
  static void record(String kind, String message, String stack, {DateTime? at}) {
    final file = _pending;
    if (file == null) return;
    message = message.trim();
    if (message.isEmpty) return;
    if (message.length > 500) message = message.substring(0, 500);
    if (stack.length > 4000) stack = stack.substring(0, 4000);
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final same = _items.where((e) => e['kind'] == kind && e['message'] == message).firstOrNull;
    if (same != null) {
      same['count'] = (same['count'] as int? ?? 1) + 1;
      same['last'] = now;
      same['stack'] = stack;
    } else {
      _items.add({'kind': kind, 'message': message, 'stack': stack, 'count': 1, 'first': now, 'last': now});
      if (_items.length > maxItems) _items.removeAt(0);
    }
    _save();
    _schedule(const Duration(seconds: 30));
  }

  /// Sends what is waiting; true when the list is empty afterwards.
  static Future<bool> send() async {
    _timer?.cancel();
    if (_items.isEmpty) return true;
    if (_sending) return false;
    var session = _session();
    if (session == null) return false;
    _sending = true;
    final sent = _items.length;
    final client = _client();
    try {
      final body = jsonEncode({
        'app': currentApp,
        'model': await DeviceInfo.phoneModel(),
        'items': _items.take(20).toList(),
      });
      Future<http.Response> post(Session s) => client
          .post(_endpoint, headers: {'content-type': 'application/json', sessionHeader: s.token}, body: body)
          .timeout(const Duration(seconds: 20));
      var response = await post(session);
      if (response.statusCode == 401) {
        session = await _renew();
        if (session == null) return false;
        response = await post(session);
      }
      if (response.statusCode != 200) return false;
      // Problems recorded while sending stay for next time.
      _items = _items.skip(sent > 20 ? 20 : sent).toList();
      _save();
      if (_items.isNotEmpty) _schedule(const Duration(seconds: 30));
      return _items.isEmpty;
    } on Object {
      return false;
    } finally {
      _sending = false;
      client.close();
    }
  }

  static void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(send()));
  }

  /// Android's reasons for closing the app that are new since the last
  /// start. The first start only remembers where it is, so old crashes from
  /// before this version are not sent.
  static Future<void> _readExits(List<Map<Object?, Object?>> exits) async {
    final state = _state;
    if (state == null) return;
    int? seen;
    try {
      seen = (jsonDecode(state.readAsStringSync()) as Map)['exits_seen'] as int?;
    } on Object {
      seen = null;
    }
    var newest = seen ?? 0;
    for (final e in exits) {
      final time = e['time'] as int? ?? 0;
      if (time > newest) newest = time;
      final reason = '${e['reason']}';
      if (seen == null || time <= seen || !_exitKinds.contains(reason)) continue;
      final description = '${e['description'] ?? ''}'.trim();
      record(
        reason,
        'Aplikasi ditutup Android ($reason)${description.isEmpty ? '' : ': $description'}',
        'Catatan aplikasi sebelum tertutup:\n${Diagnostics.tail()}',
        at: DateTime.fromMillisecondsSinceEpoch(time),
      );
    }
    try {
      state.writeAsStringSync(jsonEncode({'exits_seen': newest}));
    } on FileSystemException {
      // Next start reads them again; the count only grows.
    }
  }

  static List<Map<String, dynamic>> _load() {
    try {
      return [
        for (final e in jsonDecode(_pending!.readAsStringSync()) as List) (e as Map).cast<String, dynamic>(),
      ];
    } on Object {
      return [];
    }
  }

  static void _save() {
    try {
      _pending?.writeAsStringSync(jsonEncode(_items));
    } on FileSystemException {
      // Reports must never break the app.
    }
  }

  @visibleForTesting
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _items = [];
    _pending = null;
    _state = null;
    _sending = false;
    Diagnostics.onError = null;
  }
}

/// One problem as the admin list shows it: the same message from every
/// phone, counted together.
class ErrorGroup {
  const ErrorGroup({
    required this.kind,
    required this.message,
    required this.stack,
    required this.count,
    required this.phones,
    required this.people,
    required this.apps,
    required this.last,
  });

  factory ErrorGroup.fromJson(Map<String, dynamic> json) => ErrorGroup(
        kind: json['kind'] as String? ?? 'error',
        message: json['message'] as String? ?? '',
        stack: json['stack'] as String? ?? '',
        count: json['count'] as int? ?? 1,
        phones: json['phones'] as int? ?? 1,
        people: [for (final p in json['people'] as List? ?? const []) '$p'],
        apps: [for (final a in json['apps'] as List? ?? const []) '$a'],
        last: DateTime.fromMillisecondsSinceEpoch(json['last'] as int? ?? 0),
      );

  final String kind;
  final String message;
  final String stack;
  final int count;
  final int phones;
  final List<String> people;
  final List<String> apps;
  final DateTime last;

  /// A closed app is worse than an error the app survived.
  bool get closedApp => kind != 'error';

  String get kindLabel => switch (kind) {
        'error' => 'Error',
        'ANR' => 'Macet (ANR)',
        'CRASH_NATIVE' => 'Crash native',
        'CRASH' => 'Crash',
        _ => kind,
      };
}

/// Admins: the grouped reports from the server, newest problem first.
Future<List<ErrorGroup>> fetchErrorGroups(http.Client client, {Uri? endpoint}) async {
  final http.Response response;
  try {
    response = await client.get(endpoint ?? Uri.parse('$aiUrl/errors')).timeout(const Duration(seconds: 25));
  } on Object {
    throw AuthException('network', 'Koneksi terputus');
  }
  Map<String, dynamic>? data;
  try {
    data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  } on FormatException {
    data = null;
  }
  if (response.statusCode != 200 || data == null) {
    throw AuthException(
      data?['error'] as String? ?? 'server',
      data?['message'] as String? ?? 'Server sedang bermasalah (kode ${response.statusCode}).',
    );
  }
  return [for (final g in data['groups'] as List? ?? const []) ErrorGroup.fromJson((g as Map).cast<String, dynamic>())];
}
