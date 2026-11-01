import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../core/theme.dart';
import '../core/ui_kit.dart';
import '../core/utils.dart';

class AITip {
  final IconData icon;
  final String title;
  final String description;

  const AITip({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final String geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY');

  double _avgIntake = 0;
  double _dailyTarget = 2400;
  int _percentTarget = 0;
  int _healthScore = 0;
  int _consistency = 0;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String _selectedLanguage = 'th';

  // 🌟 ตัวแปรเก็บเวลานอน (เชื่อมตรงกับ settings/quiet_start)
  // เวลานอน = เวลาเริ่มปิดเสียง (ค่าเริ่มต้นตรงกับหน้าแจ้งเตือน)
  String _bedtimeStr = '22:00';
  double _expectedIntakeNow = 0;
  double _recommendedRatePerHour = 0;
  int _minutesUntilBed = 0;

  List<AITip> _tips = [];
  StreamSubscription<DatabaseEvent>? _subscription;
  StreamSubscription<DatabaseEvent>? _settingsSubscription;
  Timer? _smartCheckTimer;

  final Map<String, Map<String, String>> _aiTexts = {
    'th': {
      'title': 'คำแนะนำจาก AI',
      'subtitle': 'วิเคราะห์พฤติกรรมการดื่มของคุณ',
      'analyzing': 'กำลังคิด...',
      'analyze': 'วิเคราะห์',
      'result_today': 'ผลการวิเคราะห์วันนี้',
      'intake_today': 'ปริมาณการดื่มวันนี้',
      'achieved': 'ทำได้',
      'of_target': '% ของเป้าหมาย',
      'health_score': 'Health Score',
      'consistency': 'Consistency',
      'tips_for_you': 'คำแนะนำสำหรับคุณ',
      'no_tips': 'กดปุ่ม "วิเคราะห์" เพื่อรับคำแนะนำจาก AI',
      'success': 'AI วิเคราะห์และประเมินการแจ้งเตือนสำเร็จแล้ว',
      'error': 'เกิดข้อผิดพลาดในการวิเคราะห์',
      'pacing_title': 'แผนการดื่ม 12 ชม. (06:00 - 18:00) & ก่อนนอน',
      'bedtime_at': 'เวลานอนที่ตั้งไว้:',
      'expected_now': 'เกณฑ์ที่ควรดื่มได้ตอนนี้:',
      'rate_needed': 'อัตราเร่งก่อนเข้านอน:',
      'on_track': 'อยู่ในเกณฑ์ดีเยี่ยม!',
      'behind_schedule': 'ต่ำกว่าเกณฑ์ ควรเร่งดื่มน้ำ',
    },
    'en': {
      'title': 'AI Insights',
      'subtitle': 'Analyzing your hydration habits',
      'analyzing': 'Thinking...',
      'analyze': 'Analyze',
      'result_today': 'Today\'s Analysis',
      'intake_today': 'Today\'s Intake',
      'achieved': 'Achieved',
      'of_target': '% of target',
      'health_score': 'Health Score',
      'consistency': 'Consistency',
      'tips_for_you': 'Tips for You',
      'no_tips': 'Press "Analyze" to get your daily AI insights.',
      'success': 'AI analysis and alert check completed.',
      'error': 'An error occurred during analysis.',
      'pacing_title': '12-Hr Pacing (06:00 - 18:00) & Bedtime',
      'bedtime_at': 'Target Bedtime:',
      'expected_now': 'Expected by now:',
      'rate_needed': 'Required pace before bed:',
      'on_track': 'On Track!',
      'behind_schedule': 'Behind schedule, speed up!',
    },
  };

  String _t(String key) {
    return _aiTexts[_selectedLanguage]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _listenFirebase();
    _listenSettings(); // 🌟 ดึงค่า settings แยกโหนดแบบ Real-time 100%
    _smartCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _evaluateSmartPacingAndAutoAlert();
    });
  }

  IconData _mapIcon(String? iconType) {
    switch (iconType) {
      case 'trophy':
        return Icons.emoji_events_outlined;
      case 'sunny':
        return Icons.wb_sunny_outlined;
      case 'fire':
        return Icons.local_fire_department;
      case 'coffee':
        return Icons.coffee_outlined;
      case 'alert':
        return Icons.warning_amber_rounded;
      default:
        return Icons.lightbulb_outline;
    }
  }

