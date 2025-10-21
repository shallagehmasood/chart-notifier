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
        setState(() {});
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
    final sessionJson = prefs.getString('session_prefs') ?? '{}';
    setState(() {
      userMode = mode;
      symbolPrefs = jsonDecode(symJson);
      if(sessionJson.isNotEmpty){
        final Map<String,dynamic> s = jsonDecode(sessionJson);
        for(var k in s.keys){
          sessionPrefs[k] = s[k];
        }
      }
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
            'filename': img['filename'] ?? img['image_url'].split('/').last,
          };
        }).toList();
        setState(() {
          _receivedImages = List<Map<String, dynamic>>.from(filtered);
        });
      }
    } catch (_) {}
  }

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
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('ذخیره شد: ${file.path}')));
        }
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
                  leading: Checkbox(
                    value: selected,
                    onChanged: (v){
                      setModal(()=>sessionPrefs[s] = v ?? false);
                      _saveLocalPrefs();
                    },
                  ),
                  title: Text(s),
                  onTap: (){
                    setModal(()=>sessionPrefs[s] = !(sessionPrefs[s]??false));
                    _saveLocalPrefs();
                  },
                );
              }).toList(),
            ),
          );
        });
      },
    );
  }

  void _openModeSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ModeSettingsBottomSheet(
          initialMode: userMode,
          onModeChanged: (newMode) async {
            setState(() {
              userMode = newMode;
            });
            await _saveLocalPrefs();
            await _loadImagesFromServer();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Amino_First_Hidden')),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: SettingsPanel(
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
              onSessionSettingsPressed: _openSessionModal,
              onModeSettingsPressed: _openModeSettings,
            ),
          ),
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

// ---------- ModeSettingsBottomSheet ----------
class ModeSettingsBottomSheet extends StatefulWidget {
  final String initialMode;
  final Function(String) onModeChanged;

  const ModeSettingsBottomSheet({super.key, required this.initialMode, required this.onModeChanged});

  @override
  State<ModeSettingsBottomSheet> createState() => _ModeSettingsBottomSheetState();
}

class _ModeSettingsBottomSheetState extends State<ModeSettingsBottomSheet> {
  late List<bool> modeValues;
  final List<String> modeLabels = [
    'همه هیدن ها',
    'هیدن اول',
    'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول1',
    'دایورجنس نبودن نقطه 2 در مکدی چهاربرابر',
    'زده شدن سقف یا کف جدید نسبت به 52کندل قبل',
    'عدم تناسب در نقطه 3 بین مکدی دیفالت و مووینگ60',
    'از 2 تا 3 اصلاح مناسبی داشته باشد',
    'دایورجنس نبودن نقطه 2 در مکدی دیفالت لول2',
  ];

  @override
  void initState() {
    super.initState();
    modeValues = List.generate(modeLabels.length, (_) => false);

    final bits = widget.initialMode.padRight(7, '0').substring(0,7);
    for (int i = 0; i < bits.length && i < modeValues.length; i++) {
      modeValues[i] = bits[i] == '1';
    }
  }

  String _build7BitString() {
    final bits = modeValues.map((v) => v ? '1' : '0').toList();
    return bits.join().substring(0,7);
  }

  void _toggleMode(int index) async {
    setState(() {
      modeValues[index] = !modeValues[index];
    });
    final modeStr = _build7BitString();
    await widget.onModeChanged(modeStr);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          int columns = constraints.maxWidth ~/ 160;
          columns = columns < 1 ? 1 : columns;

          return SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(modeLabels.length, (index) {
                final isActive = modeValues[index];
                return SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                  child: ElevatedButton(
                    onPressed: () => _toggleMode(index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.green : Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      modeLabels[index],
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
