import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../domain/models/chat_message.dart';
import 'message_version_info.dart';
import 'message_version_navigator.dart';
import 'reasoning_panel.dart';

/// 单条聊天消息气泡，负责正文、推理内容和消息操作。
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    this.canEdit = false,
    this.canRetry = false,
    this.onEditPressed,
    this.onRetryPressed,
    this.versionInfo,
    this.onSwitchVersion,
    super.key,
  });

  final ChatMessage message;
  final bool canEdit;
  final bool canRetry;
  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;
  final MessageVersionInfo? versionInfo;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;

  /// 将消息正文复制到剪贴板。
  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制消息内容')));
  }

  @override
  /// 构建按角色区分样式的消息气泡。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatMessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isUser ? '你' : '模型',
                      style: theme.textTheme.labelLarge,
                    ),
                    if (message.isStreaming) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        _copyMessage(context);
                      },
                      tooltip: '复制消息',
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    if (canEdit)
                      IconButton(
                        onPressed: onEditPressed,
                        tooltip: '编辑消息',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (canRetry)
                      IconButton(
                        onPressed: onRetryPressed,
                        tooltip: '重试回复',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
                if (!isUser && message.reasoningContent.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ReasoningPanel(content: message.reasoningContent),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 8),
                _buildMessageContent(theme, isUser: isUser),
                if (versionInfo != null) ...[
                  const SizedBox(height: 8),
                  MessageVersionNavigator(
                    currentIndex: versionInfo!.currentIndex,
                    total: versionInfo!.siblings.length,
                    onPrevious: versionInfo!.currentIndex > 0
                        ? () {
                            onSwitchVersion?.call(
                              versionInfo!
                                  .siblings[versionInfo!.currentIndex - 1]
                                  .id,
                            );
                          }
                        : null,
                    onNext:
                        versionInfo!.currentIndex <
                            versionInfo!.siblings.length - 1
                        ? () {
                            onSwitchVersion?.call(
                              versionInfo!
                                  .siblings[versionInfo!.currentIndex + 1]
                                  .id,
                            );
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 根据消息角色选择更合适的正文渲染方式。
  Widget _buildMessageContent(ThemeData theme, {required bool isUser}) {
    if (isUser) {
      // 用户消息只需要按原文展示，不需要为 Markdown 解析支付额外成本。
      return SelectableText(message.content, style: theme.textTheme.bodyLarge);
    }

    return MarkdownBody(
      data: message.content.isEmpty && message.isStreaming
          ? '_正在等待模型返回内容..._'
          : message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge,
        blockquote: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
