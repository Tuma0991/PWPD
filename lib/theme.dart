// lib/theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // ─── Brand ───────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1565C0);       // Deep Blue
  static const Color primaryDark = Color(0xFF0D47A1);   // Pressed / gradients
  static const Color primaryLight = Color(0xFF1E88E5);  // Medium Blue
  static const Color accent = Color(0xFF0288D1);        // Sky Blue

  // ─── Status (one meaning per color) ──────────────────────────────────────
  static const Color danger = Color(0xFFD32F2F);        // SOS / fall ONLY
  static const Color success = Color(0xFF2E7D32);       // Normal / online
  static const Color warning = Color(0xFFF57C00);       // Caution
  static const Color offline = Color(0xFFE65100);       // Offline / stale data
  static const Color offlineBg = Color(0xFFFFF3E0);     // Offline card tint
  static const Color geofence = Color(0xFF7C4DFF);      // Zone alerts

  // ─── Surfaces & text ─────────────────────────────────────────────────────
  static const Color background = Color(0xFFF0F4FF);    // Matches the screens
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A2340);
  static const Color textSecondary = Color(0xFF5C6B7A); // ~5.5:1 on white
  static const Color textMuted = Color(0xFF6B7A99);     // Hints / last seen (readable)
  static const Color inactive = Color(0xFF9EA8C2);      // Disabled dots/icons only — NOT for text
  static const Color cardShadow = Color(0x1A1565C0);

  // ─── Gradients ───────────────────────────────────────────────────────────
  static const List<Color> offlineGradient = [
    Color(0xFFE65100),
    Color(0xFFEF6C00),
    Color(0xFFF57C00), // deep enough for white text
  ];

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: accent,
          surface: surface,
          error: danger,
        ),
        scaffoldBackgroundColor: background,
        fontFamily: 'Nunito',
        // Matches what every screen already does: blue bar, white title, left-aligned.
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: surface,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          prefixIconColor: primary,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      );
}