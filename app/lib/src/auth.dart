import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'ai.dart';

/// Header that carries the session to the server (ai-worker/src/auth.ts).
const sessionHeader = 'x-mymanual-session';

/// How long the server accepts a session after it was issued; the phone
/// swaps it well before (see [Session.stale]).
const _swapAfter = Duration(hours: 12);

/// Who is logged in on this phone. The token is signed by the server, which
/// is the only one that checks it; the phone only reads its dates.
class Session {
  const Session({
    required this.token,
    required this.nrp,
    required this.name,
    required this.admin,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        nrp: json['nrp'] as String,
        name: json['name'] as String? ?? json['nrp'] as String,
        admin: json['admin'] as bool? ?? false,
        issuedAt: DateTime.fromMillisecondsSinceEpoch((json['iat'] as num).toInt() * 1000),
        expiresAt: DateTime.fromMillisecondsSinceEpoch((json['exp'] as num).toInt() * 1000),
      );

  final String token;
  final String nrp;
  final String name;

  /// Sees "Kelola karyawan" and has no daily nyel AI limit.
  final bool admin;
  final DateTime issuedAt;

  /// 30 days after the last swap: past it the app logs out by itself.
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);

  /// Due for swapping the next time the phone is online.
  bool get stale => DateTime.now().difference(issuedAt) > _swapAfter;

  Map<String, dynamic> toJson() => {
        'token': token,
        'nrp': nrp,
        'name': name,
        'admin': admin,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
      };
}

/// A refusal from the server, with the message to show.
class AuthException implements Exception {
  AuthException(this.code, this.message);

  /// 'unknown' (NRP not in the list), 'inactive', 'pin', 'locked', 'login'
  /// (session no longer valid), 'network', ...
  final String code;
  final String message;

  /// The server no longer lets this NRP in.
  bool get revoked => code == 'unknown' || code == 'inactive' || code == 'login';

  @override
  String toString() => message;
}

/// Logged in, or asked to choose a PIN first.
sealed class LoginResult {}

class LoggedIn extends LoginResult {
  LoggedIn(this.session);
  final Session session;
}

/// The employee used their starting PIN; [setupToken] lets them set their
/// own for a few minutes.
class ChoosePin extends LoginResult {
  ChoosePin(this.setupToken, this.name);
  final String setupToken;
  final String name;
}

/// One row of the admin's employee list.
class Employee {
  Employee({
    required this.nrp,
    required this.name,
    required this.admin,
    required this.active,
    required this.isNew,
    required this.lastSeen,
    required this.devices,
    required this.aiToday,
  });

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        nrp: json['nrp'] as String,
        name: json['name'] as String? ?? json['nrp'] as String,
        admin: json['admin'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        isNew: json['status'] == 'new',
        lastSeen: (json['seen'] as num? ?? 0) == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['seen'] as num).toInt() * 1000),
        devices: (json['devices'] as List? ?? const []).cast<String>(),
        aiToday: (json['ai_today'] as num? ?? 0).toInt(),
      );

  final String nrp;
  final String name;
  final bool admin;
  bool active;

  /// Has not logged in yet.
  final bool isNew;
  final DateTime? lastSeen;
  final List<String> devices;
  final int aiToday;
}

/// What the app sends about this phone: a random id made once, and the
/// model name the admin sees.
class DeviceInfo {
  const DeviceInfo(this.id, this.model);
  final String id;
  final String model;

  Map<String, String> toJson() => {'id': id, 'model': model};

  static String newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static const _channel = MethodChannel('mymanual/diagnostics');

  static Future<String> phoneModel() async {
    try {
      return await _channel.invokeMethod<String>('device') ?? 'HP';
    } on Object {
      return 'HP';
    }
  }
}

/// The login and admin calls to the server.
class AuthApi {
  AuthApi(this.client, {Uri? base}) : _base = base ?? Uri.parse(aiUrl);

  final http.Client client;
  final Uri _base;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {Session? session}) async {
    final http.Response response;
    try {
      response = await client
          .post(
            _base.resolve(path),
            headers: {
              'content-type': 'application/json',
              if (session != null) sessionHeader: session.token,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw AuthException('network', 'Sinyal lemah, server tidak menjawab. Coba lagi.');
    } on Exception {
      throw AuthException('network', 'Tidak ada koneksi internet. Login butuh internet.');
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
    return data;
  }

  Future<LoginResult> login(String nrp, String pin, DeviceInfo device) async {
    final data = await _post('/auth/login', {'nrp': nrp.trim(), 'pin': pin.trim(), 'device': device.toJson()});
    if (data['status'] == 'set_pin') {
      return ChoosePin(data['setup'] as String, data['name'] as String? ?? nrp);
    }
    return LoggedIn(Session.fromJson(data));
  }

  Future<Session> choosePin(String setupToken, String pin, DeviceInfo device) async =>
      Session.fromJson(await _post('/auth/pin', {'setup': setupToken, 'pin': pin, 'device': device.toJson()}));

  /// A new session for [session]; throws an [AuthException] that is
  /// [AuthException.revoked] when the NRP is no longer allowed in.
  Future<Session> refresh(Session session, DeviceInfo device) async =>
      Session.fromJson(await _post('/auth/refresh', {'device': device.toJson()}, session: session));

  Future<List<Employee>> employees(Session session) async {
    final data = await _post('/admin/employees', const {}, session: session);
    final list = [
      for (final e in data['employees'] as List) Employee.fromJson(e as Map<String, dynamic>),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// A new starting PIN for [nrp], to give to the employee.
  Future<String> newPin(Session session, String nrp) async =>
      (await _post('/admin/pin', {'nrp': nrp}, session: session))['pin'] as String;

  Future<void> setActive(Session session, String nrp, bool active) =>
      _post('/admin/active', {'nrp': nrp, 'active': active}, session: session);
}

/// Adds the session to requests for the app's own servers and, when the
/// server says the session is too old, swaps it once and tries again.
class SessionClient extends http.BaseClient {
  SessionClient(this._inner, {required this.session, required this.renew});

  final http.Client _inner;
  final Session? Function() session;

  /// Swaps the session; null when that was not possible.
  final Future<Session?> Function() renew;

  static bool ours(Uri url) => url.host == 'mymanual.my.id' || url.host.endsWith('.mymanual.my.id');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final s = session();
    if (s == null || !ours(request.url)) return _inner.send(request);
    // Only bodiless requests can be sent twice.
    final retry = request is http.Request && request.bodyBytes.isEmpty ? _copy(request) : null;
    request.headers[sessionHeader] = s.token;
    final response = await _inner.send(request);
    if (response.statusCode != 401 || retry == null) return response;
    await response.stream.drain<void>();
    final fresh = await renew();
    if (fresh == null) {
      throw const HttpException('Sesi berakhir. Silakan masuk lagi.');
    }
    retry.headers[sessionHeader] = fresh.token;
    return _inner.send(retry);
  }

  static http.Request _copy(http.Request r) =>
      http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..followRedirects = r.followRedirects
        ..persistentConnection = r.persistentConnection;

  @override
  void close() => _inner.close();
}
