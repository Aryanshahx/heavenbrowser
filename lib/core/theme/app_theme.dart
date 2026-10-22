import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  // Signature Cosmic Violet Palette (matched to Heaven Winged-Planet App Icon)
  static const Color cosmicViolet = Color(0xFFA855F7);
  static const Color luminousLavender = Color(0xFFD8B4FE);
  static const Color royalPurple = Color(0xFF7E22CE);
  static const Color shieldEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color fireCrimson = Color(0xFFEF4444);
  static const Color incognitoCyan = Color(0xFF38BDF8);

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[Color(0xFFC084FC), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incognitoGradient = LinearGradient(
    colors: <Color>[Color(0xFF38BDF8), Color(0xFF334155)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: royalPurple,
      brightness: Brightness.light,
      primary: royalPurple,
      secondary: cosmicViolet,
      surface: const Color(0xFFF6F4FC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F4FC),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF6F4FC),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static ThemeData get darkTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: cosmicViolet,
      brightness: Brightness.dark,
      primary: const Color(0xFFC084FC),
      secondary: royalPurple,
      surface: const Color(0xFF080414),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF080414),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF080414),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFF130B26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF130B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static ThemeData get incognitoTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: incognitoCyan,
      brightness: Brightness.dark,
      primary: incognitoCyan,
      secondary: const Color(0xFF94A3B8),
      surface: const Color(0xFF090D16),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF090D16),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF090D16),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
