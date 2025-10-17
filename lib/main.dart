import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String SERVER_URL = 'http://178.63.171.244:5000';

final List<String> symbols = [
  'EURUSD', 'XAUUSD', 'GBPUSD', 'USDJPY', 'USDCHF',
  'AUDUSD', 'AUDJPY', 'CADJPY', 'EURJPY',
  'BTCUSD', 'ETHUSD', 'ADAUSD',
  'DowJones', 'NASDAQ', 'S&P500',
];

final List<String> timeframes = [
  'M1', 'M2', 'M3', 'M4',
  'M5', 'M6', 'M10', 'M12',
  'M15', 'M20', 'M30', 'H1',
  'H2', 'H3', 'H4', 'H6',
  'H8', 'H12', 'D1', 'W1',
];

void main() async {
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
  String _userId = 'user_123';
  bool _isRegistered = false;
  Map<String, Set<String>> subscribed = {};
  List<String> _receivedImages = [];

  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      setState(() => _fcmToken = token);
      await _registerOnServer(token);
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final imageUrl = message.data['image_url'];
      if (imageUrl != null) {
        setState(() {
          _receivedImages.insert(0, imageUrl);
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🔔 ${message.notification?.title ?? "سیگنال جدید"}')),
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
        setState(() => _isRegistered = true);
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
        setState(() {
          subscribed.putIfAbsent(symbol, () => {}).add(timeframe);
        });
      }
    } catch (e) {
      print('❌ خطا در سابسکرایب: $e');
    }
  }

  Future<void> _unsubscribe(String symbol, String timeframe) async {
    if (!_isRegistered) return;
    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/unsubscribe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'symbol': symbol,
          'timeframe': timeframe,
        }),
      );
      if (response.statusCode == 200) {
        setState(() {
          subscribed[symbol]?.remove(timeframe);
        });
      }
    } catch (e) {
      print('❌ خطا در لغو سابسکرایب: $e');
    }
  }

  List<Widget> buildSymbolTiles() {
    return symbols.map((symbol) {
      return ExpansionTile(
        title: Text(symbol),
        children: [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: timeframes.map((tf) {
              final isActive = subscribed[symbol]?.contains(tf) ?? false;
              return Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.green : Colors.red,
                  ),
                  onPressed: () {
                    if (isActive) {
                      _unsubscribe(symbol, tf);
                    } else {
                      _subscribe(symbol, tf);
                    }
                  },
                  child: Text(tf),
                ),
              );
            }).toList(),
          ),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت سیگنال چارت')),
      body: Column(
        children: [
          Expanded(child: ListView(children: buildSymbolTiles())),
          const Divider(),
          const Text('📸 تصاویر دریافت‌شده'),
          Expanded(
            child: ListView.builder(
              itemCount: _receivedImages.length,
              itemBuilder: (context, index) {
                final url = _receivedImages[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(url),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('چارت دریافت‌شده', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
