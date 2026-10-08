import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One row of Cetok Online's stock: one part number of one unit model at one
/// location with one status (RFU / NOT RFU, or none once it ran out).
class CetokPart {
  const CetokPart({
    required this.id,
    required this.unit,
    required this.pn,
    required this.desc,
    required this.loc,
    required this.qty,
    this.status,
    this.remarks,
  });

  factory CetokPart.fromJson(Map<String, dynamic> json) => CetokPart(
        id: '${json['id']}',
        unit: json['unit'] as String? ?? '',
        pn: json['pn'] as String? ?? '',
        desc: json['desc'] as String? ?? '',
        loc: (json['loc'] as String? ?? '').trim(),
        qty: (json['qty'] as num?)?.toInt() ?? 0,
        status: _blankToNull(json['status'] as String?)?.toUpperCase(),
        remarks: _blankToNull(json['remarks'] as String?),
      );

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  final String id;
  final String unit;

  /// May hold several part numbers separated by commas or semicolons.
  final String pn;
  final String desc;
  final String loc;
  final int qty;
  final String? status;
  final String? remarks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit': unit,
        'pn': pn,
        'desc': desc,
        'loc': loc,
        'qty': qty,
        'status': status,
        'remarks': remarks,
      };

  /// The part numbers in [pn], one per entry, like the website shows them.
  List<String> get numbers => [
        for (final n in pn.split(RegExp(r'[,;]+'))) if (n.trim().isNotEmpty) n.trim(),
      ];

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || pn.toLowerCase().contains(q) || desc.toLowerCase().contains(q);
  }
}

