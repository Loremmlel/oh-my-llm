// flutter_smooth_markdown 0.10 仍使用旧版 SDK Material 的 InkWell 与选区控件。
// ignore: deprecated_member_use
import 'package:flutter/material.dart'
    as legacy
    show Material, MaterialLocalizations, MaterialType;
import 'package:flutter/services.dart';
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

/// 使用 `material_ui` 构建 Markdown 选择菜单，避免挂到顶层 Overlay 时依赖旧版
/// SDK 的 `MaterialLocalizations`，并保留过滤非文本占位行的复制行为。
Widget readingMarkdownContextMenuBuilder(
  BuildContext context,
  SmoothSelectionRegionState selectableRegionState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: selectableRegionState.contextMenuAnchors,
    buttonItems: selectableRegionState.contextMenuButtonItems
        .map((item) {
          if (item.type == ContextMenuButtonType.copy) {
            final originalOnPressed = item.onPressed;
            return ContextMenuButtonItem(
              label: item.label,
              type: ContextMenuButtonType.copy,
              onPressed: () {
                originalOnPressed?.call();
                _scheduleMarkdownClipboardFilter();
              },
            );
          }
          return item;
        })
        .toList(growable: false),
  );
}

void _scheduleMarkdownClipboardFilter() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    final filtered = text
        .split('\n')
        .where((line) => !RegExp(r'^\u00A0+$').hasMatch(line))
        .join('\n');
    if (filtered != text) {
      await Clipboard.setData(ClipboardData(text: filtered));
    }
  });
}

/// 为 Markdown 折叠块提供旧版墨水层；脱离应用根桥接时按需补齐旧版主题与本地化。
/// 上游改用 material_ui 后删掉此包装；Markdown 折叠块与长按选择用例覆盖这条路径。
class ReadingMarkdownMaterial extends StatelessWidget {
  const ReadingMarkdownMaterial({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final material = legacy.Material(
      type: legacy.MaterialType.transparency,
      child: child,
    );
    final hasLegacyLocalizations =
        Localizations.of<legacy.MaterialLocalizations>(
          context,
          legacy.MaterialLocalizations,
        ) !=
        null;
    if (hasLegacyLocalizations) {
      return material;
    }
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(child: material);
  }
}
