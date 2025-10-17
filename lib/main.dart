import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String SERVER_URL = 'http://178.63.171.244:5000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chart Notifier',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _fcmToken;
  String _userId = 'user_123'; // می‌تونی به UID فایربیس تغییر بدی
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    // دریافت FCM token
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      setState(() {
        _fcmToken = token;
      });
      // ثبت در سرور
      await _registerOnServer(token);
    }

    // گوش دادن به نوتیفیکیشن‌های ورودی
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🔔 ${message.notification?.title}')),
      );
    });
  }

  Future<void> _registerOnServer(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'fcm_token': token}),
      );
      if (response.statusCode == 200) {
        setState(() {
          _isRegistered = true;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', _userId);
      }
    } catch (e) {
      print('❌ خطا در ثبت: $e');
    }
  }

  Future<void> _subscribe(String symbol, String timeframe) async {
    if (!_isRegistered) return;

    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/subscribe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'symbol': symbol,
          'timeframe': timeframe,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ سابسکرایب شد: $symbol - $timeframe')),
        );
      }
    } catch (e) {
      print('❌ خطا در سابسکرایب: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ارسال سیگنال چارت')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('وضعیت: ${_isRegistered ? "✅ ثبت‌شده" : "❌ ثبت نشده"}'),
            const SizedBox(height: 20),
            const Text('انتخاب جفت‌ارز و تایم‌فریم:'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _subscribe('EURUSD', 'M5'),
              child: const Text('EURUSD - M5'),
            ),
            ElevatedButton(
              onPressed: () => _subscribe('XAUUSD', 'H1'),
              child: const Text('XAUUSD - H1'),
            ),
            ElevatedButton(
              onPressed: () => _subscribe('BTCUSD', 'M15'),
              child: const Text('BTCUSD - M15'),
            ),
          ],
        ),
      ),
    );
  }
}
