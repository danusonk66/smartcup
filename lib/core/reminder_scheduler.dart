import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../main.dart' show flutterLocalNotificationsPlugin;
import 'utils.dart';

/// ชนิดของแจ้งเตือน (ใช้เลือกข้อความ SnackBar ในแอป)
enum ReminderKind { drink, bedtime }

/// 🌟 ตั้งเวลาแจ้งเตือนไว้ในมือถือล่วงหน้า (ทำงานแม้ปิดแอป)
///
/// 1) แจ้งเตือนดื่มน้ำตามความถี่: นับจากเวลาดื่มล่าสุด ตั้งล่วงหน้า 24 รอบ ข้ามช่วงปิดเสียง
/// 2) แจ้งเตือนก่อนเวลานอน: ทุกวัน ณ (เวลาเริ่มปิดเสียง - เวลาที่ตั้งไว้)
///
/// - อ่านการตั้งค่าจาก /SmartCup/settings และเวลาดื่มล่าสุดจาก /SmartCup/last_drink_timestamp
/// - ทุกครั้งที่ตั้งเวลาใหม่ จะบันทึกแจ้งเตือนที่เด้งไปแล้วลง notification_logs
/// - ระหว่างเปิดแอปอยู่ จะเรียก [onReminderDue] ตรงเวลา เพื่อแสดง SnackBar ในแอป
class ReminderScheduler {
  ReminderScheduler._();

  static const int _drinkBaseId = 1000; // id 1000-1023: แจ้งเตือนดื่มน้ำ
  static const int _bedtimeId = 1100; //   id 1100: แจ้งเตือนก่อนนอน
  static const int _maxReminders = 24;
  static const int _defaultIntervalMinutes = 120;
  static const int _minIntervalMinutes =
      1; // ให้ตั้ง 1 นาทีได้ (ไว้ทดสอบ/สาธิต)
  static const int _defaultBeforeBedMinutes =
      30; // ตรงกับค่าเริ่มต้นในหน้าแจ้งเตือน
  static const String _defaultBedtime =
      '22:00'; // ตรงกับค่าเริ่มต้นในหน้าแจ้งเตือน

  static const String drinkLogMessage = 'ถึงเวลาที่ควรดื่มน้ำ';
  static const String bedtimeLogMessage =
      'ใกล้ถึงเวลานอนแล้ว ดื่มน้ำให้ครบเป้าหมายนะ';

  /// ให้ main.dart ตั้งค่าไว้ เพื่อแสดง SnackBar เมื่อถึงเวลาแจ้งเตือนขณะเปิดแอป
  static void Function(ReminderKind kind)? onReminderDue;

