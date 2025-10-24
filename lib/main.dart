import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/outbox_page.dart';
import 'services/api_service.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("📩 Background message: ${message.data}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final int _userId = 123456; // شناسه تستی
  RemoteMessage? _initialMessage;

  @override
  void initState() {
    super.initState();
    _setupFCM();
  }

  void _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token != null) {
      await ApiService.registerToken(_userId, token);
      print('✅ Registered FCM Token: $token');
    }

    _initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (_initialMessage != null) {
      _handleMessage(_initialMessage!);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    FirebaseMessaging.onMessage.listen((msg) {
      print('📨 Foreground message: ${msg.notification?.title}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.notification?.body ?? "New signal")),
        );
      }
    });
  }

  void _handleMessage(RemoteMessage message) {
    final fileName = message.data['file'];
    if (fileName != null && fileName.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutboxPage(userId: _userId, highlightFile: fileName),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OutboxPage(userId: _userId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Signal App',
      home: OutboxPage(userId: 123456),
    );
  }
}
