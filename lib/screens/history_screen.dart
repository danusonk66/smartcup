import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/theme.dart';
import '../core/ui_kit.dart';
import '../core/utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // ตัวควบคุมการเลื่อนของกราฟ
  final ScrollController _chartScrollController = ScrollController();

  // เก็บข้อมูลทั้งหมดจาก Firebase เพื่อใช้สลับดูแต่ละวันได้ทันที
  Map<dynamic, dynamic> _allHistoryMap = {};

  // เก็บข้อมูลกราฟ 15 วัน
  List<Map<String, dynamic>> _chartData = [];

  // 🌟 เก็บวันที่ที่ผู้ใช้กดเลือกบนกราฟ (ค่าเริ่มต้นคือวันนี้)
  String _selectedDateKey = '';
  bool _hasScrolledInitially = false;

  String _filterKey =
      'all'; // ใช้ key เป็น 'all', 'water', 'other' เพื่อจัดการภาษาง่าย
  double _selectedDayTotal = 0;
  double _dailyTarget = 2400;
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรภาษา

  List<Map<String, dynamic>> _selectedDayLogs = [];
  StreamSubscription<DatabaseEvent>? _logsSubscription;

  // 🌟 พจนานุกรมประวัติการดื่มน้ำ
  final Map<String, Map<String, String>> _histTexts = {
    'th': {
      'title': 'ประวัติการดื่มน้ำ',
      'records': 'รายการบันทึก',
      'tap_chart': 'แตะที่แท่งกราฟเพื่อดูประวัติการดื่มน้ำในแต่ละวัน',
      'stat_15_days': 'สถิติ 15 วัน',
      'viewing': 'เลือกดู: ',
      'all': 'ทั้งหมด',
      'water': 'น้ำเปล่า',
      'other': 'เครื่องดื่มอื่น',
      'timeline': 'ไทม์ไลน์การดื่มน้ำ',
      'items': 'รายการ',
      'total_summary': 'สรุปยอดรวม',
      'daily_total': 'ยอดรวมทั้งหมดของวัน',
      'time_at': 'เวลา ',
      'no_history': 'ไม่มีประวัติการดื่มน้ำใน',
      'no_filter_item': 'ไม่มีรายการ "\$_filterKey" ใน',
      'today': 'วันนี้',
      'yesterday': 'เมื่อวาน',
      'date': 'วันที่',
    },
    'en': {
      'title': 'Hydration History',
      'records': 'Records',
      'tap_chart': 'Tap a bar to see your daily hydration history',
      'stat_15_days': '15-Day Stats',
      'viewing': 'Viewing: ',
      'all': 'All',
      'water': 'Water',
      'other': 'Other Drinks',
      'timeline': 'Hydration Timeline',
      'items': 'Items',
      'total_summary': 'Total Summary',
      'daily_total': 'Total intake for the day',
      'time_at': 'Time ',
      'no_history': 'No drink history for ',
      'no_filter_item': 'No records for "\$_filterKey" on ',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'date': 'Date',
    },
  };

  String _t(String key) {
    return _histTexts[_selectedLanguage]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _selectedDateKey = _getDateKey(DateTime.now());
    _listenLogsData();
  }

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _getTranslatedDay(int weekday) {
    if (_selectedLanguage == 'en') {
      switch (weekday) {
        case 1:
          return 'Mon';
        case 2:
          return 'Tue';
        case 3:
          return 'Wed';
        case 4:
          return 'Thu';
        case 5:
          return 'Fri';
        case 6:
          return 'Sat';
        case 7:
          return 'Sun';
        default:
          return '';
      }
    } else {
      switch (weekday) {
        case 1:
          return 'จ';
        case 2:
          return 'อ';
        case 3:
          return 'พ';
        case 4:
          return 'พฤ';
        case 5:
          return 'ศ';
        case 6:
          return 'ส';
        case 7:
          return 'อา';
        default:
          return '';
      }
    }
  }

  String _getFormattedSelectedDateTitle() {
    final now = DateTime.now();
    final todayKey = _getDateKey(now);
    final yesterdayKey = _getDateKey(now.subtract(const Duration(days: 1)));

    if (_selectedDateKey == todayKey) return _t('today');

    try {
      final parts = _selectedDateKey.split('-');
      if (parts.length == 3) {
        final day = int.parse(parts[2]);
        final month = int.parse(parts[1]);

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
          if (_selectedDateKey == yesterdayKey) {
            return '${_t('yesterday')} ($day ${enMonths[month]})';
          }
          return '$day ${enMonths[month]}';
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
          if (_selectedDateKey == yesterdayKey) {
            return '${_t('yesterday')} ($day ${thaiMonths[month]})';
          }
          return '${_t('date')} $day ${thaiMonths[month]}';
        }
      }
    } catch (_) {}

    return _selectedDateKey;
  }

  void _updateSelectedDayData() {
    double tempTotal = 0;
    List<Map<String, dynamic>> tempLogs = [];

    if (_allHistoryMap.containsKey(_selectedDateKey) &&
        _allHistoryMap[_selectedDateKey] is Map) {
      final dayMap = Map<dynamic, dynamic>.from(
        _allHistoryMap[_selectedDateKey] as dynamic,
      );
      tempTotal = double.tryParse('${dayMap['daily_total']}') ?? 0;

      if (dayMap['logs'] != null && dayMap['logs'] is Map) {
        final logs = Map<dynamic, dynamic>.from(dayMap['logs'] as dynamic);
        logs.forEach((key, value) {
          if (value is Map) {
            final log = Map<dynamic, dynamic>.from(value as dynamic);
            tempLogs.add({
              'time': log['time']?.toString() ?? '--:--',
              'amount':
                  '${formatNumber(double.tryParse('${log['amount']}') ?? 0)} ml',
              'type': log['type']?.toString() ?? 'น้ำเปล่า',
              'timestamp': num.tryParse('${log['timestamp'] ?? key}') ?? 0,
            });
          }
        });
      }
    }

    tempLogs.sort(
      (a, b) => (b['timestamp'] as num).compareTo(a['timestamp'] as num),
    );

    _selectedDayTotal = tempTotal;
    _selectedDayLogs = tempLogs;
  }

  void _listenLogsData() {
    if (!isFirebaseReady()) return;
    try {
      _logsSubscription = smartCupRef().onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) {
          if (mounted) {
            setState(() {
              _allHistoryMap = {};
              _selectedDayLogs = [];
              _selectedDayTotal = 0;
              _chartData = [];
            });
          }
          return;
        }

        Map<dynamic, dynamic> mapData;
        try {
          mapData = Map<dynamic, dynamic>.from(data as dynamic);
        } catch (_) {
          return;
        }

        String lang = _selectedLanguage;
        double newDailyTarget = 2400;

        if (mapData['profile'] != null) {
          try {
            final profile = Map<dynamic, dynamic>.from(
              mapData['profile'] as dynamic,
            );
            lang = profile['language']?.toString() ?? _selectedLanguage;
            newDailyTarget =
                double.tryParse('${profile['daily_target']}') ?? 2400;
          } catch (_) {}
        }

        _selectedLanguage = lang;
        _dailyTarget = newDailyTarget > 0 ? newDailyTarget : 2400;

        Map<dynamic, dynamic> historyData = {};
        if (mapData['history_logs'] != null) {
          historyData = Map<dynamic, dynamic>.from(
            mapData['history_logs'] as dynamic,
          );
        }
        _allHistoryMap = historyData;

        DateTime now = DateTime.now();
        String todayKey = _getDateKey(now);

        if (_selectedDateKey.isEmpty) {
          _selectedDateKey = todayKey;
        }

        int maxDaysToShow = 1;
        if (historyData.isNotEmpty) {
          DateTime? oldestDate;
          for (var key in historyData.keys) {
            try {
              List<String> parts = key.toString().split('-');
              if (parts.length == 3) {
                DateTime date = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
                if (oldestDate == null || date.isBefore(oldestDate)) {
                  oldestDate = date;
                }
              }
            } catch (_) {}
          }
          if (oldestDate != null) {
            DateTime todayDate = DateTime(now.year, now.month, now.day);
            int diffDays = todayDate.difference(oldestDate).inDays;
            maxDaysToShow = (diffDays + 1).clamp(1, 15);
          }
        }

        List<Map<String, dynamic>> tempChartData = [];
        for (int i = maxDaysToShow - 1; i >= 0; i--) {
          DateTime targetDate = now.subtract(Duration(days: i));
          String targetKey = _getDateKey(targetDate);
          String dateLabel = "${targetDate.day}/${targetDate.month}";

          double dailyTot = 0;
          if (historyData.containsKey(targetKey) &&
              historyData[targetKey] is Map) {
            dailyTot =
                double.tryParse('${historyData[targetKey]['daily_total']}') ??
                0;
          }

          tempChartData.add({
            'dateKey': targetKey,
            'weekday': targetDate.weekday,
            'date': dateLabel,
            'value': dailyTot,
            'isToday': (i == 0),
          });
        }

        _updateSelectedDayData();

        if (mounted) {
          setState(() {
            _chartData = tempChartData;
          });

          if (!_hasScrolledInitially) {
            _hasScrolledInitially = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_chartScrollController.hasClients) {
                _chartScrollController.jumpTo(
                  _chartScrollController.position.maxScrollExtent,
                );
              }
            });
          }
        }
      });
    } catch (e) {
      debugPrint('History logs error: $e');
    }
  }

  IconData _getDrinkIcon(String type) {
    switch (type) {
      case 'น้ำเปล่า':
        return Icons.water_drop_rounded;
      case 'น้ำผลไม้':
        return Icons.local_drink_rounded;
      case 'กาแฟ/ชา':
        return Icons.coffee_rounded;
      case 'นม':
        return Icons.local_drink_outlined;
      case 'ชานมไข่มุก':
        return Icons.bubble_chart_rounded;
      default:
        return Icons.local_bar_rounded;
    }
  }

  String _translateDrinkType(String thaiKey) {
    if (_selectedLanguage == 'th') return thaiKey;
    switch (thaiKey) {
      case 'น้ำเปล่า':
        return 'Water';
      case 'น้ำผลไม้':
        return 'Juice';
      case 'กาแฟ/ชา':
        return 'Coffee/Tea';
      case 'นม':
        return 'Milk';
      case 'ชานมไข่มุก':
        return 'Boba Tea';
      case 'อื่น ๆ':
        return 'Others';
      default:
        return thaiKey;
    }
  }

  @override
  void dispose() {
    _chartScrollController.dispose();
    _logsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _selectedDayLogs.where((log) {
      if (_filterKey == 'all') return true;
      if (_filterKey == 'water') return log['type'] == 'น้ำเปล่า';
      return log['type'] != 'น้ำเปล่า';
    }).toList();

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
                  const SizedBox(height: 22),
                  _buildWeeklyChart(),
                  const SizedBox(height: 18),
                  _buildFilterChips(),
                  const SizedBox(height: 18),
                  _buildTimeline(filteredLogs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('title'),
          style: const TextStyle(
            color: textDark,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _t('tap_chart'),
          style: const TextStyle(color: textGrey, fontSize: 14, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildWeeklyChart() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: glassDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GradientIconChip(
                icon: Icons.bar_chart_rounded,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('stat_15_days'),
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cyanLight.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_t('viewing')}${_getFormattedSelectedDateTitle()}',
              style: const TextStyle(
                color: primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 206,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double itemWidth = constraints.maxWidth / 7.0;

                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: _chartScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _chartData.map((data) {
                        final String dateKey =
                            data['dateKey']?.toString() ?? '';
                        final bool isSelected = (dateKey == _selectedDateKey);
                        final double val = (data['value'] as num).toDouble();

                        final double height = (val / _dailyTarget) * 100;
                        final bool isGoalMet = val >= _dailyTarget;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDateKey = dateKey;
                              _updateSelectedDayData();
                            });
                          },
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: itemWidth,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.9),
                                        cyanLight.withValues(alpha: 0.22),
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              border: isSelected
                                  ? Border.all(color: cyanLight, width: 1.5)
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: cyanLight.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ]
                                  : const [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (isGoalMet)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 12,
                                    color: accentGreen,
                                  ),
                                Text(
                                  formatNumber(val),
                                  style: TextStyle(
                                    color: isSelected ? primaryDark : textGrey,
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 24,
                                  height: 100,
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: oceanBlue.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 450,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        width: 24,
                                        height: height
                                            .clamp(6.0, 100.0)
                                            .toDouble(),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: isGoalMet
                                                ? [mint, accentGreen]
                                                : [cyanLight, oceanBlue],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _getTranslatedDay(data['weekday']),
                                  style: TextStyle(
                                    color: isSelected ? primaryDark : textGrey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  data['date'],
                                  style: TextStyle(
                                    color: isSelected ? oceanBlue : textGrey,
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': _t('all')},
      {'key': 'water', 'label': _t('water')},
      {'key': 'other', 'label': _t('other')},
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
      ),
      child: Row(
        children: filters.map((item) {
          final filterKey = item['key']!;
          final label = item['label']!;
          final selected = filterKey == _filterKey;

          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _filterKey = filterKey;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? primaryDark : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : textGrey,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> logs) {
    final String dateTitle = _getFormattedSelectedDateTitle();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: glassDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            '${_t('timeline')} ($dateTitle)',
            trailing: logs.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: oceanBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${logs.length} ${_t('items')}',
                      style: const TextStyle(
                        color: primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 18),

          if (_filterKey == 'all')
            _historyRow(
              time: '${_t('total_summary')} $dateTitle',
              amount: '${formatNumber(_selectedDayTotal)} ml',
              type: _t('daily_total'),
              isSpecial: true,
            ),

          ...logs.map(
            (log) => _historyRow(
              time: '${_t('time_at')}${log['time']}',
              amount: log['amount'] ?? '',
              type: _translateDrinkType(log['type'] ?? ''),
              rawType: log['type'],
              isSpecial: false,
            ),
          ),

          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cyanLight.withValues(alpha: 0.18),
                      ),
                      child: const Icon(
                        Icons.water_drop_outlined,
                        color: oceanBlue,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _filterKey == 'all'
                          ? '${_t('no_history')} $dateTitle'
                          : _t('no_filter_item').replaceAll(
                                  '\$_filterKey',
                                  _filterKey == 'water'
                                      ? _t('water')
                                      : _t('other'),
                                ) +
                                dateTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: textGrey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyRow({
    required String time,
    required String amount,
    required String type,
    String? rawType,
    bool isSpecial = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isSpecial
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFDDF8EE), Color(0xFFF1FCF8)],
              )
            : null,
        color: isSpecial ? null : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSpecial ? const Color(0xFFBBF7D0) : surfaceLine,
        ),
      ),
      child: Row(
        children: [
          GradientIconChip(
            icon: isSpecial
                ? Icons.auto_awesome_rounded
                : _getDrinkIcon(rawType ?? type),
            color: isSpecial ? accentGreen : oceanBlue,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    color: isSpecial ? const Color(0xFF065F46) : primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: TextStyle(
              color: isSpecial ? const Color(0xFF047857) : oceanBlue,
              fontSize: isSpecial ? 18 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
