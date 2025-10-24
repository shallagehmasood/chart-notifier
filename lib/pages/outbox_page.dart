import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class OutboxPage extends StatefulWidget {
  final int userId;
  const OutboxPage({super.key, required this.userId});

  @override
  State<OutboxPage> createState() => _OutboxPageState();
}

class _OutboxPageState extends State<OutboxPage> {
  List<Map<String,dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.fetchOutbox(widget.userId);
    setState(() {
      items = res;
      loading = false;
    });
  }

  Future<void> _download(String url, String filename) async {
    // درخواست دسترسی ذخیره‌سازی (اندروید)
    if (Platform.isAndroid) {
      if (!await Permission.storage.request().isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای دانلود نیاز به دسترسی است')));
        return;
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$filename';
    try {
      final resp = await http.get(Uri.parse(url));
      final file = File(savePath);
      await file.writeAsBytes(resp.bodyBytes);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره شد: $savePath')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در دانلود')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Outbox ${widget.userId}'),
        actions: [ IconButton(onPressed: _load, icon: const Icon(Icons.refresh)) ],
      ),
      body: loading ? const Center(child: CircularProgressIndicator()) :
      items.isEmpty ? const Center(child: Text('No images')) :
      ListView.builder(
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final it = items[i];
          return Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                CachedNetworkImage(
                  imageUrl: it['url'],
                  placeholder: (_, __) => const SizedBox(height:150, child: Center(child: CircularProgressIndicator())),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
                ),
                Padding(padding: const EdgeInsets.all(8), child: Text(it['caption'] ?? '')),
                ButtonBar(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('دانلود'),
                      onPressed: () => _download(it['url'], it['file']),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
