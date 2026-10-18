import 'package:flutter/material.dart';

// คงชื่อตัวแปรเดิมไว้ทั้งหมดเพื่อไม่ให้ไฟล์อื่นในโปรเจกต์เกิด Error (ปรับเฉพาะค่าสี)
const Color primaryDark = Color(0xFF0B2F45); // น้ำทะเลลึก
const Color bgLight = Color(0xFFEFF9FB); // ขาวอมฟ้าน้ำใส
const Color accentGreen = Color(0xFF14B58A);
const Color accentOrange = Color(0xFFF59E0B);
const Color textDark = Color(0xFF0E2A38);
const Color textGrey = Color(0xFF4F6877);

const Color oceanBlue = Color(0xFF0B86B8);
const Color cyanLight = Color(0xFF4CCBF0);

// สีเพิ่มใหม่
const Color coral = Color(0xFFFF7A59);
const Color mint = Color(0xFF2DD4A7);
const Color surfaceLine = Color(0xFFDCE8ED);

ThemeData smartCupTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: oceanBlue,
    primary: oceanBlue,
    secondary: cyanLight,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bgLight,
    colorScheme: scheme,
    // ไม่ล็อกฟอนต์ 'Arial' เพราะไม่รองรับภาษาไทย ให้ระบบเลือกฟอนต์ไทยที่เหมาะสมเอง
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: textDark,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: cyanLight.withValues(alpha: 0.28),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected) ? primaryDark : textGrey,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? textDark : textGrey,
        );
      }),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primaryDark,
      unselectedItemColor: textGrey,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: primaryDark,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
