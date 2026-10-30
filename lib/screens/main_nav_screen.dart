import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/ui_kit.dart';
import '../core/utils.dart'; // สำคัญ: ต้องนำเข้าเพื่อเรียกใช้ isFirebaseReady และ smartCupRef

import 'profile_screen.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'ai_screen.dart';
import 'notification_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรเก็บภาษา
  StreamSubscription<DatabaseEvent>? _langSubscription;

  // 🌟 จัดเรียงลำดับหน้าจอใหม่: [0] โปรไฟล์, [1] ตรวจสอบน้ำหนัก, [2] ประวัติ, [3] AI, [4] แจ้งเตือน
  final List<Widget> _screens = const [
    ProfileScreen(),
    HomeScreen(),
    HistoryScreen(),
    AIScreen(),
    NotificationScreen(),
  ];

  // 🌟 พจนานุกรมแปลภาษาสำหรับแถบเมนูด้านล่าง (key ตรงกับหน้าจอ อ่านง่าย ไม่สลับกัน)
  static const Map<String, Map<String, String>> _navTexts = {
    'th': {
      'profile': 'โปรไฟล์',
      'water': 'ตรวจสอบน้ำหนัก',
      'history': 'ประวัติ',
      'ai': 'AI',
      'noti': 'แจ้งเตือน',
    },
    'en': {
      'profile': 'Profile',
      'water': 'Check Weight',
      'history': 'History',
      'ai': 'AI',
      'noti': 'Alerts',
    },
  };

  String _t(String key) {
    return _navTexts[_selectedLanguage]?[key] ?? _navTexts['th']?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _listenLanguage();
  }

  // 🌟 ฟังก์ชันดึงค่าภาษาจาก Firebase แบบ Real-time
  void _listenLanguage() {
    if (!isFirebaseReady()) return;
    try {
      _langSubscription = smartCupRef('profile/language').onValue
          .listen((event) {
            final lang = event.snapshot.value?.toString() ?? 'th';
            if (mounted) {
              setState(() {
                _selectedLanguage = lang;
              });
            }
          });
    } catch (e) {
      debugPrint('Main Nav Lang error: $e');
    }
  }

  @override
  void dispose() {
    _langSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // พื้นหลังแสงน้ำอันเดียว ใช้ร่วมกันทุกแท็บ
          const AuraBackground(),
          IndexedStack(index: _currentIndex, children: _screens),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        // 🌟 จัดเรียงไอคอนและปุ่มเมนูด้านล่างให้ตรงกับลำดับหน้าจอเป๊ะๆ
        destinations: [
          // [0] โปรไฟล์และการตั้งค่า (หน้าแรกที่เปิดมาเจอ)
          NavigationDestination(
            icon: const Icon(Icons.account_circle_outlined),
            selectedIcon: const Icon(Icons.account_circle),
            label: _t('profile'),
          ),
          // [1] ตรวจสอบน้ำหนัก / ปริมาณน้ำวันนี้ (ใช้หยดน้ำ ให้ตรงกับหยดน้ำในหน้านั้น)
          NavigationDestination(
            icon: const Icon(Icons.water_drop_outlined),
            selectedIcon: const Icon(Icons.water_drop),
            label: _t('water'),
          ),
          // [2] ประวัติ
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: _t('history'),
          ),
          // [3] AI
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: _t('ai'),
          ),
          // [4] แจ้งเตือน
          NavigationDestination(
            icon: const Icon(Icons.notifications_none),
            selectedIcon: const Icon(Icons.notifications),
            label: _t('noti'),
          ),
        ],
      ),
    );
  }
}
