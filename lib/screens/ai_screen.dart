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
  // อ่านคีย์จาก --dart-define เพื่อไม่ให้คีย์อยู่ในซอร์สโค้ดที่อัปโหลดขึ้น GitHub
  // (รันในเครื่อง: flutter run --dart-define-from-file=env.json)
  final String geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY');

  double _avgIntake = 0;
  int _percentTarget = 0;
  int _healthScore = 0;
  int _consistency = 0;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรภาษา

  List<AITip> _tips = [];
  StreamSubscription<DatabaseEvent>? _subscription;

  // 🌟 พจนานุกรมแปลภาษาหน้า AI
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
      'no_tips': 'กดปุ่ม "วิเคราะห์" เพื่อเริ่มรับคำแนะนำจาก AI ประจำวัน',
      'success': 'AI วิเคราะห์ข้อมูลสำเร็จแล้ว',
      'error': 'เกิดข้อผิดพลาดในการวิเคราะห์',
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
      'success': 'AI analysis completed successfully.',
      'error': 'An error occurred during analysis.',
    },
  };

  String _t(String key) {
    return _aiTexts[_selectedLanguage]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _listenFirebase();
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
        if (mapData['history_logs'] != null) {
          try {
            final historyMap = Map<dynamic, dynamic>.from(
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

        int healthScore = 0;
        int consistency = 0;
        List<AITip> fetchedTips = [];

        if (mapData['ai_insights'] != null) {
          Map<dynamic, dynamic> aiData = Map<dynamic, dynamic>.from(
            mapData['ai_insights'] as dynamic,
          );
          final String? savedDate = aiData['date']?.toString();

          if (savedDate == null || savedDate != todayKey) {
            smartCupRef('ai_insights').remove();
          } else {
            healthScore = int.tryParse('${aiData['health_score']}') ?? 0;
            consistency = int.tryParse('${aiData['consistency']}') ?? 0;

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

        if (!mounted) return;

        setState(() {
          _selectedLanguage = lang;
          _avgIntake = todayTotal;
          _percentTarget = percentInt;
          _healthScore = healthScore;
          _consistency = consistency;
          _tips = fetchedTips;
          _isLoading = false;
        });
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
    required int streakDays,
  }) {
    int healthScore = 50;
    if (percentInt >= 100) {
      healthScore = 95;
    } else if (percentInt >= 70)
      // ignore: curly_braces_in_flow_control_structures
      healthScore = 80;
    else if (percentInt >= 40)
      // ignore: curly_braces_in_flow_control_structures
      healthScore = 65;
    else
      // ignore: curly_braces_in_flow_control_structures
      healthScore = 40;

    int consistency = (streakDays * 20).clamp(20, 100);

    List<Map<String, dynamic>> tips = [];
    bool isEn = _selectedLanguage == 'en';

    if (todayTotal <= 0) {
      tips.add({
        "icon_type": "sunny",
        "title": isEn ? "Start Your Day" : "เริ่มต้นวันใหม่",
        "description": isEn
            ? "It's $currentTime and you haven't started drinking water yet. Have a glass to wake up your body!"
            : "ขณะนี้เวลา $currentTime วันนี้ยังไม่ได้เริ่มดื่มน้ำ แนะนำจิบน้ำแก้วแรกเพื่อปลุกความสดชื่นกันครับ",
      });
      tips.add({
        "icon_type": "coffee",
        "title": isEn ? "Today's Goal" : "เป้าหมายวันนี้",
        "description": isEn
            ? "Your goal is ${dailyTarget.toInt()} ml. Try to sip 150-200 ml at a time."
            : "เป้าหมายการดื่มน้ำของคุณคือ ${dailyTarget.toInt()} ml พยายามแบ่งจิบแก้วละ 150-200 ml ระหว่างวัน",
      });
    } else if (percentInt >= 100) {
      tips.add({
        "icon_type": "trophy",
        "title": isEn ? "Goal Achieved!" : "ยอดเยี่ยม บรรลุเป้าหมายแล้ว!",
        "description": isEn
            ? "You've reached your ${dailyTarget.toInt()} ml target today. Keep it up!"
            : "คุณดื่มน้ำครบตามเป้าหมาย ${dailyTarget.toInt()} ml ในวันนี้แล้ว รักษามาตรฐานที่ดีนี้ไว้",
      });
      tips.add({
        "icon_type": "fire",
        "title": isEn ? "Keep the Streak" : "สะสม Streak ต่อเนื่อง",
        "description": isEn
            ? "You're on a $streakDays day streak. Let's do it again tomorrow!"
            : "ดื่มต่อเนื่องเป็นวันที่ $streakDays พรุ่งนี้มารักษาเป้าหมายกันต่อ",
      });
    } else {
      final remaining = (dailyTarget - todayTotal)
          .clamp(0, dailyTarget)
          .toInt();
      tips.add({
        "icon_type": "sunny",
        "title": isEn ? "Hydrate Your Body" : "เติมน้ำให้ร่างกาย",
        "description": isEn
            ? "It's $currentTime and you have $remaining ml left. Keep drinking steadily."
            : "ขณะนี้เวลา $currentTime ยังขาดอีก $remaining ml ควรจิบน้ำเพิ่มอย่างต่อเนื่อง",
      });
      tips.add({
        "icon_type": "coffee",
        "title": isEn ? "Sip Throughout the Day" : "แบ่งจิบน้ำทีละแก้ว",
        "description": isEn
            ? "Try sipping 150-200 ml every 30-45 minutes for optimal absorption."
            : "แนะนำจิบน้ำครั้งละ 150-200 ml ทุก 30-45 นาที เพื่อให้ร่างกายดูดซึมได้ดีที่สุด",
      });
    }

    return {
      "date": _getCurrentDateKey(),
      "avg_intake": todayTotal,
      "percent_target": percentInt,
      "health_score": healthScore,
      "consistency": consistency,
      "tips": tips,
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
      if (data['history_logs'] != null) {
        try {
          final historyMap = Map<dynamic, dynamic>.from(
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
      final currentDrink = latestDrink['type']?.toString() ?? 'น้ำเปล่า';
      final lastDrinkDesc =
          latestDrink['description']?.toString() ?? currentFormattedTime;
      final double lastDrinkAmount =
          double.tryParse('${latestDrink['amount']}') ?? 0.0;
      final streakDays = int.tryParse('${data['streak_days'] ?? 0}') ?? 0;

      double dailyTarget = 2400.0;
      if (data['profile'] != null && data['profile'] is Map) {
        final profile = Map<dynamic, dynamic>.from(data['profile'] as dynamic);
        dailyTarget =
            double.tryParse('${profile['daily_target'] ?? 2400}') ?? 2400.0;
      }

      final int percentInt = dailyTarget > 0
          ? ((todayTotal / dailyTarget) * 100).clamp(0, 100).toInt()
          : 0;
      final int remainingMl = (dailyTarget - todayTotal)
          .clamp(0, dailyTarget)
          .round();

      // 🌟 สั่งให้ AI ตอบกลับเป็นภาษาที่เลือก
      final String aiLangStr = _selectedLanguage == 'en' ? 'ENGLISH' : 'THAI';

      final prompt =
          """
คุณเป็น AI ผู้เชี่ยวชาญด้านสุขภาพและการดื่มน้ำ (Smart Cup AI)
ข้อมูลผู้ใช้จริง:
- วันที่: $todayKey
- เวลาปัจจุบัน: $currentFormattedTime
- ปริมาณที่ดื่มวันนี้: ${todayTotal.toStringAsFixed(1)} ml (เป้าหมาย: ${dailyTarget.toInt()} ml)
- ดื่มน้ำครั้งล่าสุดเมื่อ: $lastDrinkDesc (ประเภท: $currentDrink, ปริมาณ: ${lastDrinkAmount.toInt()} ml)
- Streak: $streakDays วัน

คำสั่ง:
1. แนะนำการดื่มน้ำให้กระชับ เหมาะกับช่วงเวลาปัจจุบัน ($currentFormattedTime)
2. หากปริมาณที่ดื่มวันนี้เป็น 0 ml ให้อ้างอิงการดื่มล่าสุด ($lastDrinkDesc) แล้วแนะนำเริ่มต้นจิบน้ำแก้วแรกของวัน ห้ามระบุว่าดื่มไปแล้ว
3. ห้ามแต่งตัวเลขเปอร์เซ็นต์ขึ้นมาเองในเนื้อหาเด็ดขาด
4. LANGUAGE REQUIREMENT: You MUST generate your response in $aiLangStr language ONLY.
5. ตอบเป็น JSON โครงสร้างนี้เท่านั้น:
{
  "health_score": <คะแนนสุขภาพ 0-100>,
  "consistency": <คะแนนความสม่ำเสมอ 0-100>,
  "tips": [
    {
      "icon_type": "<sunny หรือ fire หรือ coffee หรือ alert>",
      "title": "<หัวข้อคำแนะนำ>",
      "description": "<คำแนะนำสั้นๆ สอดคล้องกับเวลาปัจจุบัน>"
    }
  ]
}
""";

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey',
      );

      http.Response? response;
      for (int i = 0; i < 2; i++) {
        try {
          response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
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

          if (response.statusCode == 200) {
            break;
          } else if (response.statusCode == 503) {
            await Future.delayed(const Duration(seconds: 1));
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }

      Map<String, dynamic> aiResult;

      if (response != null && response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final rawText = resJson['candidates'][0]['content']['parts'][0]['text'];
        final Map<String, dynamic> generated = jsonDecode(rawText);

        List<dynamic> parsedTips = generated['tips'] ?? [];
        List<Map<String, dynamic>> finalTips = [];

        bool isEn = _selectedLanguage == 'en';

        if (todayTotal <= 0) {
          finalTips.add({
            "icon_type": "sunny",
            "title": isEn ? "Start Your Day" : "เริ่มต้นวันใหม่",
            "description": isEn
                ? "It's $currentFormattedTime, start your first glass to wake up!"
                : "ขณะนี้เวลา $currentFormattedTime วันนี้ยังไม่ได้เริ่มดื่มน้ำ แนะนำจิบน้ำแก้วแรกเพื่อปลุกความสดชื่น",
          });
        } else if (percentInt >= 100) {
          finalTips.add({
            "icon_type": "trophy",
            "title": isEn ? "Goal Achieved!" : "ยอดเยี่ยม บรรลุเป้าหมายแล้ว!",
            "description": isEn
                ? "You drank ${dailyTarget.toInt()} ml today. Great job!"
                : "คุณดื่มน้ำครบตามเป้าหมาย ${dailyTarget.toInt()} ml ในวันนี้แล้ว รักษามาตรฐานที่ดีนี้ไว้",
          });
        } else {
          finalTips.add({
            "icon_type": "sunny",
            "title": isEn ? "Hydrate Now" : "เติมน้ำให้ร่างกาย",
            "description": isEn
                ? "It's $currentFormattedTime, you need $remainingMl ml more. Keep it up!"
                : "ขณะนี้เวลา $currentFormattedTime ยังขาดอีก $remainingMl ml ควรจิบน้ำเพิ่มอย่างต่อเนื่อง",
          });
        }

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
          "health_score": generated['health_score'] ?? 75,
          "consistency": generated['consistency'] ?? 50,
          "tips": finalTips,
        };
      } else {
        aiResult = _generateLocalAnalysis(
          todayTotal: todayTotal,
          dailyTarget: dailyTarget,
          percentInt: percentInt,
          currentTime: currentFormattedTime,
          streakDays: streakDays,
        );
      }

      await smartCupRef('ai_insights').set(aiResult);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_t('success'))));
      }
    } catch (e) {
      debugPrint('Error analyzing AI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${_t('error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
                  _buildScoreCards(),
                  const SizedBox(height: 28),
                  SectionTitle(_t('tips_for_you')),
                  const SizedBox(height: 14),
                  if (_tips.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          _t('no_tips'),
                          style: const TextStyle(color: textGrey, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ..._tips.map(_buildTipCard),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
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
