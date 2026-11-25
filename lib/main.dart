import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  runApp(const MyApp());
}

const dayNames = ['شنبه','یکشنبه','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه'];
const palette = [
  0xFFE0F7FA, 0xFFFFF9C4, 0xFFF8BBD0, 0xFFD1C4E9,
  0xFFC8E6C9, 0xFFFFCCBC, 0xFFB3E5FC, 0xFFDCEDC8,
];

class Task {
  String id;
  String title;
  bool done;
  int colorValue;
  Task({required this.id, required this.title, this.done = false, required this.colorValue});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done, 'colorValue': colorValue};
  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    title: j['title'] as String,
    done: (j['done'] as bool?) ?? false,
    colorValue: j['colorValue'] as int,
  );
}

class Storage {
  static const _key = 'tasks_v2';
  static Future<Map<int, List<Task>>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    final result = <int, List<Task>>{for (var i = 0; i < 7; i++) i: <Task>[]};
    if (raw != null) {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      decoded.forEach((k, v) {
        final idx = int.parse(k);
        result[idx] = (v as List).map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      });
    }
    return result;
  }
  static Future<void> save(Map<int, List<Task>> data) async {
    final sp = await SharedPreferences.getInstance();
    final m = <String, dynamic>{};
    data.forEach((k, v) => m[k.toString()] = v.map((e) => e.toJson()).toList());
    await sp.setString(_key, jsonEncode(m));
  }
}

class Notifications {
  static final _p = FlutterLocalNotificationsPlugin();
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _p.initialize(const InitializationSettings(android: android));
    await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  static Future<void> scheduleDaily(TimeOfDay time, String body) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _p.zonedSchedule(
      0, 'مشاوره و محمد مهدی', body, when,
      const NotificationDetails(android: AndroidNotificationDetails(
        'alarm_channel', 'یادآورها',
        importance: Importance.max, priority: Priority.high, playSound: true,
      )),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'مشاوره و محمد مهدی',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa', 'IR'),
    supportedLocales: const [Locale('fa', 'IR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<int, List<Task>> data = {for (var i = 0; i < 7; i++) i: <Task>[]};
  int selectedDay = 0;
  Timer? _clock;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() { _clock?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final d = await Storage.load();
    if (mounted) setState(() => data = d);
  }

  Future<void> _save() async => Storage.save(data);

  void _add() async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context, builder: (_) => const _EditDialog());
    if (res == null) return;
    setState(() {
      data[selectedDay]!.add(Task(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: res['title'] as String,
        colorValue: res['color'] as int,
      ));
    });
    await _save();
  }

  void _edit(Task t) async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context, builder: (_) => _EditDialog(initial: t));
    if (res == null) return;
    setState(() { t.title = res['title'] as String; t.colorValue = res['color'] as int; });
    await _save();
  }

  void _del(Task t) async {
    setState(() => data[selectedDay]!.remove(t));
    await _save();
  }

  void _toggle(Task t) async {
    setState(() => t.done = !t.done);
    await _save();
  }

  Future<void> _setAlarm() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    await Notifications.scheduleDaily(time, 'وقتشه کارهات رو انجام بدی!');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('ساعت ${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')} تنظیم شد'),
    ));
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final tasks = data[selectedDay] ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشاوره و محمد مهدی'),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.alarm), onPressed: _setAlarm)],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.teal.shade300, Colors.teal.shade700]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold)),
              Text(dayNames[selectedDay], style: const TextStyle(color: Colors.white70)),
            ]),
            const Icon(Icons.access_time, color: Colors.white, size: 42),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: 7,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(dayNames[i]),
                selected: selectedDay == i,
                onSelected: (_) => setState(() => selectedDay = i),
              ),
            ),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
            ? const Center(child: Text('هنوز کاری برای این روز ثبت نشده'))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: tasks.length,
                itemBuilder: (_, i) {
                  final t = tasks[i];
                  return Card(
                    color: Color(t.colorValue),
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    elevation: t.done ? 4 : 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: t.done ? Colors.green.shade700 : Colors.transparent, width: 2),
                    ),
                    child: ListTile(
                      leading: Checkbox(
                        value: t.done,
                        activeColor: Colors.green.shade700,
                        onChanged: (_) => _toggle(t),
                      ),
                      title: Text(t.title, style: TextStyle(
                        fontSize: 16,
                        fontWeight: t.done ? FontWeight.w900 : FontWeight.normal,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                      )),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _edit(t)),
                        IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _del(t)),
                      ]),
                    ),
                  );
                },
              ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('کار جدید'),
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  final Task? initial;
  const _EditDialog({this.initial});
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late TextEditingController _c;
  late int _color;
  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial?.title ?? '');
    _color = widget.initial?.colorValue ?? palette[0];
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'کار جدید' : 'ویرایش کار'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _c, autofocus: true,
        decoration: const InputDecoration(labelText: 'عنوان کار', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: palette.map((c) {
        final sel = _color == c;
        return GestureDetector(
          onTap: () => setState(() => _color = c),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(
            color: Color(c), shape: BoxShape.circle,
            border: Border.all(color: sel ? Colors.black : Colors.transparent, width: 2),
          )),
        );
      }).toList()),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      FilledButton(onPressed: () {
        final t = _c.text.trim();
        if (t.isEmpty) return;
        Navigator.pop(context, {'title': t, 'color': _color});
      }, child: const Text('ذخیره')),
    ],
  );
}
