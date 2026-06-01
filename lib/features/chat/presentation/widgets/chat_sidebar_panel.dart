import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_sidebar_controller.dart';

/// 聊天页三级侧边面板。
///
/// 从 [ChatActivityBar] 右侧展开，显示当前激活功能对应的详细内容。
/// 支持：
/// - 动画展开/折叠（250ms easeInOutCubic）
/// - 右侧边缘拖拽调整宽度（180–400px）
/// - 根据 [ChatSidebarFunction] 切换内容视图
class ChatSidebarPanel extends ConsumerWidget {
  const ChatSidebarPanel({super.key, required this.content});

  /// 面板内容区 widget，由调用方根据当前激活功能传入。
  final Widget content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatSidebarProvider);
    final theme = Theme.of(context);

    final width = state.isExpanded ? state.panelWidth : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: width,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        border: state.isExpanded
            ? Border(
                right: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              )
            : null,
      ),
      child: Column(
        children: [
          if (state.isExpanded && state.activeFunction != null) ...[
            // ── 标题栏 ──────────────────────
            _SidebarHeader(
              title: state.activeFunction!.label,
              onCollapse: () {
                ref.read(chatSidebarProvider.notifier).collapse();
              },
            ),
            const SizedBox(height: 8),
          ],
          // ── 内容区 ──────────────────────
          if (state.isExpanded) Expanded(child: content),
        ],
      ),
    );
  }
}

/// 面板标题栏：功能名称 + 折叠按钮。
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.title, required this.onCollapse});

  final String title;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onCollapse,
            tooltip: '折叠面板',
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
