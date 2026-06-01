import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_sidebar_controller.dart';

/// 聊天页二级功能面板（Activity Bar）。
///
/// 48px 宽的功能图标列，每个图标对应一个 [ChatSidebarFunction] 入口。
/// 点击图标切换激活功能，已激活的图标再次点击则折叠三级面板。
/// 未来新增功能只需在 [ChatSidebarFunction] 枚举中添加成员即可自动渲染。
class ChatActivityBar extends ConsumerWidget {
  const ChatActivityBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatSidebarProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            const SizedBox(height: 12),
            for (final function in ChatSidebarFunction.values)
              _ActivityBarIcon(
                function: function,
                isSelected: state.activeFunction == function,
                onTap: () {
                  ref
                      .read(chatSidebarProvider.notifier)
                      .toggleFunction(function);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityBarIcon extends StatelessWidget {
  const _ActivityBarIcon({
    required this.function,
    required this.isSelected,
    required this.onTap,
  });

  final ChatSidebarFunction function;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        onPressed: onTap,
        tooltip: function.label,
        icon: Icon(function.icon),
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        iconSize: 22,
        style: IconButton.styleFrom(
          backgroundColor: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
