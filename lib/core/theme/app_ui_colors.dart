import 'package:flutter/material.dart';

/// 选中记录、用户输入和警告各有固定语义，避免借用 Material 容器色。
@immutable
class AppUiColors extends ThemeExtension<AppUiColors> {
  const AppUiColors({
    required this.selection,
    required this.userInput,
    required this.warning,
  });

  final Color selection;
  final Color userInput;
  final Color warning;

  @override
  AppUiColors copyWith({Color? selection, Color? userInput, Color? warning}) =>
      AppUiColors(
        selection: selection ?? this.selection,
        userInput: userInput ?? this.userInput,
        warning: warning ?? this.warning,
      );

  @override
  AppUiColors lerp(covariant AppUiColors? other, double t) => other == null
      ? this
      : AppUiColors(
          selection: Color.lerp(selection, other.selection, t)!,
          userInput: Color.lerp(userInput, other.userInput, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

extension AppUiTheme on ThemeData {
  AppUiColors get uiColors =>
      extension<AppUiColors>() ??
      AppUiColors(
        selection: colorScheme.surfaceContainerHigh,
        userInput: colorScheme.surfaceContainerLow,
        warning: colorScheme.error,
      );
}
