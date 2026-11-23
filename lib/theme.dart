import 'package:flutter/material.dart';

class VK {
  static const bg = Color(0xFF0A0E1C);
  static const panel = Color(0xFF12182A);
  static const panel2 = Color(0xFF1A2238);
  static const border = Color(0xFF2A3550);
  static const accent = Color(0xFF5090FF);
  static const accent2 = Color(0xFF7AB0FF);
  static const text = Color(0xFFE8EEFF);
  static const muted = Color(0xFF8A96B0);
  static const userBubble = Color(0xFF1E3A6E);
  static const botBubble = Color(0xFF151C2E);
  static const danger = Color(0xFFFF6A7A);
  static const ok = Color(0xFF4AFF9A);
}

ThemeData vektorTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VK.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: VK.accent, brightness: Brightness.dark),
    appBarTheme: const AppBarTheme(
      backgroundColor: VK.panel,
      foregroundColor: VK.text,
      elevation: 0,
    ),
    useMaterial3: true,
  );
}
