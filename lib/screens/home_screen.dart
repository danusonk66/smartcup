import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import 'battery_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _currentDisplayWeight = 0;
  double _lastStableWeight = 0;
  double _pendingWeight = -1;
  Timer? _debounceTimer;

  double _todayTotal = 0;
  double _dailyTarget = 2400;
  double _battery = 100;
  String _userName = 'สมชาย';
  String _selectedLanguage =
      'th'; // 🌟 ตัวแปรที่ซิงค์กับหน้าโปรไฟล์ผ่าน Firebase

  double _lastDrinkAmount = 0;
  String _lastDrinkSubtitle = 'ยังไม่มีประวัติ';

  String _currentDrinkType = 'น้ำเปล่า'; // เก็บค่าภาษาไทยเพื่ออ้างอิงในระบบ
  String _lastDrinkTime = '08:00';
  String _sinceLastDrink = '0h 0m';

  int _streakDays = 0;
  bool _isInitialLoad = true;
  String _lastLoadedDateKey = "";

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
  final Map<String, Map<String, String>> _homeTexts = {
    'th': {
      'greeting': 'สวัสดี, ',
      'progress': 'ความคืบหน้า: ',
      'from_goal': 'จากเป้าหมาย ',
      'water_in_cup': 'น้ำในแก้วตอนนี้: ',
      'miss_target': 'ยังขาดอีก ',
      'miss_target_hint': ' ml ถึงเป้าหมาย\nลองแบ่งจิบเรื่อยๆ ดูนะ!',
      'last_drink': 'ดื่มล่าสุด',
      'streak': 'ต่อเนื่อง',
      'days': ' วัน',
      'keep_it_up': 'เก่งมาก!',
      'select_drink': 'เลือกเครื่องดื่มในแก้ว',
      'reset_title': 'ตั้งค่าระบบใหม่',
      'reset_subtitle': 'รีเซ็ตยอดสะสมกรณีที่ข้อมูลผิดพลาด',
      'reset_button': 'รีเซ็ตข้อมูลน้ำวันนี้',
      'today': 'วันนี้ • ',
      'yesterday': 'เมื่อวาน • ',
      'no_history': 'ยังไม่มีประวัติ',
      'reset_success': 'รีเซ็ตข้อมูลปริมาณน้ำวันนี้แล้ว',
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
      'water_in_cup': 'Current water in cup: ',
      'miss_target': '',
      'miss_target_hint':
          ' ml remaining to reach goal\nKeep taking small sips!',
      'last_drink': 'Last Drink',
      'streak': 'Streak',
      'days': ' days',
      'keep_it_up': 'Great job!',
      'select_drink': 'Select drink in cup',
      'reset_title': 'System Settings',
      'reset_subtitle': 'Reset today\'s intake if data is incorrect',
      'reset_button': 'Reset today\'s data',
      'today': 'Today • ',
      'yesterday': 'Yesterday • ',
      'no_history': 'No history yet',
      'reset_success': 'Today\'s water intake reset successfully',
      'water': 'Water',
      'juice': 'Juice',
      'coffee_tea': 'Coffee/Tea',
      'milk': 'Milk',
      'boba': 'Boba Tea',
      'other': 'Others',
    },
  };

  String _t(String key) {
    return _homeTexts[_selectedLanguage]?[key] ?? key;
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
    _lastLoadedDateKey = _getCurrentDateKey();
    _listenFirebase();
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

  void _listenFirebase() {
    if (!isFirebaseReady()) return;

    try {
      _subscription = smartCupRef().onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) return;

        Map<dynamic, dynamic> mapData;
        try {
          mapData = Map<dynamic, dynamic>.from(data as dynamic);
        } catch (_) {
          return;
        }

        double rawWeight = double.tryParse('${mapData['weight']}') ?? 0;

        double newDailyTarget = 2400;
        String newName = _userName;
        String newLang = _selectedLanguage;

        // 🌟 ดึงภาษาและโปรไฟล์จาก Firebase แบบ Realtime
        if (mapData['profile'] != null) {
          try {
            final profileMap = Map<dynamic, dynamic>.from(
              mapData['profile'] as dynamic,
            );
            newDailyTarget =
                double.tryParse('${profileMap['daily_target']}') ?? 2400;
            newName = profileMap['name']?.toString() ?? _userName;
            newLang = profileMap['language']?.toString() ?? _selectedLanguage;
          } catch (_) {}
        }

        String currentDateKey = _getCurrentDateKey();

        if (_lastLoadedDateKey != currentDateKey) {
          if (mapData['history_logs'] != null) {
            Map<dynamic, dynamic> historyMap = Map<dynamic, dynamic>.from(
              mapData['history_logs'],
            );
            if (historyMap[_lastLoadedDateKey] != null) {
              double yesterdayTotal =
                  double.tryParse(
                    '${historyMap[_lastLoadedDateKey]['daily_total']}',
                  ) ??
                  0;
              if (yesterdayTotal < newDailyTarget) {
                smartCupRef().update({'streak_days': 0});
              }
            } else {
              smartCupRef().update({'streak_days': 0});
            }
          } else {
            smartCupRef().update({'streak_days': 0});
          }

          _todayTotal = 0;
          _lastLoadedDateKey = currentDateKey;

          smartCupRef().update({
            'last_stable_weight': rawWeight < 20 ? 0 : rawWeight,
          });
        }

        double fbTodayTotal = 0;
        if (mapData['history_logs'] != null) {
          Map<dynamic, dynamic> historyMap = Map<dynamic, dynamic>.from(
            mapData['history_logs'],
          );
          if (historyMap[currentDateKey] != null) {
            fbTodayTotal =
                double.tryParse(
                  '${historyMap[currentDateKey]['daily_total']}',
                ) ??
                0;
          }
          _cleanOldHistoryLogs(historyMap);
        }

        _calculateLatestDrink(mapData);

        double fbLastStable =
            double.tryParse('${mapData['last_stable_weight']}') ?? 0;

        if (_isInitialLoad) {
          _todayTotal = fbTodayTotal;

          if (rawWeight >= 20 &&
              fbLastStable >= 20 &&
              rawWeight < fbLastStable) {
            double missedDiff = fbLastStable - rawWeight;
            if (missedDiff >= 15) {
              double prevTotal = _todayTotal;
              _todayTotal += missedDiff;
              final int nowMs = DateTime.now().millisecondsSinceEpoch;
              final String nowTime = formatTOD(TimeOfDay.now());

              Map<String, Object> updates = {
                'last_stable_weight': rawWeight,
                'last_drink_amount': missedDiff,
                'last_drink_time': nowTime,
                'last_drink_timestamp': nowMs,
                'history_logs/$currentDateKey/daily_total': _todayTotal,
                'history_logs/$currentDateKey/logs/$nowMs': {
                  'time': nowTime,
                  'amount': missedDiff,
                  'type': _currentDrinkType,
                  'timestamp': nowMs,
                },
              };

              if (prevTotal < newDailyTarget && _todayTotal >= newDailyTarget) {
                int currentStreak =
                    int.tryParse('${mapData['streak_days']}') ?? 0;
                updates['streak_days'] = currentStreak + 1;
              }

              smartCupRef().update(updates);
              fbLastStable = rawWeight;
              _lastDrinkAmount = missedDiff;
              _lastDrinkSubtitle = '${_t('today')}$nowTime';
            }
          } else if (fbLastStable == 0 && rawWeight >= 20) {
            smartCupRef().update({'last_stable_weight': rawWeight});
            fbLastStable = rawWeight;
          }

          _lastStableWeight = fbLastStable;
          _pendingWeight = rawWeight;

          setState(() {
            _userName = newName;
            _selectedLanguage = newLang;
            _currentDisplayWeight = rawWeight < 20 ? 0 : rawWeight;
            _isInitialLoad = false;
          });
        } else {
          setState(() {
            if (_lastLoadedDateKey == currentDateKey) {
              _todayTotal = fbTodayTotal;
            }
            _userName = newName;
            _selectedLanguage = newLang; // 🌟 อัปเดตภาษาจาก Firebase อัตโนมัติ
            _dailyTarget = newDailyTarget;
            _battery =
                double.tryParse('${mapData['battery_percent']}') ?? _battery;
            _currentDrinkType =
                mapData['current_drink_type']?.toString() ?? _currentDrinkType;

            if (!_drinkTypes.contains(_currentDrinkType)) {
              _currentDrinkType = 'น้ำเปล่า';
            }

            _lastDrinkTime =
                mapData['last_drink_time']?.toString() ?? _lastDrinkTime;
            _sinceLastDrink =
                mapData['since_last_drink']?.toString() ?? _sinceLastDrink;
            _streakDays =
                int.tryParse('${mapData['streak_days']}') ?? _streakDays;
          });

          if ((rawWeight - _pendingWeight).abs() > 15) {
            _pendingWeight = rawWeight;
            _debounceTimer?.cancel();

            _debounceTimer = Timer(const Duration(seconds: 5), () {
              if (!mounted) return;

              double finalWeight = _pendingWeight;

              setState(() {
                _currentDisplayWeight = finalWeight < 20 ? 0 : finalWeight;
              });

              if (finalWeight >= 20) {
                if (_lastStableWeight >= 20 &&
                    finalWeight < _lastStableWeight) {
                  double diff = _lastStableWeight - finalWeight;

                  if (diff >= 15) {
                    double prevTotal = _todayTotal;
                    double updatedTotal = _todayTotal + diff;
                    final int nowMs = DateTime.now().millisecondsSinceEpoch;
                    final String nowTime = formatTOD(TimeOfDay.now());

                    Map<String, Object> updates = {
                      'last_stable_weight': finalWeight,
                      'last_drink_amount': diff,
                      'last_drink_time': nowTime,
                      'last_drink_timestamp': nowMs,
                      'history_logs/$currentDateKey/daily_total': updatedTotal,
                      'history_logs/$currentDateKey/logs/$nowMs': {
                        'time': nowTime,
                        'amount': diff,
                        'type': _currentDrinkType,
                        'timestamp': nowMs,
                      },
                    };

                    if (prevTotal < newDailyTarget &&
                        updatedTotal >= newDailyTarget) {
                      int currentStreak =
                          int.tryParse('${mapData['streak_days']}') ?? 0;
                      updates['streak_days'] = currentStreak + 1;
                    }

                    smartCupRef().update(updates);
                    _lastDrinkAmount = diff;
                    _lastDrinkSubtitle = '${_t('today')}$nowTime';
                  } else {
                    smartCupRef().update({'last_stable_weight': finalWeight});
                  }
                } else if (finalWeight > _lastStableWeight + 15) {
                  smartCupRef().update({'last_stable_weight': finalWeight});
                }

                _lastStableWeight = finalWeight;
              }
            });
          }
        }
      });
    } catch (e) {
      debugPrint('❌ [Home] Logic error: $e');
    }
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

  Future<void> _resetWater() async {
    if (!isFirebaseReady()) return;

    try {
      final snapshot = await smartCupRef('weight').get();
      final currentWeight = double.tryParse('${snapshot.value}') ?? 0.0;
      String dateKey = _getCurrentDateKey();

      await smartCupRef().update({
        'last_stable_weight': currentWeight,
        'history_logs/$dateKey': null,
      });

      _lastStableWeight = currentWeight >= 20 ? currentWeight : 0;
      _pendingWeight = currentWeight;

      setState(() {
        _currentDisplayWeight = currentWeight < 20 ? 0 : currentWeight;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('reset_success'))));
      // ignore: empty_catches
    } catch (e) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
        Material(
          color: Colors.white.withValues(alpha: 0.7),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.95)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatteryScreen(battery: _battery),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.battery_charging_full,
                    color: batteryColor,
                    size: 20,
                  ),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_t('from_goal')}${formatNumber(_dailyTarget)} ml',
          textAlign: TextAlign.center,
          style: const TextStyle(color: textGrey, fontSize: 15),
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

  // ปุ่มรีเซ็ตถูกลดน้ำหนักลง ให้ไม่แย่งความสนใจจากข้อมูลหลัก
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
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(_t('reset_button')),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFC62828),
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
