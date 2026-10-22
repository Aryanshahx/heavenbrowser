import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  // Electric Sapphire & Celestial Sky Blue Palette (matched to Blue App Icon)
  static const Color sapphireBlue = Color(0xFF2563EB);
  static const Color electricBlue = Color(0xFF3B82F6);
  static const Color skyHighlight = Color(0xFF93C5FD);
  static const Color deepNavyBg = Color(0xFF040B16);
  static const Color navySurface = Color(0xFF0B162C);
  static const Color navyElevated = Color(0xFF11203D);

  static const Color shieldEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color fireCrimson = Color(0xFFEF4444);
  static const Color incognitoCyan = Color(0xFF2DD4BF);

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[Color(0xFF60A5FA), Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incognitoGradient = LinearGradient(
    colors: <Color>[Color(0xFF2DD4BF), Color(0xFF0F766E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: sapphireBlue,
      brightness: Brightness.light,
      primary: sapphireBlue,
      secondary: electricBlue,
      surface: const Color(0xFFF3F7FD),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F7FD),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF3F7FD),
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
      seedColor: electricBlue,
      brightness: Brightness.dark,
      primary: const Color(0xFF60A5FA),
      secondary: sapphireBlue,
      surface: deepNavyBg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: deepNavyBg,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: deepNavyBg,
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: navySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: navySurface,
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
      surface: const Color(0xFF061015),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF061015),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF061015),
        foregroundColor: scheme.onSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFF0D1B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0D1B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
