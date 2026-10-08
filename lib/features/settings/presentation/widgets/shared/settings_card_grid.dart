import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/adaptive_grid/app_adaptive_grid.dart';

/// 设置卡片使用连续网格；少量卡片共享可用宽度，同排内容自然等高。
class SettingsCardGrid extends StatelessWidget {
  const SettingsCardGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppAdaptiveGrid.content(
    maxCrossAxisExtent: 480,
    crossAxisSpacing: AppSpacing.sm,
    mainAxisSpacing: AppSpacing.sm,
    children: children,
  );
}