  String _getCurrentDateKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Map<String, dynamic> _calculate12HrAndBedtimeMetrics({
    required double todayTotal,
    required double dailyTarget,
    required String bedtimeStr,
  }) {
    final now = DateTime.now();
    final int currentMinutes = now.hour * 60 + now.minute;

    const int start12Hr = 6 * 60; // 06:00
    const int end12Hr = 18 * 60; // 18:00

    double progress12Hr;
    if (currentMinutes <= start12Hr) {
      progress12Hr = 0.0;
    } else if (currentMinutes >= end12Hr) {
      progress12Hr = 1.0;
    } else {
      progress12Hr = (currentMinutes - start12Hr) / (end12Hr - start12Hr);
    }

    final double expectedByNow = (dailyTarget * progress12Hr).clamp(
      0.0,
      dailyTarget,
    );
    final double remainingMl = (dailyTarget - todayTotal).clamp(
      0.0,
      dailyTarget,
    );

    final TimeOfDay bedTOD = parseTOD(bedtimeStr);
    int bedMinutes = bedTOD.hour * 60 + bedTOD.minute;
    int minsUntilBed = bedMinutes - currentMinutes;

    // 🌟 ป้องกันเวลาติดลบหรือเลยเวลานอน ให้คิดเวลาที่เหลืออย่างน้อย 1 ชั่วโมงเต็ม
    if (minsUntilBed <= 0) {
      minsUntilBed += 24 * 60;
    }
    if (minsUntilBed < 60) {
      minsUntilBed = 60;
    }

    double hoursLeftBeforeBed = (minsUntilBed / 60.0).clamp(1.0, 12.0);
    double requiredRatePerHr = remainingMl > 0
        ? (remainingMl / hoursLeftBeforeBed)
        : 0.0;

    // 🌟 จำกัดเพดานสูงสุดไม่ให้เกิน 1,000 ml/ชม. เพื่อความสมจริงตอนพรีเซนต์
    if (requiredRatePerHr > 1000) {
      requiredRatePerHr = 1000.0;
    }

    return {
      'expected_by_now': expectedByNow,
      'remaining_ml': remainingMl,
      'mins_until_bed': minsUntilBed,
      'rate_per_hr': requiredRatePerHr,
      'is_past_18': currentMinutes >= end12Hr,
    };
  }

  // 🌟 ฟังค่า settings/quiet_start โดยตรงเพื่อให้เวลานอนตรงเป๊ะตลอดเวลา
  void _listenSettings() {
    if (!isFirebaseReady()) return;
    try {
      _settingsSubscription = smartCupRef('settings').onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) return;
        try {
          final settingsMap = Map<dynamic, dynamic>.from(data as dynamic);
          final quietStart = settingsMap['quiet_start']?.toString();

          if (quietStart != null && quietStart.isNotEmpty && mounted) {
            setState(() {
              _bedtimeStr = quietStart;
              final metrics = _calculate12HrAndBedtimeMetrics(
                todayTotal: _avgIntake,
                dailyTarget: _dailyTarget,
                bedtimeStr: _bedtimeStr,
              );
              _expectedIntakeNow = metrics['expected_by_now'] as double;
              _minutesUntilBed = metrics['mins_until_bed'] as int;
              _recommendedRatePerHour = metrics['rate_per_hr'] as double;
            });
          }
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Settings listen error: $e');
    }
  }

