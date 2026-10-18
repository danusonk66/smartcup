import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/theme.dart';
import '../core/ui_kit.dart';
import '../core/utils.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _enabled = true;

  int _alertHours = 2;
  int _alertMinutes = 0;

  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 6, minute: 0);
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรภาษา

  List<Map<String, String>> _logs = [];

  String _currentDateKey = '';
  Timer? _midnightTimer;

  StreamSubscription<DatabaseEvent>? _langSubscription; // 🌟 ตัวดักจับภาษา
  StreamSubscription<DatabaseEvent>? _settingsSubscription;
  StreamSubscription<DatabaseEvent>? _logsSubscription;

  // 🌟 พจนานุกรมแปลภาษาหน้าการแจ้งเตือน
  final Map<String, Map<String, String>> _notiTexts = {
    'th': {
      'title': 'การแจ้งเตือน',
      'subtitle': 'ตั้งค่าการแจ้งเตือนของ SmartCup',
      'enable_noti': 'เปิดการแจ้งเตือน',
      'freq_title': 'ความถี่ในการแจ้งเตือน',
      'hour': 'ชั่วโมง',
      'hr': 'ชม.',
      'min': 'น.',
      'custom': 'กำหนดเอง',
      'quiet_time': 'ช่วงเวลาปิดเสียงแจ้งเตือน',
      'start': 'เริ่มต้น',
      'end': 'สิ้นสุด',
      'save_settings': 'บันทึกการตั้งค่า',
      'today_history': 'ประวัติการแจ้งเตือนวันนี้',
      'no_history': 'ยังไม่มีประวัติการแจ้งเตือนในวันนี้',
      'save_success': 'บันทึกการตั้งค่าแล้ว',
      'cancel': 'ยกเลิก',
      'ok': 'ตกลง',
      'select_duration': 'เลือกระยะเวลา',
      'time_to_drink': 'ถึงเวลาที่ควรดื่มน้ำ',
    },
    'en': {
      'title': 'Notifications',
      'subtitle': 'Manage SmartCup alert settings',
      'enable_noti': 'Enable Notifications',
      'freq_title': 'Notification Frequency',
      'hour': 'Hour',
      'hr': 'hr',
      'min': 'm',
      'custom': 'Custom',
      'quiet_time': 'Do Not Disturb (Quiet Time)',
      'start': 'Start',
      'end': 'End',
      'save_settings': 'Save Settings',
      'today_history': 'Today\'s Alert History',
      'no_history': 'No notifications today.',
      'save_success': 'Settings saved successfully',
      'cancel': 'Cancel',
      'ok': 'OK',
      'select_duration': 'Select Duration',
      'time_to_drink': 'Time to drink water',
    },
  };

  String _t(String key) {
    return _notiTexts[_selectedLanguage]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _currentDateKey = _getCurrentDateKey();
    _listenLanguage(); // 🌟 เรียกฟังภาษาทันที
    _listenSettings();
    _listenLogs();

    _midnightTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final nowKey = _getCurrentDateKey();
      if (nowKey != _currentDateKey) {
        _currentDateKey = nowKey;
        _cleanMidnightLogs();
      }
    });
  }

  String _getCurrentDateKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  int _timeStringToMinutes(String timeStr) {
    try {
      final clean = timeStr
          .replaceAll(' น.', '')
          .replaceAll(' AM', '')
          .replaceAll(' PM', '')
          .trim();
      final parts = clean.split(':');
      if (parts.length >= 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _cleanMidnightLogs() async {
    if (!isFirebaseReady()) return;
    try {
      await smartCupRef('notification_logs').remove();
      if (mounted) {
        setState(() {
          _logs = [];
        });
      }
    } catch (e) {
      debugPrint('Error cleaning midnight logs: $e');
    }
  }

  // 🌟 ฟังการตั้งค่าภาษาแบบ Real-time
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
      debugPrint('Noti Lang error: $e');
    }
  }

  void _listenSettings() {
    if (!isFirebaseReady()) return;

    try {
      _settingsSubscription = smartCupRef('settings').onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) return;

        Map<dynamic, dynamic> mapData;
        try {
          mapData = Map<dynamic, dynamic>.from(data as dynamic);
        } catch (_) {
          return;
        }

        if (!mounted) return;

        setState(() {
          _enabled = mapData['notification_enabled'] != false;
          _alertHours =
              int.tryParse('${mapData['alert_hours'] ?? _alertHours}') ??
              _alertHours;
          _alertMinutes =
              int.tryParse('${mapData['alert_minutes'] ?? _alertMinutes}') ??
              _alertMinutes;

          if (mapData['quiet_start'] != null) {
            _quietStart = parseTOD(mapData['quiet_start']);
          }
          if (mapData['quiet_end'] != null) {
            _quietEnd = parseTOD(mapData['quiet_end']);
          }
        });
      });
    } catch (e) {
      debugPrint('Notification Settings error: $e');
    }
  }

  void _listenLogs() {
    if (!isFirebaseReady()) return;

    try {
      _logsSubscription = smartCupRef('notification_logs')
          .limitToLast(30)
          .onValue
          .listen((event) {
            final data = event.snapshot.value;
            if (data == null) {
              if (mounted) setState(() => _logs = []);
              return;
            }

            try {
              final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(
                data as dynamic,
              );
              final List<Map<String, dynamic>> tempLogs = [];
              final String todayKey = _getCurrentDateKey();
              final Map<String, dynamic> dbUpdates = {};

              rawMap.forEach((key, value) {
                if (value is Map) {
                  final String logKey = key.toString();
                  final String? itemDate = value['date']?.toString();
                  final String timeStr = value['time']?.toString() ?? '';
                  final String messageStr =
                      value['message']?.toString() ?? 'ถึงเวลาที่ควรดื่มน้ำ';

                  if (itemDate == null) {
                    dbUpdates['notification_logs/$logKey/date'] = todayKey;
                    tempLogs.add({
                      'time': timeStr,
                      'message': messageStr,
                      'sortKey': _timeStringToMinutes(timeStr),
                    });
                  } else if (itemDate != todayKey) {
                    dbUpdates['notification_logs/$logKey'] = null;
                  } else {
                    tempLogs.add({
                      'time': timeStr,
                      'message': messageStr,
                      'sortKey': _timeStringToMinutes(timeStr),
                    });
                  }
                }
              });

              if (dbUpdates.isNotEmpty) {
                smartCupRef().update(dbUpdates);
              }

              tempLogs.sort(
                (a, b) => (b['sortKey'] as int).compareTo(a['sortKey'] as int),
              );

              final List<Map<String, String>> sortedLogs = tempLogs
                  .map(
                    (item) => {
                      'time': item['time'].toString(),
                      'message': item['message']
                          .toString(), // เก็บข้อความดิบไว้ก่อน
                    },
                  )
                  .toList();

              if (mounted) {
                setState(() {
                  _logs = sortedLogs;
                });
              }
            } catch (e) {
              debugPrint('Error parsing notification logs: $e');
            }
          });
    } catch (e) {
      debugPrint('Notification Logs error: $e');
    }
  }

  Future<void> _saveSettings() async {
    if (!isFirebaseReady()) return;

    try {
      await smartCupRef('settings').update({
        'notification_enabled': _enabled,
        'alert_hours': _alertHours,
        'alert_minutes': _alertMinutes,
        'interval_minutes': (_alertHours * 60) + _alertMinutes,
        'quiet_start': formatTOD(_quietStart),
        'quiet_end': formatTOD(_quietEnd),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('save_success')),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Notification save error: $e');
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = start ? _quietStart : _quietEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked == null || !mounted) return;

    setState(() {
      if (start) {
        _quietStart = picked;
      } else {
        _quietEnd = picked;
      }
    });
  }

  void _showIntervalPicker() {
    int tempHours = _alertHours;
    int tempMinutes = _alertMinutes;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        _t('cancel'),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      _t('select_duration'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryDark,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _alertHours = tempHours;
                          _alertMinutes = tempMinutes;
                        });
                        Navigator.pop(context);
                      },
                      child: Text(
                        _t('ok'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: oceanBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  initialTimerDuration: Duration(
                    hours: tempHours,
                    minutes: tempMinutes,
                  ),
                  onTimerDurationChanged: (Duration newDuration) {
                    tempHours = newDuration.inHours;
                    tempMinutes = newDuration.inMinutes % 60;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _langSubscription?.cancel();
    _settingsSubscription?.cancel();
    _logsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    _t('subtitle'),
                    style: const TextStyle(color: textGrey, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  _buildNotificationSetting(),
                  const SizedBox(height: 16),
                  _buildQuietSetting(),
                  const SizedBox(height: 16),
                  _buildTodayLogs(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _freqChip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    IconData? trailing,
  }) {
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? oceanBlue
              : Colors.white.withValues(alpha: enabled ? 0.8 : 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? oceanBlue : surfaceLine),
          boxShadow: selected && enabled
              ? [
                  BoxShadow(
                    color: oceanBlue.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : (enabled ? textDark : textGrey),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      trailing,
                      size: 16,
                      color: selected ? Colors.white : textGrey,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationSetting() {
    bool isCustomTime =
        !([1, 2, 3].contains(_alertHours) && _alertMinutes == 0);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: glassDecoration(radius: 24),
      child: Column(
        children: [
          Row(
            children: [
              const GradientIconChip(
                icon: Icons.notifications_active_rounded,
                size: 50,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _t('enable_noti'),
                  style: const TextStyle(
                    color: primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Switch(
                value: _enabled,
                activeThumbColor: Colors.white,
                activeTrackColor: oceanBlue,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: oceanBlue.withValues(alpha: 0.10)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _t('freq_title'),
              style: const TextStyle(
                color: primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                ...[1, 2, 3].map((hour) {
                  final isSelected =
                      (_alertHours == hour && _alertMinutes == 0);
                  String labelHourText = _selectedLanguage == 'en' && hour > 1
                      ? '${_t('hour')}s'
                      : _t('hour');
                  return _freqChip(
                    label: '$hour $labelHourText',
                    selected: isSelected,
                    onTap: _enabled
                        ? () {
                            setState(() {
                              _alertHours = hour;
                              _alertMinutes = 0;
                            });
                          }
                        : null,
                  );
                }),
                _freqChip(
                  label: isCustomTime
                      ? '$_alertHours ${_t('hr')} ${_alertMinutes > 0 ? '$_alertMinutes ${_t('min')}' : ''}'
                      : _t('custom'),
                  selected: isCustomTime,
                  trailing: Icons.timer_outlined,
                  onTap: _enabled
                      ? () {
                          _showIntervalPicker();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuietSetting() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GradientIconChip(
                icon: Icons.bedtime_rounded,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _t('quiet_time'),
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _timeRow(
                  title: _t('start'),
                  time: _quietStart,
                  onTap: () => _pickTime(start: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, color: oceanBlue),
              ),
              Expanded(
                child: _timeRow(
                  title: _t('end'),
                  time: _quietEnd,
                  onTap: () => _pickTime(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          GradientButton(
            onPressed: _saveSettings,
            expand: true,
            label: Text(_t('save_settings')),
          ),
        ],
      ),
    );
  }

  // การ์ดเวลาโทนน้ำลึก (เหมือนช่วงกลางคืน) แตะเพื่อเปลี่ยนเวลา
  Widget _timeRow({
    required String title,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E4A66), primaryDark],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: cyanLight,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatTOD(time),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayLogs() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(_t('today_history')),
          const SizedBox(height: 14),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cyanLight.withValues(alpha: 0.18),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: oceanBlue,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t('no_history'),
                      style: const TextStyle(color: textGrey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._logs.map((log) {
              // 🌟 แปลภาษาสำหรับรายการประวัติแจ้งเตือน
              String displayMsg = log['message'] ?? '';
              if (displayMsg == 'ถึงเวลาที่ควรดื่มน้ำ' ||
                  displayMsg == 'Time to drink water') {
                displayMsg = _t('time_to_drink');
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const GradientIconChip(
                      icon: Icons.notifications_none_rounded,
                      size: 42,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        displayMsg,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: oceanBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        log['time'] ?? '',
                        style: const TextStyle(
                          color: primaryDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
