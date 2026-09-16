import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

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

  static ThemeData _buildTheme(
    Brightness brightness, {
    double bodyFontSize = 14,
  }) {
    final baseColor = brightness == Brightness.light
        ? const Color(0xFF4F46E5)
        : const Color(0xFF818CF8);
    final isLight = brightness == Brightness.light;
    final surface = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1B1D22);
    final canvas = isLight ? const Color(0xFFF5F6F8) : const Color(0xFF121418);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: baseColor,
          brightness: brightness,
        ).copyWith(
          surface: surface,
          surfaceContainerLowest: surface,
          surfaceContainerLow: canvas,
          surfaceContainer: isLight
              ? const Color(0xFFF0F1F4)
              : const Color(0xFF22252B),
          surfaceContainerHigh: isLight
              ? const Color(0xFFE9EBEF)
              : const Color(0xFF2A2D34),
          surfaceContainerHighest: isLight
              ? const Color(0xFFE1E4EA)
              : const Color(0xFF333740),
          outlineVariant: isLight
              ? const Color(0xFFD8DCE4)
              : const Color(0xFF424752),
        );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.sm),
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
      scaffoldBackgroundColor: canvas,
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
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: controlShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: controlShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: controlShape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
    );
  }
}
