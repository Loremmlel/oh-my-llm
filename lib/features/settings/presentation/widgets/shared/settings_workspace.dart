import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 宽屏分类常驻左侧，窄屏标签横向滚动；各分类保留自己的滚动与状态。
class SettingsWorkspace extends StatelessWidget {
  const SettingsWorkspace({
    required this.controller,
    required this.children,
    required this.providerAction,
    this.onPromptCategorySelected,
    this.onPromptOverview,
    super.key,
  });

  final TabController controller;
  final List<Widget> children;
  final Widget providerAction;
  final ValueChanged<int>? onPromptCategorySelected;
  final VoidCallback? onPromptOverview;

  static const _labels = ['服务商', '预设', '提示词', '网络', '输出处理', '其它', '世界书'];
  static const _promptLabels = ['记忆总结提示词', '模板提示词', '固定顺序提示词'];

  void _select(int index) {
    controller.animateTo(index);
    if (index == 2) onPromptOverview?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            AppBreakpoints.formMasterDetail;
        final content = TabBarView(controller: controller, children: children);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 176,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  children: [
                    for (var index = 0; index < _labels.length; index++) ...[
                      ListTile(
                        dense: true,
                        selected: controller.index == index,
                        title: Text(
                          _labels[index],
                          style: TextStyle(
                            fontWeight: controller.index == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        onTap: () => _select(index),
                      ),
                      if (index == 2 && controller.index == 2)
                        for (
                          var category = 0;
                          category < _promptLabels.length;
                          category++
                        )
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(
                              left: AppSpacing.lg,
                              right: AppSpacing.xs,
                            ),
                            title: Text(
                              _promptLabels[category],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: () =>
                                onPromptCategorySelected?.call(category),
                          ),
                    ],
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    if (controller.index == 0)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: providerAction,
                        ),
                      ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: _select,
              tabs: [for (final label in _labels) Tab(text: label)],
            ),
            if (controller.index == 2)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: PopupMenuButton<int>(
                    tooltip: '提示词分类',
                    onSelected: onPromptCategorySelected,
                    itemBuilder: (_) => [
                      for (var index = 0; index < _promptLabels.length; index++)
                        PopupMenuItem(
                          value: index,
                          child: Text(_promptLabels[index]),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('提示词分类'),
                          Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (controller.index == 0)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: providerAction,
              ),
            Expanded(child: content),
          ],
        );
      },
    ),
  );
}
