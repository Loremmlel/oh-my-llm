import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class AppTheme {
  const AppTheme._();

  /// M3 默认 textTheme，light 和 dark 共用同一套字号层级
  /// （颜色由 ColorScheme 驱动而非 textStyle.color）。
  static final _defaultM3TextTheme =
      ThemeData(brightness: Brightness.light, useMaterial3: true).textTheme;

  static ThemeData lightTheme({double bodyFontSize = 14}) =>
      _buildTheme(Brightness.light, bodyFontSize: bodyFontSize);

  static ThemeData darkTheme({double bodyFontSize = 14}) =>
      _buildTheme(Brightness.dark, bodyFontSize: bodyFontSize);

  static ThemeData _buildTheme(Brightness brightness, {double bodyFontSize = 14}) {
    final baseColor = brightness == Brightness.light
        ? const Color(0xFF4F46E5)
        : const Color(0xFF818CF8);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: baseColor,
      brightness: brightness,
    );

    // 基于缓存的 M3 默认 textTheme，按用户设置覆盖正文三级字号。

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: _defaultM3TextTheme.copyWith(
        bodyMedium: _defaultM3TextTheme.bodyMedium?.copyWith(
          fontSize: bodyFontSize,
        ),
        bodyLarge: _defaultM3TextTheme.bodyLarge?.copyWith(
          fontSize: bodyFontSize + 2,
        ),
        bodySmall: _defaultM3TextTheme.bodySmall?.copyWith(
          fontSize: bodyFontSize - 2,
        ),
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7FB)
          : const Color(0xFF0F1117),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF171A22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF171A22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
    );
  }
}
