import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../core/ui_kit.dart';
import '../core/utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _age = 25;
  double _weight = 68;
  double _height = 172;
  // ใช้ค่าภาษาไทยเป็นค่าหลักในระบบ (Backend) เพื่อไม่ให้ข้อมูลเดิมใน Firebase พัง
  String _gender = 'ชาย';
  String _statusType = 'บุคคลทั่วไป';
  String _statusDetail = 'ไตรมาสที่ 2';
  String _name = 'สมชาย ใจดี';
  String? _imagePath;
  String _profileIcon = 'person';
  String _selectedLanguage = 'th';

  // 🌟 ตัวแปรสำหรับตั้งค่าภาชนะ/ขวดน้ำ (ค่าเริ่มต้นคือ แก้ว SmartCup)
  String _cupType = 'smartcup';
  double _cupWeight =
      396; // น้ำหนักแก้วประจำ SmartCup (กรัม) ให้ตรงกับ _cupOptions

  // ค่าภาชนะที่บันทึกอยู่ใน Firebase ล่าสุด (ใช้เช็คว่ามีการเปลี่ยนที่ยังไม่ได้บันทึกไหม)
  String _savedCupType = 'smartcup';
  double _savedCupWeight = 396;
  bool _savingCup = false;

  double get _pendingCupWeight =>
      double.tryParse(_cupWeightController.text) ?? _cupWeight;

  bool get _isCupDirty =>
      _cupType != _savedCupType || _pendingCupWeight != _savedCupWeight;

  double _dailyTarget = 2400;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _cupWeightController = TextEditingController();

  StreamSubscription<DatabaseEvent>? _subscription;

  // 🌟 รายการประเภทแก้ว/ขวดน้ำและน้ำหนักมาตรฐาน (กรัม)
  final List<Map<String, dynamic>> _cupOptions = [
    {'key': 'smartcup', 'weight': 396.0, 'icon': Icons.auto_awesome_rounded},
    // ขวดน้ำพลาสติก 500-600 ml (ขวดเปล่าหนัก 18 g)
    {
      'key': 'plastic_bottle',
      'weight': 18.0,
      'icon': Icons.local_drink_rounded,
    },
    // ขวดน้ำพลาสติก 1.5 ลิตร (ขวดเปล่าหนัก 34 g)
    {
      'key': 'plastic_bottle_1500',
      'weight': 34.0,
      'icon': Icons.local_drink_rounded,
    },
    // แก้วพลาสติก / คาเฟ่ (หนัก 18 g)
    {'key': 'cafe_cup', 'weight': 18.0, 'icon': Icons.takeout_dining_rounded},
    {'key': 'custom', 'weight': 0.0, 'icon': Icons.scale_rounded},
  ];

  // 🌟 พจนานุกรมแปลภาษาหน้าโปรไฟล์
  // static const: ให้ Hot Reload เห็นข้อความที่เพิ่ม/แก้ใหม่ทันที
  // (ถ้าเป็น field ปกติ Hot Reload จะไม่สร้าง Map ใหม่ ต้อง Hot Restart ถึงจะเห็น)
  static const Map<String, Map<String, String>> _localizedTexts = {
    'th': {
      'title': 'โปรไฟล์และการตั้งค่า',
      'subtitle': 'ตั้งค่าภาชนะและข้อมูลส่วนตัวก่อนเริ่มใช้งาน',
      'target': 'เป้าหมายการดื่มน้ำต่อวัน',
      'target_hint': 'แสดงเป้าหมายปัจจุบัน (จะอัปเดตเมื่อกดปุ่มบันทึกข้อมูล)',
      'cup_section_title': 'เลือกแก้วหรือขวดน้ำที่ใช้',
      'cup_section_subtitle': 'ระบบจะหักน้ำหนักภาชนะออกให้อัตโนมัติขณะชั่งน้ำ',
      'cup_smartcup': 'แก้วประจำ SmartCup (แนะนำ)',
      'cup_plastic_bottle': 'ขวดน้ำพลาสติก 500–600 ml',
      'cup_plastic_bottle_1500': 'ขวดน้ำพลาสติก 1.5 ลิตร',
      'cup_cafe_cup': 'แก้วพลาสติก / คาเฟ่',
      'cup_custom': 'ภาชนะอื่นๆ (ระบุน้ำหนักเอง)',
      'cup_weight_label': 'น้ำหนักภาชนะเปล่า (กรัม)',
      'personal_info': 'ข้อมูลส่วนตัว',
      'gender': 'เพศ',
      'male': 'ชาย',
      'female': 'หญิง',
      'special_status': 'สถานะพิเศษ',
      'general': 'บุคคลทั่วไป',
      'pregnant': 'หญิงตั้งครรภ์',
      'breastfeeding': 'หญิงให้นมบุตร',
      'pregnancy_term': 'ระยะตั้งครรภ์',
      'trimester_1': 'ไตรมาสที่ 1',
      'trimester_2': 'ไตรมาสที่ 2',
      'trimester_3': 'ไตรมาสที่ 3',
      'child_age': 'ช่วงอายุของบุตร',
      'month_0_5': '0-5 เดือน',
      'month_6_11': '6-11 เดือน',
      'age': 'อายุ',
      'weight': 'น้ำหนัก',
      'height': 'ส่วนสูง',
      'info_notice': 'ชื่อ รูปโปรไฟล์ และข้อมูลส่วนตัวจะบันทึกเมื่อกดปุ่ม "บันทึกข้อมูล" ด้านล่าง (ภาชนะบันทึกแยกในการ์ดด้านบน)',
      'save': 'บันทึกข้อมูล',
      'saved_success': 'บันทึกข้อมูลโปรไฟล์เรียบร้อยแล้ว',
      'save_cup': 'บันทึกภาชนะ',
      'cup_saved_success':
          'บันทึกภาชนะเรียบร้อยแล้ว เครื่องจะอัปเดตภายในไม่กี่วินาที',
      'cup_save_failed': 'ไม่สามารถบันทึกภาชนะได้',
      'cup_unsaved': 'ยังไม่ได้บันทึก',
    },
    'en': {
      'title': 'Profile & Settings',
      'subtitle': 'Set up your cup and personal info before starting',
      'target': 'Daily Water Intake Goal',
      'target_hint': 'Current goal (updates when you press save)',
      'cup_section_title': 'Select Your Cup / Bottle',
      'cup_section_subtitle':
          'Container weight will be automatically deducted when weighing',
      'cup_smartcup': 'Official SmartCup (Default)',
      'cup_plastic_bottle': 'Plastic Bottle 500–600 ml',
      'cup_plastic_bottle_1500': 'Plastic Bottle 1.5 L',
      'cup_cafe_cup': 'Plastic / Cafe Cup',
      'cup_custom': 'Other Container (Custom Weight)',
      'cup_weight_label': 'Empty container weight (grams)',
      'personal_info': 'Personal Information',
      'gender': 'Gender',
      'male': 'Male',
      'female': 'Female',
      'special_status': 'Special Status',
      'general': 'General',
      'pregnant': 'Pregnant',
      'breastfeeding': 'Breastfeeding',
      'pregnancy_term': 'Pregnancy Trimester',
      'trimester_1': '1st Trimester',
      'trimester_2': '2nd Trimester',
      'trimester_3': '3rd Trimester',
      'child_age': 'Child\'s Age',
      'month_0_5': '0-5 Months',
      'month_6_11': '6-11 Months',
      'age': 'Age',
      'weight': 'Weight',
      'height': 'Height',
      'info_notice': 'Name, picture, and personal info update when you press "Save Profile" below (the cup is saved separately in the card above).',
      'save': 'Save Profile',
      'saved_success': 'Profile saved successfully',
      'save_cup': 'Save Cup',
      'cup_saved_success': 'Cup saved. The device will update in a few seconds',
      'cup_save_failed': 'Could not save cup settings',
      'cup_unsaved': 'Not saved yet',
    },
  };

  String _t(String key) {
    // หาในภาษาที่เลือกก่อน ไม่เจอค่อยใช้ภาษาไทย สุดท้ายค่อยแสดง key แบบไม่มี _
    return _localizedTexts[_selectedLanguage]?[key] ??
        _localizedTexts['th']?[key] ??
        key.replaceAll('_', ' ');
  }

  @override
  void initState() {
    super.initState();
    _nameController.text = _name;
    _ageController.text = '$_age';
    _weightController.text = '$_weight';
    _heightController.text = '$_height';
    _cupWeightController.text = '${_cupWeight.toInt()}';
    // รีเฟรชสถานะปุ่มบันทึกภาชนะขณะพิมพ์น้ำหนักเอง
    _cupWeightController.addListener(() {
      if (mounted) setState(() {});
    });

    _dailyTarget = _calculateHybridTarget(
      _age,
      _gender,
      _weight,
      _height,
      _statusType,
      _statusDetail,
    );
    _listenFirebase();
  }

  // ─────────────────────────────────────────────────────────────
  // 🌟 ตารางอ้างอิง (เล่มโครงงาน ตาราง 2.1 และ 2.2 / DRI ไทย พ.ศ. 2563)
  // แต่ละแถว: [อายุสูงสุดของกลุ่ม, น้ำต่ำสุด, น้ำสูงสุด, น้ำหนักเฉลี่ย(kg), ส่วนสูงเฉลี่ย(cm)]
  // อายุเป็นจำนวนเต็ม (ปี): 0 = ทารก 6-11 เดือน (0-5 เดือนตารางให้ดื่มนมแม่ ไม่มีค่าน้ำ)
  // ─────────────────────────────────────────────────────────────
  static const List<List<double>> _maleWaterTable = [
    [0, 800, 1200, 8.7, 71.2], //   6-11 เดือน
    [3, 1000, 1500, 13.1, 90.8], // 1-3 ปี
    [5, 1300, 1950, 18.3, 109.5], // 4-5 ปี
    [8, 1400, 2100, 23.0, 122.3], // 6-8 ปี
    [12, 1700, 2550, 35.6, 142.2], // 9-12 ปี
    [15, 2500, 2550, 51.5, 164.3], // 13-15 ปี
    [18, 2250, 3375, 58.3, 171.2], // 16-18 ปี
    [30, 2150, 3225, 61.3, 170.8], // 19-30 ปี
    [50, 2100, 3150, 60.1, 169.2], // 31-50 ปี
    [60, 2100, 3150, 59.5, 167.8], // 51-60 ปี
    [70, 2100, 3150, 58.7, 165.1], // 61-70 ปี
    [999, 1750, 2625, 56.2, 163.6], // ≥71 ปี
  ];

  static const List<List<double>> _femaleWaterTable = [
    [0, 800, 1200, 8.0, 69.4], //   6-11 เดือน
    [3, 1000, 1500, 12.5, 89.6], // 1-3 ปี
    [5, 1300, 1950, 18.1, 108.9], // 4-5 ปี
    [8, 1400, 2100, 22.5, 121.0], // 6-8 ปี
    [12, 1600, 2400, 36.5, 143.9], // 9-12 ปี
    [15, 1800, 2550, 47.7, 157.1], // 13-15 ปี
    [18, 1850, 2775, 48.9, 158.8], // 16-18 ปี
    [30, 1750, 2625, 53.0, 158.9], // 19-30 ปี
    [50, 1750, 2625, 52.2, 157.6], // 31-50 ปี
    [60, 1750, 2625, 51.9, 156.5], // 51-60 ปี
    [70, 1750, 2625, 49.9, 153.5], // 61-70 ปี
    [999, 1550, 2325, 48.5, 152.0], // ≥71 ปี
  ];

  /// คำนวณเป้าหมายการดื่มน้ำต่อวัน (ml) ตามเล่มโครงงาน หัวข้อ 3.1:
  /// 1. หากลุ่มตามเพศ/อายุ ในตาราง 2.1 (ช่วงน้ำ) และ 2.2 (น้ำหนัก/ส่วนสูงเฉลี่ย)
  /// 2. น้ำหนัก "และ" ส่วนสูง เกินค่าเฉลี่ยทั้งคู่ → ใช้สูตร น้ำหนัก × 2.2 × 30 / 2
  ///    โดยไม่ต่ำกว่าค่ากลาง และไม่เกินค่าสูงสุดของตาราง 2.1
  /// 3. กรณีอื่น → ใช้ค่ากลางของช่วงในตาราง 2.1
  /// 4. บวกเพิ่ม หญิงตั้งครรภ์ไตรมาส 2-3 (+300) / หญิงให้นมบุตร (+500)
  double _calculateHybridTarget(
    int age,
    String gender,
    double currentWeight,
    double currentHeight,
    String statusType,
    String statusDetail,
  ) {
    final table = gender == 'ชาย' ? _maleWaterTable : _femaleWaterTable;
    final int safeAge = age < 0 ? 0 : age;
    final List<double> row = table.firstWhere(
      (r) => safeAge <= r[0],
      orElse: () => table.last,
    );

    final double minWater = row[1];
    final double maxWater = row[2];
    final double avgWeight = row[3];
    final double avgHeight = row[4];
    final double midWater = (minWater + maxWater) / 2;

    double target;
    final bool aboveStandard =
        currentWeight > avgWeight && currentHeight > avgHeight;

    if (aboveStandard) {
      // สูตรจาก utils.dart: น้ำหนัก × 2.2 × 30 / 2
      final double byFormula = calculateDailyTarget(currentWeight);
      target = byFormula < midWater ? midWater : byFormula;
      if (target > maxWater) target = maxWater;
    } else {
      target = midWater;
    }

    if (gender == 'หญิง') {
      if (statusType == 'หญิงตั้งครรภ์') {
        if (statusDetail == 'ไตรมาสที่ 2' || statusDetail == 'ไตรมาสที่ 3') {
          target += 300;
        }
      } else if (statusType == 'หญิงให้นมบุตร') {
        target += 500;
      }
    }

    // ปัดเป็นจำนวนเต็ม ให้ทุกหน้าแสดงเลขเดียวกัน
    return target.roundToDouble();
  }

  void _listenFirebase() {
    if (!isFirebaseReady()) return;

    try {
      _subscription = smartCupRef('profile').onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) return;

        Map<dynamic, dynamic> mapData;
        try {
          mapData = Map<dynamic, dynamic>.from(data as dynamic);
        } catch (_) {
          return;
        }

        if (!mounted) return;

        final name = mapData['name']?.toString() ?? _name;
        final imagePath = mapData['image_path']?.toString();
        final profileIcon = mapData['profile_icon']?.toString() ?? _profileIcon;
        final language = mapData['language']?.toString() ?? _selectedLanguage;
        final age = int.tryParse('${mapData['age'] ?? _age}') ?? _age;
        final weight =
            double.tryParse('${mapData['weight'] ?? _weight}') ?? _weight;
        final height =
            double.tryParse('${mapData['height'] ?? _height}') ?? _height;
        final gender = mapData['gender']?.toString() ?? _gender;
        final statusType = mapData['status_type']?.toString() ?? _statusType;
        final statusDetail =
            mapData['status_detail']?.toString() ?? _statusDetail;

        // ถ้า Firebase ยังไม่มีค่าภาชนะ ให้ถือค่าที่บันทึกล่าสุดเป็นหลัก
        final cupType = mapData['cup_type']?.toString() ?? _savedCupType;
        final cupWeight =
            double.tryParse('${mapData['cup_weight'] ?? _savedCupWeight}') ??
            _savedCupWeight;

        // 🌟 Firebase (profile/daily_target) เป็นแหล่งเดียวของเป้าหมาย ทุกหน้าอ่านจากที่นี่
        // คำนวณจากข้อมูลโปรไฟล์ที่บันทึกใน Firebase (ไม่ใช่ค่าที่กำลังแก้ค้างในฟอร์ม)
        final double target = _calculateHybridTarget(
          age,
          gender,
          weight,
          height,
          statusType,
          statusDetail,
        );
        final double? storedTarget = double.tryParse(
          '${mapData['daily_target']}',
        );

        // ยังไม่มีค่า หรือค่าเดิมคำนวณจากสูตรเก่า → เขียนค่าใหม่ทับ
        // ทุกหน้า (โฮม/ประวัติ/AI) จะได้ใช้เป้าหมายเดียวกัน
        if (storedTarget != target) {
          smartCupRef('profile').update({'daily_target': target});
        }

        // ถ้าค่าภาชนะใน Firebase ไม่เปลี่ยน อย่าทับสิ่งที่ผู้ใช้กำลังเลือกค้างไว้
        // (เช่น ตอนกดสลับภาษา listener จะยิงมาใหม่ทั้งก้อน)
        final bool cupChangedRemotely =
            cupType != _savedCupType || cupWeight != _savedCupWeight;
        final bool keepLocalCup = _isCupDirty && !cupChangedRemotely;

        setState(() {
          _savedCupType = cupType;
          _savedCupWeight = cupWeight;
          if (!keepLocalCup) {
            _cupType = cupType;
            _cupWeight = cupWeight;
            _cupWeightController.text = '${_cupWeight.toInt()}';
          }

          _name = name;
          _imagePath = imagePath;
          _profileIcon = profileIcon;
          _selectedLanguage = language;
          _age = age;
          _weight = weight;
          _height = height;
          _gender = gender;
          _statusType = statusType;
          _statusDetail = statusDetail;
          _dailyTarget = target;

          _nameController.text = _name;
          _ageController.text = '$_age';
          _weightController.text = '$_weight';
          _heightController.text = '$_height';
        });
      });
    } catch (e) {
      debugPrint('Profile Firebase error: $e');
    }
  }

  void _changeLanguage(String lang) {
    setState(() {
      _selectedLanguage = lang;
    });
    if (isFirebaseReady()) {
      smartCupRef('profile').update({'language': lang});
    }
  }

  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _imagePath = image.path;
      });
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'จัดการรูปโปรไฟล์',
                style: TextStyle(
                  color: primaryDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: oceanBlue),
                title: const Text('อัปโหลดรูปจากเครื่อง'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions, color: oceanBlue),
                title: const Text('เลือกไอคอนสำเร็จรูป'),
                onTap: () {
                  Navigator.pop(context);
                  _showIconPicker();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ไม่เปลี่ยนแล้ว (กลับหน้าโปรไฟล์)',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showIconPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final icons = [
          'person',
          'face',
          'sentiment_satisfied',
          'emoji_emotions',
          'pets',
          'local_fire_department',
        ];
        return AlertDialog(
          title: const Text(
            'เลือกไอคอน',
            style: TextStyle(color: primaryDark, fontWeight: FontWeight.bold),
          ),
          content: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: icons.map((iconName) {
              IconData iconData;
              switch (iconName) {
                case 'face':
                  iconData = Icons.face;
                  break;
                case 'sentiment_satisfied':
                  iconData = Icons.sentiment_satisfied;
                  break;
                case 'emoji_emotions':
                  iconData = Icons.emoji_emotions;
                  break;
                case 'pets':
                  iconData = Icons.pets;
                  break;
                case 'local_fire_department':
                  iconData = Icons.local_fire_department;
                  break;
                default:
                  iconData = Icons.person;
              }
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _imagePath = null;
                    _profileIcon = iconName;
                  });
                  Navigator.pop(context);
                },
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: _profileIcon == iconName
                      ? oceanBlue
                      : const Color(0xFFE6F4F8),
                  child: Icon(
                    iconData,
                    color: _profileIcon == iconName ? Colors.white : oceanBlue,
                    size: 30,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // 🌟 มีไฟล์รูปโปรไฟล์อยู่จริงไหม
  // รูปจาก image_picker ถูกเก็บในโฟลเดอร์ cache ซึ่งระบบลบได้ (ลงแอปใหม่/ล้างแคช)
  // ถ้าไฟล์หายไปแล้ว ให้แสดงไอคอนแทน ไม่ให้เกิด PathNotFoundException
  // (บนเว็บใช้ไฟล์ในเครื่องไม่ได้ จึงแสดงไอคอนเสมอ)
  bool get _hasProfileImage {
    if (kIsWeb) return false;
    final path = _imagePath;
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  IconData _getProfileIconData(String name) {
    switch (name) {
      case 'face':
        return Icons.face;
      case 'sentiment_satisfied':
        return Icons.sentiment_satisfied;
      case 'emoji_emotions':
        return Icons.emoji_emotions;
      case 'pets':
        return Icons.pets;
      case 'local_fire_department':
        return Icons.local_fire_department;
      default:
        return Icons.person;
    }
  }

  void _showEditNameDialog() {
    _nameController.text = _name;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'แก้ไขชื่อโปรไฟล์',
            style: TextStyle(color: primaryDark, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: primaryDark,
            ),
            decoration: InputDecoration(
              hintText: 'กรอกชื่อของคุณ',
              filled: true,
              fillColor: const Color(0xFFE6F4F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (_nameController.text.trim().isNotEmpty) {
                    _name = _nameController.text.trim();
                  }
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: oceanBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('ตกลง'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final age = int.tryParse(_ageController.text) ?? _age;
    final weight = double.tryParse(_weightController.text) ?? _weight;
    final height = double.tryParse(_heightController.text) ?? _height;

    final target = _calculateHybridTarget(
      age,
      _gender,
      weight,
      height,
      _statusType,
      _statusDetail,
    );

    setState(() {
      _age = age;
      _weight = weight;
      _height = height;
      _dailyTarget = target;
    });

    if (!isFirebaseReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกในเครื่องแล้ว (Firebase ยังไม่ได้เชื่อมต่อ)'),
        ),
      );
      return;
    }

    try {
      await smartCupRef('profile').update({
        'name': _name,
        'image_path': _imagePath ?? '',
        'profile_icon': _profileIcon,
        'language': _selectedLanguage,
        'age': age,
        'weight': weight,
        'height': height,
        'gender': _gender,
        'status_type': _statusType,
        'status_detail': _statusDetail,
        'daily_target': target,
        // ภาชนะ (cup_type / cup_weight) แยกไปบันทึกที่ _saveCup() แล้ว
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('saved_success'))));
    } catch (e) {
      debugPrint('Profile save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่สามารถบันทึกข้อมูลได้')));
    }
  }

  // 🌟 บันทึกเฉพาะภาชนะ: เขียนแค่ cup_type / cup_weight ไม่แตะข้อมูลโปรไฟล์อื่น
  // ESP32 อ่าน profile/cup_weight ทุก 5 วินาที จอ OLED จึงอัปเดตตามเองหลังบันทึก
  Future<void> _saveCup() async {
    final double cupWeight = _pendingCupWeight.clamp(0.0, 2000.0).toDouble();

    if (!isFirebaseReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('cup_save_failed'))));
      return;
    }

    setState(() => _savingCup = true);
    try {
      await smartCupRef('profile')
          .update({'cup_type': _cupType, 'cup_weight': cupWeight});

      if (!mounted) return;
      setState(() {
        _cupWeight = cupWeight;
        _savedCupType = _cupType;
        _savedCupWeight = cupWeight;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('cup_saved_success'))));
    } catch (e) {
      debugPrint('Cup save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t('cup_save_failed'))));
    } finally {
      if (mounted) setState(() => _savingCup = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _cupWeightController.dispose();
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
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
                              style: const TextStyle(
                                color: textGrey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildLangToggle(),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _buildProfileHeader(),
                  const SizedBox(height: 16),
                  _buildCupSelectionCard(), // 🌟 การ์ดเลือกแก้ว/ขวดน้ำแบบดรอปดาวน์
                  const SizedBox(height: 16),
                  _buildTargetCard(),
                  const SizedBox(height: 16),
                  _buildPersonalInfo(),
                  const SizedBox(height: 26),
                  GradientButton(
                    onPressed: _saveProfile,
                    expand: true,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_t('save')),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🌟 การ์ดเลือกประเภทแก้ว/ขวดน้ำแบบ Dropdown (ไม่เกะกะ และซ่อนข้อความกรัมที่หักออก)
  Widget _buildCupSelectionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GradientIconChip(
                icon: Icons.local_cafe_rounded,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('cup_section_title'),
                      style: const TextStyle(
                        color: primaryDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _t('cup_section_subtitle'),
                      style: const TextStyle(color: textGrey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            // key ผูกกับ _cupType เพื่อให้ dropdown เปลี่ยนตามเมื่อค่าใน Firebase เปลี่ยน
            key: ValueKey('cup_$_cupType'),
            initialValue: _cupOptions.any((item) => item['key'] == _cupType)
                ? _cupType
                : 'smartcup',
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFE6F4F8),
              prefixIcon: const Icon(
                Icons.local_cafe_outlined,
                color: oceanBlue,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: _cupOptions.map((item) {
              final String key = item['key'] as String;
              final String label = _t('cup_$key');

              return DropdownMenuItem<String>(
                value: key,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: primaryDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newKey) {
              if (newKey != null) {
                setState(() {
                  _cupType = newKey;
                  final selectedOption = _cupOptions.firstWhere(
                    (item) => item['key'] == newKey,
                  );
                  final double presetWeight =
                      selectedOption['weight'] as double;
                  if (newKey != 'custom') {
                    _cupWeight = presetWeight;
                    _cupWeightController.text = '${presetWeight.toInt()}';
                  }
                });
              }
            },
          ),
          if (_cupType == 'custom') ...[
            const SizedBox(height: 16),
            _numberField(
              controller: _cupWeightController,
              label: _t('cup_weight_label'),
              suffix: 'g',
              icon: Icons.scale_outlined,
            ),
          ],
          const SizedBox(height: 16),
          // 🌟 ปุ่มบันทึกภาชนะ (แยกจากปุ่มบันทึกข้อมูลโปรไฟล์)
          Row(
            children: [
              if (_isCupDirty)
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: coral),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _t('cup_unsaved'),
                          style: const TextStyle(
                            color: coral,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: (_isCupDirty && !_savingCup) ? _saveCup : null,
                icon: _savingCup
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_t('save_cup')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: oceanBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: oceanBlue.withValues(alpha: 0.25),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langOption(String code, String flag) {
    final bool selected = _selectedLanguage == code;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _changeLanguage(code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? oceanBlue.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? oceanBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(flag, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }

  Widget _buildLangToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _langOption('th', '🇹🇭'),
          const SizedBox(width: 4),
          _langOption('en', '🇬🇧'),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cyanLight),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return DeepSeaCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Stack(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cyanLight.withValues(alpha: 0.55),
                            blurRadius: 22,
                          ),
                        ],
                        image: _hasProfileImage
                            ? DecorationImage(
                                image: FileImage(File(_imagePath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: !_hasProfileImage
                          ? Icon(
                              _getProfileIconData(_profileIcon),
                              color: oceanBlue,
                              size: 42,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: cyanLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _showEditNameDialog,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.edit, color: cyanLight, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'SmartCup User',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill(
                Icons.cake_outlined,
                '$_age ${_selectedLanguage == 'th' ? 'ปี' : 'yrs'}',
              ),
              _statPill(
                Icons.monitor_weight_outlined,
                '${_weight.toStringAsFixed(0)} kg',
              ),
              _statPill(
                Icons.height_rounded,
                '${_height.toStringAsFixed(0)} cm',
              ),
              // 🌟 ลบการแสดงผลจำนวนกรัมที่หักออกตรงนี้ออกแล้ว ตามคำขอ
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GradientIconChip(
                icon: Icons.water_drop_rounded,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('target'),
                  style: const TextStyle(
                    color: primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatNumber(_dailyTarget), // รูปแบบเดียวกับหน้าโฮม
                style: const TextStyle(
                  color: oceanBlue,
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'ml',
                style: TextStyle(
                  color: textGrey,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              // 🌟 เป้าหมายเป็นจำนวนแก้ว (1 แก้ว = 240 ml)
              Flexible(
                child: Text(
                  formatGlasses(_dailyTarget, lang: _selectedLanguage),
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t('target_hint'),
            style: const TextStyle(color: textGrey, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfo() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: glassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(_t('personal_info')),
          const SizedBox(height: 20),

          Text(
            _t('gender'),
            style: const TextStyle(
              color: textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['ชาย', 'หญิง'].map((genderKey) {
              final isSelected = _gender == genderKey;
              String labelText = genderKey == 'ชาย' ? _t('male') : _t('female');
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: genderKey == 'ชาย' ? 8.0 : 0.0,
                  ),
                  child: ChoiceChip(
                    label: Center(
                      child: Text(
                        labelText,
                        style: TextStyle(
                          color: isSelected ? Colors.white : textGrey,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _gender = genderKey;
                        if (_gender == 'ชาย') {
                          _statusType = 'บุคคลทั่วไป';
                        }
                      });
                    },
                    backgroundColor: const Color(0xFFE6F4F8),
                    selectedColor: oceanBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide.none,
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              );
            }).toList(),
          ),

          if (_gender == 'หญิง') ...[
            const SizedBox(height: 16),
            Text(
              _t('special_status'),
              style: const TextStyle(
                color: textGrey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _statusType,
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFE6F4F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: ['บุคคลทั่วไป', 'หญิงตั้งครรภ์', 'หญิงให้นมบุตร'].map((
                String value,
              ) {
                String translatedValue = value;
                if (value == 'บุคคลทั่วไป') translatedValue = _t('general');
                if (value == 'หญิงตั้งครรภ์') translatedValue = _t('pregnant');
                if (value == 'หญิงให้นมบุตร') {
                  translatedValue = _t('breastfeeding');
                }

                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(
                    translatedValue,
                    style: const TextStyle(
                      color: primaryDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _statusType = newValue;
                    if (_statusType == 'หญิงตั้งครรภ์') {
                      _statusDetail = 'ไตรมาสที่ 2';
                    } else if (_statusType == 'หญิงให้นมบุตร') {
                      _statusDetail = '0-5 เดือน';
                    }
                  });
                }
              },
            ),

            if (_statusType == 'หญิงตั้งครรภ์') ...[
              const SizedBox(height: 12),
              Text(
                _t('pregnancy_term'),
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: ['ไตรมาสที่ 1', 'ไตรมาสที่ 2', 'ไตรมาสที่ 3'].map((
                  trimester,
                ) {
                  final isSelected = _statusDetail == trimester;
                  String labelText = trimester;
                  if (trimester == 'ไตรมาสที่ 1') labelText = _t('trimester_1');
                  if (trimester == 'ไตรมาสที่ 2') labelText = _t('trimester_2');
                  if (trimester == 'ไตรมาสที่ 3') labelText = _t('trimester_3');

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            labelText,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : textGrey,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _statusDetail = trimester;
                          });
                        },
                        backgroundColor: const Color(0xFFE6F4F8),
                        selectedColor: oceanBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide.none,
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            if (_statusType == 'หญิงให้นมบุตร') ...[
              const SizedBox(height: 12),
              Text(
                _t('child_age'),
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: ['0-5 เดือน', '6-11 เดือน'].map((period) {
                  final isSelected = _statusDetail == period;
                  String labelText = period;
                  if (period == '0-5 เดือน') labelText = _t('month_0_5');
                  if (period == '6-11 เดือน') labelText = _t('month_6_11');

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            labelText,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? Colors.white : textGrey,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _statusDetail = period;
                          });
                        },
                        backgroundColor: const Color(0xFFE6F4F8),
                        selectedColor: oceanBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide.none,
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],

          const SizedBox(height: 16),
          _numberField(
            controller: _ageController,
            label: _t('age'),
            suffix: _selectedLanguage == 'th' ? 'ปี' : 'yrs',
            icon: Icons.cake_outlined,
          ),
          const SizedBox(height: 16),
          _numberField(
            controller: _weightController,
            label: _t('weight'),
            suffix: 'kg',
            icon: Icons.monitor_weight_outlined,
          ),
          const SizedBox(height: 16),
          _numberField(
            controller: _heightController,
            label: _t('height'),
            suffix: 'cm',
            icon: Icons.height_outlined,
          ),
          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4F8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: oceanBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _t('info_notice'),
                    style: const TextStyle(
                      color: primaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontWeight: FontWeight.bold, color: primaryDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: textGrey,
          fontWeight: FontWeight.normal,
        ),
        suffixText: suffix,
        suffixStyle: const TextStyle(
          color: textGrey,
          fontWeight: FontWeight.bold,
        ),
        prefixIcon: Icon(icon, color: oceanBlue),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: surfaceLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: surfaceLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: oceanBlue, width: 1.5),
        ),
      ),
    );
  }
}
