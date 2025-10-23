// lib/screens/settings_page.dart

import 'package:flutter/material.dart';
import 'package:signal_bot/models/models.dart';
import 'package:signal_bot/services/api_service.dart';

class SettingsPage extends StatefulWidget {
  final int userId;

  const SettingsPage({Key? key, required this.userId}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ApiService _apiService;
  late SettingsModel _settings;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _settings = SettingsModel(timeframes: {}, modes: {}, sessions: {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // تنظیمات تایم‌فریم‌ها
            Text('Timeframes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: Text('EUR/USD M1'),
              value: _settings.timeframes['EURUSD']?['M1'] ?? false,
              onChanged: (bool? value) {
                setState(() {
                  _settings.timeframes['EURUSD'] = {'M1': value};
                });
              },
            ),
            // تنظیمات مودها
            Text('Modes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: Text('A1'),
              value: _settings.modes['A1'] ?? false,
              onChanged: (bool? value) {
                setState(() {
                  _settings.modes['A1'] = value;
                });
              },
            ),
            // تنظیمات سشن‌ها
            Text('Sessions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: Text('TOKYO'),
              value: _settings.sessions['TOKYO'] ?? false,
              onChanged: (bool? value) {
                setState(() {
                  _settings.sessions['TOKYO'] = value;
                });
              },
            ),
            // دکمه ارسال تنظیمات
            ElevatedButton(
              onPressed: () async {
                try {
                  await _apiService.setSettings(widget.userId, _settings);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings updated successfully')));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update settings')));
                }
              },
              child: Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
