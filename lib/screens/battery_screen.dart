import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/theme.dart';
import '../core/ui_kit.dart';
import '../core/utils.dart';

class BatteryScreen extends StatefulWidget {
  final double battery;

  const BatteryScreen({super.key, required this.battery});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  late double _battery;
  bool _charging = false;
  String _cableType = 'USB Type-C';
  double _capacity = 2500; // mAh
  double _voltage = 3.95; // V
  int _batteryHealth = 98; // %
  String _selectedLanguage = 'th'; // 🌟 ตัวแปรภาษา

  StreamSubscription<DatabaseEvent>? _subscription;

  // 🌟 พจนานุกรมแปลหน้าแบตเตอรี่
  final Map<String, Map<String, String>> _batTexts = {
    'th': {
      'title': 'สถานะแบตเตอรี่',
      'charging': 'กำลังชาร์จไฟ',
      'remaining': 'แบตเตอรี่คงเหลือ',
      'cable': 'กำลังเชื่อมต่อสายชาร์จ',
      'available_time': 'ใช้งานได้อีกประมาณ',
      'hours': 'ชม.',
      'warn_low': 'แบตเตอรี่ใกล้หมด กรุณาชาร์จ SmartCup เพื่อการบันทึกข้อมูลที่ต่อเนื่อง',
      'hw_info': 'ข้อมูลฮาร์ดแวร์แบตเตอรี่',
      'voltage': 'แรงดันไฟฟ้า (Voltage)',
      'voltage_sub': 'ช่วงทำงานปกติ 3.3V – 4.2V',
      'capacity': 'ความจุเซลล์แบตเตอรี่',
      'capacity_sub': 'Li-ion Battery',
      'health': 'สุขภาพแบตเตอรี่ (Health)',
      'health_sub': 'สถานะเซลล์สมบูรณ์',
      'port': 'พอร์ตชาร์จ',
      'port_sub': 'รองรับไฟชาร์จ 5V / 1A',
      'tip_prefix': 'เคล็ดลับ: ',
      'tip_desc': 'ไม่ควรปล่อยให้แบตเตอรี่หมดเกลี้ยง (0%) บ่อยครั้ง เพื่อยืดอายุการใช้งานของเซลล์แบตเตอรี่ในแก้วน้ำ',
    },
    'en': {
      'title': 'Battery Status',
      'charging': 'Charging',
      'remaining': 'Battery Remaining',
      'cable': 'Connected to charger',
      'available_time': 'Estimated time remaining',
      'hours': 'hrs.',
      'warn_low':
          'Low battery. Please charge your SmartCup to continue logging data.',
      'hw_info': 'Hardware Information',
      'voltage': 'Voltage',
      'voltage_sub': 'Normal range: 3.3V – 4.2V',
      'capacity': 'Battery Capacity',
      'capacity_sub': 'Li-ion Battery',
      'health': 'Battery Health',
      'health_sub': 'Healthy Cell Status',
      'port': 'Charging Port',
      'port_sub': 'Supports 5V / 1A',
      'tip_prefix': 'Tip: ',
      'tip_desc': 'Avoid draining the battery completely (0%) frequently to prolong the battery lifespan.',
    },
  };