class CetokException implements Exception {
  CetokException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The model code a unit name starts with (PC210-10MO -> PC210, D375A-6R ->
/// D375), so Cetok Online's units match the manuals' units.
String unitModelCode(String unit) =>
    RegExp(r'^[A-Z]+\d+').firstMatch(unit.toUpperCase().replaceAll(RegExp(r'[\s_]'), ''))?[0] ?? unit.toUpperCase();

/// Cetok Online's parts stock, read and changed through the same database
/// functions (Supabase RPC) as its website and WhatsApp bot, so the stock
/// rules (no negative stock, upper case, every change in its history) stay
/// in the database. The last list read is kept on the phone for offline use.
class Cetok extends ChangeNotifier {
  Cetok({required this.cachePath, required this.client, Uri? baseUrl, String? key})
      : _base = baseUrl ?? Uri.parse(supabaseUrl),
        _key = key ?? publishableKey;

  /// Cetok Online's Supabase project. The key is the public (anon) one the
  /// website ships; what it may do is limited by the database's own rules.
  static const supabaseUrl = 'https://zdmlydqxvtvuktcfijzx.supabase.co';
  static const publishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpkbWx5ZHF4dnR2dWt0Y2Zpanp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxMjE2NTksImV4cCI6MjEwMjY5NzY1OX0.HbZY03oiDZ9J7RkakbtVR3S3Dze89ttd2NbLQkqGYPY';

  /// Unit models for new stock, as on the website.
  static const unitModels = [
    'PC2000-11R',
    'PC1250SP-11',
    'CAT395',
    'PC500LC-10R',
    'PC210-10MO',
    'D375A-6R',
    'D155A-6R',
    'D85ESS-2',
  ];

  /// Like cetok-online.vercel.app: only the stock at LOGISTIK, FABRIKASI,
  /// LAYDOWN and TRACKINDO (the database hides the rest).
  static const showHidden = false;

  final String cachePath;
  final http.Client client;
  final Uri _base;
  final String _key;

  List<CetokPart> parts = const [];
  DateTime? updated;
  bool loading = false;
  String? error;

  /// The name last used for a transaction, filled in next time.
  String name = '';

  bool _loaded = false;
  bool _again = false;

  /// Reads the copy kept on the phone, then the live stock.
  Future<void> open() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final file = File(cachePath);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          parts = [for (final p in json['parts'] as List? ?? const []) CetokPart.fromJson(p as Map<String, dynamic>)];
          final at = json['updated'] as String?;
          updated = at == null ? null : DateTime.tryParse(at);
          name = json['name'] as String? ?? '';
          notifyListeners();
        }
      } on Object catch (e) {
        debugPrint('cetok cache unreadable: $e');
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (loading) {
      // A change was saved while reading: read again once this one is done.
      _again = true;
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final data = await _rpc('get_all_data', {'p_riwayat_limit': 1, 'p_show_hidden': showHidden});
      final list = (data is Map ? data['parts'] : null) as List? ?? const [];
      parts = [for (final p in list) CetokPart.fromJson((p as Map).cast<String, dynamic>())];
      updated = DateTime.now();
      error = null;
      unawaited(_save());
    } on CetokException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await refresh();
    }
  }

  /// Takes [qty] of [part] out of stock.
  Future<void> take(CetokPart part, {required int qty, required String note, required String name}) =>
      _write('ambil_barang', {'p_id': part.id, 'p_qty': qty, 'p_note': note.trim(), 'p_nama': name.trim()}, name);

  /// Moves [qty] of [part] to another location and/or status.
  Future<void> move(
    CetokPart part, {
    required int qty,
    required String location,
    required String status,
    required String note,
    required String name,
  }) =>
      _write('transfer_stok', {
        'p_source_id': part.id,
        'p_qty': qty,
        'p_dest_loc': location.trim(),
        'p_dest_status': status,
        'p_note': note.trim(),
        'p_nama': name.trim(),
      }, name);

  /// Adds stock: a new row, or more of an existing one.
  Future<void> add({
    required String unit,
    required String pn,
    required String desc,
    required String location,
    required int qty,
    required String status,
    required String remarks,
    required String name,
  }) =>
      _write('input_barang', {
        'p_unit': unit,
        'p_pn': pn.trim(),
        'p_desc': desc.trim(),
        'p_loc': location.trim(),
        'p_qty': qty,
        'p_nama': name.trim(),
        'p_status': status,
        'p_remarks': remarks.trim(),
      }, name);

  Future<void> _write(String function, Map<String, dynamic> args, String usedName) async {
    await _rpc(function, args);
    name = usedName.trim();
    await refresh();
  }

  /// Locations in the stock list, for filters and suggestions.
  List<String> get locations {
    final seen = <String, String>{};
    for (final p in parts) {
      if (p.loc.isNotEmpty) seen.putIfAbsent(p.loc.toLowerCase(), () => p.loc);
    }
    return seen.values.toList()..sort();
  }

  /// Unit models in the stock list, in the website's order first.
  List<String> get units {
    final inStock = {for (final p in parts) p.unit};
    return [
      for (final u in unitModels) if (inStock.contains(u)) u,
      ...(inStock.difference(unitModels.toSet()).toList()..sort()),
    ];
  }

  Future<dynamic> _rpc(String function, Map<String, dynamic> args) async {
    final http.Response response;
    try {
      response = await client
          .post(
            _base.resolve('/rest/v1/rpc/$function'),
            headers: {
              'apikey': _key,
              'authorization': 'Bearer $_key',
              'content-type': 'application/json',
            },
            body: jsonEncode(args),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw CetokException('Tidak bisa terhubung ke Cetok Online. Periksa sinyal internet.');
    }
    final body = utf8.decode(response.bodyBytes);
    dynamic data;
    try {
      data = body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      data = null;
    }
    if (response.statusCode >= 300) {
      // The database's own message, e.g. "Stok tidak cukup".
      final message = data is Map ? data['message'] as String? : null;
      throw CetokException(message ?? 'Cetok Online sedang bermasalah (kode ${response.statusCode}).');
    }
    return data;
  }

  Future<void> _save() async {
    try {
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      final tmp = File('$cachePath.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmp.writeAsString(jsonEncode({
        'parts': [for (final p in parts) p.toJson()],
        'updated': updated?.toIso8601String(),
        'name': name,
      }));
      await tmp.rename(cachePath);
    } on Object catch (e) {
      debugPrint('saving cetok cache failed: $e');
    }
  }
}
