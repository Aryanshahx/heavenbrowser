import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  // Signature Celestial Cyber-Deck Palette (matches Heaven Falcon-Shield logo)
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color electricViolet = Color(0xFF7C3AED);
  static const Color shieldEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color fireCrimson = Color(0xFFEF4444);
  static const Color incognitoOrchid = Color(0xFFC084FC);

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[neonCyan, electricViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incognitoGradient = LinearGradient(
    colors: <Color>[Color(0xFFC084FC), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: Brightness.light,
      primary: const Color(0xFF2563EB),
      secondary: electricViolet,
      surface: const Color(0xFFF3F6FC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F6FC),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF3F6FC),
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
      seedColor: neonCyan,
      brightness: Brightness.dark,
      primary: neonCyan,
      secondary: electricViolet,
      surface: const Color(0xFF060913),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF060913),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF060913),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFF0D1426),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0D1426),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static ThemeData get incognitoTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: incognitoOrchid,
      brightness: Brightness.dark,
      primary: incognitoOrchid,
      secondary: const Color(0xFFE879F9),
      surface: const Color(0xFF0B0514),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0514),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF0B0514),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFF170B29),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF170B29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
