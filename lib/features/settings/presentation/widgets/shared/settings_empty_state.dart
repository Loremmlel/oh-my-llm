import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/widgets/app_empty_state.dart';

/// 设置页中的空状态提示组件。
///
/// 默认给定 [minHeight]（200px）让 [AppEmptyState] 在卡片内有足够空间
/// 垂直居中，避免"图标 + 文案"贴在标题下方显得局促。调用方需要更高
/// 或更矮的占位时可显式传值。
class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.minHeight = 200,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: minHeight,
      child: AppEmptyState(icon: icon, title: title, description: description),
    );
  }
}
