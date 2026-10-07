import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('live AI web search', () async {
    for (final q in [
      'Apa itu Komatsu Smart Construction Retrofit kit?',
      'Apa itu SL1?',
      'Apa itu hydraulic oil ISO VG 46?',
    ]) {
      print('\n=== Q: $q');
      final r = await http.post(Uri.parse('http://127.0.0.1:8787/chat'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': q}
            ],
            'manuals': ['[M1] D155A-6: Shop Manual (Shop Manual, 1200 pages)'],
          }));
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final m = data['message'] as Map?;
      print('status=${r.statusCode} model=${data['model']} web=${data['web']} calls=${jsonEncode(m?['tool_calls'])}');
      print((m?['content'] ?? data).toString());
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
