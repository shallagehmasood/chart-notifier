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
// ---------- HomePage بهینه و جمع و جور ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _userId = '';
  String userMode = '0000000'; // 7-bit string
  Map<String, dynamic> symbolPrefs = {};
  List<Map<String, dynamic>> _receivedImages = [];

  Map<String, Set<String>> _confirmedTfs = {};
  Map<String, String> _confirmedDirection = {};
  String _confirmedMode = '';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('user_id', _userId);

    userMode = prefs.getString('mode_7bit') ?? '0000000';
    _confirmedMode = userMode;

    final symJson = prefs.getString('symbol_prefs') ?? '{}';
    symbolPrefs = jsonDecode(symJson);

    for (var s in symbolPrefs.keys) {
      _confirmedTfs[s] = Set<String>.from(symbolPrefs[s]['timeframes'] ?? []);
      _confirmedDirection[s] = symbolPrefs[s]['direction'] ?? 'BUY&SELL';
    }

    await _loadImagesFromServer();
    setState(() {});
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
        setState(() {
          _receivedImages = imgs.map((img) => {
            'url': img['image_url'],
            'symbol': img['symbol'],
            'timeframe': img['timeframe'],
            'filename': img['filename'] ?? img['image_url'].split('/').last,
            'timestamp': img['timestamp'] != null
                ? DateTime.fromMillisecondsSinceEpoch(img['timestamp']).toLocal()
                : null,
          }).toList();
        });
      }
    } catch (e) {}
  }

  // ---------- ارسال تغییرات به سرور ----------
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
        setState(() {
          _confirmedTfs[symbol] = Set<String>.from(symbolPrefs[symbol]?['timeframes'] ?? []);
          _confirmedDirection[symbol] = symbolPrefs[symbol]?['direction'] ?? 'BUY&SELL';
        });
      }
    } catch (e) {}
  }

  Future<void> _sendModeToServer() async {
    try {
      final payload = {'user_id': _userId, 'mode': userMode};
      final rsp = await http.post(Uri.parse('$SERVER_URL/save_preferences'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload));
      if (rsp.statusCode == 200) setState(() => _confirmedMode = userMode);
    } catch (e) {}
  }

  // ---------- UI نیمه بالا ----------
  Widget _buildModeWidget() {
    final modeKeys = ['A1','B','C','D','E','F','G'];
    Map<String,bool> modeMap = {};
    final init = userMode.padRight(7,'0').substring(0,7);
    for (int i=0;i<7;i++) modeMap[modeKeys[i]] = init[i]=='1';

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: modeKeys.map((k){
            final isConfirmed = (_confirmedMode.length>=7 && _confirmedMode[modeKeys.indexOf(k)]=='1');
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isConfirmed ? Colors.green : Colors.grey),
              onPressed: (){
                modeMap[k] = !(modeMap[k] ?? false);
                final bits = modeKeys.map((mk)=> modeMap[mk]! ? '1':'0').toList();
                userMode = bits.join();
                _saveLocalPrefs();
                _sendModeToServer();
                setState(() {});
              },
              child: Text(k, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSymbolsWidget() {
    return Column(
      children: symbols.map((s) {
        final prefs = symbolPrefs[s] ?? {'timeframes': <String>[], 'direction': 'BUY&SELL'};
        final confirmedTfs = _confirmedTfs[s] ?? <String>{};
        final confirmedDir = _confirmedDirection[s] ?? 'BUY&SELL';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: timeframes.map((tf){
                    final isConfirmed = confirmedTfs.contains(tf);
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: isConfirmed ? Colors.green : Colors.grey, minimumSize: const Size(40,28), padding: const EdgeInsets.symmetric(horizontal:6, vertical:2)),
                      onPressed: (){
                        final tfs = List<String>.from(prefs['timeframes']);
                        if(tfs.contains(tf)) tfs.remove(tf); else tfs.add(tf);
                        prefs['timeframes'] = tfs;
                        symbolPrefs[s] = prefs;
                        _saveLocalPrefs();
                        _sendPreferenceToServer(s);
                        setState(() {});
                      },
                      child: Text(tf, style: const TextStyle(fontSize: 10)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: ['BUY','SELL','BUY&SELL'].map((dir){
                    final isConfirmed = confirmedDir==dir;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: isConfirmed ? Colors.green : Colors.grey, padding: const EdgeInsets.symmetric(horizontal:8, vertical:4)),
                      onPressed: (){
                        prefs['direction'] = dir;
                        symbolPrefs[s] = prefs;
                        _saveLocalPrefs();
                        _sendPreferenceToServer(s);
                        setState(() {});
                      },
                      child: Text(dir, style: const TextStyle(fontSize:10)),
                    );
                  }).toList(),
                )
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageList() {
    return _receivedImages.isEmpty
        ? const Center(child: Text('هیچ تصویری برای نمایش نیست'))
        : ListView.builder(
            itemCount: _receivedImages.length,
            itemBuilder: (context,index){
              final img = _receivedImages[index];
              final tsText = img['timestamp'] != null ? img['timestamp'].toString() : '—';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: ()=>_showImageFullScreen(img['url'], img['filename']),
                      child: Image.network(img['url'], fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("جفت ارز: ${img['symbol']}"),
                          Text("تایم فریم: ${img['timeframe']}"),
                          Text("زمان: $tsText"),
                          Text("نام تصویر: ${img['filename']}", style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height:4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: ()=>_downloadImage(img['url'], img['symbol'], img['timeframe']),
                                icon: const Icon(Icons.download, size:16),
                                label: const Text('دانلود', style: TextStyle(fontSize:12)),
                              ),
                              ElevatedButton.icon(
                                onPressed: ()=>_deleteImageForUser(img['url']),
                                icon: const Icon(Icons.delete, size:16),
                                label: const Text('حذف', style: TextStyle(fontSize:12)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              )
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

  void _showImageFullScreen(String url, String filename){
    Navigator.push(context, MaterialPageRoute(builder: (_){
      return Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: PhotoView(imageProvider: NetworkImage(url)),
      );
    }));
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('داشبورد سیگنال‌ها')),
      body: Column(
        children: [
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
          const Divider(height:1),
          Expanded(
            flex:3,
            child: _buildImageList(),
          )
        ],
      ),
    );
  }
}
