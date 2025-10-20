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

const String SERVER_URL = 'http://178.63.171.244:5000';

final List<String> symbols = [
  'EURUSD','XAUUSD','GBPUSD','USDJPY','USDCHF',
  'AUDUSD','AUDJPY','CADJPY','EURJPY','BTCUSD',
  'ETHUSD','ADAUSD','DowJones','NASDAQ','S&P500',
];

final List<String> timeframes = [
  'M1','M2','M3','M4','M5','M6','M10','M12','M15','M20',
  'M30','H1','H2','H3','H4','H6','H8','H12','D1','W1',
];

// Background handler is kept minimal
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // We do not modify shared prefs here for complexity; main app listens to messages.
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
  String userMode = '0000000'; // 7-bit string
  Map<String, dynamic> symbolPrefs = {}; // symbol -> { "timeframes": ["M1"], "direction": "BUY" }
  List<Map<String, dynamic>> _receivedImages = [];

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
      // Register on server (best-effort)
      try {
        await http.post(Uri.parse('$SERVER_URL/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': _userId, 'fcm_token': _fcmToken}));
      } catch (_) {}
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // When new message arrives, reload images from server
      _loadImagesFromServer();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      _loadImagesFromServer();
    });
  }

  // ---------- Local prefs ----------
  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('mode_7bit') ?? '0000000';
    final symJson = prefs.getString('symbol_prefs') ?? '{}';
    final Map<String, dynamic> s = jsonDecode(symJson);
    setState(() {
      userMode = mode;
      symbolPrefs = s;
    });
  }

  Future<void> _saveLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode_7bit', userMode);
    await prefs.setString('symbol_prefs', jsonEncode(symbolPrefs));
  }

  // ---------- Helper: shouldDisplayImage ----------
  bool _shouldDisplayImageForUser(Map<String, dynamic> image) {
    // image must contain: code_8bit (string length 8), symbol, timeframe
    final code = (image['code_8bit'] ?? '') as String;
    final sym = (image['symbol'] ?? '') as String;
    final tf = (image['timeframe'] ?? '') as String;
    if (code.length < 8) return false;

    // Check if user has preferences for this symbol and timeframe
    final userSym = symbolPrefs[sym];
    if (userSym == null) {
      // if no prefs for symbol, treat as not subscribed => do not show
      return false;
    }
    final List<dynamic> userTfs = userSym['timeframes'] ?? [];
    if (!userTfs.contains(tf)) {
      return false;
    }

    // Direction check: use per-symbol direction
    final String userDir = (userSym['direction'] ?? 'BUY').toString();
    final int dirBit = int.parse(code[0]);
    if (userDir == 'BUY' && dirBit != 0) return false;
    if (userDir == 'SELL' && dirBit != 1) return false;
    // BUY&SELL => any

    // Mode check (7 bits) — userMode is 7-bit string
    for (int i = 0; i < 7; i++) {
      final int userBit = int.parse(userMode[i]);
      final int imgBit = int.parse(code[i + 1]);
      if (userBit == 1 && imgBit != 1) return false;
    }

    return true;
  }

  // ---------- Load images ----------
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
    } catch (e) {
      // ignore errors, optionally show snackbar
    }
  }

  String _extractFilename(String url) {
    try {
      return url.split('/').last;
    } catch (e) {
      return url;
    }
  }

  // ---------- UI helpers (download/delete/fullscreen) ----------
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
      } else {
        // ignore / show
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

  // ---------- Navigate to Settings ----------
  void _openSettings() async {
    // push and wait for potential changes
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(
      userId: _userId,
      userMode: userMode,
      symbolPrefs: symbolPrefs,
      onLocalPrefsChanged: (mode, prefs) async {
        setState(() {
          userMode = mode;
          symbolPrefs = prefs;
        });
        await _saveLocalPrefs();
        await _loadImagesFromServer();
      },
    )));
    // when returned, reload images in case settings changed
    await _loadLocalPrefs();
    await _loadImagesFromServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد سیگنال‌ها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
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
      floatingActionButton: FloatingActionButton(
        onPressed: _loadImagesFromServer,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ---------- SettingsPage ----------
class SettingsPage extends StatefulWidget {
  final String userId;
  final String userMode;
  final Map<String, dynamic> symbolPrefs;
  final Function(String, Map<String, dynamic>) onLocalPrefsChanged;

  const SettingsPage({
    super.key,
    required this.userId,
    required this.userMode,
    required this.symbolPrefs,
    required this.onLocalPrefsChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String localMode; // 7-bit
  late Map<String, dynamic> localSymbolPrefs;

  @override
  void initState() {
    super.initState();
    localMode = widget.userMode;
    localSymbolPrefs = Map<String, dynamic>.from(widget.symbolPrefs);
  }

  Future<void> _saveAndNotify() async {
    // save to shared prefs (caller will also save)
    await widget.onLocalPrefsChanged(localMode, localSymbolPrefs);
  }

  void _openSymbolModal(String symbol) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        // local copies to avoid immediate closure effects
        final prefsForSymbol = Map<String, dynamic>.from(localSymbolPrefs[symbol] ?? {'timeframes': [], 'direction': 'BUY'});
        return StatefulBuilder(builder: (contextModal, setModal) {
          void _toggleTf(String tf) {
            final tfs = List<String>.from(prefsForSymbol['timeframes'] ?? []);
            if (tfs.contains(tf)) {
              tfs.remove(tf);
            } else {
              tfs.add(tf);
            }
            prefsForSymbol['timeframes'] = tfs;
            setModal(() {});
          }

          void _setDirection(String dir) {
            prefsForSymbol['direction'] = dir;
            setModal(() {});
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  // Mode (global) display (readonly here) - if you want to allow per-symbol Mode, adjust
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text("Mode (global): $localMode", style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(height: 8),
                  // Timeframes grid
                  GridView.count(
                    crossAxisCount: 5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: timeframes.map((tf) {
                      final isActive = (prefsForSymbol['timeframes'] as List<dynamic>).contains(tf);
                      return Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: isActive ? Colors.green : Colors.red,
                          ),
                          onPressed: () {
                            _toggleTf(tf);
                          },
                          child: Text(tf, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // Direction buttons under timeframes
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Wrap(
                      spacing: 8,
                      children: ['BUY','SELL','BUY&SELL'].map((pos) {
                        final isActive = prefsForSymbol['direction'] == pos;
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive ? Colors.green : Colors.red,
                          ),
                          onPressed: () {
                            _setDirection(pos);
                          },
                          child: Text(pos),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          // Save to localSymbolPrefs and to shared prefs via onLocalPrefsChanged
                          localSymbolPrefs[symbol] = prefsForSymbol;
                          _saveAndNotify();
                          Navigator.pop(contextModal);
                        },
                        child: const Text('ذخیره محلی'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(contextModal);
                        },
                        child: const Text('لغو'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _openModeSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ModeSettingsPage(
      initialMode: localMode,
      onModeChanged: (newMode) async {
        setState(() => localMode = newMode);
        await _saveAndNotify();
      },
    )));
    // after return, notify parent
    await _saveAndNotify();
  }

  Widget _buildSymbolsWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: symbols.map((s) {
        final has = (localSymbolPrefs[s] != null && (localSymbolPrefs[s]['timeframes'] as List<dynamic>).isNotEmpty);
        return ElevatedButton(
          onPressed: () => _openSymbolModal(s),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: has ? Colors.green : null,
          ),
          child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }

  Future<void> _sendPreferencesToServer() async {
    // Build JSON
    final List<Map<String, dynamic>> syms = [];
    localSymbolPrefs.forEach((key, value) {
      final List<dynamic> tfs = value['timeframes'] ?? [];
      final dir = value['direction'] ?? 'BUY';
      if (tfs.isNotEmpty) {
        syms.add({
          'symbol': key,
          'timeframes': List<String>.from(tfs),
          'direction': dir,
        });
      }
    });
    final payload = {
      'user_id': widget.userId,
      'mode': localMode,
      'symbols': syms,
    };

    try {
      final rsp = await http.post(Uri.parse('$SERVER_URL/save_preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (rsp.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات با موفقیت ارسال شد')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ارسال: ${rsp.statusCode}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildSymbolsWrap(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openModeSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Mode Settings'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _sendPreferencesToServer,
              icon: const Icon(Icons.send),
              label: const Text('ارسال تنظیمات به سرور (جایگزین)'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
            const SizedBox(height: 12),
            const Text('توضیح: تغییرات تایم‌فریم و جهت هر جفت‌ارز بلافاصله ذخیره محلی می‌شود. برای ارسال نهایی از دکمه بالا استفاده کنید.'),
          ],
        ),
      ),
    );
  }
}

// ---------- ModeSettingsPage ----------
class ModeSettingsPage extends StatefulWidget {
  final String initialMode;
  final Function(String) onModeChanged;

  const ModeSettingsPage({super.key, required this.initialMode, required this.onModeChanged});

  @override
  State<ModeSettingsPage> createState() => _ModeSettingsPageState();
}

class _ModeSettingsPageState extends State<ModeSettingsPage> {
  late Map<String, bool> modeMap;
  // Keys order: A1/A2, B, C, D, E, F, G
  final List<String> modeKeys = ['A1','A2','B','C','D','E','F','G'];
  String position = 'BUY'; // this is optional per-symbol; we keep local

  @override
  void initState() {
    super.initState();
    modeMap = {};
    // load from initialMode (7-bit). initialMode length 7 expected
    final init = widget.initialMode.padRight(7, '0').substring(0,7);
    // We map init[0] => A1/A2 encoded as: if init[0]=='1' we treat it as A1 selected (A2=0)
    // But since original design had A1 or A2 single choice, we store two bits interpretation:
    // For simplicity: if init[0] == '1' -> A1 true, A2 false ; else A1 false, A2 true ? 
    // To be consistent with earlier, treat bit0 as A1/A2 where 1 -> A1, 0 -> A2 inactive. We'll expose toggles anyway.
    // Here we will decode as A1 = init[0]=='1', A2 = init[0]=='0' (but user will choose one)
    modeMap['A1'] = init[0] == '1';
    modeMap['A2'] = init[0] == '0' ? false : false; // We'll handle toggle logic instead of direct decode
    // For other bits:
    final others = init.split('');
    // others[0] was A1/A2 bit. set B..G from others[1..6]
    final otherKeys = ['B','C','D','E','F','G'];
    for (int i=0;i<otherKeys.length;i++){
      modeMap[otherKeys[i]] = others.length > i+1 ? others[i+1] == '1' : false;
    }
    // Ensure A2 loaded reasonably: if A1 true -> A2 false; else A1 false.
    if (!modeMap['A1']!) modeMap['A2'] = false;
  }

  String _build7BitString() {
    // Build [A1-or-A2, B, C, D, E, F, G] where first bit means A1 selected(1) or not(0)
    final a1 = (modeMap['A1'] ?? false) ? '1' : '0';
    final bits = [
      a1,
      (modeMap['B'] ?? false) ? '1' : '0',
      (modeMap['C'] ?? false) ? '1' : '0',
      (modeMap['D'] ?? false) ? '1' : '0',
      (modeMap['E'] ?? false) ? '1' : '0',
      (modeMap['F'] ?? false) ? '1' : '0',
      (modeMap['G'] ?? false) ? '1' : '0',
    ];
    return bits.join();
  }

  Future<void> _saveLocalMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = _build7BitString();
    await prefs.setString('mode_7bit', modeStr);
    widget.onModeChanged(modeStr);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mode ذخیره شد')));
  }

  void _toggleMode(String key) {
    setState(() {
      if (key == 'A1') {
        modeMap['A1'] = true;
        modeMap['A2'] = false;
      } else if (key == 'A2') {
        modeMap['A2'] = true;
        modeMap['A1'] = false;
      } else {
        modeMap[key] = !(modeMap[key] ?? false);
      }
    });
  }

  void _setPosition(String pos) {
    setState(() => position = pos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mode Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mode Buttons', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: modeKeys.map((k) {
                final isActive = modeMap[k] ?? false;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.green : Colors.red),
                  onPressed: () => _toggleMode(k),
                  child: Text(k),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Position (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['BUY','SELL','BUY&SELL'].map((p) {
                final isActive = position == p;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.green : Colors.red),
                  onPressed: () => _setPosition(p),
                  child: Text(p),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _saveLocalMode, child: const Text('ذخیره محلی')),
                ElevatedButton(
                  onPressed: () {
                    final modeStr = _build7BitString();
                    widget.onModeChanged(modeStr);
                    Navigator.pop(context);
                  },
                  child: const Text('تأیید و بازگشت'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
