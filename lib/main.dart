import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

import 'core/theme.dart';
import 'core/reminder_scheduler.dart';
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

// (เช็กช่วงปิดเสียงย้ายไปอยู่ใน core/reminder_scheduler.dart แล้ว)

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

  // 🌟 ใช้เขตเวลาไทยสำหรับตั้งเวลาแจ้งเตือนล่วงหน้า
  ReminderScheduler.initTimeZone();

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
  // 🌟 แจ้งเตือนดื่มน้ำ: ตั้งเวลาไว้ในเครื่องล่วงหน้า (ทำงานแม้ปิดแอป)
  // แทนการรอ ESP32 ยิง /notification/trigger ซึ่งเด้งได้เฉพาะตอนเปิดแอปอยู่
  @override
  void initState() {
    super.initState();
    // 🌟 ถึงเวลาแจ้งเตือนตอนเปิดแอปอยู่ → แสดง SnackBar ในแอปด้วย
    ReminderScheduler.onReminderDue = _showReminderSnackBar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReminderScheduler.start();
    });
  }

  void _showReminderSnackBar(ReminderKind kind) {
    final bool isEn = ReminderScheduler.language == 'en';
    final bool bedtime = kind == ReminderKind.bedtime;

    final String title = bedtime
        ? (isEn ? 'Bedtime is coming up 🌙' : 'ใกล้ถึงเวลานอนแล้ว 🌙')
        : (isEn ? 'Time to drink water! 💧' : 'ได้เวลาดื่มน้ำแล้ว! 💧');
    final String subtitle = bedtime
        ? (isEn
              ? 'Finish your water goal before bed.'
              : 'ดื่มน้ำให้ครบเป้าหมายก่อนนอนนะครับ')
        : (isEn
              ? 'Take a few sips to stay refreshed.'
              : 'จิบน้ำสักนิดเพื่อความสดชื่นนะครับ');

    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                bedtime ? Icons.bedtime_rounded : Icons.water_drop_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: primaryDark,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  void dispose() {
    ReminderScheduler.onReminderDue = null;
    ReminderScheduler.stop();
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