  List<AITip> _buildLiveDynamicTips(List<AITip> extraAiTips) {
    final now = DateTime.now();
    final String currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final bool isEn = _selectedLanguage == 'en';
    final int remaining = (_dailyTarget - _avgIntake)
        .clamp(0, _dailyTarget)
        .toInt();

    List<AITip> liveList = [];

    if (_percentTarget >= 100) {
      liveList.add(
        AITip(
          icon: Icons.emoji_events_outlined,
          title: isEn ? "Goal Achieved!" : "ยอดเยี่ยม บรรลุเป้าหมายแล้ว!",
          description: isEn
              ? "You've reached your ${_dailyTarget.toInt()} ml target before bedtime ($_bedtimeStr)!"
              : "คุณดื่มน้ำครบตามเป้าหมาย ${_dailyTarget.toInt()} ml ก่อนถึงเวลานอน ($_bedtimeStr น.) เรียบร้อยแล้ว!",
        ),
      );
    } else {
      liveList.add(
        AITip(
          icon: Icons.warning_amber_rounded,
          title: isEn
              ? "12-Hr Pacing (06:00 - 18:00)"
              : "วิเคราะห์แผน 12 ชม. (06:00 - 18:00 น.)",
          description: isEn
              ? "By $currentTime, you should have drunk ${_expectedIntakeNow.toInt()} ml. You still need $remaining ml before bedtime at $_bedtimeStr."
              : "ณ เวลา $currentTime น. ตามเกณฑ์ 12 ชม. คุณควรดื่มได้ ${_expectedIntakeNow.toInt()} ml (ยังขาดอีก $remaining ml ก่อนถึงเวลานอน $_bedtimeStr น.)",
        ),
      );
      liveList.add(
        AITip(
          icon: Icons.wb_sunny_outlined,
          title: isEn
              ? "Bedtime Countdown Plan ($_bedtimeStr)"
              : "แผนเร่งดื่มน้ำก่อนเข้านอน ($_bedtimeStr น.)",
          description: isEn
              ? "Sip ~${_recommendedRatePerHour.toInt()} ml per hour before $_bedtimeStr."
              : "แนะนำให้เร่งจิบน้ำเฉลี่ยชั่วโมงละ ${_recommendedRatePerHour.toInt()} ml เพื่อให้ครบเป้าก่อนเวลานอน $_bedtimeStr น.",
        ),
      );
    }

    for (final tip in extraAiTips) {
      if (liveList.length >= 3) break;
      final bool isDuplicatePacing =
          tip.title.contains('12') ||
          tip.title.contains('06:00') ||
          tip.title.contains('ก่อนเข้านอน') ||
          tip.title.contains('ก่อนเวลานอน') ||
          tip.title.contains('Bedtime');
      if (!isDuplicatePacing) {
        liveList.add(tip);
      }
    }

    return liveList;
  }

  // 🌟 อัปเดตตัวเลขแผนการดื่ม 12 ชม. ในหน้านี้ทุก 30 วินาที
  // (แจ้งเตือนจาก AI ย้ายไปทำงานเบื้องหลังใน core/ai_reminder.dart แล้ว:
  //  12:00 / 18:00 / ก่อนนอน วันละครั้ง ทำงานแม้ปิดแอป จึงไม่ส่งแจ้งเตือนจากหน้านี้อีก)
  Future<void> _evaluateSmartPacingAndAutoAlert() async {
    if (!mounted) return;

    final metrics = _calculate12HrAndBedtimeMetrics(
      todayTotal: _avgIntake,
      dailyTarget: _dailyTarget,
      bedtimeStr: _bedtimeStr,
    );

    setState(() {
      _expectedIntakeNow = metrics['expected_by_now'] as double;
      _minutesUntilBed = metrics['mins_until_bed'] as int;
      _recommendedRatePerHour = metrics['rate_per_hr'] as double;
    });
  }

