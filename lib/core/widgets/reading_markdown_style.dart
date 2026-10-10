import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

/// 阅读区域单独使用宋体，避免表单和输入框继承长文排版。
MarkdownStyleSheet readingMarkdownStyle(ThemeData theme) {
  final reading = theme.textTheme.apply(
    fontFamily: 'Noto Serif SC',
    fontFamilyFallback: const ['Noto Sans SC'],
  );
  final base = MarkdownStyleSheet.fromTheme(theme.copyWith(textTheme: reading));
  return base.copyWith(
    textStyle: reading.bodyMedium?.copyWith(height: 1.85),
    paragraphStyle: reading.bodyMedium?.copyWith(height: 1.85),
    h1Style: reading.headlineSmall,
    h2Style: reading.titleLarge,
    h3Style: reading.titleMedium,
  );
}
