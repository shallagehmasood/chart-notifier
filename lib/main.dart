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
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
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
  String userMode = '0000000';
  Map<String, dynamic> symbolPrefs = {};
  Map<String, bool> sessionPrefs = {
    'Tokyo': false,
    'London': false,
    'New York': false,
    'Sydney': false
  };
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
      try {
        await http.post(Uri.parse('$SERVER_URL/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': _userId, 'fcm_token': _fcmToken}));
      } catch (_) {}
    }
    FirebaseMessaging.onMessage.listen((_) => _loadImagesFromServer());
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _loadImagesFromServer());
  }

  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('mode_7bit') ?? '0000000';
    final symJson = prefs.getString('symbol_prefs') ?? '{}';
    final sessJson = prefs.getString('session_prefs') ?? '{}';
    setState(() {
      userMode = mode;
      symbolPrefs = jsonDecode(symJson);
      sessionPrefs = Map<String, bool>.from(jsonDecode(sessJson) ?? sessionPrefs);
    });
  }

  Future<void> _saveLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode_7bit', userMode);
    await prefs.setString('symbol_prefs', jsonEncode(symbolPrefs));
    await prefs.setString('session_prefs', jsonEncode(sessionPrefs));
  }

  bool _shouldDisplayImageForUser(Map<String, dynamic> image) {
    final code = (image['code_8bit'] ?? '') as String;
    final sym = (image['symbol'] ?? '') as String;
    final tf = (image['timeframe'] ?? '') as String;
    if (code.length < 8) return false;

    final userSym = symbolPrefs[sym];
    if (userSym == null) return false;

    final List<dynamic> userTfs = userSym['timeframes'] ?? [];
    if (!userTfs.contains(tf)) return false;

    final String userDir = (userSym['direction'] ?? 'BUY&SELL').toString();
    final int dirBit = int.parse(code[0]);
    if (userDir == 'BUY' && dirBit != 0) return false;
    if (userDir == 'SELL' && dirBit != 1) return false;

    for (int i = 0; i < 7; i++) {
      final int userBit = int.parse(userMode[i]);
      final int imgBit = int.parse(code[i + 1]);
      if (userBit == 1 && imgBit != 1) return false;
    }
    return true;
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
            'filename': img['filename'] ?? _extractFilename(img['image_url']),
          };
        }).toList();
        setState(() {
          _receivedImages = List<Map<String, dynamic>>.from(filtered);
        });
      }
    } catch (_) {}
  }

  String _extractFilename(String url) => url.split('/').last;

  Future<void> _downloadImage(String url, String symbol, String timeframe) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) return;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final directory = await getExternalStorageDirectory();
        final filename = '${symbol}_${timeframe}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${directory!.path}/$filename');
        await file.writeAsBytes(bytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      }
    } catch (e) {}
  }

  Future<void> _deleteImageForUser(String url) async {
    try {
      await http.post(Uri.parse('$SERVER_URL/delete_image'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': _userId, 'image_url': url}));
      setState(() {
        _receivedImages.removeWhere((i) => i['url'] == url);
      });
    } catch (_) {}
  }

  void _showImageFullScreen(String imageUrl, String filename) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: PhotoView(imageProvider: NetworkImage(imageUrl)),
      );
    }));
  }

  void _openSettingsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettingsPanel(
        userMode: userMode,
        symbolPrefs: symbolPrefs,
        sessionPrefs: sessionPrefs,
        onLocalPrefsChanged: (mode, prefs) async {
          // ابتدا تغییرات را به سرور ارسال کن
          final prevMode = userMode;
          final prevPrefs = Map<String, dynamic>.from(symbolPrefs);
          final prevSession = Map<String, bool>.from(sessionPrefs);
          try {
            final rsp = await http.post(
              Uri.parse('$SERVER_URL/save_preferences'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': _userId,
                'mode': mode,
                'symbol_prefs': prefs,
                'session_prefs': sessionPrefs
              }),
            );
            if (rsp.statusCode == 200) {
              setState(() {
                userMode = mode;
                symbolPrefs = prefs;
              });
              await _saveLocalPrefs();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved')));
            } else {
              throw Exception('Server error');
            }
          } catch (e) {
            // بازگردانی حالت قبلی
            setState(() {
              userMode = prevMode;
              symbolPrefs = prevPrefs;
              sessionPrefs = prevSession;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save preferences')));
          }
        },
        onSessionPrefsChanged: (newSession) async {
          final prevSession = Map<String, bool>.from(sessionPrefs);
          try {
            final rsp = await http.post(
              Uri.parse('$SERVER_URL/save_preferences'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': _userId,
                'mode': userMode,
                'symbol_prefs': symbolPrefs,
                'session_prefs': newSession
              }),
            );
            if (rsp.statusCode == 200) {
              setState(() {
                sessionPrefs = newSession;
              });
              await _saveLocalPrefs();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session saved')));
            } else {
              throw Exception('Server error');
            }
          } catch (e) {
            setState(() {
              sessionPrefs = prevSession;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save session')));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Center(child: Text('Amino_First_Hidden')),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: SettingsPanel(
              userMode: userMode,
              symbolPrefs: symbolPrefs,
              sessionPrefs: sessionPrefs,
              onLocalPrefsChanged: (m, s) async {},
              onSessionPrefsChanged: (s) async {},
            ),
          ),
          Container(height: 1, color: Colors.grey), // خط وسط
          Expanded(
            flex: 1,
            child: _receivedImages.isEmpty
                ? const Center(child: Text('??? ?????? ???? ????? ????'))
                : ListView.builder(
                    itemCount: _receivedImages.length,
                    itemBuilder: (context, i) {
                      final img = _receivedImages[i];
                      return Card(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () => _showImageFullScreen(img['url'], img['filename']),
                              child: Image.network(img['url'], fit: BoxFit.cover),
                            ),
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

// ---------- SettingsPanel ----------
class SettingsPanel extends StatefulWidget {
  final String userMode;
  final Map<String, dynamic> symbolPrefs;
  final Map<String, bool> sessionPrefs;
  final Function(String, Map<String, dynamic>) onLocalPrefsChanged;
  final Function(Map<String, bool>) onSessionPrefsChanged;

  const SettingsPanel({
    super.key,
    required this.userMode,
    required this.symbolPrefs,
    required this.sessionPrefs,
    required this.onLocalPrefsChanged,
    required this.onSessionPrefsChanged,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late String localMode;
  late Map<String, dynamic> localSymbolPrefs;
  late Map<String, bool> localSessionPrefs;

  final Map<String, String> modeOptionText = {
    'A1': 'آن',
    'A2': 'هیدن اول',
    'B': 'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول1',
    'C': 'دایورجنس نبودن نقطه 2 در مکدی چهاربرابر',
    'D': 'زده شدن سقف یا کف جدید نسبت به 52 کندل قبل',
    'E': 'عدم تناسب در نقطه 3 بین مکدی دیفالت و مووینگ60',
    'F': 'از 2 تا 3 اصلاح مناسبی داشته باشد',
    'G': 'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول2',
  };

  @override
  void initState() {
    super.initState();
    localMode = widget.userMode;
    localSymbolPrefs = Map<String, dynamic>.from(widget.symbolPrefs);
    localSessionPrefs = Map<String, bool>.from(widget.sessionPrefs);
  }

  Future<void> _saveModeChanges() async {
    await widget.onLocalPrefsChanged(localMode, localSymbolPrefs);
  }

  Future<void> _saveSessionChanges() async {
    await widget.onSessionPrefsChanged(localSessionPrefs);
  }

  void _openModeSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (contextModal, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: modeOptionText.entries.map((entry) {
                    final key = entry.key;
                    final text = entry.value;
                    final isChecked = localModePad()[key]!;
                    return CheckboxListTile(
                      title: Text(text),
                      value: isChecked,
                      onChanged: (val) async {
                        setModal(() {
                          _toggleMode(key);
                        });
                        await _saveModeChanges();
                      },
                    );
                  }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSessionSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (contextModal, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: localSessionPrefs.keys.map((sess) {
                    return CheckboxListTile(
                      title: Text(sess),
                      value: localSessionPrefs[sess],
                      onChanged: (val) async {
                        setModal(() {
                          localSessionPrefs[sess] = val ?? false;
                        });
                        await _saveSessionChanges();
                      },
                    );
                  }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, bool> localModePad() {
    // طول 7
    final bits = localMode.padRight(7, '0').substring(0,7);
    final map = <String, bool>{};
    map['A1'] = bits[0]=='1';
    map['A2'] = bits[1]=='1';
    map['B'] = bits[2]=='1';
    map['C'] = bits[3]=='1';
    map['D'] = bits[4]=='1';
    map['E'] = bits[5]=='1';
    map['F'] = bits[6]=='1';
    map['G'] = bits.length>7 ? bits[7]=='1':false;
    return map;
  }

  void _toggleMode(String key) {
    final modeMap = localModePad();
    modeMap[key] = !(modeMap[key] ?? false);
    // ساختن رشته 7 بیتی
    final bits = [
      modeMap['A1']! ? '1' : '0',
      modeMap['A2']! ? '1' : '0',
      modeMap['B']! ? '1' : '0',
      modeMap['C']! ? '1' : '0',
      modeMap['D']! ? '1' : '0',
      modeMap['E']! ? '1' : '0',
      modeMap['F']! ? '1' : '0',
    ];
    localMode = bits.join();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Mode Settings'),
                  onPressed: _openModeSettings,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Session Settings'),
                  onPressed: _openSessionSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