  Map<String, dynamic> _getLatestDrinkDetails(Map<dynamic, dynamic> mapData) {
    double foundAmount = 0;
    String foundTime = '';
    String drinkType = mapData['current_drink_type']?.toString() ?? 'น้ำเปล่า';
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
                drinkType = logVal['type']?.toString() ?? drinkType;

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

    String timeDescription = _selectedLanguage == 'th'
        ? 'ยังไม่มีประวัติการดื่ม'
        : 'No drink history yet';
    if (foundDateTime != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final drinkDay = DateTime(
        foundDateTime!.year,
        foundDateTime!.month,
        foundDateTime!.day,
      );
      final diffDays = today.difference(drinkDay).inDays;

      if (_selectedLanguage == 'en') {
        const enMonths = [
          '',
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final monthName = enMonths[foundDateTime!.month];
        if (diffDays == 0) {
          timeDescription = 'Today at $foundTime';
        } else if (diffDays == 1) {
          timeDescription =
              'Yesterday (${foundDateTime!.day} $monthName) at $foundTime';
        } else {
          timeDescription = '${foundDateTime!.day} $monthName at $foundTime';
        }
      } else {
        const thaiMonths = [
          '',
          'ม.ค.',
          'ก.พ.',
          'มี.ค.',
          'เม.ย.',
          'พ.ค.',
          'มิ.ย.',
          'ก.ค.',
          'ส.ค.',
          'ก.ย.',
          'ต.ค.',
          'พ.ย.',
          'ธ.ค.',
        ];
        final monthName = thaiMonths[foundDateTime!.month];
        if (diffDays == 0) {
          timeDescription = 'วันนี้ เวลา $foundTime น.';
        } else if (diffDays == 1) {
          timeDescription =
              'เมื่อวาน (${foundDateTime!.day} $monthName) เวลา $foundTime น.';
        } else {
          timeDescription =
              '${foundDateTime!.day} $monthName เวลา $foundTime น.';
        }
      }
    }

    return {
      'amount': foundAmount,
      'type': drinkType,
      'description': timeDescription,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // 🌟 คำนวณคะแนนจากประวัติการดื่มจริง (สูตรตายตัว อธิบายได้ทุกตัวเลข)
  //
  // ใช้ "7 วันที่ผ่านมา" ไม่รวมวันนี้ (วันนี้ยังดื่มไม่จบ จะทำให้คะแนนตอนเช้าต่ำเกินจริง)
  // ถ้าเพิ่งเริ่มใช้งาน ใช้เท่าจำนวนวันที่มีจริงตั้งแต่วันแรกที่มีประวัติ (สูงสุด 7 วัน)
  // ถ้ายังไม่มีวันที่จบแล้วเลย ใช้ข้อมูลวันนี้แทน
  //
  // 1) % ของแต่ละวัน = ยอดดื่มวันนั้น ÷ เป้าหมาย × 100 (ไม่เกิน 100, วันที่ไม่มีข้อมูล = 0)
  // 2) Health Score  = ค่าเฉลี่ย % ของวันเหล่านั้น
  // 3) Consistency   = จำนวนวันที่ดื่มครบเป้า ÷ จำนวนวัน × 100
  // ─────────────────────────────────────────────────────────────
  Map<String, dynamic> _computeScores(
    Map<dynamic, dynamic> historyMap,
    double dailyTarget,
  ) {
    String keyOf(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    double totalOf(DateTime d) {
      final day = historyMap[keyOf(d)];
      if (day is Map) return double.tryParse('${day['daily_total']}') ?? 0;
      return 0;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = dailyTarget > 0 ? dailyTarget : 2400.0;

    // วันแรกที่มีประวัติ (ไม่นับวันก่อนเริ่มใช้งานเป็น 0%)
    DateTime? firstDay;
    for (final k in historyMap.keys) {
      final d = DateTime.tryParse(k.toString());
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (firstDay == null || day.isBefore(firstDay)) firstDay = day;
    }

    int completedDays = 0;
    if (firstDay != null && firstDay.isBefore(today)) {
      completedDays = today.difference(firstDay).inDays.clamp(0, 7).toInt();
    }

    final List<Map<String, dynamic>> days = [];
    if (completedDays == 0) {
      // ยังไม่มีวันที่จบแล้ว → ใช้วันนี้
      final total = totalOf(today);
      days.add({
        'date': keyOf(today),
        'total': total,
        'percent': (total / target * 100).clamp(0, 100).toDouble(),
      });
    } else {
      for (int i = completedDays; i >= 1; i--) {
        final d = today.subtract(Duration(days: i));
        final total = totalOf(d);
        days.add({
          'date': keyOf(d),
          'total': total,
          'percent': (total / target * 100).clamp(0, 100).toDouble(),
        });
      }
    }

    final double avgPercent =
        days.fold<double>(0, (sum, d) => sum + (d['percent'] as double)) /
        days.length;
    final int metDays = days
        .where((d) => (d['percent'] as double) >= 100)
        .length;

    return {
      'health_score': avgPercent.round(),
      'consistency': (metDays / days.length * 100).round(),
      'days_used': days.length,
      'met_days': metDays,
      'days': days,
    };
  }

  void _listenFirebase() {
    if (!isFirebaseReady()) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      _subscription = smartCupRef().onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        Map<dynamic, dynamic> mapData;
        try {
          mapData = Map<dynamic, dynamic>.from(data as dynamic);
        } catch (_) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        double dailyTarget = 2400.0;
        String lang = _selectedLanguage;

        if (mapData['profile'] != null) {
          try {
            final profile = Map<dynamic, dynamic>.from(
              mapData['profile'] as dynamic,
            );
            dailyTarget =
                double.tryParse('${profile['daily_target']}') ?? 2400.0;
            lang = profile['language']?.toString() ?? _selectedLanguage;
          } catch (_) {}
        }

        String todayKey = _getCurrentDateKey();
        double todayTotal = 0.0;
        Map<dynamic, dynamic> historyMap = {};
        if (mapData['history_logs'] != null) {
          try {
            historyMap = Map<dynamic, dynamic>.from(
              mapData['history_logs'] as dynamic,
            );
            if (historyMap[todayKey] != null) {
              todayTotal =
                  double.tryParse('${historyMap[todayKey]['daily_total']}') ??
                  0.0;
            }
          } catch (_) {}
        }

        int percentInt = dailyTarget > 0
            ? ((todayTotal / dailyTarget) * 100).clamp(0, 100).toInt()
            : 0;

        // 🌟 คะแนนคำนวณจากประวัติจริงทุกครั้งที่ข้อมูลเปลี่ยน (ไม่ต้องรอกดวิเคราะห์)
        final scores = _computeScores(historyMap, dailyTarget);
        final int healthScore = scores['health_score'] as int;
        final int consistency = scores['consistency'] as int;
        List<AITip> fetchedTips = [];

        if (mapData['ai_insights'] != null) {
          Map<dynamic, dynamic> aiData = Map<dynamic, dynamic>.from(
            mapData['ai_insights'] as dynamic,
          );
          final String? savedDate = aiData['date']?.toString();

          if (savedDate == null || savedDate != todayKey) {
            smartCupRef('ai_insights').remove();
          } else {
            // ai_insights ใช้เก็บเฉพาะคำแนะนำ (คะแนนคำนวณจากประวัติด้านบนแล้ว)
            if (aiData['tips'] != null && aiData['tips'] is List) {
              for (var item in aiData['tips']) {
                if (item != null) {
                  final mapItem = Map<dynamic, dynamic>.from(item as dynamic);
                  fetchedTips.add(
                    AITip(
                      icon: _mapIcon(mapItem['icon_type']?.toString()),
                      title: mapItem['title']?.toString() ?? '',
                      description: mapItem['description']?.toString() ?? '',
                    ),
                  );
                }
              }
            }
          }
        }

        final metrics = _calculate12HrAndBedtimeMetrics(
          todayTotal: todayTotal,
          dailyTarget: dailyTarget,
          bedtimeStr: _bedtimeStr,
        );

        if (!mounted) return;

        setState(() {
          _selectedLanguage = lang;
          _dailyTarget = dailyTarget;
          _avgIntake = todayTotal;
          _percentTarget = percentInt;
          _expectedIntakeNow = metrics['expected_by_now'] as double;
          _minutesUntilBed = metrics['mins_until_bed'] as int;
          _recommendedRatePerHour = metrics['rate_per_hr'] as double;
          _healthScore = healthScore;
          _consistency = consistency;
          _tips = fetchedTips;
          _isLoading = false;
        });

        _evaluateSmartPacingAndAutoAlert();
      });
    } catch (e) {
      debugPrint('AI Firebase error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _generateLocalAnalysis({
    required double todayTotal,
    required double dailyTarget,
    required int percentInt,
    required String currentTime,
    required int healthScore,
    required int consistency,
    required String bedtimeStr,
    required double expectedByNow,
    required double ratePerHr,
  }) {
    List<AITip> tips = [];
    bool isEn = _selectedLanguage == 'en';
    final remaining = (dailyTarget - todayTotal).clamp(0, dailyTarget).toInt();

    if (percentInt >= 100) {
      tips.add(
        AITip(
          icon: Icons.emoji_events_outlined,
          title: isEn ? "Goal Achieved!" : "ยอดเยี่ยม บรรลุเป้าหมายแล้ว!",
          description: isEn
              ? "You've reached your ${dailyTarget.toInt()} ml target before bedtime ($bedtimeStr)!"
              : "คุณดื่มน้ำครบตามเป้าหมาย ${dailyTarget.toInt()} ml ก่อนถึงเวลานอน ($bedtimeStr น.) เรียบร้อยแล้ว!",
        ),
      );
    } else {
      tips.add(
        AITip(
          icon: Icons.warning_amber_rounded,
          title: isEn
              ? "12-Hr Pacing (06:00 - 18:00)"
              : "วิเคราะห์แผน 12 ชม. (06:00 - 18:00 น.)",
          description: isEn
              ? "By $currentTime, you should have drunk ${expectedByNow.toInt()} ml. You still need $remaining ml before bedtime at $bedtimeStr."
              : "ณ เวลา $currentTime น. ตามเกณฑ์ 12 ชม. คุณควรดื่มได้ ${expectedByNow.toInt()} ml (ยังขาดอีก $remaining ml ก่อนถึงเวลานอน $bedtimeStr น.)",
        ),
      );
    }

    return {
      "date": _getCurrentDateKey(),
      "avg_intake": todayTotal,
      "percent_target": percentInt,
      "health_score": healthScore,
      "consistency": consistency,
      "tips": tips
          .map(
            (e) => {
              "icon_type": e.icon == Icons.emoji_events_outlined
                  ? "trophy"
                  : "alert",
              "title": e.title,
              "description": e.description,
            },
          )
          .toList(),
    };
  }

  Future<void> _analyzeWithAI() async {
    if (_isAnalyzing) return;

    setState(() => _isAnalyzing = true);

    try {
      final now = DateTime.now();
      final currentFormattedTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final snapshot = await smartCupRef('').get();
      final data = snapshot.value != null
          ? Map<dynamic, dynamic>.from(snapshot.value as dynamic)
          : {};

      String todayKey = _getCurrentDateKey();
      double todayTotal = 0.0;
      Map<dynamic, dynamic> historyMap = {};
      if (data['history_logs'] != null) {
        try {
          historyMap = Map<dynamic, dynamic>.from(
            data['history_logs'] as dynamic,
          );
          if (historyMap[todayKey] != null) {
            todayTotal =
                double.tryParse('${historyMap[todayKey]['daily_total']}') ??
                0.0;
          }
        } catch (_) {}
      }

      final latestDrink = _getLatestDrinkDetails(data);
      latestDrink['type']?.toString() ?? 'น้ำเปล่า';
      latestDrink['description']?.toString() ?? currentFormattedTime;
      double.tryParse('${latestDrink['amount']}') ?? 0.0;

      double dailyTarget = 2400.0;
      if (data['profile'] != null && data['profile'] is Map) {
        final profile = Map<dynamic, dynamic>.from(data['profile'] as dynamic);
        dailyTarget =
            double.tryParse('${profile['daily_target'] ?? 2400}') ?? 2400.0;
      }

      // 🌟 คะแนนคำนวณจากประวัติ (สูตรเดียวกับที่แสดงบนหน้าจอ)
      final scores = _computeScores(historyMap, dailyTarget);
      final int healthScore = scores['health_score'] as int;
      final int consistency = scores['consistency'] as int;
      final String historyLines = (scores['days'] as List)
          .map(
            (d) =>
                '  - ${d['date']}: ${(d['total'] as double).toInt()} ml (${(d['percent'] as double).round()}%)',
          )
          .join('\n');

      final metrics = _calculate12HrAndBedtimeMetrics(
        todayTotal: todayTotal,
        dailyTarget: dailyTarget,
        bedtimeStr: _bedtimeStr,
      );
      final double expectedByNow = metrics['expected_by_now'] as double;
      final double ratePerHr = metrics['rate_per_hr'] as double;

      final int percentInt = dailyTarget > 0
          ? ((todayTotal / dailyTarget) * 100).clamp(0, 100).toInt()
          : 0;

      final prompt =
          """
คุณเป็น AI อัจฉริยะด้านการวางแผนดื่มน้ำ (Smart Cup AI)
ข้อมูลผู้ใช้จริง:
- วันที่: $todayKey เวลาปัจจุบัน: $currentFormattedTime น.
- เวลานอนที่ผู้ใช้ตั้งไว้: $_bedtimeStr น.
- ปริมาณที่ดื่มวันนี้: ${todayTotal.toInt()} ml จากเป้าหมาย ${dailyTarget.toInt()} ml (คิดเป็น $percentInt%)
- ประวัติการดื่มย้อนหลัง (เทียบกับเป้าหมาย):
$historyLines
- Health Score (ค่าเฉลี่ย % ที่ทำได้ตามเป้า): $healthScore/100
- Consistency (สัดส่วนวันที่ดื่มครบเป้า ${scores['met_days']} จาก ${scores['days_used']} วัน): $consistency/100
- หากดื่มไม่ถึง 50% และเวลาผ่าน 18:00 น. แล้ว ให้วางแผนเร่งดื่มน้ำให้ทันเวลานอน $_bedtimeStr น.

คะแนนด้านบนคำนวณไว้แล้ว ไม่ต้องให้คะแนนใหม่
ให้วิเคราะห์รูปแบบการดื่มจากข้อมูลข้างต้น แล้วเขียนคำแนะนำเฉพาะบุคคล 2-3 ข้อ
ตอบเป็น JSON โครงสร้างนี้เท่านั้น:
{
  "tips": [
    {
      "icon_type": "<sunny หรือ fire หรือ coffee หรือ alert>",
      "title": "<หัวข้อคำแนะนำ>",
      "description": "<คำแนะนำอ้างอิงเวลานอน $_bedtimeStr น.>"
    }
  ]
}
""";

      final url = Uri.parse(
        // gemini-2.0-flash ถูกปิดแล้ว → ใช้รุ่นที่ Google แนะนำในข้อความ error (404)
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent',
      );

      http.Response? response;
      for (int i = 0; i < 2; i++) {
        try {
          response = await http.post(
            url,
            // ส่ง key ทาง header (รองรับทั้ง key แบบใหม่ "AQ." และแบบเก่า "AIza")
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': geminiApiKey,
            },
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": prompt},
                  ],
                },
              ],
              "generationConfig": {"responseMimeType": "application/json"},
            }),
          );
          if (response.statusCode == 200) break;
        } catch (e) {
          debugPrint('🤖 [Gemini] เชื่อมต่อไม่ได้: $e');
        }
      }

      // 🔍 log ไว้เช็กว่าใช้ Gemini จริง หรือตกไปใช้การวิเคราะห์สำรองในเครื่อง
      debugPrint('🤖 [Gemini] API key ยาว ${geminiApiKey.length} ตัวอักษร');
      debugPrint('🤖 [Gemini] status = ${response?.statusCode}');
      if (response != null && response.statusCode != 200) {
        final body = response.body;
        debugPrint(
          '🤖 [Gemini] error = ${body.length > 500 ? body.substring(0, 500) : body}',
        );
        debugPrint(
          '🤖 [Gemini] → ใช้การวิเคราะห์สำรอง (_generateLocalAnalysis)',
        );
      }

      Map<String, dynamic> aiResult;
      if (response != null && response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final rawText = resJson['candidates'][0]['content']['parts'][0]['text'];
        final Map<String, dynamic> generated = jsonDecode(rawText);

        List<dynamic> parsedTips = generated['tips'] ?? [];
        List<Map<String, dynamic>> finalTips = [];
        bool isEn = _selectedLanguage == 'en';

        finalTips.add({
          "icon_type": "alert",
          "title": isEn
              ? "Bedtime Goal ($_bedtimeStr)"
              : "เป้าหมายก่อนนอน ($_bedtimeStr น.)",
          "description": isEn
              ? "You've drunk ${todayTotal.toInt()} ml. Keep pacing before bedtime at $_bedtimeStr."
              : "คุณดื่มไปแล้ว ${todayTotal.toInt()} ml ควบคุมอัตราการดื่มให้ทันก่อนนอนเวลา $_bedtimeStr น.",
        });

        for (var tip in parsedTips) {
          if (finalTips.length >= 3) break;
          finalTips.add({
            "icon_type": tip['icon_type'] ?? 'lightbulb',
            "title": tip['title'] ?? 'Tips',
            "description": tip['description'] ?? '',
          });
        }

        aiResult = {
          "date": todayKey,
          // คะแนนมาจากสูตรในแอปเสมอ (Gemini เขียนเฉพาะคำแนะนำ)
          "health_score": healthScore,
          "consistency": consistency,
          "tips": finalTips,
        };
      } else {
        aiResult = _generateLocalAnalysis(
          todayTotal: todayTotal,
          dailyTarget: dailyTarget,
          percentInt: percentInt,
          currentTime: currentFormattedTime,
          healthScore: healthScore,
          consistency: consistency,
          bedtimeStr: _bedtimeStr,
          expectedByNow: expectedByNow,
          ratePerHr: ratePerHr,
        );
      }

      await smartCupRef('ai_insights').set(aiResult);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_t('success'))));
      }
    } catch (e) {
      debugPrint('AI Error: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  void dispose() {
    _smartCheckTimer?.cancel();
    _subscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: oceanBlue)),
      );
    }

    final List<AITip> displayTips = _buildLiveDynamicTips(_tips);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildAnalysisCard(),
                  const SizedBox(height: 16),
                  _buildSmartPacingCard(),
                  const SizedBox(height: 16),
                  _buildScoreCards(),
                  const SizedBox(height: 28),
                  SectionTitle(_t('tips_for_you')),
                  const SizedBox(height: 14),
                  ...displayTips.map(_buildTipCard),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartPacingCard() {
    final bool isOnTrack =
        _avgIntake >= _expectedIntakeNow || _percentTarget >= 100;
    final int hrsLeft = _minutesUntilBed ~/ 60;
    final int minsLeft = _minutesUntilBed % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GradientIconChip(
                icon: Icons.schedule_rounded,
                color: isOnTrack ? accentGreen : coral,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('pacing_title'),
                      style: const TextStyle(
                        color: primaryDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnTrack ? _t('on_track') : _t('behind_schedule'),
                      style: TextStyle(
                        color: isOnTrack ? accentGreen : coral,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('expected_now'),
                style: const TextStyle(color: textGrey, fontSize: 13),
              ),
              Text(
                '${_expectedIntakeNow.toInt()} ml',
                style: const TextStyle(
                  color: primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('bedtime_at'),
                style: const TextStyle(color: textGrey, fontSize: 13),
              ),
              Text(
                '$_bedtimeStr (${hrsLeft}h ${minsLeft}m)',
                style: const TextStyle(
                  color: primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('rate_needed'),
                style: const TextStyle(color: textGrey, fontSize: 13),
              ),
              Text(
                '${_recommendedRatePerHour.toInt()} ml / hr',
                style: const TextStyle(
                  color: oceanBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cyanLight, mint],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cyanLight.withValues(alpha: 0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      _t('subtitle'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: textGrey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GradientButton(
          onPressed: _isAnalyzing ? null : _analyzeWithAI,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          icon: _isAnalyzing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(
            _isAnalyzing ? _t('analyzing') : _t('analyze'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisCard() {
    final double progress = (_percentTarget / 100).clamp(0.0, 1.0).toDouble();
    return DeepSeaCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: cyanLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t('result_today'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            _t('intake_today'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatNumber(_avgIntake),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ml',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 10,
              color: Colors.white.withValues(alpha: 0.18),
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [cyanLight, mint]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_t('achieved')} $_percentTarget${_t('of_target')}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCards() {
    return Row(
      children: [
        Expanded(
          child: _scoreCard(
            title: _t('health_score'),
            score: _healthScore,
            icon: Icons.favorite_rounded,
            iconColor: coral,
            colors: const [Color(0xFFFFB199), coral],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _scoreCard(
            title: _t('consistency'),
            score: _consistency,
            icon: Icons.insights_rounded,
            iconColor: oceanBlue,
            colors: const [cyanLight, oceanBlue],
          ),
        ),
      ],
    );
  }

  Widget _scoreCard({
    required String title,
    required int score,
    required IconData icon,
    required Color iconColor,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassDecoration(radius: 24),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
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
          const SizedBox(height: 14),
          RingGauge(
            value: score / 100,
            size: 104,
            stroke: 10,
            colors: colors,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: const TextStyle(
                    color: primaryDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const Text(
                  '/ 100',
                  style: TextStyle(color: textGrey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(AITip tip) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: glassDecoration(radius: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientIconChip(icon: tip.icon, color: coral, size: 50),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: const TextStyle(
                    color: primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tip.description,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
