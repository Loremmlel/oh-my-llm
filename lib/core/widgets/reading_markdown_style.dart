// flutter_smooth_markdown 0.10 的折叠块仍使用 SDK Material 的 InkWell。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy show Material, MaterialType;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

/// 阅读区域单独使用宋体，避免表单和输入框继承长文排版。
MarkdownStyleSheet readingMarkdownStyle(ThemeData theme, {double? fontSize}) {
  final reading = theme.textTheme.apply(
    fontFamily: 'Noto Serif SC',
    fontFamilyFallback: const ['Noto Sans SC'],
  );
  final base = MarkdownStyleSheet.fromBrightness(
    theme.brightness,
    baseStyle: reading.bodyMedium,
  );
  final readingSize =
      fontSize ?? (theme.textTheme.bodyMedium?.fontSize ?? 14) + 2;
  return base.copyWith(
    textStyle: reading.bodyMedium?.copyWith(
      height: 1.85,
      fontSize: readingSize,
    ),
    paragraphStyle: reading.bodyMedium?.copyWith(
      height: 1.85,
      fontSize: readingSize,
    ),
    h1Style: reading.headlineSmall,
    h2Style: reading.titleLarge,
    h3Style: reading.titleMedium,
  );
}

/// 为 Markdown 选择菜单和折叠块提供旧版主题、本地化和墨水层。
/// 上游改用 material_ui 后删掉此包装；Markdown 折叠块用例覆盖这条路径。
class ReadingMarkdownMaterial extends StatelessWidget {
  const ReadingMarkdownMaterial({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(
      child: legacy.Material(
        type: legacy.MaterialType.transparency,
        child: child,
      ),
    );
  }
}