  String _t(String key) {
    return _batTexts[_selectedLanguage]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _battery = widget.battery;
    _listenFirebase();
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

        String lang = _selectedLanguage;
        if (mapData['profile'] != null) {
          try {
            final profile = Map<dynamic, dynamic>.from(
              mapData['profile'] as dynamic,
            );
            lang = profile['language']?.toString() ?? _selectedLanguage;
          } catch (_) {}
        }

        if (!mounted) return;

        setState(() {
          _selectedLanguage = lang;
          _battery =
              double.tryParse('${mapData['battery_percent'] ?? _battery}') ??
              _battery;
          _charging =
              mapData['charging'] == true || mapData['is_charging'] == true;
          _cableType = '${mapData['cable_type'] ?? _cableType}';
          _capacity =
              double.tryParse('${mapData['battery_capacity'] ?? _capacity}') ??
              _capacity;
          _voltage =
              double.tryParse('${mapData['battery_voltage'] ?? _voltage}') ??
              _voltage;
          _batteryHealth =
              int.tryParse('${mapData['battery_health'] ?? _batteryHealth}') ??
              _batteryHealth;
        });
      });
    } catch (e) {
      debugPrint('Battery listener error: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estimatedHours = ((_battery / 100) * 18).clamp(0.0, 48.0);
    final bool low = _battery <= 20 && !_charging;
    final Color ringA = low
        ? coral
        : (_charging ? mint : const Color(0xFF22C3E6));
    final Color ringB = low
        ? const Color(0xFFE5484D)
        : (_charging ? const Color(0xFF22C3E6) : mint);

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: bgLight)),
        const AuraBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            iconTheme: const IconThemeData(color: primaryDark),
            title: Text(
              _t('title'),
              style: const TextStyle(
                color: primaryDark,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final double s = math.min(c.maxWidth, 270.0);
                        return Center(
                          child: TickRing(
                            size: s,
                            value: _battery / 100,
                            start: ringA,
                            end: ringB,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _charging
                                      ? Icons.bolt_rounded
                                      : Icons.battery_charging_full_rounded,
                                  color: _charging ? accentOrange : oceanBlue,
                                  size: 34,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_battery.toInt()}%',
                                  style: TextStyle(
                                    color: primaryDark,
                                    fontSize: s * 0.21,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _charging ? _t('charging') : _t('remaining'),
                                  style: const TextStyle(
                                    color: textGrey,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: glassDecoration(radius: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: oceanBlue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _charging
                                    ? '${_t('cable')} ($_cableType)'
                                    : '${_t('available_time')} ${estimatedHours.toStringAsFixed(1)} ${_t('hours')}',
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (low)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1ED),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFC9BA)),
                        ),
                        child: Row(
                          children: [
                            const GradientIconChip(
                              icon: Icons.warning_amber_rounded,
                              color: coral,
                              size: 40,
                              iconSize: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _t('warn_low'),
                                style: const TextStyle(
                                  color: Color(0xFF9A3412),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SectionTitle(_t('hw_info')),
                    const SizedBox(height: 16),
                    _specTile(
                      icon: Icons.electrical_services_rounded,
                      title: _t('voltage'),
                      value: '${_voltage.toStringAsFixed(2)} V',
                      sub: _t('voltage_sub'),
                      progress: (_voltage - 3.3) / (4.2 - 3.3),
                    ),
                    _specTile(
                      icon: Icons.battery_saver_rounded,
                      title: _t('capacity'),
                      value: '${_capacity.toInt()} mAh',
                      sub: _t('capacity_sub'),
                    ),
                    _specTile(
                      icon: Icons.health_and_safety_outlined,
                      title: _t('health'),
                      value: '$_batteryHealth%',
                      sub: _t('health_sub'),
                      progress: _batteryHealth / 100,
                    ),
                    _specTile(
                      icon: Icons.power_outlined,
                      title: _t('port'),
                      value: _cableType,
                      sub: _t('port_sub'),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: glassDecoration(radius: 22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const GradientIconChip(
                            icon: Icons.lightbulb_outline_rounded,
                            color: coral,
                            size: 44,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: textGrey,
                                  fontSize: 13,
                                  height: 1.55,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text: _t('tip_prefix'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: textDark,
                                    ),
                                  ),
                                  TextSpan(text: _t('tip_desc')),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniBar(double p) {
    final double f = p.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 6,
        color: oceanBlue.withValues(alpha: 0.12),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: f,
          heightFactor: 1,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cyanLight, mint]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _specTile({
    required IconData icon,
    required String title,
    required String value,
    required String sub,
    double? progress,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: glassDecoration(radius: 22),
      child: Row(
        children: [
          GradientIconChip(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  _miniBar(progress),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: primaryDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
