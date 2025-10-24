import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static const String baseUrl = "http://178.63.171.244:8000";

  static Future<bool> sendSettings(int userId, Map<String, dynamic> body) async {
    final url = Uri.parse('$baseUrl/settings/$userId');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      print('sendSettings error: $e');
      return false;
    }
  }

  static Future<bool> registerToken(int userId, String token) async {
    final url = Uri.parse('$baseUrl/register_token/$userId');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      print('registerToken error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchOutbox(int userId) async {
    final url = Uri.parse('$baseUrl/outbox/$userId');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List items = data['outbox'] ?? [];
        return items.map<Map<String, dynamic>>((it) {
          final path = it['path'] ?? '';
          final fullUrl = path.startsWith('http') ? path : '${baseUrl}${path}';
          return {
            'file': it['file'],
            'url': fullUrl,
            'caption': it['caption'] ?? '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('fetchOutbox error: $e');
      return [];
    }
  }

  static Future<http.Response?> downloadFile(int userId, String filename) async {
    final url = Uri.parse('$baseUrl/download/$userId/$filename');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return res;
      return null;
    } catch (e) {
      print('downloadFile error: $e');
      return null;
    }
  }
}
