// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signal_bot/models/models.dart';

class ApiService {
  final String baseUrl = 'http://178.63.171.244:8000'; // آدرس سرور خود را وارد کنید

  // ارسال تنظیمات به سرور
  Future<void> setSettings(int userId, SettingsModel settings) async {
    final url = Uri.parse('$baseUrl/settings/$userId');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(settings.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update settings');
    }
  }

  // دریافت فایل‌ها از پوشه Outbox
  Future<List<FileModel>> getOutbox(int userId) async {
    final url = Uri.parse('$baseUrl/outbox/$userId');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body)['outbox'];
      return data.map((item) => FileModel.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load outbox');
    }
  }

  // دانلود فایل
  Future<http.Response> downloadFile(int userId, String filename) async {
    final url = Uri.parse('$baseUrl/download/$userId/$filename');
    return await http.get(url);
  }
}
