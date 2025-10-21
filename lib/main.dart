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

const String SERVER_URL = 'http://178.63.171.244:5000'; // ← این را تغییر بده

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

// ---------- HomePage بازنویسی شده ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _userId = '';
  String _fcmToken = '';
  String userMode = '0000000'; // 7-bit string
  Map<String, dynamic> symbolPrefs = {}; // symbol -> { "timeframes": ["M1"], "direction": "BUY&SELL" }
  List<Map<String, dynamic>> _receivedImages = [];

  // برای ردیابی وضعیت ثبت سرور
  Map<String, Set<String>> _confirmedTfs = {}; // symbol -> set of confirmed timeframes
  Map<String, String> _confirmedDirection = {}; // symbol -> confirmed direction
  String _confirmedMode = ''; // مود تایید شده سرور

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _initUserId();
    await _loadLocalPrefs();
    await _initFirebase();
    await _loadImagesFromServer();
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
      _loadImagesFromServer();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      _loadImagesFromServer();
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

  Future<void> _loadImagesFromServer() async {
    try {
      final rsp = await http.post(
        Uri.parse('$SERVER_URL/images_for_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}),
      );
      if (rsp.statusCode == 200) {
        final data = jsonDecode(rsp.body);
        final List imgs = data['images'] ?? [];
        final filtered = imgs.where((img) => _shouldDisplayImageForUser(img)).map((img) {
          return {
            'url': img['image_url'],
            'symbol': img['symbol'],
            'timeframe': img['timeframe'],
            'code_8bit': img['code_8bit'],
            'filename': img['filename'] ?? _extractFilename(img['image_url']),
            'timestamp': img['timestamp'] != null
                ? DateTime.fromMillisecondsSinceEpoch(img['timestamp']).toLocal()
                : null,
          };
        }).toList();
        setState(() {
          _receivedImages = List<Map<String, dynamic>>.from(filtered);
        });
      }
    } catch (e) {}
  }

  String _extractFilename(String url) {
    try {
      return url.split('/').last;
    } catch (e) {
      return url;
    }
  }
  // ---------- Helpers برای فیلتر نمایش تصویر ----------
  bool _shouldDisplayImageForUser(Map<String, dynamic> img) {
    final code = img['code_8bit'] ?? '00000000';
    if (code.length < 8) return false;

    // بیت 0 = جهت BUY/SELL
    final direction = symbolPrefs[img['symbol']]?['direction'] ?? 'BUY&SELL';
    if (direction == 'BUY' && code[0] != '0') return false;
    if (direction == 'SELL' && code[0] != '1') return false;
    // اگر BUY&SELL باشد، اهمیتی ندارد

    // بیت‌های 1 تا 7 بر اساس userMode (تنظیم کاربر)
    for (int i = 0; i < 7; i++) {
      final userBit = userMode[i];
      final imgBit = code[i + 1];
      // اگر کاربر بیت را 1 انتخاب کرده ولی در تصویر 0 است → رد
      if (userBit == '1' && imgBit != '1') return false;
      // اگر کاربر بیت را 0 انتخاب کرده → هر دو حالت قابل قبول است
    }

    return true;
  }

  // ---------- تابع دانلود تصویر ----------
  Future<void> _downloadImage(String url, String symbol, String timeframe) async {
    ...

  Future<void> _downloadImage(String url, String symbol, String timeframe) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied')));
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download error: $e')));
    }
  }

  Future<void> _deleteImageForUser(String url) async {
    try {
      final resp = await http.post(Uri.parse('$SERVER_URL/delete_image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'image_url': url}),
      );
      if (resp.statusCode == 200) {
        setState(() {
          _receivedImages.removeWhere((i) => i['url'] == url);
        });
        _loadImagesFromServer();
      }
    } catch (e) {}
  }

  void _showImageFullScreen(String imageUrl, String filename) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: PhotoView(imageProvider: NetworkImage(imageUrl)),
      );
    }));
  }

  // ---------- Helpers برای ثبت خودکار به سرور ----------
  Future<void> _sendPreferenceToServer(String symbol) async {
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
      final rsp = await http.post(Uri.parse('$SERVER_URL/save_preferences'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload));
      if (rsp.statusCode == 200) {
        // اگر موفق بود، رنگ دکمه‌ها تایید شود
        setState(() {
          _confirmedTfs[symbol] = Set<String>.from(symbolPrefs[symbol]?['timeframes'] ?? []);
          _confirmedDirection[symbol] = symbolPrefs[symbol]?['direction'] ?? 'BUY&SELL';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا: تنظیمات ثبت نشد')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _sendModeToServer() async {
    final payload = {
      'user_id': _userId,
      'mode': userMode,
    };
    try {
      final rsp = await http.post(Uri.parse('$SERVER_URL/save_preferences'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload));
      if (rsp.statusCode == 200) {
        setState(() {
          _confirmedMode = userMode;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا: مود ثبت نشد')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  // ---------- UI نیمه بالایی ----------
  Widget _buildSymbolsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: symbols.map((s) {
        final prefs = symbolPrefs[s] ?? {'timeframes': <String>[], 'direction': 'BUY&SELL'};
        final confirmedTfs = _confirmedTfs[s] ?? <String>{};
        final confirmedDir = _confirmedDirection[s] ?? 'BUY&SELL';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                // تایم فریم‌ها
                Wrap(
                  spacing: 4,
                  children: timeframes.map((tf) {
                    final isSelected = (prefs['timeframes'] as List).contains(tf);
                    final isConfirmed = confirmedTfs.contains(tf);
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(40, 28),
                      ),
                      onPressed: () {
                        // تغییر محلی
                        final tfs = List<String>.from(prefs['timeframes']);
                        if (tfs.contains(tf)) {
                          tfs.remove(tf);
                        } else {
                          tfs.add(tf);
                        }
                        prefs['timeframes'] = tfs;
                        symbolPrefs[s] = prefs;
                        _saveLocalPrefs();
                        // ارسال به سرور
                        _sendPreferenceToServer(s);
                        setState(() {}); // برای refresh UI
                      },
                      child: Text(tf, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                // جهت
                Wrap(
                  spacing: 4,
                  children: ['BUY', 'SELL', 'BUY&SELL'].map((dir) {
                    final isSelected = prefs['direction'] == dir;
                    final isConfirmed = confirmedDir == dir;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      onPressed: () {
                        prefs['direction'] = dir;
                        symbolPrefs[s] = prefs;
                        _saveLocalPrefs();
                        _sendPreferenceToServer(s);
                        setState(() {});
                      },
                      child: Text(dir),
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

  Widget _buildModeSettings() {
    final modeKeys = ['A1','B','C','D','E','F','G'];
    Map<String,bool> modeMap = {};
    final init = userMode.padRight(7,'0').substring(0,7);
    for (int i=0;i<7;i++){
      modeMap[modeKeys[i]] = init[i]=='1';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mode 7-bit', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: modeKeys.map((k){
                final isConfirmed = (_confirmedMode.length>=7 && _confirmedMode[modeKeys.indexOf(k)]=='1');
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConfirmed ? Colors.green : Colors.grey,
                  ),
                  onPressed: (){
                    modeMap[k] = !(modeMap[k] ?? false);
                    // بازسازی رشته 7 بیتی
                    final bits = modeKeys.map((mk)=> modeMap[mk]! ? '1':'0').toList();
                    userMode = bits.join();
                    _saveLocalPrefs();
                    _sendModeToServer();
                    setState(() {});
                  },
                  child: Text(k),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد سیگنال‌ها'),
      ),
      body: Column(
        children: [
          // ---------- نیمه بالایی: تنظیمات ----------
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildModeSettings(),
                  _buildSymbolsSettings(),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: Colors.black),

          // ---------- نیمه پایین: تصاویر ----------
          Expanded(
            flex: 3,
            child: _receivedImages.isEmpty
                ? const Center(child: Text('هیچ تصویری برای نمایش نیست'))
                : ListView.builder(
                    itemCount: _receivedImages.length,
                    itemBuilder: (context, index) {
                      final img = _receivedImages[index];
                      final timestamp = img['timestamp'] as DateTime?;
                      final tsText = timestamp != null ? timestamp.toString() : '—';
                      final filename = img['filename'] ?? _extractFilename(img['url']);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _showImageFullScreen(img['url'], filename),
                              child: Image.network(img['url'], fit: BoxFit.cover),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("جفت ارز: ${img['symbol']}"),
                                  Text("تایم فریم: ${img['timeframe']}"),
                                  Text("زمان: $tsText"),
                                  Text("نام تصویر: $filename", style: const TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _downloadImage(img['url'], img['symbol'], img['timeframe']),
                                        icon: const Icon(Icons.download),
                                        label: const Text('دانلود'),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () => _deleteImageForUser(img['url']),
                                        icon: const Icon(Icons.delete),
                                        label: const Text('حذف'),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      ),
                                    ],
                                  )
                                ],
                              ),
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

