import 'package:flutter/material.dart';
import 'screens/settings_page.dart';
import 'screens/outbox_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signal Bot',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SettingsPage(userId: 12345), // نمایش صفحه تنظیمات برای کاربر 12345
    );
  }
}
