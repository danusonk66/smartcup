import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'battery_watch.dart';
import 'utils.dart';

// ═════════════════════════════════════════════════════════════════════
// 🤖 แจ้งเตือนจาก AI (วันละ 3 ครั้ง) — ทำงานเบื้องหลัง แม้ปิดแอป
//
//   12:00          ตรวจยอดดื่ม: ไม่ถึงครึ่ง → เร่งดื่ม / ถึงครึ่งแล้ว → ชวนดื่มเชิงบวก
//   18:00          ตรวจยอดดื่มแบบเดียวกัน (ครั้งเดียวต่อวัน)
//   ก่อนเวลานอน    สรุปยอดที่เหลือ (เวลา = เวลาเริ่มปิดเสียง − "แจ้งเตือนก่อนเวลานอน")
//
// ถึงเวลา → มือถือรันงานเบื้องหลัง (WorkManager) → อ่านยอดจริงจาก Firebase
//         → ให้ Gemini เขียนข้อความเฉพาะตัว → เด้งแจ้งเตือน
// ถ้า Gemini/เน็ตใช้ไม่ได้ ใช้ข้อความแม่แบบแทน (แจ้งเตือนยังเด้งเสมอ)
// ครบเป้าแล้ว: 12:00 และ 18:00 จะไม่เด้ง / ก่อนนอนเด้งชม
// เคารพสวิตช์ "เปิดการแจ้งเตือน" และช่วงปิดเสียงเหมือนแจ้งเตือนอื่น
// ═════════════════════════════════════════════════════════════════════

const String _taskName = 'smartcup_ai_reminder';

/// จุดเริ่มของงานเบื้องหลังทั้งหมดของแอป (ต้องเป็นฟังก์ชันระดับบนสุด)
/// รวมงานแจ้งเตือน AI และงานเช็กแบตแก้ว
@pragma('vm:entry-point')
void aiReminderDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 🔋 งานเช็กแบตแก้ว (ทุก 15 นาที)
    if (task == batteryTaskName) {
      try {
        await BatteryWatch.runInBackground();
      } catch (e) {
        debugPrint('❌ [Battery] เช็กแบตผิดพลาด: $e');
      }
      return true;
    }
    if (task != _taskName) return true;
    final String slot = inputData?['slot']?.toString() ?? '';
    final int dueMs = int.tryParse('${inputData?['due']}') ?? 0;
    final String name = inputData?['name']?.toString() ?? 'ai_$slot';
    try {
      await AiReminder.runSlot(slot, dueMs, name);
    } catch (e) {
      debugPrint('❌ [AI Reminder] $slot ผิดพลาด: $e');
    }
    return true; // ไม่ให้ลองซ้ำ (ตั้งรอบถัดไปไว้แล้ว)
  });
}

class AiReminder {
  AiReminder._();

  static const List<String> slots = ['noon', 'evening', 'bedtime'];
  static const String _noonTime = '12:00';
  static const String _eveningTime = '18:00';
  static const String _defaultBedtime = '22:00';
  static const int _defaultBeforeBedMinutes = 30;

  /// งานที่ช้ากว่ากำหนดเกินนี้ (เช่น มือถือปิดเครื่องไว้) ไม่เด้งแล้ว เพราะข้อความไม่ทันสมัย
  static const Duration _maxLate = Duration(minutes: 90);

  static const Map<String, int> _notifIds = {
    'noon': 2001,
    'evening': 2002,
    'bedtime': 2003,
  };

  // ------------------------------------------------------------- helpers

