import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../main.dart' show flutterLocalNotificationsPlugin;
import 'ai_reminder.dart';
import 'battery_watch.dart';
import 'utils.dart';

/// ชนิดของแจ้งเตือน (ใช้เลือกข้อความ SnackBar ในแอป)
enum ReminderKind { drink, bedtime }

/// 🌟 ตั้งเวลาแจ้งเตือนไว้ในมือถือล่วงหน้า (ทำงานแม้ปิดแอป)
///
/// 1) แจ้งเตือนดื่มน้ำตามความถี่: นับจากเวลาดื่มล่าสุด ตั้งล่วงหน้า 24 รอบ ข้ามช่วงปิดเสียง
///    และข้ามรอบที่ห่างจากแจ้งเตือน AI ไม่ถึง 15 นาที (ไม่ให้เด้งซ้อนกัน)
/// 2) แจ้งเตือนจาก AI 12:00 / 18:00 / ก่อนเวลานอน → ตั้งงานเบื้องหลังผ่าน [AiReminder]
///    (แจ้งเตือนก่อนนอนแบบเดิมรวมเข้ากับ AI แล้ว)
///
/// - อ่านการตั้งค่าจาก /SmartCup/settings และเวลาดื่มล่าสุดจาก /SmartCup/last_drink_timestamp
/// - ทุกครั้งที่ตั้งเวลาใหม่ จะบันทึกแจ้งเตือนที่เด้งไปแล้วลง notification_logs
/// - ระหว่างเปิดแอปอยู่ จะเรียก [onReminderDue] ตรงเวลา เพื่อแสดง SnackBar ในแอป
class ReminderScheduler {
  ReminderScheduler._();

  static const int _drinkBaseId = 1000; // id 1000-1023: แจ้งเตือนดื่มน้ำ
  static const int _bedtimeId =
      1100; //   id 1100: แจ้งเตือนก่อนนอนแบบเดิม (ยกเลิกทิ้ง)
  static const int _maxReminders = 24;
  static const int _defaultIntervalMinutes = 120;
  static const int _minIntervalMinutes =
      1; // ให้ตั้ง 1 นาทีได้ (ไว้ทดสอบ/สาธิต)
  static const String _defaultBedtime =
      '22:00'; // ตรงกับค่าเริ่มต้นในหน้าแจ้งเตือน

  static const String drinkLogMessage = 'ถึงเวลาที่ควรดื่มน้ำ';

  /// ให้ main.dart ตั้งค่าไว้ เพื่อแสดง SnackBar เมื่อถึงเวลาแจ้งเตือนขณะเปิดแอป
  static void Function(ReminderKind kind)? onReminderDue;

  /// แจ้งเตือนจาก AI เด้งขณะเปิดแอป → แสดง SnackBar ข้อความเดียวกัน
  static void Function(String title, String body)? onAiAlert;

  /// ไม่ตั้งแจ้งเตือนตามความถี่ใกล้แจ้งเตือน AI เกินกี่นาที
  static const int _aiGapMinutes = 15;

  static StreamSubscription<DatabaseEvent>? _settingsSub;
  static StreamSubscription<DatabaseEvent>? _drinkSub;
  static StreamSubscription<DatabaseEvent>? _langSub;
  static StreamSubscription<DatabaseEvent>? _aiAlertSub;
  static StreamSubscription<DatabaseEvent>? _batterySub;
  static bool _checkingBattery = false;
  static Timer? _debounce;
  static Timer? _inAppTimer;

  static Map<dynamic, dynamic> _settings = {};
  static int? _lastDrinkMs;
  static String _lang = 'th';
  static bool _started = false;

  /// ภาษาปัจจุบัน ('th' / 'en') ให้ SnackBar ใช้
  static String get language => _lang;

  // เวลาที่ตั้งไว้รอบล่าสุด (ใช้ตั้ง Timer สำหรับ SnackBar ในแอป)
  static List<DateTime> _drinkTimes = [];

