import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VscodeTheme {
  // VSCode Dark+ colors
  static const bg = Color(0xFF1E1E1E);
  static const bgSidebar = Color(0xFF252526);
  static const bgPanel = Color(0xFF1E1E1E);
  static const bgTab = Color(0xFF2D2D2D);
  static const bgTabActive = Color(0xFF1E1E1E);
  static const bgInput = Color(0xFF3C3C3C);
  static const bgHover = Color(0xFF2A2D2E);
  static const bgSelection = Color(0xFF264F78);
  static const accent = Color(0xFF007ACC);
  static const accentHover = Color(0xFF1177BB);
  static const border = Color(0xFF3C3C3C);
  static const borderActive = Color(0xFF007ACC);
  static const fg = Color(0xFFD4D4D4);
  static const fgMuted = Color(0xFF858585);
  static const fgLabel = Color(0xFFBBBBBB);
  static const fgKeyword = Color(0xFF569CD6);
  static const fgString = Color(0xFFCE9178);
  static const fgFunction = Color(0xFFDCDCAA);
  static const fgType = Color(0xFF4EC9B0);
  static const fgVariable = Color(0xFF9CDCFE);
  static const red = Color(0xFFF48771);
  static const green = Color(0xFF4EC9B0);
  static const yellow = Color(0xFFDCDCAA);
  static const statusBg = Color(0xFF007ACC);
  static const statusFg = Colors.white;
  static const activityBg = Color(0xFF333333);

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: bgSidebar,
        onSurface: fg,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          bodyMedium: TextStyle(color: fg, fontSize: 13),
          bodySmall: TextStyle(color: fgMuted, fontSize: 12),
          labelMedium: TextStyle(color: fgLabel, fontSize: 11, letterSpacing: 1),
        ),
      ),
      iconTheme: const IconThemeData(color: fgMuted, size: 20),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        hintStyle: const TextStyle(color: fgMuted, fontSize: 13),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFF424242)),
        thickness: WidgetStateProperty.all(6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSidebar,
        elevation: 0,
        titleTextStyle: TextStyle(color: fg, fontSize: 13),
        iconTheme: IconThemeData(color: fgMuted),
      ),
    );
  }
}

/// Extended theme data for light mode and Linux desktop customization.
/// Keeps the legacy [VscodeTheme] static consts intact while offering
/// dynamic ThemeData builders for different modes.
class AppTheme {
  static const _lightBg = Color(0xFFFFFFFF);
  static const _lightSidebar = Color(0xFFF3F3F3);
  static const _lightFg = Color(0xFF333333);
  static const _lightFgMuted = Color(0xFF6E6E6E);
  static const _lightBorder = Color(0xFFE5E5E5);

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      colorScheme: const ColorScheme.light(
        primary: VscodeTheme.accent,
        secondary: VscodeTheme.accent,
        surface: _lightSidebar,
        onSurface: _lightFg,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          bodyMedium: TextStyle(color: _lightFg, fontSize: 13),
          bodySmall: TextStyle(color: _lightFgMuted, fontSize: 12),
          labelMedium: TextStyle(
              color: Color(0xFF616161), fontSize: 11, letterSpacing: 1),
        ),
      ),
      iconTheme: const IconThemeData(color: _lightFgMuted, size: 20),
      dividerColor: _lightBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: VscodeTheme.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        hintStyle: const TextStyle(color: _lightFgMuted, fontSize: 13),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFBDBDBD)),
        thickness: WidgetStateProperty.all(6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightSidebar,
        elevation: 0,
        titleTextStyle: TextStyle(color: _lightFg, fontSize: 13),
        iconTheme: IconThemeData(color: _lightFgMuted),
      ),
    );
  }
}
