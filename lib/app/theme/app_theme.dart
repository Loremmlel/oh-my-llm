import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/theme/app_ui_colors.dart';

final class AppTheme {
  const AppTheme._();

  /// 按 brightness 生成 M3 默认 textTheme，确保 light/dark 各自拿到正确的文字颜色。
  /// 同时注入 fontFamily，使所有 TextStyle 默认携带思源黑体（外层 ThemeData.fontFamily 不会向显式 textTheme 内部回退）。
  static TextTheme _m3TextTheme(Brightness brightness) {
    final text = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
    ).textTheme;
    // 部分默认层级没有 letterSpacing，不能通过 apply 的乘法归零。
    TextStyle? zeroSpacing(TextStyle? style) =>
        style?.copyWith(letterSpacing: 0);
    return text.copyWith(
      displayLarge: zeroSpacing(text.displayLarge),
      displayMedium: zeroSpacing(text.displayMedium),
      displaySmall: zeroSpacing(text.displaySmall),
      headlineLarge: zeroSpacing(text.headlineLarge),
      headlineMedium: zeroSpacing(text.headlineMedium),
      headlineSmall: zeroSpacing(text.headlineSmall),
      titleLarge: zeroSpacing(text.titleLarge),
      titleMedium: zeroSpacing(text.titleMedium),
      titleSmall: zeroSpacing(text.titleSmall),
      bodyLarge: zeroSpacing(text.bodyLarge),
      bodyMedium: zeroSpacing(text.bodyMedium),
      bodySmall: zeroSpacing(text.bodySmall),
      labelLarge: zeroSpacing(text.labelLarge),
      labelMedium: zeroSpacing(text.labelMedium),
      labelSmall: zeroSpacing(text.labelSmall),
    );
  }

  static ThemeData lightTheme({double bodyFontSize = 14}) =>
      _buildTheme(Brightness.light, bodyFontSize: bodyFontSize);

  static ThemeData darkTheme({double bodyFontSize = 14}) =>
      _buildTheme(Brightness.dark, bodyFontSize: bodyFontSize);

  static ThemeData _buildTheme(
    Brightness brightness, {
    double bodyFontSize = 14,
  }) {
    final baseColor = brightness == Brightness.light
        ? const Color(0xFF2F5D46)
        : const Color(0xFFAACBB4);
    final isLight = brightness == Brightness.light;
    final surface = isLight ? const Color(0xFFFEFDF9) : const Color(0xFF242923);
    final canvas = isLight ? const Color(0xFFF8F7F2) : const Color(0xFF191D19);
    final ink = isLight ? const Color(0xFF292923) : const Color(0xFFE8E9DF);
    final muted = isLight ? const Color(0xFF706E64) : const Color(0xFFB4B7AA);
    final selection = isLight
        ? const Color(0xFFEDEBE3)
        : const Color(0xFF343A32);
    final userInput = isLight
        ? const Color(0xFFF0F2E9)
        : const Color(0xFF2C382E);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: baseColor,
          brightness: brightness,
        ).copyWith(
          primary: baseColor,
          onPrimary: isLight ? Colors.white : const Color(0xFF183523),
          primaryContainer: userInput,
          onPrimaryContainer: ink,
          secondary: muted,
          onSecondary: surface,
          secondaryContainer: selection,
          onSecondaryContainer: ink,
          tertiary: muted,
          onTertiary: surface,
          tertiaryContainer: selection,
          onTertiaryContainer: ink,
          onSurface: ink,
          onSurfaceVariant: muted,
          inverseSurface: isLight
              ? const Color(0xFF30312B)
              : const Color(0xFFE8E9DF),
          onInverseSurface: isLight ? surface : canvas,
          inversePrimary: isLight
              ? const Color(0xFFAACBB4)
              : const Color(0xFF2F5D46),
          surfaceTint: Colors.transparent,
          surface: surface,
          surfaceContainerLowest: surface,
          surfaceContainerLow: canvas,
          surfaceContainer: isLight
              ? const Color(0xFFF1EFE7)
              : const Color(0xFF2B322B),
          surfaceContainerHigh: isLight
              ? const Color(0xFFEAE7DD)
              : const Color(0xFF343A32),
          surfaceContainerHighest: isLight
              ? const Color(0xFFE1DDD2)
              : const Color(0xFF40463C),
          outline: isLight ? const Color(0xFF969184) : const Color(0xFF858B7D),
          outlineVariant: isLight
              ? const Color(0xFFDAD6CA)
              : const Color(0xFF4B5548),
        );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.sm),
    );

    // 操作字号跟随用户偏好，阅读区在此基础上采用自己的字号与行距。
    final defaultTextTheme = _m3TextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [
        AppUiColors(
          selection: selection,
          userInput: userInput,
          warning: isLight ? const Color(0xFF94651B) : const Color(0xFFE2BE79),
        ),
      ],
      splashFactory: NoSplash.splashFactory,
      fontFamily: 'Noto Sans SC',
      textTheme: defaultTextTheme.copyWith(
        headlineSmall: defaultTextTheme.headlineSmall?.copyWith(
          fontFamily: 'Noto Serif SC',
          fontFamilyFallback: const ['Noto Sans SC'],
        ),
        titleLarge: defaultTextTheme.titleLarge?.copyWith(
          fontFamily: 'Noto Serif SC',
          fontFamilyFallback: const ['Noto Sans SC'],
          fontWeight: FontWeight.w600,
        ),
        titleMedium: defaultTextTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: defaultTextTheme.titleSmall?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
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
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          foregroundColor: ink,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape, foregroundColor: ink),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          iconSize: 20,
          shape: controlShape,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? baseColor
              : colorScheme.surfaceContainerHighest,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? muted : surface,
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: BorderSide(color: colorScheme.outline, width: 1),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(controlShape),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? muted.withValues(alpha: 0.5)
                : ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? surface
                : colorScheme.surfaceContainer,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => defaultTextTheme.labelLarge?.copyWith(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        labelStyle: defaultTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: defaultTextTheme.labelLarge,
        indicatorColor: baseColor,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: baseColor, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: ink,
        selectedTileColor: selection,
        iconColor: muted,
        shape: controlShape,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        textColor: ink,
        collapsedTextColor: ink,
        iconColor: muted,
        collapsedIconColor: muted,
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        backgroundColor: canvas,
        selectedColor: selection,
        secondarySelectedColor: selection,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: controlShape,
        labelStyle: defaultTextTheme.labelMedium?.copyWith(color: ink),
        secondaryLabelStyle: defaultTextTheme.labelMedium?.copyWith(color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: selection,
        indicatorShape: controlShape,
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: ink, size: 22)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => defaultTextTheme.labelSmall?.copyWith(
            color: ink,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        indicatorColor: selection,
        indicatorShape: controlShape,
        selectedIconTheme: IconThemeData(color: ink, size: 22),
        unselectedIconTheme: IconThemeData(color: muted, size: 22),
        selectedLabelTextStyle: defaultTextTheme.labelSmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: defaultTextTheme.labelSmall?.copyWith(
          color: muted,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: baseColor,
        inactiveTrackColor: colorScheme.outlineVariant,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => muted.withValues(
            alpha:
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.dragged)
                ? 0.7
                : 0.4,
          ),
        ),
        radius: const Radius.circular(AppRadii.sm),
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 6 : 4,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: surface,
        foregroundColor: ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadii.tag),
        ),
        textStyle: defaultTextTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.dialog),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      drawerTheme: DrawerThemeData(
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: Border(left: BorderSide(color: colorScheme.outlineVariant)),
        endShape: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(controlShape),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        titleTextStyle: defaultTextTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: controlShape.copyWith(
          side: BorderSide(color: colorScheme.outlineVariant),
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
