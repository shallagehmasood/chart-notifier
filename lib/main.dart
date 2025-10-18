import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

const String SERVER_URL = 'http://178.63.171.244:5000';

final List<String> symbols = [
  'EURUSD', 'XAUUSD', 'GBPUSD', 'USDJPY', 'USDCHF',
  'AUDUSD', 'AUDJPY', 'CADJPY', 'EURJPY',
  'BTCUSD', 'ETHUSD', 'ADAUSD',
  'DowJones', 'NASDAQ', 'S&P500',
];

final List<String> timeframes = [
  'M1', 'M2', 'M3', 'M4', 'M5', 'M6',
  'M10', 'M12', 'M15', 'M20', 'M30', 'H1',
  'H2', 'H3', 'H4', 'H6', 'H8', 'H12', 'D1', 'W1',
];

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final imageUrl = message.data['image_url'];
  if (imageUrl != null) {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList('images') ?? [];
    final filenames = prefs.getStringList('filenames') ?? [];

    final filenameWithExt = imageUrl.split('/').last;
    final filename = filenameWithExt.split('.').first;
    final parts = filename.split('_');
    final symbol = parts.isNotEmpty ? parts[0] : '';
    final timeframe = parts.length > 1 ? parts[1] : '';
    final label = '$symbol|$timeframe';

    images.insert(0, imageUrl);
    filenames.insert(0, label);

    await prefs.setStringList('images', images);
    await prefs.setStringList('filenames', filenames);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(),
  ));
}

// ---------- SplashScreen ----------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _animation,
        child: Center(
          child: Image.asset('assets/icon.jpg', width: 150, height: 150),
        ),
      ),
    );
  }
}

// ---------- HomePage ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _userId = '';
  String? _fcmToken;
  Map<String, Set<String>> subscribed = {};
  List<String> _receivedImages = [];
  List<String> _receivedFilenames = [];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadImagesFromStorage();
    await _initUserId();
    await _initFirebase();
    await _handleNotificationClick();
    await _loadImagesFromServer();
  }

  Future<void> _initUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString('user_id');
    if (savedId == null) {
      savedId = 'user_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey()}';
      await prefs.setString('user_id', savedId);
    }
    setState(() => _userId = savedId!);
    debugPrint('🧩 User ID: $_userId');
  }

  Future<void> _initFirebase() async {
    _fcmToken = await FirebaseMessaging.instance.getToken();
    if (_fcmToken != null) {
      await _registerOnServer(_fcmToken!);
      await _loadSubscriptions();
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final imageUrl = message.data['image_url'];
      if (imageUrl != null) _handleIncomingImage(imageUrl);
    });
  }

  Future<void> _handleNotificationClick() async {
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage?.data['image_url'] != null) {
      await _loadImagesFromServer();
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _loadImagesFromServer();
    });
  }

  void _handleIncomingImage(String imageUrl) async {
    final filenameWithExt = imageUrl.split('/').last;
    final filename = filenameWithExt.split('.').first;
    final parts = filename.split('_');
    final symbol = parts.isNotEmpty ? parts[0] : '';
    final timeframe = parts.length > 1 ? parts[1] : '';
    final label = '$symbol|$timeframe';

    setState(() {
      _receivedImages.insert(0, imageUrl);
      _receivedFilenames.insert(0, label);
    });
    await _saveImagesToStorage();
  }

  Future<void> _saveImagesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('images', _receivedImages);
    await prefs.setStringList('filenames', _receivedFilenames);
  }

  Future<void> _loadImagesFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList('images') ?? [];
    final filenames = prefs.getStringList('filenames') ?? [];
    setState(() {
      _receivedImages = images;
      _receivedFilenames = filenames;
    });
  }

  Future<void> _loadImagesFromServer() async {
    final response = await http.post(
      Uri.parse('$SERVER_URL/images_for_user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List images = data['images'];
      setState(() {
        _receivedImages = images.map((e) => e['image_url'] as String).toList();
        _receivedFilenames =
            images.map((e) => '${e['symbol']}|${e['timeframe']}').toList();
      });
      await _saveImagesToStorage();
    }
  }

  Future<void> _registerOnServer(String token) async {
    await http.post(
      Uri.parse('$SERVER_URL/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId, 'fcm_token': token}),
    );
  }

  Future<void> _loadSubscriptions() async {
    final response = await http.post(
      Uri.parse('$SERVER_URL/subscriptions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List subs = data['subscriptions'];
      setState(() {
        subscribed.clear();
        for (var sub in subs) {
          final symbol = sub['symbol'];
          final tf = sub['timeframe'];
          subscribed.putIfAbsent(symbol, () => {}).add(tf);
        }
      });
    }
  }

  Future<void> _subscribe(String symbol, String timeframe) async {
    await http.post(
      Uri.parse('$SERVER_URL/subscribe'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId, 'symbol': symbol, 'timeframe': timeframe}),
    );
    setState(() {
      subscribed.putIfAbsent(symbol, () => {}).add(timeframe);
    });
  }

  Future<void> _unsubscribe(String symbol, String timeframe) async {
    await http.post(
      Uri.parse('$SERVER_URL/unsubscribe'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId, 'symbol': symbol, 'timeframe': timeframe}),
    );
    setState(() {
      subscribed[symbol]?.remove(timeframe);
    });
  }

  // ادامه مدیریت تصویر و حذف
  Future<void> _saveImageToGallery(String imageUrl) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) return;

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final directory = await getExternalStorageDirectory();
        final path = '${directory!.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(path);
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ تصویر ذخیره شد: ${file.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطا در ذخیره تصویر: $e')),
        );
      }
    }
  }

  void _showImageFullScreen(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('نمایش تصویر')),
          body: Stack(
            children: [
              PhotoView(
                imageProvider: NetworkImage(imageUrl),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _saveImageToGallery(imageUrl),
                      icon: const Icon(Icons.download),
                      label: const Text('ذخیره'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          final index = _receivedImages.indexOf(imageUrl);
                          if (index != -1) {
                            _receivedImages.removeAt(index);
                            _receivedFilenames.removeAt(index);
                          }
                        });
                        await _saveImagesToStorage();

                        try {
                          await http.post(
                            Uri.parse('$SERVER_URL/delete_image'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({'user_id': _userId, 'image_url': imageUrl}),
                          );
                        } catch (e) {
                          debugPrint('❌ خطا در حذف تصویر از سرور: $e');
                        }

                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('حذف'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                child: SizedBox(
                  width: 60,
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.green : Colors.red,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      if (isActive) {
                        _unsubscribe(symbol, tf);
                      } else {
                        _subscribe(symbol, tf);
                      }
                    },
                    child: Text(tf, style: const TextStyle(fontSize: 12)),
                  ),
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
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('📸 تصاویر دریافت‌شده', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _receivedImages.length,
              itemBuilder: (context, index) {
                final url = _receivedImages[index];
                final meta = _receivedFilenames[index];
                final parts = meta.split('|');
                final symbol = parts.length > 0 ? parts[0] : '';
                final timeframe = parts.length > 1 ? parts[1] : '';

                return GestureDetector(
                  onTap: () => _showImageFullScreen(url),
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.network(url),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('چارت دریافت‌شده', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('📈 نماد: $symbol', style: const TextStyle(fontSize: 12)),
                              Text('⏱ تایم‌فریم: $timeframe', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
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
