import 'package:flutter/material.dart';

/// Design tokens. Swap these for the Figma values; nothing else hard-codes a color.
abstract final class Palette {
  static const green = Color(0xFF0B7A4B);
  static const greenSoft = Color(0xFFE3F2EA);
  static const sand = Color(0xFFF7F3EA);
  static const sandDeep = Color(0xFFEDE5D3);
  static const ink = Color(0xFF1C2421);
  static const muted = Color(0xFF5E6B66);
  static const line = Color(0xFFDCD5C5);
  static const gold = Color(0xFFC98A12);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFBE9E7);
  static const warning = Color(0xFF8A5A00);
  static const warningSoft = Color(0xFFFFF3D6);
  // WhatsApp brand green. White text on it is under 2:1, so the label uses dark ink (7.5:1).
  static const whatsapp = Color(0xFF25D366);
  static const whatsappInk = Color(0xFF06281A);
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const radius = 14.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.green, primary: Palette.green, surface: Colors.white, error: Palette.danger);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.sand,
    appBarTheme: const AppBarTheme(backgroundColor: Palette.sand, foregroundColor: Palette.ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.radius), side: const BorderSide(color: Palette.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.radius))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.radius))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Space.radius)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Space.radius), borderSide: const BorderSide(color: Palette.line)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: Palette.greenSoft),
  );
}
