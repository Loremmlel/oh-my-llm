import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/theme/app_ui_colors.dart';

import '../../../domain/models/preferences/settings_tab.dart';
import 'draggable_settings_tab_bar.dart';

/// 宽屏分类常驻左侧（支持拖拽排序），窄屏标签横向滚动可拖拽；各分类保留自己的滚动与状态。
class SettingsWorkspace extends StatelessWidget {
  const SettingsWorkspace({
    required this.controller,
    required this.tabs,
    required this.onReorder,
    required this.children,
    required this.providerAction,
    this.onPromptCategorySelected,
    this.onPromptOverview,
    this.selectedPromptCategory,
    super.key,
  });

  final TabController controller;
  final List<SettingsTab> tabs;
  final void Function(int oldIndex, int newIndex) onReorder;
  final List<Widget> children;
  final Widget providerAction;
  final ValueChanged<int>? onPromptCategorySelected;
  final VoidCallback? onPromptOverview;
  final int? selectedPromptCategory;

  static const _promptLabels = ['记忆总结提示词', '模板提示词', '固定顺序提示词'];

  void _select(int index, SettingsTab tab) {
    if (controller.index == index) {
      if (tab == SettingsTab.prompts) {
        onPromptOverview?.call();
      }
      return;
    }
    controller.animateTo(index);
    if (tab == SettingsTab.prompts) {
      onPromptOverview?.call();
    }
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

        final isProvidersActive =
            controller.index >= 0 &&
            controller.index < tabs.length &&
            tabs[controller.index] == SettingsTab.providers;

        final isPromptsActive =
            controller.index >= 0 &&
            controller.index < tabs.length &&
            tabs[controller.index] == SettingsTab.prompts;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 176,
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  itemCount: tabs.length,
                  onReorderStart: (_) {
                    HapticFeedback.selectionClick();
                  },
                  onReorderItem: onReorder,
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        final elevation = Tween<double>(
                          begin: 0,
                          end: 4,
                        ).animate(animation).value;
                        return Material(
                          elevation: elevation,
                          shadowColor: Colors.black38,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: child,
                        );
                      },
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final isSelected = controller.index == index;
                    final isPrompts = tab == SettingsTab.prompts;

                    return KeyedSubtree(
                      key: ValueKey(tab.key),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdaptiveReorderableDragListener(
                            index: index,
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                selected: isSelected,
                                title: Text(
                                  tab.label,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                onTap: () => _select(index, tab),
                              ),
                            ),
                          ),
                          if (isPrompts && isSelected)
                            for (
                              var category = 0;
                              category < _promptLabels.length;
                              category++
                            )
                              Material(
                                color: selectedPromptCategory == category
                                    ? Theme.of(context).uiColors.selection
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  dense: true,
                                  selected: selectedPromptCategory == category,
                                  contentPadding: const EdgeInsets.only(
                                    left: AppSpacing.lg,
                                    right: AppSpacing.xs,
                                  ),
                                  title: Text(
                                    _promptLabels[category],
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          fontWeight:
                                              selectedPromptCategory == category
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                  ),
                                  onTap: () =>
                                      onPromptCategorySelected?.call(category),
                                ),
                              ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    if (isProvidersActive)
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
            DraggableSettingsTabBar(
              controller: controller,
              tabs: tabs,
              onReorder: onReorder,
              onPromptCategorySelected: onPromptCategorySelected,
              onPromptOverview: onPromptOverview,
            ),
            if (isPromptsActive)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: PopupMenuButton<int>(
                    tooltip: '提示词分类',
                    initialValue: selectedPromptCategory ?? -1,
                    onSelected: onPromptCategorySelected,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: -1, child: Text('全部提示词')),
                      for (var index = 0; index < _promptLabels.length; index++)
                        PopupMenuItem(
                          value: index,
                          child: Text(_promptLabels[index]),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selectedPromptCategory == null
                                ? '全部提示词'
                                : _promptLabels[selectedPromptCategory!],
                          ),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (isProvidersActive)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: providerAction,
                ),
              ),
            Expanded(child: content),
          ],
        );
      },
    ),
  );
}
