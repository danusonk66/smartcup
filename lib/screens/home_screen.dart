import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/theme.dart';
import '../core/utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _currentDisplayWeight = 0;

  // ข้อมูลล่าสุดจาก Firebase เก็บไว้คำนวณใหม่ทุกนาที (เช่น ข้ามเที่ยงคืน, "วันนี้/เมื่อวาน")
  Map<dynamic, dynamic>? _latestData;
  Timer? _clockTimer;

  double _todayTotal = 0;
  double _dailyTarget = 2400;
  double _battery = 100;
  double _cupWeight =
      0; // น้ำหนักภาชนะจาก profile/cup_weight (ใช้หักออกตอนแสดงผล)
  String _userName = 'สมชาย';
  String _selectedLanguage =
      'th'; // 🌟 ตัวแปรที่ซิงค์กับหน้าโปรไฟล์ผ่าน Firebase

  double _lastDrinkAmount = 0;
  String _lastDrinkSubtitle = 'ยังไม่มีประวัติ';

  String _currentDrinkType = 'น้ำเปล่า'; // เก็บค่าภาษาไทยเพื่ออ้างอิงในระบบ

  int _streakDays = 0;

  StreamSubscription<DatabaseEvent>? _subscription;

  final List<String> _drinkTypes = [
    'น้ำเปล่า',
    'น้ำผลไม้',
    'กาแฟ/ชา',
    'นม',
    'ชานมไข่มุก',
    'อื่น ๆ',
  ];

  // 🌟 พจนานุกรมแปลภาษาหน้าแรก
  // static const: เพิ่ม/แก้ข้อความแล้ว Hot Reload เห็นทันที ไม่ต้อง Hot Restart
  static const Map<String, Map<String, String>> _homeTexts = {
    'th': {
      'greeting': 'สวัสดี, ',
      'progress': 'ความคืบหน้า: ',
      'from_goal': 'จากเป้าหมาย ',
      'remaining_line': 'ต้องดื่มอีก ',
      'drunk_label': 'ดื่มแล้ว ',
      'goal_reached': 'ดื่มครบเป้าหมายแล้ว 🎉',
      'water_in_cup': 'น้ำในแก้วตอนนี้: ',
      'miss_target': 'ยังขาดอีก ',
      'miss_target_hint': ' ml ถึงเป้าหมาย\nลองแบ่งจิบเรื่อยๆ ดูนะ!',
      'last_drink': 'ดื่มล่าสุด',
      'streak': 'ต่อเนื่อง',
      'days': ' วัน',
      'keep_it_up': 'เก่งมาก!',
      'select_drink': 'เลือกเครื่องดื่มในแก้ว',
      'reset_title': 'จัดการน้ำในแก้ว',
      'reset_subtitle': 'กดก่อนวางแก้วกลับ เมื่อเทน้ำทิ้งหรือล้างแก้ว น้ำที่เททิ้งจะไม่ถูกนับเป็นยอดดื่ม',
      'reset_button': 'ล้างแก้ว (เริ่มนับน้ำในแก้วใหม่)',
      'today': 'วันนี้ • ',
      'yesterday': 'เมื่อวาน • ',
      'no_history': 'ยังไม่มีประวัติ',
      'reset_success': 'ส่งคำสั่งล้างแก้วแล้ว เครื่องจะเริ่มนับใหม่ (น้ำที่เททิ้งไม่นับเป็นยอดดื่ม)',
      'water': 'น้ำเปล่า',
      'juice': 'น้ำผลไม้',
      'coffee_tea': 'กาแฟ/ชา',
      'milk': 'นม',
      'boba': 'ชานมไข่มุก',
      'other': 'อื่น ๆ',
    },
    'en': {
      'greeting': 'Hello, ',
      'progress': 'Progress: ',
      'from_goal': 'Goal: ',
      'remaining_line': 'Remaining: ',
      'drunk_label': 'Drank ',
      'goal_reached': 'Daily goal reached 🎉',
      'water_in_cup': 'Current water in cup: ',
      'miss_target': '',
      'miss_target_hint':
          ' ml remaining to reach goal\nKeep taking small sips!',
      'last_drink': 'Last Drink',
      'streak': 'Streak',
      'days': ' days',
      'keep_it_up': 'Great job!',
      'select_drink': 'Select drink in cup',
      'reset_title': 'Cup Management',
      'reset_subtitle': 'Press before putting the cup back after emptying or washing it. Poured-out water won\'t count as drunk.',
      'reset_button': 'Wash Cup (Restart cup count)',
      'today': 'Today • ',
      'yesterday': 'Yesterday • ',
      'no_history': 'No history yet',
      'reset_success': 'Wash request sent. The cup will restart its count (poured-out water won\'t count).',
      'water': 'Water',
      'juice': 'Juice',
      'coffee_tea': 'Coffee/Tea',
      'milk': 'Milk',
      'boba': 'Boba Tea',
      'other': 'Others',
    },
  };

  String _t(String key) {
    return _homeTexts[_selectedLanguage]?[key] ??
        _homeTexts['th']?[key] ??
        key.replaceAll('_', ' ');
  }

  // 🌟 น้ำในแก้วสุทธิ = น้ำหนักรวม - น้ำหนักภาชนะ (สูตรเดียวกับจอ OLED บน ESP32)
  // 🌟 เกณฑ์ "ยกแก้วออก": น้ำหนักรวมต่ำกว่านี้ = ไม่มีแก้วบนเครื่อง
  // แก้วหนัก (≥ 40 g) ใช้ 20 g เหมือนเดิม / แก้วเบาใช้ครึ่งหนึ่งของน้ำหนักแก้ว แต่ไม่ต่ำกว่า 5 g
  // (สูตรเดียวกับ ESP32) กันขวดพลาสติกเปล่าถูกเข้าใจว่ายกออก แล้วไม่นับอึกสุดท้าย
  double get _liftThreshold {
    if (_cupWeight >= 40) return 20;
    return math.max(5, _cupWeight / 2).toDouble();
  }

  double _netWater(double gross) {
    if (gross < _liftThreshold) return 0;
    return math.max(0, gross - _cupWeight).toDouble();
  }

  // แปลงประเภทเครื่องดื่มให้สอดคล้องกับภาษา
  String _translateDrinkType(String thaiKey) {
    if (_selectedLanguage == 'th') return thaiKey;
    switch (thaiKey) {
      case 'น้ำเปล่า':
        return _t('water');
      case 'น้ำผลไม้':
        return _t('juice');
      case 'กาแฟ/ชา':
        return _t('coffee_tea');
      case 'นม':
        return _t('milk');
      case 'ชานมไข่มุก':
        return _t('boba');
      case 'อื่น ๆ':
        return _t('other');
      default:
        return thaiKey;
    }
  }

  @override
  void initState() {
    super.initState();
    _listenFirebase();
    // คำนวณใหม่ทุกนาที: ยอดวันนี้จะเป็น 0 เองเมื่อข้ามเที่ยงคืน แม้ไม่มีข้อมูลใหม่เข้ามา
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_latestData != null && mounted) _applyData(_latestData!);
    });
  }

  String _getCurrentDateKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _cleanOldHistoryLogs(
    Map<dynamic, dynamic> historyLogsMap,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime cutoffDate = today.subtract(const Duration(days: 15));
    final String cutoffDateString =
        "${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}";

    Map<String, dynamic> updates = {};
    bool hasOldData = false;

    historyLogsMap.forEach((key, value) {
      String dateKey = key.toString();
      if (dateKey.compareTo(cutoffDateString) < 0) {
        updates['history_logs/$dateKey'] = null;
        hasOldData = true;
      }
    });

    if (hasOldData) {
      try {
        await smartCupRef().update(updates);
      } catch (e) {
        debugPrint('Error cleaning old history: $e');
      }
    }
  }

  void _calculateLatestDrink(Map<dynamic, dynamic> mapData) {
    double foundAmount = 0;
    String foundTime = '';
    int maxTimestamp = -1;
    DateTime? foundDateTime;

    if (mapData['history_logs'] != null && mapData['history_logs'] is Map) {
      final historyMap = Map<dynamic, dynamic>.from(
        mapData['history_logs'] as dynamic,
      );

      historyMap.forEach((dateKey, dateVal) {
        if (dateVal is Map &&
            dateVal['logs'] != null &&
            dateVal['logs'] is Map) {
          final logsMap = Map<dynamic, dynamic>.from(
            dateVal['logs'] as dynamic,
          );
          final DateTime? parsedDate = DateTime.tryParse(dateKey.toString());

          logsMap.forEach((logId, logVal) {
            if (logVal is Map) {
              int ts = int.tryParse('${logVal['timestamp'] ?? logId}') ?? 0;
              if (ts > maxTimestamp) {
                maxTimestamp = ts;
                foundAmount = double.tryParse('${logVal['amount']}') ?? 0;
                foundTime = logVal['time']?.toString() ?? '';

                if (ts > 0) {
                  foundDateTime = DateTime.fromMillisecondsSinceEpoch(ts);
                } else if (parsedDate != null && foundTime.isNotEmpty) {
                  try {
                    final parts = foundTime.split(':');
                    if (parts.length >= 2) {
                      foundDateTime = DateTime(
                        parsedDate.year,
                        parsedDate.month,
                        parsedDate.day,
                        int.parse(parts[0]),
                        int.parse(parts[1]),
                      );
                    }
                  } catch (_) {}
                }
              }
            }
          });
        }
      });
    }

    if (foundDateTime == null && mapData['last_drink_timestamp'] != null) {
      int ts = int.tryParse('${mapData['last_drink_timestamp']}') ?? 0;
      if (ts > 0) {
        foundDateTime = DateTime.fromMillisecondsSinceEpoch(ts);
        foundAmount =
            double.tryParse('${mapData['last_drink_amount']}') ?? foundAmount;
        foundTime = mapData['last_drink_time']?.toString() ?? foundTime;
      }
    }

    if (foundDateTime != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final drinkDay = DateTime(
        foundDateTime!.year,
        foundDateTime!.month,
        foundDateTime!.day,
      );
      final diffDays = today.difference(drinkDay).inDays;

      if (diffDays == 0) {
        _lastDrinkSubtitle = '${_t('today')}$foundTime';
      } else if (diffDays == 1) {
        _lastDrinkSubtitle = '${_t('yesterday')}$foundTime';
      } else {
        _lastDrinkSubtitle =
            '${foundDateTime!.day}/${foundDateTime!.month} • $foundTime';
      }
    } else if (foundTime.isNotEmpty) {
      _lastDrinkSubtitle = foundTime;
    } else {
      _lastDrinkSubtitle = _t('no_history');
    }

    _lastDrinkAmount = foundAmount;
  }

  // 🌟 นับวันต่อเนื่องจากประวัติจริง (ไม่ต้องเก็บ streak แยกแล้วคอยรีเซ็ต)
  // วันนี้ครบเป้าแล้วนับวันนี้ด้วย ถ้ายังไม่ครบเริ่มนับจากเมื่อวานย้อนหลังไป
  int _computeStreak(Map<dynamic, dynamic> historyMap, double target) {
    if (target <= 0) return 0;
    double totalOf(DateTime d) {
      final key =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      final day = historyMap[key];
      if (day is Map) return double.tryParse('${day['daily_total']}') ?? 0;
      return 0;
    }

    final now = DateTime.now();
    DateTime day = DateTime(now.year, now.month, now.day);
    int streak = 0;
    if (totalOf(day) >= target) streak = 1;
    day = day.subtract(const Duration(days: 1));
    while (streak < 365 && totalOf(day) >= target) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // 🌟 หน้าโฮมแสดงผลอย่างเดียว การตรวจจับการดื่ม/บันทึกยอดอยู่ใน ESP32 แล้ว
  // (นับได้ถูกต้องแม้ไม่ได้เปิดแอป)
  void _listenFirebase() {
    if (!isFirebaseReady()) return;

    try {
      _subscription = smartCupRef().onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) return;
        try {
          final mapData = Map<dynamic, dynamic>.from(data as dynamic);
          _latestData = mapData;
          _applyData(mapData);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('❌ [Home] Logic error: $e');
    }
  }

  void _applyData(Map<dynamic, dynamic> mapData) {
    final double rawWeight = double.tryParse('${mapData['weight']}') ?? 0;

    double newDailyTarget = 2400;
    String newName = _userName;
    String newLang = _selectedLanguage;

    if (mapData['profile'] is Map) {
      final profileMap = Map<dynamic, dynamic>.from(
        mapData['profile'] as dynamic,
      );
      newDailyTarget = double.tryParse('${profileMap['daily_target']}') ?? 2400;
      newName = profileMap['name']?.toString() ?? _userName;
      newLang = profileMap['language']?.toString() ?? _selectedLanguage;
      _cupWeight = double.tryParse('${profileMap['cup_weight']}') ?? _cupWeight;
    }

    final String todayKey = _getCurrentDateKey();
    double todayTotal = 0;
    int streak = 0;
    if (mapData['history_logs'] is Map) {
      final historyMap = Map<dynamic, dynamic>.from(
        mapData['history_logs'] as dynamic,
      );
      final today = historyMap[todayKey];
      if (today is Map) {
        todayTotal = double.tryParse('${today['daily_total']}') ?? 0;
      }
      streak = _computeStreak(historyMap, newDailyTarget);
      _cleanOldHistoryLogs(historyMap);
    }

    // เก็บ streak ลง Firebase ไว้ให้หน้า AI ใช้ (เขียนเฉพาะตอนค่าเปลี่ยน)
    final int storedStreak = int.tryParse('${mapData['streak_days']}') ?? -1;
    if (storedStreak != streak) {
      smartCupRef().update({'streak_days': streak});
    }

    _selectedLanguage =
        newLang; // ให้ข้อความ "วันนี้/เมื่อวาน" ใช้ภาษาที่ถูกต้อง
    _calculateLatestDrink(mapData);

    String drinkType =
        mapData['current_drink_type']?.toString() ?? _currentDrinkType;
    if (!_drinkTypes.contains(drinkType)) drinkType = 'น้ำเปล่า';

    if (!mounted) return;
    setState(() {
      _userName = newName;
      _selectedLanguage = newLang;
      _dailyTarget = newDailyTarget;
      _todayTotal = todayTotal;
      _streakDays = streak;
      _battery = double.tryParse('${mapData['battery_percent']}') ?? _battery;
      _currentDrinkType = drinkType;
      // ESP32 ส่งเฉพาะน้ำหนักที่นิ่งแล้ว แสดงได้ทันที
      _currentDisplayWeight = _netWater(rawWeight);
    });
  }

  Future<void> _selectDrink(String? translatedType) async {
    if (translatedType == null) return;

    // ค้นหาคีย์ภาษาไทยเพื่อเก็บลงระบบแบบมาตรฐาน
    String thaiKey = 'น้ำเปล่า';
    for (String key in _drinkTypes) {
      if (_translateDrinkType(key) == translatedType) {
        thaiKey = key;
        break;
      }
    }

    setState(() {
      _currentDrinkType = thaiKey;
    });

    if (!isFirebaseReady()) return;
    try {
      await smartCupRef().update({'current_drink_type': thaiKey});
      // ignore: empty_catches
    } catch (e) {}
  }

  // 🌟 ปุ่มล้างแก้ว: ส่งคำขอให้ ESP32 ตั้งจุดเริ่มนับใหม่
  // ESP32 จะไม่นับน้ำที่หายไปครั้งถัดไปเป็นการดื่ม (เพราะคือน้ำที่เททิ้ง)
  // แล้วเริ่มนับจากน้ำหนักที่วางอยู่ตอนนั้น
  Future<void> _resetWater() async {
    if (!isFirebaseReady()) return;

    try {
      await smartCupRef('control').update({'reset_baseline': true});

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('reset_success'))));
    } catch (e) {
      debugPrint('Reset request error: $e');
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double percent = _dailyTarget <= 0
        ? 0.0
        : (_todayTotal / _dailyTarget).clamp(0.0, 1.0).toDouble();

    final double remaining = (_dailyTarget - _todayTotal)
        .clamp(0.0, double.infinity)
        .toDouble();

    return Scaffold(
      backgroundColor: bgLight,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Stack(
          children: [
            const _AuraBackground(),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 20),
                        _buildHydrationDashboard(percent, remaining),
                        if (remaining > 0) ...[
                          const SizedBox(height: 24),
                          _buildNotificationBanner(remaining),
                        ],
                        const SizedBox(height: 12),
                        _buildStatsRow(),
                        const SizedBox(height: 12),
                        _buildDrinkTypeCard(),
                        const SizedBox(height: 28),
                        _buildResetButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final Color batteryColor = _battery > 20 ? accentGreen : Colors.red;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_t('greeting')}$_userName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textDark,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // แสดงค่าแบตเตอรี่อย่างเดียว (ไม่สามารถกดเข้าไปดูรายละเอียดได้)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: ShapeDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: StadiumBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.95)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.battery_charging_full, color: batteryColor, size: 20),
              const SizedBox(width: 6),
              Text(
                '${_battery.toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHydrationDashboard(double percent, double remaining) {
    final String label = _t('progress').replaceAll(':', '').trim();
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final double dw = math.min(c.maxWidth / 1.5, 220.0);
            return Center(
              child: _HydroDrop(width: dw, percent: percent, label: label),
            );
          },
        ),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                // 🌟 ป้าย "ดื่มแล้ว" หน้าตัวเลขยอดดื่มวันนี้
                TextSpan(
                  text: _t('drunk_label'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: textGrey,
                  ),
                ),
                TextSpan(
                  text: formatNumber(_todayTotal),
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                    color: textDark,
                    height: 1.1,
                  ),
                ),
                const TextSpan(
                  text: ' ml',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: oceanBlue,
                  ),
                ),
                // 🌟 ปริมาณที่ดื่มแล้วเป็นจำนวนแก้ว (1 แก้ว = 240 ml)
                TextSpan(
                  text:
                      ' ${formatGlasses(_todayTotal, lang: _selectedLanguage)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: textGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_t('from_goal')}${formatNumber(_dailyTarget)} ml '
          '${formatGlasses(_dailyTarget, lang: _selectedLanguage)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: textGrey, fontSize: 15),
        ),
        const SizedBox(height: 4),
        // 🌟 ปริมาณที่เหลือต้องดื่ม (ml + แก้ว) หรือข้อความเมื่อครบเป้าหมาย
        Text(
          remaining > 0
              ? '${_t('remaining_line')}${formatNumber(remaining)} ml '
                    '${formatGlasses(remaining, lang: _selectedLanguage)}'
              : _t('goal_reached'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: remaining > 0 ? oceanBlue : accentGreen,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.water_drop_rounded,
                  color: oceanBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${_t('water_in_cup')}${formatNumber(_currentDisplayWeight)} ml',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textDark,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationBanner(double remaining) {
    return _Glass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: coral.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: coral,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${_t('miss_target')}${formatNumber(remaining)}${_t('miss_target_hint')}',
              style: const TextStyle(
                color: textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return _Glass(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _statTile(
                icon: Icons.history_rounded,
                title: _t('last_drink'),
                value: _lastDrinkAmount > 0
                    ? '${formatNumber(_lastDrinkAmount)} ml'
                    : '0 ml',
                subtitle: _lastDrinkSubtitle,
                color: oceanBlue,
              ),
            ),
            Container(width: 1, color: oceanBlue.withValues(alpha: 0.12)),
            Expanded(
              child: _statTile(
                icon: Icons.local_fire_department_rounded,
                title: _t('streak'),
                value: '$_streakDays${_t('days')}',
                subtitle: _t('keep_it_up'),
                color: coral,
                extra: Row(
                  children: List.generate(7, (i) {
                    final bool lit = i < _streakDays;
                    return Container(
                      width: 14,
                      height: 5,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: lit ? coral : oceanBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    Widget? extra,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: textGrey, fontSize: 12),
          ),
          if (extra != null) ...[const SizedBox(height: 8), extra],
        ],
      ),
    );
  }

  Widget _buildDrinkTypeCard() {
    return _Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('select_drink'),
            style: const TextStyle(
              color: textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _drinkTypes.map((type) {
              final bool selected = _currentDrinkType == type;
              return Semantics(
                button: true,
                selected: selected,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected
                        ? oceanBlue
                        : Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? oceanBlue
                          : Colors.white.withValues(alpha: 0.95),
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: oceanBlue.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _selectDrink(_translateDrinkType(type)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getDrinkIcon(type),
                              size: 18,
                              color: selected ? Colors.white : oceanBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _translateDrinkType(type),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected ? Colors.white : textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _getDrinkIcon(String type) {
    switch (type) {
      case 'น้ำเปล่า':
        return Icons.water_drop;
      case 'น้ำผลไม้':
        return Icons.local_drink;
      case 'กาแฟ/ชา':
        return Icons.coffee;
      case 'นม':
        return Icons.local_drink_outlined;
      case 'ชานมไข่มุก':
        return Icons.bubble_chart;
      default:
        return Icons.local_bar;
    }
  }

  // ปุ่มล้างแก้ว (เคลียร์ค่าน้ำในแก้วปัจจุบันเป็น 0 โดยไม่กระทบยอดรวมของวันนี้)
  Widget _buildResetButton() {
    return Column(
      children: [
        Text(
          _t('reset_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _t('reset_subtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: textGrey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _resetWater,
          icon: const Icon(Icons.cleaning_services_rounded, size: 18),
          label: Text(_t('reset_button')),
          style: TextButton.styleFrom(
            foregroundColor: oceanBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── พื้นหลังแสงน้ำ ─────────────────────────

class _AuraBackground extends StatelessWidget {
  const _AuraBackground();

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -70,
              child: _blob(cyanLight.withValues(alpha: 0.45), 360),
            ),
            Positioned(
              top: 360,
              right: -120,
              child: _blob(mint.withValues(alpha: 0.30), 340),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: _blob(cyanLight.withValues(alpha: 0.25), 320),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── การ์ดกระจกฝ้า ─────────────────────────

class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const _Glass({
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(
            color: oceanBlue.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.78),
                  Colors.white.withValues(alpha: 0.50),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── หยดน้ำแสดงความคืบหน้า ─────────────────────────

const Color _waterTop = Color(0xFF7BDDF7);
const Color _waterBottom = Color(0xFF1FB3E0);
const Color _ringStart = Color(0xFF22C3E6);

class _HydroDrop extends StatefulWidget {
  final double width; // ความกว้างของตัวหยดน้ำ
  final double percent;
  final String label;
  const _HydroDrop({
    required this.width,
    required this.percent,
    required this.label,
  });

  @override
  State<_HydroDrop> createState() => _HydroDropState();
}

class _HydroDropState extends State<_HydroDrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    final double dw = widget.width;
    final double dh = dw * 1.28;
    final double totalW = dw * 1.5;
    final double totalH = dw * 1.58; // เผื่อพื้นที่คลื่นน้ำใต้หยด
    final double bodyCenterY = dh - dw / 2;

    return RepaintBoundary(
      child: SizedBox(
        width: totalW,
        height: totalH,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: widget.percent),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 1300),
          curve: Curves.easeOutCubic,
          builder: (context, level, _) {
            return AnimatedBuilder(
              animation: _wave,
              builder: (context, _) {
                return Stack(
                  children: [
                    CustomPaint(
                      size: Size(totalW, totalH),
                      painter: _DropPainter(
                        level: level,
                        phase: reduceMotion ? 0 : _wave.value * 2 * math.pi,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: bodyCenterY - 40,
                      height: 80,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${(level * 100).toInt()}',
                                    style: TextStyle(
                                      fontSize: dw * 0.2,
                                      fontWeight: FontWeight.w700,
                                      color: primaryDark,
                                      height: 1.1,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '%',
                                    style: TextStyle(
                                      fontSize: dw * 0.08,
                                      fontWeight: FontWeight.w700,
                                      color: primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              widget.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DropPainter extends CustomPainter {
  final double level;
  final double phase;
  const _DropPainter({required this.level, required this.phase});

  // รูปทรงหยดน้ำ: ปลายแหลมด้านบน ตัวป้อมกลมด้านล่าง
  static Path _dropPath(Rect r) {
    final double w = r.width;
    final double h = r.height;
    final double rad = w / 2;
    return Path()
      ..moveTo(r.left + w / 2, r.top)
      ..cubicTo(
        r.left + w / 2 + w * 0.08,
        r.top + h * 0.18,
        r.right,
        r.top + h * 0.42,
        r.right,
        r.bottom - rad,
      )
      ..arcToPoint(
        Offset(r.left, r.bottom - rad),
        radius: Radius.circular(rad),
        clockwise: true,
      )
      ..cubicTo(
        r.left,
        r.top + h * 0.42,
        r.left + w / 2 - w * 0.08,
        r.top + h * 0.18,
        r.left + w / 2,
        r.top,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double dw = size.width / 1.5;
    final double dh = dw * 1.28;
    final double left = (size.width - dw) / 2;
    final Rect rect = Rect.fromLTWH(left, 0, dw, dh);
    final Path drop = _dropPath(rect);
    final double lv = level.clamp(0.0, 1.0).toDouble();
    final double cycle = phase / (2 * math.pi);

    // วงคลื่นน้ำใต้หยด แผ่ออกเป็นระลอก
    for (int k = 0; k < 3; k++) {
      final double t = (cycle + k / 3) % 1.0;
      final double rw = dw * (0.5 + 0.9 * t);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, dh + dw * 0.10),
          width: rw,
          height: rw * 0.22,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _ringStart.withValues(alpha: 0.45 * (1 - t)),
      );
    }

    // แสงเรืองด้านหลังหยดน้ำ
    canvas.drawPath(
      drop,
      Paint()
        ..color = cyanLight.withValues(alpha: 0.20 + 0.22 * lv)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    // เนื้อกระจกของหยดน้ำ
    canvas.drawPath(drop, Paint()..color = Colors.white.withValues(alpha: 0.6));

    // น้ำภายในหยด
    if (lv > 0.005) {
      canvas.save();
      canvas.clipPath(drop);
      final double top = rect.bottom - rect.height * lv;
      final double amp =
          5.0 * math.sin(math.pi * lv).clamp(0.25, 1.0).toDouble();

      void layer(double ph, double yOff, double alpha, bool foam) {
        final Path fill = Path()..moveTo(rect.left, rect.bottom + 2);
        final Path line = Path();
        bool first = true;
        for (double x = rect.left; x <= rect.right; x += 3) {
          final double y =
              top +
              yOff +
              amp *
                  math.sin(
                    (x - rect.left) / rect.width * 2 * math.pi * 1.2 + ph,
                  );
          fill.lineTo(x, y);
          if (first) {
            line.moveTo(x, y);
            first = false;
          } else {
            line.lineTo(x, y);
          }
        }
        fill
          ..lineTo(rect.right, rect.bottom + 2)
          ..close();
        final Shader shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _waterTop.withValues(alpha: alpha),
            _waterBottom.withValues(alpha: alpha),
          ],
        ).createShader(rect);
        canvas.drawPath(fill, Paint()..shader = shader);
        if (foam) {
          canvas.drawPath(
            line,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.white.withValues(alpha: 0.9),
          );
        }
      }

      layer(phase + math.pi, -5, 0.55, false);
      layer(phase, 0, 1.0, true);

      // ฟองอากาศลอยขึ้นในน้ำ
      final double waterH = rect.bottom - top;
      if (waterH > 24) {
        const List<List<double>> bubbles = [
          [0.30, 0.00, 3.0],
          [0.55, 0.30, 2.2],
          [0.70, 0.60, 3.4],
          [0.45, 0.80, 1.8],
          [0.62, 0.15, 2.6],
        ];
        for (final b in bubbles) {
          final double t = (cycle * 2 + b[1]) % 1.0;
          final double y = rect.bottom - 10 - t * (waterH - 18);
          final double x =
              rect.left +
              rect.width * b[0] +
              4 * math.sin(t * 2 * math.pi * 2 + b[1] * 10);
          canvas.drawCircle(
            Offset(x, y),
            b[2],
            Paint()
              ..color = Colors.white.withValues(alpha: 0.6 * (1 - t * 0.5)),
          );
        }
      }
      canvas.restore();
    }

    // ขอบกระจก + ไฮไลต์
    canvas.drawPath(
      drop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + dw * 0.16, dh * 0.70)
        ..quadraticBezierTo(
          rect.left + dw * 0.12,
          dh * 0.52,
          rect.left + dw * 0.30,
          dh * 0.36,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // สเกลระดับน้ำ 10 ขีดสองข้าง สว่างไล่สีฟ้า → มิ้นต์ ตามความคืบหน้า
    final double yBottom = dh - dw * 0.18;
    final double yTop = dw * 0.15;
    final Paint off = Paint()
      ..color = oceanBlue.withValues(alpha: 0.16)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final Path glow = Path();
    for (final int side in const [-1, 1]) {
      final double x0 = side < 0
          ? rect.left - dw * 0.10
          : rect.right + dw * 0.10;
      for (int i = 0; i < 10; i++) {
        final double y = yBottom - (yBottom - yTop) * (i / 9);
        final double len = (i == 4 || i == 9) ? 18 : 10;
        final Offset p1 = Offset(x0, y);
        final Offset p2 = Offset(x0 + side * len, y);
        if (lv > i / 10) {
          glow
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy);
          canvas.drawLine(
            p1,
            p2,
            Paint()
              ..color = Color.lerp(_ringStart, mint, i / 9)!
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawLine(p1, p2, off);
        }
      }
    }
    canvas.drawPath(
      glow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = _ringStart.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  @override
  bool shouldRepaint(covariant _DropPainter old) =>
      old.level != level || old.phase != phase;
}
