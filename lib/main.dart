// lib/main.dart
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

final List<String> sessions = ['توکیو','لندن','نیویورک','سیدنی'];

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
        if (mounted) setState(() {});
        _controller.play();
      });
    _controller.addListener(() {
      if (_controller.value.position >=
          _controller.value.duration - const Duration(milliseconds: 200)) {
        if (mounted) _goToHome();
      }
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) _goToHome();
    });
  }

  void _goToHome() {
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomePage()));
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
  List<Map<String, dynamic>> _receivedImages = [];
  Map<String,bool> sessionPrefs = {
    'توکیو': false,
    'لندن': false,
    'نیویورک': false,
    'سیدنی': false,
  };

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
    if (mounted) setState(() => _userId = saved!);
  }

  Future<void> _initFirebase() async {
    _fcmToken = (await FirebaseMessaging.instance.getToken()) ?? '';
    if (_fcmToken.isNotEmpty) {
      try {
        await http.post(Uri.parse('$SERVER_URL/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': _userId, 'fcm_token': _fcmToken}));
      } catch (e) {
        print('FCM register error: $e');
      }
    }
    FirebaseMessaging.onMessage.listen((_) => _loadImagesFromServer());
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _loadImagesFromServer());
  }

  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    bool hasLocalMode = prefs.containsKey('mode_7bit');
    bool hasLocalSymbols = prefs.containsKey('symbol_prefs');
    bool hasLocalSessions = prefs.containsKey('session_prefs');

    if (hasLocalMode && hasLocalSymbols && hasLocalSessions) {
      final mode = prefs.getString('mode_7bit') ?? '0000000';
      final symJson = prefs.getString('symbol_prefs') ?? '{}';
      final sessionJson = prefs.getString('session_prefs') ?? '{}';
      
      if (mounted) setState(() {
        userMode = mode;
        symbolPrefs = jsonDecode(symJson);
        final Map<String, dynamic> s = jsonDecode(sessionJson);
        for (var k in s.keys) {
          sessionPrefs[k] = s[k] ?? false;
        }
      });
    } else {
      await _loadPrefsFromServer();
    }
  }

  Future<void> _loadPrefsFromServer() async {
    try {
      final rsp = await http.post(
        Uri.parse('$SERVER_URL/get_user_prefs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}),
      );
      
      if (rsp.statusCode == 200) {
        final data = jsonDecode(rsp.body);
        String mode = data['mode'] ?? '0000000';
        Map<String, dynamic> symbols = data['symbol_prefs'] ?? {};
        Map<String, dynamic> sessions = data['sessions'] ?? {};

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('mode_7bit', mode);
        await prefs.setString('symbol_prefs', jsonEncode(symbols));
        await prefs.setString('session_prefs', jsonEncode(sessions));

        if (mounted) setState(() {
          userMode = mode;
          symbolPrefs = symbols;
          for (var session in this.sessionPrefs.keys.toList()) {
            this.sessionPrefs[session] = sessions[session] == true;
          }
        });
      } else {
        await _saveLocalPrefs();
      }
    } catch (e) {
      print('Load prefs from server error: $e');
      await _saveLocalPrefs();
    }
  }

  Future<void> _saveLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode_7bit', userMode);
    await prefs.setString('symbol_prefs', jsonEncode(symbolPrefs));
    await prefs.setString('session_prefs', jsonEncode(sessionPrefs));

    // ارسال همه تنظیمات به سرور
    try {
      await http.post(
        Uri.parse('$SERVER_URL/update_mode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'mode': userMode}),
      );
      await http.post(
        Uri.parse('$SERVER_URL/update_session_prefs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'sessions': sessionPrefs}),
      );
      await http.post(
        Uri.parse('$SERVER_URL/update_symbol_prefs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'symbol_prefs': symbolPrefs}),
      );
    } catch (e) {
      print('Error saving prefs to server: $e');
    }
  }

  // ---------------- Session Settings ----------------
  void _toggleSession(String session) async {
    final newValue = !(sessionPrefs[session] ?? false);

    try {
      final resp = await http.post(
        Uri.parse('$SERVER_URL/update_session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'session': session, 'value': newValue}),
      );

      if (resp.statusCode == 200) {
        sessionPrefs[session] = newValue;
        await _saveLocalPrefs();
        if (mounted) setState(() {});
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خطا در ثبت سشن. دوباره تلاش کنید')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  void _openSessionModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(builder: (contextModal,setModal){
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: sessions.map((s){
                final selected = sessionPrefs[s] ?? false;
                return ListTile(
                  trailing: Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSession(s),
                  ),
                  title: Text(s, textAlign: TextAlign.right),
                );
              }).toList(),
            ),
          );
        });
      },
    );
  }

  // ---------------- Mode Settings ----------------
  void _openModeSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ModeSettingsPage(
          initialMode: userMode,
          userId: _userId,
          onModeChanged: (newMode) async {
            if (mounted) setState(() => userMode = newMode);
            await _saveLocalPrefs();
            await _loadImagesFromServer();
          },
        );
      },
    );
  }

  // ---------------- Symbol & Image Handling ----------------
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
            'filename': img['filename'] ?? img['image_url'].split('/').last,
          };
        }).toList();
        if (mounted) setState(() {
          _receivedImages = List<Map<String, dynamic>>.from(filtered);
        });
      }
    } catch (e) {
      print('Load images error: $e');
    }
  }

  Future<void> _downloadImage(String url, String symbol, String timeframe) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) return;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final directory = await getApplicationDocumentsDirectory();
        final filename = '${symbol}_${timeframe}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('ذخیره شد: ${file.path}')));
        }
      }
    } catch (e) {
      print('Download error: $e');
    }
  }

  Future<void> _deleteImageForUser(String url) async {
    try {
      await http.post(Uri.parse('$SERVER_URL/delete_image'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': _userId, 'image_url': url}));
      if (mounted) setState(() {
        _receivedImages.removeWhere((i) => i['url'] == url);
      });
    } catch (e) {
      print('Delete error: $e');
    }
  }

  void _showImageFullScreen(String imageUrl, String filename) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: PhotoView(imageProvider: NetworkImage(imageUrl)),
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Amino_First_Hidden'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: SettingsPanel(
              userId: _userId,
              userMode: userMode,
              symbolPrefs: symbolPrefs,
              onLocalPrefsChanged: (mode, prefs) async {
                if (mounted) setState(() {
                  userMode = mode;
                  symbolPrefs = prefs;
                });
                await _saveLocalPrefs();
                await _loadImagesFromServer();
              },
              onSessionSettingsPressed: _openSessionModal,
              onModeSettingsPressed: _openModeSettings,
            ),
          ),
          const Divider(thickness: 2, color: Colors.grey, height: 0),
          Expanded(
            flex: 1,
            child: _receivedImages.isEmpty
                ? const Center(child: Text('هیچ تصویری موجود نیست'))
                : ListView.builder(
                    itemCount: _receivedImages.length,
                    itemBuilder: (context, i) {
                      final img = _receivedImages[i];
                      return Card(
                        margin: const EdgeInsets.all(6),
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
  final String userId;
  final String userMode;
  final Map<String, dynamic> symbolPrefs;
  final Function(String, Map<String, dynamic>) onLocalPrefsChanged;
  final VoidCallback onSessionSettingsPressed;
  final VoidCallback onModeSettingsPressed;

  const SettingsPanel({
    super.key,
    required this.userId,
    required this.userMode,
    required this.symbolPrefs,
    required this.onLocalPrefsChanged,
    required this.onSessionSettingsPressed,
    required this.onModeSettingsPressed,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late String localMode;
  late Map<String, dynamic> localSymbolPrefs;

  @override
  void initState() {
    super.initState();
    localMode = widget.userMode;
    localSymbolPrefs = Map<String, dynamic>.from(widget.symbolPrefs);
  }

  Future<void> _saveAndNotify() async {
    await widget.onLocalPrefsChanged(localMode, localSymbolPrefs);
  }

  void _openSymbolModal(String symbol) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final prefsForSymbol = Map<String, dynamic>.from(
            localSymbolPrefs[symbol] ?? {'timeframes': [], 'direction': 'BUY&SELL'});
        return StatefulBuilder(builder: (contextModal, setModal) {
          void _toggleTf(String tf) async {
            final tfs = List<String>.from(prefsForSymbol['timeframes'] ?? []);
            if (tfs.contains(tf)) {
              tfs.remove(tf);
            } else {
              tfs.add(tf);
            }
            prefsForSymbol['timeframes'] = tfs;
            localSymbolPrefs[symbol] = prefsForSymbol;
            await _saveAndNotify();
            setModal(() {});
          }

          void _setDirection(String dir) async {
            prefsForSymbol['direction'] = dir;
            localSymbolPrefs[symbol] = prefsForSymbol;
            await _saveAndNotify();
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
                          onPressed: () => _toggleTf(tf),
                          child: Text(tf, style: const TextStyle(fontSize: 11)),
                        ),
                      );
                    }).toList(),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ['BUY','SELL','BUY&SELL'].map((pos) {
                      final isActive = prefsForSymbol['direction'] == pos;
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.green : Colors.red),
                        onPressed: () => _setDirection(pos),
                        child: Text(pos),
                      );
                    }).toList(),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: symbols.map((s) {
              return ElevatedButton(
                onPressed: () => _openSymbolModal(s),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: widget.onModeSettingsPressed,
                icon: const Icon(Icons.tune),
                label: const Text('Mode Settings'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.onSessionSettingsPressed,
                icon: const Icon(Icons.access_time),
                label: const Text('Session Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- ModeSettingsPage ----------
class ModeSettingsPage extends StatefulWidget {
  final String initialMode;
  final String userId;
  final Function(String) onModeChanged;

  const ModeSettingsPage({
    super.key,
    required this.initialMode,
    required this.onModeChanged,
    required this.userId,
  });

  @override
  State<ModeSettingsPage> createState() => _ModeSettingsPageState();
}

class _ModeSettingsPageState extends State<ModeSettingsPage> {
  late Map<String, bool> modeMap;
  final List<Map<String, String>> modeItems = [
    {'key': 'A1', 'label': 'هیدن اول'},
    {'key': 'A2', 'label': 'همه هیدن ها'},
    {'key': 'B', 'label': 'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول1'},
    {'key': 'C', 'label': 'دایورجنس نبودن نقطه 2 در مکدی چهاربرابر'},
    {'key': 'D', 'label': 'زده شدن سقف یا کف جدید نسبت به 52 کندل قبل'},
    {'key': 'E', 'label': 'عدم تناسب در نقطه 3 بین مکدی دیفالت و مووینگ60'},
    {'key': 'F', 'label': 'از 2 تا 3 اصلاح مناسبی داشته باشد'},
    {'key': 'G', 'label': 'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول2'},
  ];

  @override
  void initState() {
    super.initState();
    final bits = widget.initialMode.padRight(7, '0').substring(0, 7);
    modeMap = {
      'A1': bits[0] == '1',
      'A2': bits[0] == '0', 
      'B': bits[1] == '1',
      'C': bits[2] == '1',
      'D': bits[3] == '1',
      'E': bits[4] == '1',
      'F': bits[5] == '1',
      'G': bits[6] == '1',
    };
  }

  String _build7BitStringFromMap(Map<String, bool> map) {
    final a1 = map['A1']! ? '1' : '0';
    return [
      a1,
      map['B']! ? '1' : '0',
      map['C']! ? '1' : '0',
      map['D']! ? '1' : '0',
      map['E']! ? '1' : '0',
      map['F']! ? '1' : '0',
      map['G']! ? '1' : '0',
    ].join();
  }

  Future<void> _toggleMode(String key, bool newValue) async {
    final newModeMap = Map<String, bool>.from(modeMap);

    if (key == 'A1') {
      newModeMap['A1'] = newValue;
      newModeMap['A2'] = !newValue;
    } else if (key == 'A2') {
      newModeMap['A2'] = newValue;
      newModeMap['A1'] = !newValue;
    } else {
      newModeMap[key] = newValue;
    }

    final newModeStr = _build7BitStringFromMap(newModeMap);

    try {
      final resp = await http.post(
        Uri.parse('$SERVER_URL/update_mode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.userId, 'mode': newModeStr}),
      );

      if (resp.statusCode == 200) {
        if (mounted) setState(() => modeMap = newModeMap);
        await widget.onModeChanged(newModeStr);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خطا در ثبت مود. دوباره تلاش کنید')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('تنظیمات مود', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            ...modeItems.map((item) {
              final key = item['key']!;
              final label = item['label']!;
              return CheckboxListTile(
                title: Text(label, textAlign: TextAlign.right),
                value: modeMap[key],
                onChanged: (v) {
                  _toggleMode(key, v ?? false);
                },
                controlAffinity: ListTileControlAffinity.trailing,
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
