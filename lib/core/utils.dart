import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

bool isFirebaseReady() {
  try {
    return Firebase.apps.isNotEmpty;
  } catch (_) {
    return false;
  }
}

DatabaseReference smartCupRef([String path = '']) {
  final ref = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://testurlesp32-default-rtdb.asia-southeast1.firebasedatabase.app/',
  ).ref('SmartCup');

  if (path.isEmpty) {
    return ref;
  }
  return ref.child(path);
}

double calculateDailyTarget(double weightKg) {
  return (weightKg * 2.2 * 30) / 2;
}

String formatTOD(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay parseTOD(dynamic raw) {
  if (raw == null) {
    return const TimeOfDay(hour: 22, minute: 0);
  }
  final text = raw.toString();
  final parts = text.split(':');
  if (parts.length >= 2) {
    final hour = int.tryParse(parts[0]) ?? 22;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }
  return const TimeOfDay(hour: 22, minute: 0);
}

String formatNumber(num value) {
  return value.toStringAsFixed(0);
}

/// ปริมาตรน้ำ 1 แก้ว (ml)
const double mlPerGlass = 240;

/// แปลง ml เป็นจำนวนแก้ว (1 แก้ว = 240 ml) ทศนิยม 1 ตำแหน่ง ตัด .0 ทิ้ง
/// เช่น 2688 → "(11.2 แก้ว)", 480 → "(2 แก้ว)" / อังกฤษ: "(11.2 glasses)"
String formatGlasses(num ml, {String lang = 'th'}) {
  final double glasses = ml <= 0 ? 0 : ml / mlPerGlass;
  String text = glasses.toStringAsFixed(1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  if (lang == 'en') {
    return '($text ${text == '1' ? 'glass' : 'glasses'})';
  }
  return '($text แก้ว)';
}
