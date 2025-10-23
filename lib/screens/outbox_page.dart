// lib/screens/outbox_page.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/models.dart';

class OutboxPage extends StatefulWidget {
  final int userId;

  const OutboxPage({Key? key, required this.userId}) : super(key: key);

  @override
  _OutboxPageState createState() => _OutboxPageState();
}

class _OutboxPageState extends State<OutboxPage> {
  late ApiService _apiService;
  late Future<List<FileModel>> _files;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _files = _apiService.getOutbox(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Outbox')),
      body: FutureBuilder<List<FileModel>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Failed to load files'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No files found'));
          }

          final files = snapshot.data!;
          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return ListTile(
                leading: Icon(Icons.image),
                title: Text(file.file),
                subtitle: Text(file.caption),
                onTap: () async {
                  final response = await _apiService.downloadFile(widget.userId, file.file);
                  if (response.statusCode == 200) {
                    // ذخیره یا نمایش فایل دانلود شده
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
