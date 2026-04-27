import 'package:flutter/material.dart';

import '../../domain/models/chat_message.dart';

/// 右侧消息锚点条，用于快速跳转到用户消息。
class MessageAnchorRail extends StatelessWidget {
  const MessageAnchorRail({
    required this.userMessages,
    required this.activeMessageId,
    required this.maxHeight,
    required this.onSelectMessage,
    super.key,
  });

  final List<ChatMessage> userMessages;
  final String? activeMessageId;
  final double maxHeight;
  final ValueChanged<String> onSelectMessage;

  @override
  /// 构建按用户消息排列的锚点按钮列表。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        minWidth: 28,
        maxWidth: 28,
      ),
      child: DecoratedBox(
        key: const ValueKey('message-anchor-rail'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Scrollbar(
            thumbVisibility: userMessages.length > 10,
            interactive: true,
            radius: const Radius.circular(999),
            thickness: 2.5,
            child: ListView.separated(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: userMessages.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 8);
              },
              itemBuilder: (context, index) {
                final message = userMessages[index];
                final isActive = message.id == activeMessageId;

                return Semantics(
                  button: true,
                  selected: isActive,
                  label: '定位到第 ${index + 1} 条用户消息',
                  child: InkWell(
                    key: ValueKey('message-anchor-item-${index + 1}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelectMessage(message.id),
                    child: SizedBox(
                      width: 20,
                      height: 18,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 167),
                          width: isActive ? 14 : 10,
                          height: isActive ? 6 : 4,
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
