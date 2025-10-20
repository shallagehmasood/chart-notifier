// main.dart
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
import 'package:video_player/video_player.dart';

const String SERVER_URL = 'http://YOUR_SERVER_HOST:8000'; // ← این را تغییر بده

final List<String> symbols = [
  'EURUSD','XAUUSD','GBPUSD','USDJPY','USDCHF',
  'AUDUSD','AUDJPY','CADJPY','EURJPY','BTCUSD',
  'ETHUSD','ADAUSD','DowJones','NASDAQ','S&P500',
];

final List<String> timeframes = [
  'M1','M2','M3','M4','M5','M6','M10','M12','M15','M20',
  'M30','H1','H2','H3','H4','H6','H8','H12','D1','W1',
];

// ---------- Firebase Background ----------
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: IntroPage(),
  ));
}

// ---------- IntroPage ----------
class IntroPage extends StatefulWidget {
  const IntroPage({super.key});
  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/a.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });

    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        _goToHome();
      }
    });

    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) _goToHome();
    });
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
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
  String _fcmToken = '';
  String userMode = '0000000'; // رشته 7 بیتی محلی (کاربر)
  Map<String, dynamic> symbolPrefs = {}; // نگهداری انتخابهای محلی: symbol -> { timeframes: [], direction: 'BUY' }
  List<Map<String, dynamic>> _receivedImages = [];

  // نگهداری وضعیت "تأیید‌شده توسط سرور" برای تغییر رنگ دکمه‌ها
  Map<String, Set<String>> _confirmedTfs = {}; // symbol -> set(timeframe)
  Map<String, String> _confirmedDirection = {}; // symbol -> 'BUY'/'SELL'/'BUY&SELL'
  String _confirmedMode = '0000000';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  // ---------- init ----------
  Future<void> _initApp() async {
    await _initUserId();
    await _loadLocalPrefs();
    await _initFirebase();
    await _fetchImagesFromServer();
  }

  Future<void> _initUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString('user_id');
    if (saved == null) {
      saved = 'user_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('user_id', saved);
    }
    setState(() => _userId = saved!);
  }

  Future<void> _initFirebase() async {
    _fcmToken = (await FirebaseMessaging.instance.getToken()) ?? '';
    if (_fcmToken.isNotEmpty) {
      try {
        await http.post(Uri.parse('$SERVER_URL/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': _userId, 'fcm_token': _fcmToken}));
      } catch (_) {}
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _fetchImagesFromServer();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      _fetchImagesFromServer();
    });
  }

  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('mode_7bit') ?? '0000000';
    final symJson = prefs.getString('symbol_prefs') ?? '{}';
    final Map<String, dynamic> s = jsonDecode(symJson);
    setState(() {
      userMode = mode;
      _confirmedMode = mode;
      symbolPrefs = s;
      // initialize confirmed maps from saved prefs (we assume they were confirmed previously)
      for (var sym in s.keys) {
        _confirmedTfs[sym] = Set<String>.from(s[sym]['timeframes'] ?? []);
        _confirmedDirection[sym] = s[sym]['direction'] ?? 'BUY&SELL';
      }
    });
  }

  Future<void> _saveLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode_7bit', userMode);
    await prefs.setString('symbol_prefs', jsonEncode(symbolPrefs));
  }

  // ---------- سرور: دریافت تصاویر ----------
  Future<void> _fetchImagesFromServer() async {
    try {
      final rsp = await http.post(
        Uri.parse('$SERVER_URL/images_for_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}),
      );
      if (rsp.statusCode == 200) {
        final data = jsonDecode(rsp.body);
        final List imgs = data['images'] ?? [];
        setState(() {
          // تبدیل به فرمت مورد استفاده در UI
          _receivedImages = imgs.map<Map<String, dynamic>>((img) {
            return {
              'url': img['url'] ?? img['image_url'] ?? img['imageUrl'],
              'symbol': img['symbol'],
              'timeframe': img['timeframe'],
              'code_8bit': img['code_8bit'],
              'filename': img['filename'] ?? (img['image_url'] ?? '').split('/').last,
              'timestamp': img['timestamp'] != null ? DateTime.tryParse(img['timestamp'].toString()) : null,
            };
          }).toList();
        });
      }
    } catch (e) {
      // ignore یا نمایش پیام در صورت نیاز
    }
  }

  // ---------- دانلود تصویر ----------
  Future<void> _downloadImage(String url, String symbol, String timeframe) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دسترسی حافظه نیاز است')));
      return;
    }
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final directory = await getExternalStorageDirectory();
        final filename = '${symbol}_${timeframe}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final path = '${directory!.path}/$filename';
        final file = File(path);
        await file.writeAsBytes(bytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره شد: $path')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در دانلود')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  // ---------- حذف تصویر ----------
  Future<void> _deleteImageForUser(String url) async {
    try {
      final resp = await http.post(
        Uri.parse('$SERVER_URL/delete_image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'image_url': url}),
      );
      if (resp.statusCode == 200) {
        setState(() {
          _receivedImages.removeWhere((img) => img['url'] == url);
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در حذف تصویر')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  // ---------- ارسال تنظیمات یک نماد به سرور ----------
  // payload مطابق SavePreferencesModel سرور
  Future<bool> _sendPreferenceToServer(String symbol) async {
    final payload = {
      'user_id': _userId,
      'mode': userMode,
      'symbols': [
        {
          'symbol': symbol,
          'timeframes': List<String>.from(symbolPrefs[symbol]?['timeframes'] ?? []),
          'direction': symbolPrefs[symbol]?['direction'] ?? 'BUY&SELL',
        }
      ],
    };

    try {
      final rsp = await http.post(
        Uri.parse('$SERVER_URL/save_preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (rsp.statusCode == 200) {
        // در صورت موفقیت: mark confirmed for that symbol
        setState(() {
          _confirmedTfs[symbol] = Set<String>.from(symbolPrefs[symbol]?['timeframes'] ?? []);
          _confirmedDirection[symbol] = symbolPrefs[symbol]?['direction'] ?? 'BUY&SELL';
        });
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // ---------- ارسال مود به سرور ----------
  Future<bool> _sendModeToServer() async {
    final payload = {'user_id': _userId, 'mode': userMode};
    try {
      final rsp = await http.post(
        Uri.parse('$SERVER_URL/save_preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (rsp.statusCode == 200) {
        setState(() {
          _confirmedMode = userMode;
        });
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // ---------- نمایش تمام‌صفحه تصویر ----------
  void _showImageFullScreen(String imageUrl, String filename) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: PhotoView(imageProvider: NetworkImage(imageUrl)),
      );
    }));
  }

  // ---------- ویجت مود (7-bit) ----------
  Widget _buildModeWidget() {
    final modeKeys = ['A','B','C','D','E','F','G']; // نمایشی برای کاربر
    // map محلی برای ساخت رشته پس از تغییر
    Map<int, bool> tmp = {};
    final init = userMode.padRight(7, '0').substring(0, 7);
    for (int i = 0; i < 7; i++) tmp[i] = init[i] == '1';

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مود (7-bit)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (i) {
                final isConfirmed = _confirmedMode.length >= 7 && _confirmedMode[i] == '1';
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () async {
                    // toggle locally
                    tmp[i] = !(tmp[i] ?? false);
                    // rebuild userMode: رشته 7 بیتی
                    final bits = List.generate(7, (j) => tmp[j]! ? '1' : '0');
                    userMode = bits.join();
                    await _saveLocalPrefs();
                    // ارسال مود به سرور و در صورت موفق تغییر رنگ (confirmed)
                    final ok = await _sendModeToServer();
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در ثبت مود در سرور')));
                    }
                  },
                  child: Text(modeKeys[i], style: const TextStyle(fontSize: 12)),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- ویجت جفت‌ارزها (جمع‌وجور) ----------
  Widget _buildSymbolsWidget() {
    return Column(
      children: symbols.map((s) {
        final prefs = symbolPrefs[s] ?? {'timeframes': <String>[], 'direction': 'BUY&SELL'};
        final confirmedTfs = _confirmedTfs[s] ?? <String>{};
        final confirmedDir = _confirmedDirection[s] ?? 'BUY&SELL';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold))),
                    // quick indicator if any tf confirmed
                    if ((confirmedTfs.isNotEmpty || confirmedDir != 'BUY&SELL'))
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  ],
                ),
                const SizedBox(height: 6),
                // تایم‌فریم‌ها
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: timeframes.map((tf) {
                    final isSelected = (prefs['timeframes'] as List).contains(tf);
                    final isConfirmed = confirmedTfs.contains(tf);
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                        minimumSize: const Size(40, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      ),
                      onPressed: () async {
                        // تغییر محلی (تغییر وضعیت انتخاب شده ولی هنوز رنگ تغییر نمی‌کند تا سرور تایید کند)
                        final tfs = List<String>.from(prefs['timeframes']);
                        if (tfs.contains(tf)) {
                          tfs.remove(tf);
                        } else {
                          tfs.add(tf);
                        }
                        prefs['timeframes'] = tfs;
                        symbolPrefs[s] = prefs;
                        await _saveLocalPrefs();

                        // ارسال به سرور و در صورت موفق set confirmed برای آن tf
                        final ok = await _sendPreferenceToServer(s);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در ثبت تایم‌فریم در سرور')));
                        }
                      },
                      child: Text(tf, style: const TextStyle(fontSize: 11)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                // جهت
                Wrap(
                  spacing: 6,
                  children: ['BUY', 'SELL', 'BUY&SELL'].map((dir) {
                    final isSelected = prefs['direction'] == dir;
                    final isConfirmed = confirmedDir == dir;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () async {
                        prefs['direction'] = dir;
                        symbolPrefs[s] = prefs;
                        await _saveLocalPrefs();

                        final ok = await _sendPreferenceToServer(s);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در ثبت جهت در سرور')));
                        }
                      },
                      child: Text(dir, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------- لیست تصاویر ----------
  Widget _buildImageList() {
    if (_receivedImages.isEmpty) {
      return const Center(child: Text('هیچ تصویری برای نمایش نیست'));
    }
    return ListView.builder(
      itemCount: _receivedImages.length,
      itemBuilder: (context, index) {
        final img = _receivedImages[index];
        final tsText = img['timestamp'] != null ? img['timestamp'].toString() : '—';
        final filename = img['filename'] ?? img['url'].split('/').last;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _showImageFullScreen(img['url'], filename),
                child: Image.network(img['url'], fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("جفت ارز: ${img['symbol']}"),
                    Text("تایم فریم: ${img['timeframe']}"),
                    Text("زمان: $tsText"),
                    Text("کد ۸ بیتی: ${img['code_8bit']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _downloadImage(img['url'], img['symbol'], img['timeframe']),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('دانلود', style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _deleteImageForUser(img['url']),
                          icon: const Icon(Icons.delete, size: 16),
                          label: const Text('حذف', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد سیگنال‌ها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchImagesFromServer,
          )
        ],
      ),
      body: Column(
        children: [
          // نیمه بالایی: تنظیمات
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildModeWidget(),
                  _buildSymbolsWidget(),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // نیمه پایینی: تصاویر
          Expanded(
            flex: 3,
            child: _buildImageList(),
          ),
        ],
      ),
    );
  }
}
