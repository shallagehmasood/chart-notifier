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
  String userMode = '0000000'; // 7-bit string
  Map<String, dynamic> symbolPrefs = {}; // symbol -> { "timeframes": ["M1"], "direction": "BUY&SELL" }
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
      symbolPrefs = s;
    });
  }

  Future<void> _saveLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mode_7bit', userMode);
    await prefs.setString('symbol_prefs', jsonEncode(symbolPrefs));
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

  void _openSettings() async {
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

    // مقداردهی اولیه برای جفت‌ارزها
    for (var s in symbols) {
      if (!localSymbolPrefs.containsKey(s)) {
        localSymbolPrefs[s] = {
          'timeframes': <String>[],
          'direction': 'BUY&SELL',
        };
      } else {
        if (localSymbolPrefs[s]['direction'] == null) {
          localSymbolPrefs[s]['direction'] = 'BUY&SELL';
        }
      }
    }
  }

  Future<void> _saveLocalPrefs() async {
    await widget.onLocalPrefsChanged(localMode, localSymbolPrefs);
  }

  // ---------- Symbol Modal ----------
  void _openSymbolModal(String symbol) {
    final prefsForSymbol = Map<String, dynamic>.from(localSymbolPrefs[symbol]!);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(builder: (contextModal, setModal) {
          void _toggleTf(String tf) {
            final tfs = List<String>.from(prefsForSymbol['timeframes']);
            if (tfs.contains(tf)) {
              tfs.remove(tf);
            } else {
              tfs.add(tf);
            }
            prefsForSymbol['timeframes'] = tfs;
            localSymbolPrefs[symbol] = prefsForSymbol;
            _saveLocalPrefs();
            setModal(() {});
          }

          void _setDirection(String dir) {
            prefsForSymbol['direction'] = dir;
            localSymbolPrefs[symbol] = prefsForSymbol;
            _saveLocalPrefs();
            setModal(() {});
          }

          if (prefsForSymbol['direction'] == null) {
            prefsForSymbol['direction'] = 'BUY&SELL';
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.95,
              minChildSize: 0.3,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 12),
                        // تایم فریم‌ها
                        GridView.count(
                          crossAxisCount: 5,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: timeframes.map((tf) {
                            final isActive = (prefsForSymbol['timeframes'] as List).contains(tf);
                            return Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: isActive ? Colors.green : Colors.red,
                                ),
                                onPressed: () => _toggleTf(tf),
                                child: Text(tf, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        // جهت (Buy/Sell/Buy&Sell)
                        Wrap(
                          spacing: 8,
                          children: ['BUY','SELL','BUY&SELL'].map((pos) {
                            final isActive = prefsForSymbol['direction'] == pos;
                            return ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isActive ? Colors.green : Colors.red,
                              ),
                              onPressed: () => _setDirection(pos),
                              child: Text(pos),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text('برای خروج صفحه را به سمت پایین بکشید'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        });
      },
    );
  }

  // ---------- Mode Settings ----------
  void _openModeSettings() {
    final modeKeys = ['A1','A2','B','C','D','E','F','G'];
    Map<String,bool> modeMap = {};
    final init = localMode.padRight(7,'0').substring(0,7);

    // null-safe
    modeMap['A1'] = init[0]=='1';
    modeMap['A2'] = !(modeMap['A1'] ?? false);
    final others = ['B','C','D','E','F','G'];
    for (int i=0;i<others.length;i++){
      modeMap[others[i]] = init.length>i+1 ? init[i+1]=='1' : false;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(builder: (contextModal,setModal){
          void _toggleMode(String key){
            if(key=='A1'){modeMap['A1']=true; modeMap['A2']=false;}
            else if(key=='A2'){modeMap['A2']=true; modeMap['A1']=false;}
            else{modeMap[key]=!(modeMap[key] ?? false);}
            setModal((){});
            _build7BitString(modeMap);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(contextModal).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              maxChildSize: 0.9,
              minChildSize: 0.3,
              builder: (context,scrollController){
                return Container(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mode Buttons', style: TextStyle(fontWeight: FontWeight.bold,fontSize: 16)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: modeKeys.map((k){
                            final isActive = modeMap[k] ?? false;
                            return ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: isActive?Colors.green:Colors.red),
                              onPressed: ()=>_toggleMode(k),
                              child: Text(k),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text('برای خروج صفحه را به سمت پایین بکشید'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        });
      },
    );
  }

  String _build7BitString(Map<String,bool> modeMap){
    final bits = [
      (modeMap['A1'] ?? false)?'1':'0',
      (modeMap['B'] ?? false)?'1':'0',
      (modeMap['C'] ?? false)?'1':'0',
      (modeMap['D'] ?? false)?'1':'0',
      (modeMap['E'] ?? false)?'1':'0',
      (modeMap['F'] ?? false)?'1':'0',
      (modeMap['G'] ?? false)?'1':'0',
    ];
    localMode = bits.join();
    _saveLocalPrefs();
    return localMode;
  }

  // ---------- Send preferences ----------
  Future<void> _sendPreferencesToServer() async {
    final backupPrefs = Map<String,dynamic>.from(localSymbolPrefs);
    final backupMode = localMode;

    final List<Map<String,dynamic>> syms = [];
    localSymbolPrefs.forEach((key,value){
      final tfs = value['timeframes'] ?? [];
      final dir = value['direction'] ?? 'BUY&SELL';
      if(tfs.isNotEmpty){
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

    try{
      final rsp = await http.post(Uri.parse('$SERVER_URL/save_preferences'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode(payload),
      );
      if(rsp.statusCode==200){
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات با موفقیت ارسال شد')));
      }else{
        setState((){
          localSymbolPrefs = backupPrefs;
          localMode = backupMode;
        });
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا: تنظیمات ثبت نشد')));
      }
    }catch(e){
      setState((){
        localSymbolPrefs = backupPrefs;
        localMode = backupMode;
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  // ---------- UI ----------
  Widget _buildSymbolsWrap(){
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: symbols.map((s){
        return ElevatedButton(
          onPressed: ()=>_openSymbolModal(s),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(s, style: const TextStyle(fontSize: 13,fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context){
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
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _sendPreferencesToServer,
              icon: const Icon(Icons.send),
              label: const Text('ارسال تنظیمات به سرور'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
            const SizedBox(height: 12),
            const Text('توضیح: تغییرات تایم‌فریم و جهت هر جفت‌ارز بلافاصله ذخیره می‌شود. برای ارسال نهایی به سرور از دکمه بالا استفاده کنید.'),
          ],
        ),
      ),
    );
  }
}
