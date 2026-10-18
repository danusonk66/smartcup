import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/ui_kit.dart';
import '../core/utils.dart'; // สำคัญ: ต้องนำเข้าเพื่อเรียกใช้ isFirebaseReady และ smartCupRef

import 'home_screen.dart';
import 'history_screen.dart';
import 'ai_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรเก็บภาษา
  StreamSubscription<DatabaseEvent>? _langSubscription;

  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    AIScreen(),
    NotificationScreen(),
    ProfileScreen(),
  ];

  // 🌟 พจนานุกรมแปลภาษาสำหรับแถบเมนูด้านล่าง
  final Map<String, Map<String, String>> _navTexts = {
    'th': {
      'home': 'หน้าหลัก',
      'history': 'ประวัติ',
      'ai': 'AI',
      'noti': 'แจ้งเตือน',
      'profile': 'โปรไฟล์',
    },
    'en': {
      'home': 'Home',
      'history': 'History',
      'ai': 'AI',
      'noti': 'Alerts',
      'profile': 'Profile',
    },
  };

  String _t(String key) {
    return _navTexts[_selectedLanguage]?[key] ?? key;
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
        // 🌟 เอาคำว่า const ออก เพื่อให้ข้อความสามารถอัปเดตแบบ Dynamic ได้
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: _t('home'), // 🌟 ใช้คำแปลภาษา
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history),
            label: _t('history'), // 🌟 ใช้คำแปลภาษา
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: _t('ai'), // 🌟 ใช้คำแปลภาษา
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none),
            selectedIcon: const Icon(Icons.notifications),
            label: _t('noti'), // 🌟 ใช้คำแปลภาษา
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: _t('profile'), // 🌟 ใช้คำแปลภาษา
          ),
        ],
      ),
    );
  }
}
