import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'outbox_page.dart';

class SettingsPage extends StatefulWidget {
  final int userId;
  const SettingsPage({super.key, required this.userId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // لیست‌ها (مطابق چیزی که گفتیم)
  final List<String> pairs = ["EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","AUDJPY","CADJPY","EURJPY","BTCUSD","ETHUSD","ADAUSD","DowJones","NASDAQ","S&P500","XAUUSD"];
  final List<String> timeframes = ["M1","M2","M3","M4","M5","M6","M10","M12","M15","M20","M30","H1","H2","H3","H4","H6","H8","H12","D1","W1"];
  final List<String> modes = ["A1","A2","B","C","D","E","F","G"];
  final List<String> sessions = ["TOKYO","LONDON","NEWYORK","SYDNEY"];
  final List<String> directions = ["BUY","SELL","BUYSELL"];

  // وضعیت کاربر (UI state)
  late Map<String, Map<String, bool>> selectedTimeframes;
  late Map<String, bool> selectedModes;
  late Map<String, bool> selectedSessions;
  late Map<String, String> selectedDirections;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // مقداردهی اولیه
    selectedTimeframes = { for (var p in pairs) p: { for (var t in timeframes) t: false } };
    selectedModes = { for (var m in modes) m: false };
    selectedSessions = { for (var s in sessions) s: false };
    selectedDirections = { for (var p in pairs) p: 'BUYSELL' };
  }

  // تبدیل به ساختار users.json مشابه سرور
  Map<String, dynamic> _buildPayload() {
    // برای هر جفت ارز، فقط تایم‌فریم‌های true را نگه می‌داریم.
    final tfForUser = <String, dynamic>{};
    for (var p in pairs) {
      final tfMap = <String, dynamic>{};
      for (var t in timeframes) {
        if (selectedTimeframes[p]![t] == true) {
          tfMap[t] = true;
        }
      }
      if (tfMap.isNotEmpty) {
        // اضافه کردن signal در سطح جفت ارز (اگر خواستی می‌تونیم سطح سیگنال رو برای هر tf بذاریم)
        tfForUser[p] = tfMap;
        // اضافه کردن signal به همان سطح (سرور ما انتظار داره ممکنه signal در dict باشه)
        tfForUser[p]['signal'] = selectedDirections[p];
      }
    }

    return {
      "timeframes": { widget.userId.toString(): tfForUser },
      "modes": { widget.userId.toString(): selectedModes },
      "sessions": { widget.userId.toString(): selectedSessions }
    };
  }

  // snapshot برای rollback
  Map<String, dynamic> _snapshot() {
    return {
      "timeframes": Map<String, Map<String, bool>>.from(selectedTimeframes.map((k,v) => MapEntry(k, Map<String,bool>.from(v)))),
      "modes": Map<String, bool>.from(selectedModes),
      "sessions": Map<String, bool>.from(selectedSessions),
      "directions": Map<String, String>.from(selectedDirections),
    };
  }

  void _restoreSnapshot(Map<String, dynamic> snap) {
    setState(() {
      selectedTimeframes = Map<String, Map<String, bool>>.from(snap['timeframes']);
      selectedModes = Map<String, bool>.from(snap['modes']);
      selectedSessions = Map<String, bool>.from(snap['sessions']);
      selectedDirections = Map<String, String>.from(snap['directions']);
    });
  }

  Future<void> _submit() async {
    final snap = _snapshot();
    setState(() => _loading = true);

    // قانون: اگر A1 فعال باشد A2 خاموش و برعکس (اینجا تضمین می‌شود)
    if (selectedModes['A1'] == true) selectedModes['A2'] = false;
    if (selectedModes['A2'] == true) selectedModes['A1'] = false;

    final payload = _buildPayload();

    final ok = await ApiService.sendSettings(widget.userId, payload);
    if (ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات با موفقیت ذخیره شد')));
    } else {
      // rollback
      _restoreSnapshot(snap);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطا در ذخیره سازی — تنظیمات برگردانده شد')));
    }

    setState(() => _loading = false);
  }

  Widget _buildModeTile(String m) {
    return SwitchListTile(
      title: Text(m),
      value: selectedModes[m]!,
      onChanged: (v) {
        // rule: only one of A1/A2
        if (m == 'A1' && v) selectedModes['A2'] = false;
        if (m == 'A2' && v) selectedModes['A1'] = false;
        setState(() => selectedModes[m] = v);
      },
    );
  }

  Widget _buildSessionTile(String s) {
    return SwitchListTile(
      title: Text(s),
      value: selectedSessions[s]!,
      onChanged: (v) => setState(() => selectedSessions[s] = v),
    );
  }

  Widget _buildPairTile(String p) {
    return ExpansionTile(
      title: Text(p, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: timeframes.map((t) => FilterChip(
            label: Text(t),
            selected: selectedTimeframes[p]![t]!,
            onSelected: (v) => setState(() => selectedTimeframes[p]![t] = v),
          )).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Direction: '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: selectedDirections[p],
              items: directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (val) => setState(() => selectedDirections[p] = val!),
            )
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings - ${widget.userId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutboxPage(userId: widget.userId))),
          )
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...modes.map(_buildModeTile),
            const Divider(),
            const Text('Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...sessions.map(_buildSessionTile),
            const Divider(),
            const Text('Pairs & Timeframes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...pairs.map(_buildPairTile),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('Save settings'),
            )
          ],
        ),
      ),
    );
  }
}