  /// เรียกครั้งเดียวใน main() ก่อน runApp
  static void initTimeZone() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
  }

  /// เริ่มฟังค่าจาก Firebase แล้วตั้งเวลาแจ้งเตือนใหม่ทุกครั้งที่ค่าเปลี่ยน
  static void start() {
    if (_started || kIsWeb || !isFirebaseReady()) return;
    _started = true;

    _settingsSub = smartCupRef('settings').onValue.listen((event) {
      final v = event.snapshot.value;
      _settings = v is Map ? Map<dynamic, dynamic>.from(v) : {};
      _scheduleSoon();
    });

    _drinkSub = smartCupRef('last_drink_timestamp').onValue.listen((event) {
      _lastDrinkMs = int.tryParse('${event.snapshot.value}');
      _scheduleSoon();
    });

    _langSub = smartCupRef('profile/language').onValue.listen((event) {
      _lang = event.snapshot.value?.toString() ?? 'th';
      _scheduleSoon();
    });

    // 🔋 เปิดแอปอยู่: เช็กแบตแก้วทันทีที่ % เปลี่ยน → แจ้งเตือน + SnackBar
    _batterySub = smartCupRef('battery_percent').onValue.listen((_) async {
      if (_checkingBattery) return;
      _checkingBattery = true;
      try {
        final msg = await BatteryWatch.check();
        if (msg != null) onAiAlert?.call(msg['title']!, msg['body']!);
      } catch (e) {
        debugPrint('❌ [Battery] เช็กแบตผิดพลาด: $e');
      } finally {
        _checkingBattery = false;
      }
    });

    // แจ้งเตือน AI ที่เพิ่งเด้ง (ภายใน 2 นาที) → SnackBar ในแอป
    _aiAlertSub = smartCupRef('ai_alert').onValue.listen((event) {
      final v = event.snapshot.value;
      if (v is! Map) return;
      final int ts = int.tryParse('${v['timestamp']}') ?? 0;
      final int age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age < 0 || age > 2 * 60 * 1000) return;
      onAiAlert?.call('${v['title'] ?? ''}', '${v['body'] ?? ''}');
    });
  }

  static void stop() {
    _settingsSub?.cancel();
    _drinkSub?.cancel();
    _langSub?.cancel();
    _aiAlertSub?.cancel();
    _batterySub?.cancel();
    _debounce?.cancel();
    _inAppTimer?.cancel();
    _started = false;
  }

  // ค่าหลายตัวมักมาพร้อมกันตอนเปิดแอป รอ 2 วินาทีแล้วค่อยตั้งเวลาครั้งเดียว
  static void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      _reschedule().catchError((e) {
        debugPrint('❌ [Reminder] ตั้งเวลาไม่สำเร็จ: $e');
      });
    });
  }

  // ---------------------------------------------------------------- helpers

  static int _minutesOf(String? hhmm) {
    if (hhmm == null) return -1;
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }

  /// เวลานี้อยู่ในช่วงปิดเสียงหรือไม่ (รองรับช่วงข้ามเที่ยงคืน เช่น 22:00-06:00)
  static bool _inQuietTime(DateTime t, String? start, String? end) {
    final s = _minutesOf(start);
    final e = _minutesOf(end);
    if (s < 0 || e < 0 || s == e) return false;
    final cur = t.hour * 60 + t.minute;
    if (s < e) return cur >= s && cur < e;
    return cur >= s || cur < e;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dateKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// เครื่องอนุญาตแจ้งเตือนแบบตรงเวลาไหม (ต้องมีสิทธิ์ exact alarm ใน AndroidManifest)
  static Future<AndroidScheduleMode> _scheduleMode() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final bool exact = await android?.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  // ------------------------------------------------------------ history log

  /// แจ้งเตือนที่ตั้งไว้รอบก่อนและถึงเวลาไปแล้ว → บันทึกลงประวัติแจ้งเตือน
  static Future<void> _logFiredReminders() async {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    // แจ้งเตือนดื่มน้ำ
    final snap = await smartCupRef('notification_schedule').get();
    final value = snap.value;
    if (value is List || value is Map) {
      final Iterable<dynamic> items = value is List
          ? value
          : (value as Map).values;
      for (final item in items) {
        final int? ms = int.tryParse('$item');
        if (ms == null || ms > nowMs) continue;
        await _pushLog(ms, drinkLogMessage);
      }
    }
  }

  static Future<void> _pushLog(int ms, String message) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return smartCupRef('notification_logs').push().set({
      'date': _dateKey(t),
      'time': _hhmm(t),
      'message': message,
      'timestamp': ms,
    });
  }

  // -------------------------------------------------------------- schedule

  static Future<void> _reschedule() async {
    await _logFiredReminders();

    // ยกเลิกชุดเก่า (เฉพาะ id ของระบบนี้ ไม่แตะแจ้งเตือนจาก AI)
    for (int i = 0; i < _maxReminders; i++) {
      await flutterLocalNotificationsPlugin.cancel(id: _drinkBaseId + i);
    }
    // แจ้งเตือนก่อนนอนแบบเดิม → รวมเข้ากับแจ้งเตือน AI แล้ว ยกเลิกของเก่าทิ้ง
    await flutterLocalNotificationsPlugin.cancel(id: _bedtimeId);
    await smartCupRef('bedtime_reminder').remove();
    _drinkTimes = [];

    // 🤖 แจ้งเตือน AI (12:00 / 18:00 / ก่อนนอน) — ยกเลิกเองถ้าปิดแจ้งเตือน
    try {
      await AiReminder.scheduleAll(_settings);
    } catch (e) {
      debugPrint('❌ [AI Reminder] ตั้งเวลาไม่สำเร็จ: $e');
    }

    final bool enabled = _settings['notification_enabled'] != false;
    if (!enabled) {
      await smartCupRef('notification_schedule').set([]);
      _armInAppTimer();
      debugPrint('🔕 [Reminder] ปิดการแจ้งเตือน');
      return;
    }

    final AndroidScheduleMode mode = await _scheduleMode();
    final bool isEn = _lang == 'en';
    const androidDetails = AndroidNotificationDetails(
      'smartcup_water_reminder',
      'แจ้งเตือนดื่มน้ำ SmartCup',
      channelDescription: 'การแจ้งเตือนเตือนดื่มน้ำจากแก้วน้ำอัจฉริยะ',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final String quietStart =
        _settings['quiet_start']?.toString() ?? _defaultBedtime;
    final String? quietEnd = _settings['quiet_end']?.toString();
    final DateTime now = DateTime.now();

    // ---------- 1) แจ้งเตือนดื่มน้ำตามความถี่ ----------
    final int hours = int.tryParse('${_settings['alert_hours']}') ?? -1;
    final int minutes = int.tryParse('${_settings['alert_minutes']}') ?? 0;
    int interval = hours >= 0 ? hours * 60 + minutes : _defaultIntervalMinutes;
    if (interval < _minIntervalMinutes) interval = _minIntervalMinutes;

    // เริ่มนับจากเวลาดื่มล่าสุด (ถ้าไม่มี นับจากตอนนี้)
    DateTime base = now;
    if (_lastDrinkMs != null && _lastDrinkMs! > 0) {
      final lastDrink = DateTime.fromMillisecondsSinceEpoch(_lastDrinkMs!);
      if (lastDrink.isBefore(now)) base = lastDrink;
    }
    final Duration step = Duration(minutes: interval);
    DateTime next = base.add(step);
    while (!next.isAfter(now)) {
      next = next.add(step);
    }

    // เวลาแจ้งเตือน AI (นาทีของวัน) ไว้เช็กไม่ให้เด้งซ้อนกัน
    final List<int> aiMinutes = AiReminder.slotTimes(_settings).values
        .whereType<String>()
        .map(_minutesOf)
        .where((m) => m >= 0)
        .toList();
    bool nearAi(DateTime t) {
      final cur = t.hour * 60 + t.minute;
      for (final m in aiMinutes) {
        final diff = (cur - m).abs();
        if (diff < _aiGapMinutes || 1440 - diff < _aiGapMinutes) return true;
      }
      return false;
    }

    final DateTime limit = now.add(const Duration(hours: 24));
    int slot = 0;
    while (slot < _maxReminders && next.isBefore(limit)) {
      if (!_inQuietTime(next, quietStart, quietEnd) && !nearAi(next)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: _drinkBaseId + slot,
          title: 'SmartCup 💧',
          body: isEn
              ? 'Time to drink some water!'
              : 'ได้เวลาดื่มน้ำแล้ว! จิบน้ำสักนิดนะ',
          scheduledDate: tz.TZDateTime.from(next, tz.local),
          notificationDetails: details,
          androidScheduleMode: mode,
        );
        _drinkTimes.add(next);
        slot++;
      }
      next = next.add(step);
    }
    await smartCupRef('notification_schedule')
        .set(_drinkTimes.map((t) => t.millisecondsSinceEpoch).toList());

    _armInAppTimer();
    debugPrint(
      '⏰ [Reminder] ดื่มน้ำ ${_drinkTimes.length} ครั้ง ทุก $interval นาที'
      ' (${mode == AndroidScheduleMode.exactAllowWhileIdle ? 'ตรงเวลา' : 'อาจคลาดเคลื่อน'})',
    );
  }

  // --------------------------------------------------------- in-app SnackBar

  /// ตั้ง Timer ไปยังแจ้งเตือนครั้งถัดไป เพื่อแสดง SnackBar ตอนเปิดแอปอยู่
  static void _armInAppTimer() {
    _inAppTimer?.cancel();
    final now = DateTime.now();

    DateTime? nextAt;
    ReminderKind? nextKind;
    for (final t in _drinkTimes) {
      if (t.isAfter(now)) {
        nextAt = t;
        nextKind = ReminderKind.drink;
        break;
      }
    }
    // (แจ้งเตือน AI แสดง SnackBar ผ่าน onAiAlert แทน)
    if (nextAt == null || nextKind == null) return;

    final kind = nextKind;
    _inAppTimer = Timer(nextAt.difference(now), () {
      onReminderDue?.call(kind);
      _armInAppTimer(); // ตั้งครั้งถัดไปต่อ
    });
  }
}
