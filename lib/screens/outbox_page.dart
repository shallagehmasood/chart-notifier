import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class OutboxPage extends StatefulWidget {
  final int userId;
  final String? highlightFile;

  const OutboxPage({Key? key, required this.userId, this.highlightFile}) : super(key: key);

  @override
  State<OutboxPage> createState() => _OutboxPageState();
}

class _OutboxPageState extends State<OutboxPage> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  final scrollController = ScrollController();

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

    if (widget.highlightFile != null) {
      final index = items.indexWhere((it) => it['file'] == widget.highlightFile);
      if (index != -1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          scrollController.animateTo(
            index * 220.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Outbox')),
      body: ListView.builder(
        controller: scrollController,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final it = items[i];
          final isHighlighted = widget.highlightFile != null && it['file'] == widget.highlightFile;

          Widget content = Column(
            children: [
              CachedNetworkImage(
                imageUrl: it['url'],
                placeholder: (_, __) => const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(it['caption'] ?? ''),
              ),
              ButtonBar(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('دانلود'),
                    onPressed: () => ApiService.downloadFile(widget.userId, it['file']),
                  ),
                ],
              ),
            ],
          );

          if (isHighlighted) {
            content = TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.2),
              duration: const Duration(seconds: 1),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              onEnd: () => setState(() {}),
              child: content,
            );
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(
                color: isHighlighted ? Colors.amber : Colors.transparent,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                if (isHighlighted)
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
              ],
            ),
            child: content,
          );
        },
      ),
    );
  }
}
