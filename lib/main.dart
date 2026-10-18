import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

import 'core/theme.dart';
import 'core/utils.dart';
import 'screens/main_nav_screen.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
  'smartcup_water_reminder',
  'แจ้งเตือนดื่มน้ำ SmartCup',
  description: 'การแจ้งเตือนเตือนดื่มน้ำจากแก้วน้ำอัจฉริยะ',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

// ฟังก์ชันคำนวณว่าเวลาปัจจุบันอยู่ในช่วงเวลาปิดเสียงหรือไม่
bool isTimeInQuietRange(String? startStr, String? endStr) {
  if (startStr == null || endStr == null) return false;
  try {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final startParts = startStr.split(':');
    final endParts = endStr.split(':');
    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (startMinutes == endMinutes) return false;

    if (startMinutes < endMinutes) {
      // อยู่ในวันเดียวกัน เช่น 09:00 ถึง 17:00
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // ข้ามเที่ยงคืน เช่น 22:00 ถึง 06:00
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  } catch (e) {
    debugPrint('⚠️ [Quiet Time Error] ไม่สามารถคำนวณเวลาได้: $e');
    return false;
  }
}

Future<void> showSystemNotification({
  required String title,
  required String body,
}) async {
  try {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'smartcup_water_reminder',
          'แจ้งเตือนดื่มน้ำ SmartCup',
          channelDescription: 'การแจ้งเตือนเตือนดื่มน้ำจากแก้วน้ำอัจฉริยะ',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: platformDetails,
    );
    debugPrint('🚀 [Notification] เด้งแจ้งเตือนระดับระบบ Android สำเร็จ!');
  } catch (e) {
    debugPrint('❌ [Notification Error] ไม่สามารถยิงแจ้งเตือนได้: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
    "🔔 [FCM Background] ได้รับแจ้งเตือน: ${message.notification?.title}",
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ [System] Firebase เชื่อมต่อสำเร็จ!');

    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: initSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(alertChannel);
    await androidPlugin?.requestNotificationsPermission();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.subscribeToTopic('smartcup');
    debugPrint('✅ [System] ระบบแจ้งเตือนพร้อมทำงาน');
  } catch (e) {
    debugPrint('❌ [System] เกิดข้อผิดพลาดตั้งค่าเริ่มต้น: $e');
  }

  runApp(const SmartCupApp());
}

class SmartCupApp extends StatefulWidget {
  const SmartCupApp({super.key});

  @override
  State<SmartCupApp> createState() => _SmartCupAppState();
}

class _SmartCupAppState extends State<SmartCupApp> {
  StreamSubscription<DatabaseEvent>? _triggerSubscription;

  bool _isFirstEvent = true;
  bool? _lastTriggerState;
  DateTime? _lastAlertTime;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTriggerListener();
    });
  }

  void _initTriggerListener() {
    if (!isFirebaseReady()) return;

    try {
      _triggerSubscription = smartCupRef('notification')
          .child('trigger')
          .onValue
          .listen((event) async {
            final isTriggered = event.snapshot.value == true;
            debugPrint(
              '📡 [SmartCup RTDB] ค่า trigger ปัจจุบัน = $isTriggered',
            );

            // ข้ามรอบแรกเพื่อป้องกันแคชค้างส่งเสียงตอนเปิดแอป
            if (_isFirstEvent) {
              _isFirstEvent = false;
              _lastTriggerState = isTriggered;
              if (isTriggered) {
                debugPrint('🧹 [SmartCup RTDB] เคลียร์ค่า trigger เก่าทิ้ง');
                smartCupRef('notification').update({'trigger': false});
              }
              return;
            }

            final bool isChangedToTrue =
                (_lastTriggerState == false && isTriggered == true);
            _lastTriggerState = isTriggered;

            if (!isChangedToTrue) return;

            // Cooldown 15 วินาที
            final now = DateTime.now();
            if (_isProcessing ||
                (_lastAlertTime != null &&
                    now.difference(_lastAlertTime!).inSeconds < 15)) {
              debugPrint(
                '⏳ [SmartCup Alert] อยู่ในช่วง Cooldown ข้ามการแจ้งเตือน',
              );
              return;
            }

            _isProcessing = true;
            _lastAlertTime = now;

            try {
              final settingsSnapshot = await smartCupRef('settings').get();
              if (settingsSnapshot.exists && settingsSnapshot.value is Map) {
                final settings = Map<dynamic, dynamic>.from(
                  settingsSnapshot.value as Map,
                );
                final bool isNotificationEnabled =
                    settings['notification_enabled'] != false;
                final String? quietStart = settings['quiet_start']?.toString();
                final String? quietEnd = settings['quiet_end']?.toString();

                // 1. ตรวจสอบว่าเปิดการแจ้งเตือนหรือไม่
                if (!isNotificationEnabled) {
                  debugPrint('🔕 [SmartCup Alert] ผู้ใช้ปิดการแจ้งเตือนไว้');
                  await smartCupRef('notification').update({'trigger': false});
                  return;
                }

                // 2. ตรวจสอบว่าอยู่ในช่วงเวลาปิดเสียงหรือไม่
                if (isTimeInQuietRange(quietStart, quietEnd)) {
                  debugPrint(
                    '🌙 [SmartCup Alert] อยู่ในช่วงเวลาปิดเสียง ($quietStart - $quietEnd)',
                  );
                  await smartCupRef('notification').update({'trigger': false});
                  return;
                }
              }

              debugPrint('🔔 [SmartCup Alert] ส่งการแจ้งเตือนดื่มน้ำ');

              // ยิงแจ้งเตือนระดับ OS
              await showSystemNotification(
                title: 'SmartCup 💧',
                body: 'ได้เวลาดื่มน้ำแล้วครับ เพื่อสุขภาพที่ดี!',
              );

              // 🌟 บันทึกประวัติลง Firebase เพื่อนำไปแสดงในหน้าประวัติแจ้งเตือน
              final timeStr =
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              smartCupRef('notification_logs').push().set({
                'time': timeStr,
                'message': 'ถึงเวลาที่ควรดื่มน้ำ',
                'timestamp': ServerValue.timestamp,
              });

              // แสดง SnackBar ดีไซน์ใหม่ภายในแอป
              messengerKey.currentState?.showSnackBar(
                SnackBar(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  content: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.water_drop_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ได้เวลาดื่มน้ำแล้ว! 💧',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'จิบน้ำสักนิดเพื่อความสดชื่นนะครับ',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: primaryDark,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );

              // รีเซ็ตสถานะกลับเป็น false
              await smartCupRef('notification').update({'trigger': false});
            } catch (e) {
              debugPrint('❌ [SmartCup Alert Error]: $e');
            } finally {
              _isProcessing = false;
            }
          });
    } catch (e) {
      debugPrint('❌ [SmartCup RTDB] Error: $e');
    }
  }

  @override
  void dispose() {
    _triggerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      title: 'SmartCup',
      debugShowCheckedModeBanner: false,
      theme: smartCupTheme(),
      home: const MainNavigationScreen(),
    );
  }
}
