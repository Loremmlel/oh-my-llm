import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class AppTheme {
  const AppTheme._();

  /// 按 brightness 生成 M3 默认 textTheme，确保 light/dark 各自拿到正确的文字颜色。
  /// 同时注入 fontFamily，使所有 TextStyle 默认携带思源黑体（外层 ThemeData.fontFamily 不会向显式 textTheme 内部回退）。
  static TextTheme _m3TextTheme(Brightness brightness) => ThemeData(
        brightness: brightness,
        useMaterial3: true,
        fontFamily: 'Noto Sans SC',
      ).textTheme;

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

    // 按用户设置覆盖正文三级字号，其他层级沿用 M3 默认值。
    final defaultTextTheme = _m3TextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: 'Noto Sans SC',
      textTheme: defaultTextTheme.copyWith(
        bodyMedium: defaultTextTheme.bodyMedium?.copyWith(
          fontSize: bodyFontSize,
        ),
        bodyLarge: defaultTextTheme.bodyLarge?.copyWith(
          fontSize: bodyFontSize + 2,
        ),
        bodySmall: defaultTextTheme.bodySmall?.copyWith(
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
