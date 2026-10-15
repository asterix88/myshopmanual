import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const png1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==';

void main() {
  test('live AI deepseek check', () async {
    final cases = <String, List<Map<String, Object>>>{
      'text': [
        {'role': 'user', 'content': 'charging system PC2000'}
      ],
      'picture': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Gambar ini warna apa?'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$png1'}
            }
          ]
        }
      ],
    };
    for (final e in cases.entries) {
      print('\n=== CASE ${e.key}');
      final r = await http.post(Uri.parse('http://127.0.0.1:8787/chat'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'messages': e.value,
            'features': ['view_page', 'reasoning', 'read_page'],
            'manuals': ['[M1] PC2000-11R: Shop Manual (Shop Manual, 1500 pages)'],
          }));
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final m = data['message'] as Map?;
      print('status=${r.statusCode} model=${data['model']} calls=${jsonEncode(m?['tool_calls'])}');
      final text = (m?['content'] ?? data).toString();
      print(text.length > 400 ? text.substring(0, 400) : text);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
