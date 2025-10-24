import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';
import 'settings_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    final text = _ctrl.text.trim();
    final uid = int.tryParse(text);
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لطفا یک عدد معتبر وارد کنید')));
      return;
    }

    setState(() => _busy = true);

    // گرفتن توکن FCM و ثبت در سرور
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final ok = await ApiService.registerToken(uid, token);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت توکن در سرور موفقیت‌آمیز نبود')));
          // ولی اجازه ادامه می‌دهیم (ممکن است سرور گذرا مشکل داشته باشد)
        }
      }
    } catch (e) {
      print('FCM token error: $e');
    }

    setState(() => _busy = false);

    // ورود به صفحه تنظیمات
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingsPage(userId: uid)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ورود / User ID')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('User ID را وارد کنید', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'مثال: 12345'),
            ),
            const SizedBox(height: 16),
            _busy ? const CircularProgressIndicator() : ElevatedButton(
              onPressed: _login,
              child: const Text('ورود'),
            ),
          ],
        ),
      ),
    );
  }
}
