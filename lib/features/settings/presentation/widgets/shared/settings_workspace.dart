import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 设置分类与当前分类动作共用一条顶部导航，内容各自拥有滚动。
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inline =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
          AppBreakpoints.formMasterDetail;
      return Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppContentWidths.wide,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            controller: controller,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            onTap: (index) {
                              if (index == 2) onPromptOverview?.call();
                            },
                            tabs: [
                              const Tab(text: '服务商'),
                              const Tab(text: '预设'),
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('提示词'),
                                    PopupMenuButton<int>(
                                      tooltip: '提示词分类',
                                      icon: const Icon(
                                        Icons.expand_more,
                                        size: 18,
                                      ),
                                      onSelected: (index) {
                                        controller.animateTo(2);
                                        onPromptCategorySelected?.call(index);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 0,
                                          child: Text('记忆总结提示词'),
                                        ),
                                        PopupMenuItem(
                                          value: 1,
                                          child: Text('模板提示词'),
                                        ),
                                        PopupMenuItem(
                                          value: 2,
                                          child: Text('固定顺序提示词'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Tab(text: '网络'),
                              const Tab(text: '输出处理'),
                              const Tab(text: '其它'),
                            ],
                          ),
                        ),
                        if (inline && controller.index == 0) providerAction,
                      ],
                    ),
                    if (!inline && controller.index == 0)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: providerAction,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(controller: controller, children: children),
          ),
        ],
      );
    },
  );
}
