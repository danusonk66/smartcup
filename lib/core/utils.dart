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