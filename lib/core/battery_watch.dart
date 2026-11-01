import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'utils.dart';

// ═════════════════════════════════════════════════════════════════════
// 🔋 แจ้งเตือนแบตแก้วใกล้หมด — ทำงานแม้ปิดแอป
//
// - เบื้องหลัง: เช็ก /SmartCup/battery_percent ทุก 15 นาที (ขั้นต่ำของ Android)
// - เปิดแอปอยู่: เช็กทันทีทุกครั้งที่ % แบตเปลี่ยน
// - เตือน 2 ระดับ: เหลือ ≤ 20% และ ≤ 10% (ระดับละครั้ง ไม่เด้งซ้ำ)
// - ชาร์จกลับมาเกิน 30% → รีเซ็ต พร้อมเตือนใหม่รอบหน้า
// - จำว่าเตือนระดับไหนไปแล้วที่ /SmartCup/battery_alert/level
// - เคารพสวิตช์ "เปิดการแจ้งเตือน" (ไม่สนช่วงปิดเสียง เพราะเป็นเรื่องตัวเครื่อง)
// ═════════════════════════════════════════════════════════════════════

const String batteryTaskName = 'smartcup_battery_check';

class BatteryWatch {
  BatteryWatch._();

  static const int _warnLevel = 20;
  static const int _criticalLevel = 10;
  static const int _resetLevel = 30;
  static const int _notifId = 3001;

  /// ลงทะเบียนงานเช็กแบตเบื้องหลังทุก 15 นาที (เรียกครั้งเดียวใน main)
  static Future<void> register() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      'battery_watch',
      batteryTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// งานเบื้องหลัง (แอปปิดอยู่)
  static Future<void> runInBackground() async {
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await check();
  }

  /// เช็กแบตแล้วแจ้งเตือนถ้าต้องเตือน — คืนข้อความที่เตือน (null = ไม่ได้เตือน)
  static Future<Map<String, String>?> check() async {
    final snap = await smartCupRef().get().timeout(const Duration(seconds: 20));
    if (snap.value is! Map) return null;
    final data = Map<dynamic, dynamic>.from(snap.value as Map);

    final int? percent = int.tryParse('${data['battery_percent']}');
    if (percent == null) return null;

    final alert = data['battery_alert'] is Map
        ? Map<dynamic, dynamic>.from(data['battery_alert'] as Map)
        : <dynamic, dynamic>{};
    final int lastLevel = int.tryParse('${alert['level']}') ?? 0;

    // ชาร์จแล้ว → รีเซ็ตให้เตือนใหม่ได้
    if (percent >= _resetLevel) {
      if (lastLevel != 0) {
        await smartCupRef('battery_alert').set({'level': 0});
      }
      return null;
    }

    int levelToAlert = 0;
    if (percent <= _criticalLevel && lastLevel != _criticalLevel) {
      levelToAlert = _criticalLevel;
    } else if (percent <= _warnLevel && lastLevel == 0) {
      levelToAlert = _warnLevel;
    }
    if (levelToAlert == 0) return null;

    // จำไว้ก่อน (กันเด้งซ้ำแม้ปิดแจ้งเตือนไว้)
    await smartCupRef('battery_alert').set({
      'level': levelToAlert,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = data['settings'] is Map
        ? Map<dynamic, dynamic>.from(data['settings'] as Map)
        : <dynamic, dynamic>{};
    if (settings['notification_enabled'] == false) return null;

    final profile = data['profile'] is Map
        ? Map<dynamic, dynamic>.from(data['profile'] as Map)
        : <dynamic, dynamic>{};
    final bool isEn = profile['language']?.toString() == 'en';

    final bool critical = levelToAlert == _criticalLevel;
    final message = {
      'title': critical
          ? (isEn
                ? '🪫 SmartCup battery critical!'
                : '🪫 แบตแก้ว SmartCup ใกล้หมดมาก!')
          : (isEn
                ? '🔋 SmartCup battery low'
                : '🔋 แบตแก้ว SmartCup เหลือน้อย'),
      'body': isEn
          ? 'Battery at $percent%. Please charge it soon so your drinks keep being recorded.'
          : 'แบตเหลือ $percent% กรุณาชาร์จแก้ว เพื่อให้บันทึกการดื่มน้ำได้ต่อเนื่อง',
    };

    await _show(message['title']!, message['body']!);
    return message;
  }

  static Future<void> _show(String title, String body) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.show(
      id: _notifId,
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
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
    debugPrint('🔋 [Battery] แจ้งเตือน: $title');
  }
}