  static StreamSubscription<DatabaseEvent>? _settingsSub;
  static StreamSubscription<DatabaseEvent>? _drinkSub;
  static StreamSubscription<DatabaseEvent>? _langSub;
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
  static String? _bedtimeAlertHHmm;

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
  }

  static void stop() {
    _settingsSub?.cancel();
    _drinkSub?.cancel();
    _langSub?.cancel();
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

  /// เวลาเกิดครั้งถัดไปของ HH:mm (วันนี้ ถ้ายังไม่ถึง ไม่งั้นพรุ่งนี้)
  static DateTime _nextOccurrence(String hhmm, DateTime now) {
    final mins = _minutesOf(hhmm);
    DateTime t = DateTime(now.year, now.month, now.day, mins ~/ 60, mins % 60);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

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

    // แจ้งเตือนก่อนนอน (ทำซ้ำทุกวัน บันทึกเฉพาะครั้งของวันนี้ที่ผ่านไปแล้ว)
    final bedSnap = await smartCupRef('bedtime_reminder').get();
    if (bedSnap.value is Map) {
      final bed = Map<dynamic, dynamic>.from(bedSnap.value as Map);
      final String? hhmm = bed['time']?.toString();
      final int since = int.tryParse('${bed['since']}') ?? nowMs;
      final String? lastLogged = bed['last_logged']?.toString();
      if (hhmm != null && _minutesOf(hhmm) >= 0) {
        final now = DateTime.now();
        final mins = _minutesOf(hhmm);
        final today = DateTime(
          now.year,
          now.month,
          now.day,
          mins ~/ 60,
          mins % 60,
        );
        final int todayMs = today.millisecondsSinceEpoch;
        if (todayMs <= nowMs &&
            todayMs >= since &&
            lastLogged != _dateKey(today)) {
          await _pushLog(todayMs, bedtimeLogMessage);
          await smartCupRef('bedtime_reminder')
              .update({'last_logged': _dateKey(today)});
        }
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
    await flutterLocalNotificationsPlugin.cancel(id: _bedtimeId);
    _drinkTimes = [];
    _bedtimeAlertHHmm = null;

    final bool enabled = _settings['notification_enabled'] != false;
    if (!enabled) {
      await smartCupRef('notification_schedule').set([]);
      await smartCupRef('bedtime_reminder').remove();
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

    final DateTime limit = now.add(const Duration(hours: 24));
    int slot = 0;
    while (slot < _maxReminders && next.isBefore(limit)) {
      if (!_inQuietTime(next, quietStart, quietEnd)) {
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

    // ---------- 2) แจ้งเตือนก่อนเวลานอน (ทุกวัน) ----------
    // เวลานอน = เวลาเริ่มปิดเสียง (หน้า AI ใช้ค่าเดียวกัน)
    int beforeBed =
        int.tryParse('${_settings['before_bed_total_minutes']}') ?? -1;
    if (beforeBed < 0) {
      final h = int.tryParse('${_settings['before_bed_hours']}');
      final m = int.tryParse('${_settings['before_bed_minutes']}');
      beforeBed = (h == null && m == null)
          ? _defaultBeforeBedMinutes
          : (h ?? 0) * 60 + (m ?? 0);
    }

    final int bedMins = _minutesOf(quietStart);
    if (beforeBed > 0 && bedMins >= 0) {
      final int alertMins = ((bedMins - beforeBed) % 1440 + 1440) % 1440;
      final String alertHHmm =
          '${_two(alertMins ~/ 60)}:${_two(alertMins % 60)}';
      final DateTime alertAt = _nextOccurrence(alertHHmm, now);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: _bedtimeId,
        title: 'SmartCup 🌙',
        body: isEn
            ? 'Bedtime is coming up at $quietStart. Finish your water goal!'
            : 'อีก $beforeBed นาทีจะถึงเวลานอน ($quietStart น.) ดื่มน้ำให้ครบเป้าหมายนะ',
        scheduledDate: tz.TZDateTime.from(alertAt, tz.local),
        notificationDetails: details,
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time, // ซ้ำทุกวัน
      );
      _bedtimeAlertHHmm = alertHHmm;
      await smartCupRef('bedtime_reminder')
          .update({'time': alertHHmm, 'since': now.millisecondsSinceEpoch});
    } else {
      await smartCupRef('bedtime_reminder').remove();
    }

    _armInAppTimer();
    debugPrint(
      '⏰ [Reminder] ดื่มน้ำ ${_drinkTimes.length} ครั้ง ทุก $interval นาที'
      '${_bedtimeAlertHHmm != null ? ' / ก่อนนอน $_bedtimeAlertHHmm' : ''}'
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
    if (_bedtimeAlertHHmm != null) {
      final bedAt = _nextOccurrence(_bedtimeAlertHHmm!, now);
      if (nextAt == null || bedAt.isBefore(nextAt)) {
        nextAt = bedAt;
        nextKind = ReminderKind.bedtime;
      }
    }
    if (nextAt == null || nextKind == null) return;

    final kind = nextKind;
    _inAppTimer = Timer(nextAt.difference(now), () {
      onReminderDue?.call(kind);
      _armInAppTimer(); // ตั้งครั้งถัดไปต่อ
    });
  }
}
