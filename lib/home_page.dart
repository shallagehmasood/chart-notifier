import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';

const String SERVER_URL = 'http://178.63.171.244:5000';

final List<String> symbols = [
  'EURUSD','XAUUSD','GBPUSD','USDJPY','USDCHF',
  'AUDUSD','AUDJPY','CADJPY','EURJPY',
  'BTCUSD','ETHUSD','ADAUSD',
  'DowJones','NASDAQ','S&P500',
];

final List<String> timeframes = [
  'M1','M2','M3','M4','M5','M6','M10','M12',
  'M15','M20','M30','H1','H2','H3','H4','H6',
  'H8','H12','D1','W1',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _userId = 'user_123';
  String? _fcmToken;
  Map<String, Set<String>> subscribed = {};
  List<String> _receivedImages = [];
  List<String> _receivedFilenames = [];

  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    _fcmToken = await FirebaseMessaging.instance.getToken();
    if (_fcmToken != null) {
      await _registerOnServer(_fcmToken!);
      await _loadSubscriptions();
      await _loadImagesFromServer();
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final imageUrl = message.data['image_url'];
      if (imageUrl != null) _handleIncomingImage(imageUrl);
    });

    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage?.data['image_url'] != null) {
      _handleIncomingImage(initialMessage!.data['image_url']!);
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final imageUrl = message.data['image_url'];
      if (imageUrl != null) _handleIncomingImage(imageUrl);
    });
  }

  Future<void> _registerOnServer(String token) async {
    await http.post(Uri.parse('$SERVER_URL/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId, 'fcm_token': token}));
  }

  Future<void> _loadSubscriptions() async {
    final response = await http.post(Uri.parse('$SERVER_URL/subscriptions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}));
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

  Future<void> _loadImagesFromServer() async {
    final response = await http.post(Uri.parse('$SERVER_URL/images_for_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List images = data['images'];
      setState(() {
        _receivedImages = images.map((e) => e['image_url'] as String).toList();
        _receivedFilenames = images.map((e) => '${e['symbol']}|${e['timeframe']}').toList();
      });
    }
  }

  void _handleIncomingImage(String imageUrl) {
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
  }

  Future<void> _subscribe(String symbol, String timeframe) async {
    await http.post(Uri.parse('$SERVER_URL/subscribe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId,'symbol': symbol,'timeframe': timeframe}));
    setState(() {
      subscribed.putIfAbsent(symbol, () => {}).add(timeframe);
    });
  }

  Future<void> _unsubscribe(String symbol, String timeframe) async {
    await http.post(Uri.parse('$SERVER_URL/unsubscribe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId,'symbol': symbol,'timeframe': timeframe}));
    setState(() {
      subscribed[symbol]?.remove(timeframe);
    });
  }

  Future<void> _deleteImage(String imageUrl) async {
    final response = await http.post(Uri.parse('$SERVER_URL/delete_image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId,'image_url': imageUrl}));
    if (response.statusCode == 200) {
      setState(() {
        final index = _receivedImages.indexOf(imageUrl);
        if (index != -1) {
          _receivedImages.removeAt(index);
          _receivedFilenames.removeAt(index);
        }
      });
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
                      onPressed: () => _deleteImage(imageUrl),
                      icon: const Icon(Icons.delete),
                      label: const Text('حذف', style: TextStyle(fontWeight: FontWeight.bold)),
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
    List<Widget> rows = [];
    for (int i = 0; i < symbols.length; i += 5) {
      final chunk = symbols.sublist(i, (i + 5 > symbols.length) ? symbols.length : i + 5);
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: chunk.map((symbol) => Expanded(
          child: ExpansionTile(
            title: Text(symbol, textAlign: TextAlign.center),
            children: [
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: timeframes.map((tf) {
                  final isActive = subscribed[symbol]?.contains(tf) ?? false;
                  return Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? Colors.green : Colors.red,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (isActive) _unsubscribe(symbol, tf);
                        else _subscribe(symbol, tf);
                      },
                      child: Text(tf, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        )).toList(),
      ));
    }
    return rows;
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