  static int _minutesOf(String? hhmm) {
    if (hhmm == null) return -1;
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hhmmOfMinutes(int mins) =>
      '${_two((mins ~/ 60) % 24)}:${_two(mins % 60)}';

  static bool _inQuietTime(int cur, String? start, String? end) {
    final s = _minutesOf(start);
    final e = _minutesOf(end);
    if (s < 0 || e < 0 || s == e) return false;
    if (s < e) return cur >= s && cur < e;
    return cur >= s || cur < e;
  }

  static int beforeBedMinutes(Map<dynamic, dynamic> settings) {
    final total = int.tryParse('${settings['before_bed_total_minutes']}');
    if (total != null) return total;
    final h = int.tryParse('${settings['before_bed_hours']}');
    final m = int.tryParse('${settings['before_bed_minutes']}');
    if (h == null && m == null) return _defaultBeforeBedMinutes;
    return (h ?? 0) * 60 + (m ?? 0);
  }

  static String bedtimeOf(Map<dynamic, dynamic> settings) =>
      settings['quiet_start']?.toString() ?? _defaultBedtime;

  /// เวลา (HH:mm) ของแต่ละช่วง — null = ไม่ต้องแจ้ง (ปิดแจ้งเตือนก่อนนอน / ตรงกับช่วงปิดเสียง)
  static Map<String, String?> slotTimes(Map<dynamic, dynamic> settings) {
    final String bedtime = bedtimeOf(settings);
    final String? quietEnd = settings['quiet_end']?.toString();

    String? bedtimeAlert;
    final int beforeBed = beforeBedMinutes(settings);
    final int bedMins = _minutesOf(bedtime);
    if (beforeBed > 0 && bedMins >= 0) {
      bedtimeAlert = _hhmmOfMinutes(
        ((bedMins - beforeBed) % 1440 + 1440) % 1440,
      );
    }

    String? keepIfNotQuiet(String? t) {
      if (t == null) return null;
      return _inQuietTime(_minutesOf(t), bedtime, quietEnd) ? null : t;
    }

    return {
      'noon': keepIfNotQuiet(_noonTime),
      'evening': keepIfNotQuiet(_eveningTime),
      'bedtime': keepIfNotQuiet(bedtimeAlert),
    };
  }

  static DateTime _nextOccurrence(String hhmm, DateTime from) {
    final mins = _minutesOf(hhmm);
    DateTime t = DateTime(
      from.year,
      from.month,
      from.day,
      mins ~/ 60,
      mins % 60,
    );
    if (!t.isAfter(from)) t = t.add(const Duration(days: 1));
    return t;
  }

  // ---------------------------------------------------------- scheduling

  /// ตั้งเวลางานเบื้องหลังทั้ง 3 ช่วง (เรียกจากแอปทุกครั้งที่การตั้งค่าเปลี่ยน)
  static Future<void> scheduleAll(Map<dynamic, dynamic> settings) async {
    if (kIsWeb) return;
    if (settings['notification_enabled'] == false) {
      await cancelAll();
      return;
    }
    final times = slotTimes(settings);
    for (final slot in slots) {
      await _scheduleSlot(slot, times[slot], DateTime.now());
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    for (final slot in slots) {
      await Workmanager().cancelByUniqueName('ai_$slot');
      await Workmanager().cancelByUniqueName('ai_${slot}_b');
    }
  }

  // แต่ละช่วงมีชื่องาน 2 ชื่อสลับกัน (ai_noon / ai_noon_b)
  // เพราะงานที่กำลังทำงานอยู่ตั้งรอบพรุ่งนี้ด้วยชื่อเดียวกับตัวเองไม่ได้
  // (การแทนที่งานชื่อเดิมจะยกเลิกงานที่กำลังรันอยู่)
  static Future<void> _scheduleSlot(
    String slot,
    String? hhmm,
    DateTime from, {
    String? currentName,
  }) async {
    final String a = 'ai_$slot';
    final String b = 'ai_${slot}_b';
    if (hhmm == null) {
      if (currentName != a) await Workmanager().cancelByUniqueName(a);
      if (currentName != b) await Workmanager().cancelByUniqueName(b);
      return;
    }
    // จากแอป: ใช้ชื่อ a เสมอ และลบชื่อ b ที่ค้าง / จากงานเบื้องหลัง: ใช้ชื่อที่ไม่ใช่ตัวเอง
    final String name = currentName == null ? a : (currentName == a ? b : a);
    if (currentName == null) await Workmanager().cancelByUniqueName(b);

    final DateTime due = _nextOccurrence(hhmm, from);
    await Workmanager().registerOneOffTask(
      name,
      _taskName,
      inputData: {
        'slot': slot,
        'due': due.millisecondsSinceEpoch,
        'name': name,
      },
      initialDelay: due.difference(DateTime.now()),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint(
      '🤖 [AI Reminder] ตั้ง $slot เวลา $hhmm (${due.toString().substring(0, 16)})',
    );
  }

  // ------------------------------------------------------- background run

  /// ทำงานตอนถึงเวลา (รันในงานเบื้องหลัง แยกจากแอป)
  static Future<void> runSlot(
    String slot,
    int dueMs,
    String currentName,
  ) async {
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    Map<dynamic, dynamic> data = {};
    try {
      final snap = await smartCupRef().get().timeout(
        const Duration(seconds: 20),
      );
      if (snap.value is Map) {
        data = Map<dynamic, dynamic>.from(snap.value as Map);
      }
    } catch (e) {
      debugPrint('⚠️ [AI Reminder] อ่าน Firebase ไม่ได้: $e');
    }

    final Map<dynamic, dynamic> settings = data['settings'] is Map
        ? Map<dynamic, dynamic>.from(data['settings'] as Map)
        : {};

    // ตั้งรอบของพรุ่งนี้ไว้ก่อนเสมอ (ให้แจ้งเตือนทำงานต่อเนื่องแม้ไม่เปิดแอป)
    if (settings['notification_enabled'] != false) {
      final times = slotTimes(settings);
      await _scheduleSlot(
        slot,
        times[slot],
        DateTime.now().add(const Duration(minutes: 1)),
        currentName: currentName,
      );
    }

    // ไม่ต้องเด้ง: ปิดแจ้งเตือน / ช้าเกินไป / อยู่ในช่วงปิดเสียงตอนนี้
    if (settings['notification_enabled'] == false) return;
    final now = DateTime.now();
    if (dueMs > 0 &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(dueMs)) > _maxLate) {
      debugPrint('⏭️ [AI Reminder] $slot ช้าเกินไป ข้าม');
      return;
    }
    if (_inQuietTime(
      now.hour * 60 + now.minute,
      bedtimeOf(settings),
      settings['quiet_end']?.toString(),
    )) {
      return;
    }

    final message = await _buildMessage(slot, data, settings, now);
    if (message == null) return; // ครบเป้าแล้ว (12:00 / 18:00)

    await _show(slot, message['title']!, message['body']!);

    final int nowMs = now.millisecondsSinceEpoch;
    try {
      await smartCupRef('notification_logs').push().set({
        'date': '${now.year}-${_two(now.month)}-${_two(now.day)}',
        'time': '${_two(now.hour)}:${_two(now.minute)}',
        'message': message['body'],
        'timestamp': nowMs,
      });
      // ให้แอปที่เปิดอยู่แสดง SnackBar ข้อความเดียวกัน
      await smartCupRef('ai_alert').set({
        'title': message['title'],
        'body': message['body'],
        'timestamp': nowMs,
      });
    } catch (_) {}
  }

  /// สร้างข้อความ: ลองให้ Gemini เขียนก่อน ไม่ได้ค่อยใช้แม่แบบ
  static Future<Map<String, String>?> _buildMessage(
    String slot,
    Map<dynamic, dynamic> data,
    Map<dynamic, dynamic> settings,
    DateTime now,
  ) async {
    final profile = data['profile'] is Map
        ? Map<dynamic, dynamic>.from(data['profile'] as Map)
        : <dynamic, dynamic>{};
    final String lang = profile['language']?.toString() ?? 'th';
    final bool isEn = lang == 'en';
    final double target =
        double.tryParse('${profile['daily_target']}') ?? 2400.0;

    final String todayKey = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    double todayTotal = 0;
    final history = data['history_logs'];
    if (history is Map && history[todayKey] is Map) {
      todayTotal =
          double.tryParse('${(history[todayKey] as Map)['daily_total']}') ?? 0;
    }

    final bool hasData = data.isNotEmpty;
    final double remaining = (target - todayTotal).clamp(0, target).toDouble();
    final int percent = target > 0
        ? (todayTotal / target * 100).clamp(0, 100).round()
        : 0;
    final bool goalMet = hasData && remaining <= 0;
    final bool overHalf = percent >= 50;

    // 12:00 / 18:00 ครบเป้าแล้วไม่ต้องเตือน
    if (slot != 'bedtime' && goalMet) return null;

    // อัตราที่ควรดื่มก่อนนอน (ml/ชม.)
    final String bedtime = bedtimeOf(settings);
    int minsUntilBed = _minutesOf(bedtime) - (now.hour * 60 + now.minute);
    if (minsUntilBed <= 0) minsUntilBed += 1440;
    final double hoursLeft = (minsUntilBed / 60).clamp(1.0, 12.0).toDouble();
    final int ratePerHr = (remaining / hoursLeft).clamp(0, 1000).round();
    final int beforeBed = beforeBedMinutes(settings);

    final template = _templateMessage(
      slot: slot,
      isEn: isEn,
      hasData: hasData,
      goalMet: goalMet,
      overHalf: overHalf,
      todayTotal: todayTotal.round(),
      target: target.round(),
      remaining: remaining.round(),
      ratePerHr: ratePerHr,
      bedtime: bedtime,
      beforeBed: beforeBed,
    );
    if (!hasData) return template;

    final ai = await _askGemini(
      slot: slot,
      isEn: isEn,
      goalMet: goalMet,
      overHalf: overHalf,
      todayTotal: todayTotal.round(),
      target: target.round(),
      percent: percent,
      remaining: remaining.round(),
      ratePerHr: ratePerHr,
      bedtime: bedtime,
      now: now,
    );
    return ai ?? template;
  }

  static Map<String, String> _templateMessage({
    required String slot,
    required bool isEn,
    required bool hasData,
    required bool goalMet,
    required bool overHalf,
    required int todayTotal,
    required int target,
    required int remaining,
    required int ratePerHr,
    required String bedtime,
    required int beforeBed,
  }) {
    if (!hasData) {
      return {
        'title': 'SmartCup 💧',
        'body': isEn
            ? 'Time to check your water today. Take a few sips!'
            : 'ได้เวลาเช็กการดื่มน้ำวันนี้แล้ว จิบน้ำสักนิดนะ',
      };
    }

    if (slot == 'bedtime') {
      if (goalMet) {
        return {
          'title': isEn
              ? '🌙 Goal reached, well done!'
              : '🌙 ครบเป้าหมายแล้ว เก่งมาก!',
          'body': isEn
              ? 'You drank $todayTotal ml today. Have a good night!'
              : 'วันนี้ดื่มไป $todayTotal ml ครบเป้าแล้ว นอนหลับฝันดีนะ',
        };
      }
      return {
        'title': isEn ? '🌙 Bedtime is coming up' : '🌙 ใกล้ถึงเวลานอนแล้ว',
        'body': isEn
            ? 'Bedtime at $bedtime. You still need $remaining ml to reach your goal.'
            : 'อีก $beforeBed นาทีจะถึงเวลานอน ($bedtime น.) เหลืออีก $remaining ml จะครบเป้าหมาย',
      };
    }

    final String when = slot == 'noon'
        ? (isEn ? "It's noon" : 'เที่ยงแล้ว')
        : (isEn ? "It's past 18:00" : 'เลยเวลา 18:00 น. แล้ว');

    if (overHalf) {
      return {
        'title': isEn
            ? '💧 Great job! Keep it up!'
            : '💧 ทำได้เกินครึ่งทางแล้ว!',
        'body': isEn
            ? '$when and you have passed 50% of your goal! Just $remaining ml left before $bedtime.'
            : '$when ยอดเยี่ยมมาก! คุณดื่มน้ำเกินครึ่งทางแล้ว เหลืออีกแค่ $remaining ml ก็จะครบเป้าก่อนนอน $bedtime น.',
      };
    }
    return {
      'title': isEn
          ? '🤖 AI Smart Hydration Alert!'
          : '🤖 AI แจ้งเตือนเร่งดื่มน้ำอัจฉริยะ!',
      'body': isEn
          ? '$when and you have drunk less than 50% ($todayTotal/$target ml). Please drink ~$ratePerHr ml/hr before $bedtime!'
          : '$when แต่คุณดื่มน้ำยังไม่ถึงครึ่งของเป้าหมาย ($todayTotal/$target ml) แนะนำให้จิบน้ำชม.ละ $ratePerHr ml ก่อนนอนเวลา $bedtime น.',
    };
  }

  static Future<Map<String, String>?> _askGemini({
    required String slot,
    required bool isEn,
    required bool goalMet,
    required bool overHalf,
    required int todayTotal,
    required int target,
    required int percent,
    required int remaining,
    required int ratePerHr,
    required String bedtime,
    required DateTime now,
  }) async {
    const String apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) return null;

    final String situation = slot == 'bedtime'
        ? (goalMet
              ? 'ใกล้เวลานอนและดื่มครบเป้าแล้ว: ชมเชยสั้น ๆ'
              : 'ใกล้เวลานอนแต่ยังไม่ครบเป้า: บอกยอดที่เหลือ ชวนดื่มอีกนิด')
        : (overHalf
              ? 'ดื่มถึงครึ่งของเป้าแล้ว: ให้กำลังใจเชิงบวก'
              : 'ดื่มยังไม่ถึงครึ่งของเป้า: เร่งให้ดื่ม พร้อมบอกอัตราต่อชั่วโมง');

    final prompt =
        '''
คุณคือ Smart Cup AI เขียนข้อความแจ้งเตือนดื่มน้ำบนมือถือ
ภาษา: ${isEn ? 'English' : 'ไทย'}
เวลาตอนนี้: ${_two(now.hour)}:${_two(now.minute)} น.
สถานการณ์: $situation
ข้อมูลจริง: ดื่มแล้ว $todayTotal ml จากเป้า $target ml ($percent%), เหลือ $remaining ml,
ควรดื่มประมาณ $ratePerHr ml/ชม., เวลานอน $bedtime น.

กติกา:
- title สั้นไม่เกิน 40 ตัวอักษร มีอีโมจิ 1 ตัว
- body ไม่เกิน 2 ประโยค ใช้ตัวเลขจากข้อมูลจริงเท่านั้น ห้ามแต่งตัวเลขเอง
- เป็นกันเอง ให้กำลังใจ ไม่ตำหนิ
ตอบเป็น JSON เท่านั้น: {"title": "...", "body": "..."}
''';

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {'responseMimeType': 'application/json'},
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('🤖 [AI Reminder] Gemini status = ${response.statusCode}');
        return null;
      }
      final resJson = jsonDecode(response.body);
      final rawText = resJson['candidates'][0]['content']['parts'][0]['text'];
      final generated = jsonDecode(rawText);
      final String title = '${generated['title'] ?? ''}'.trim();
      final String body = '${generated['body'] ?? ''}'.trim();
      if (title.isEmpty ||
          body.isEmpty ||
          title.length > 60 ||
          body.length > 240) {
        return null;
      }
      return {'title': title, 'body': body};
    } catch (e) {
      debugPrint('🤖 [AI Reminder] Gemini ใช้ไม่ได้: $e');
      return null;
    }
  }

  static Future<void> _show(String slot, String title, String body) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.show(
      id: _notifIds[slot] ?? 2000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'smartcup_water_reminder',
          'แจ้งเตือนดื่มน้ำ SmartCup',
          channelDescription: 'การแจ้งเตือนเตือนดื่มน้ำจากแก้วน้ำอัจฉริยะ',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body), // ข้อความยาวแสดงครบ
        ),
      ),
    );
  }
}
