import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_side_drawer.dart';

import '../../../application/sidebar/chat_sidebar_controller.dart';

/// 宽窄屏共用历史与预设入口，切换分段时保留两个面板的滚动状态。
class ChatNavigationDrawer extends ConsumerWidget {
  const ChatNavigationDrawer({
    required this.historyPanel,
    required this.presetPanel,
    super.key,
  });

  final Widget historyPanel;
  final Widget presetPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFunction = ref.watch(chatSidebarProvider);
    return AppSideDrawer(
      title: '对话侧栏',
      width: AppContentWidths.chatDrawer,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: SegmentedButton<ChatSidebarFunction>(
              segments: const [
                ButtonSegment(
                  value: ChatSidebarFunction.history,
                  icon: Icon(Icons.history_rounded),
                  label: Text('历史会话'),
                ),
                ButtonSegment(
                  value: ChatSidebarFunction.preset,
                  icon: Icon(Icons.tune_rounded),
                  label: Text('预设'),
                ),
              ],
              selected: {activeFunction},
              onSelectionChanged: (selected) => ref
                  .read(chatSidebarProvider.notifier)
                  .selectFunction(selected.single),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: activeFunction.index,
              children: [historyPanel, presetPanel],
            ),
          ),
        ],
      ),
    );
  }
}
