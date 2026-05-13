import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../../application/chat_sessions_controller.dart';
import '../../../domain/chat_word_counter.dart';
import '../../../domain/models/chat_message.dart';

/// 管理当前分支哪些消息会继续参与发送上下文。
class MessageRequestFilterDialog extends ConsumerStatefulWidget {
  const MessageRequestFilterDialog({super.key});

  @override
  ConsumerState<MessageRequestFilterDialog> createState() =>
      _MessageRequestFilterDialogState();
}

class _MessageRequestFilterDialogState
    extends ConsumerState<MessageRequestFilterDialog> {
  String? _focusedMessageId;
  late final ScrollController _masterScrollController;
  late final ScrollController _compactScrollController;
  late final ScrollController _detailPreviewScrollController;
  String? _lastPreviewMessageId;

  @override
  void initState() {
    super.initState();
    _masterScrollController = ScrollController();
    _compactScrollController = ScrollController();
    _detailPreviewScrollController = ScrollController();
    // 打开时滚动到列表底部，让用户看到最新消息。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(_masterScrollController);
      _scrollToBottom(_compactScrollController);
    });
  }

  @override
  void dispose() {
    _masterScrollController.dispose();
    _compactScrollController.dispose();
    _detailPreviewScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(controller.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    final isBusy = ref.watch(isChatBusyProvider);
    final visibleMessages = conversation.messages;
    final excludedMessageIds = conversation.excludedMessageIds.toSet();
    final stats = _MessageFilterStats.compute(
      messages: visibleMessages,
      excludedMessageIds: excludedMessageIds,
    );
    final focusedMessageId = _resolveFocusedMessageId(
      messages: visibleMessages,
      excludedMessageIds: excludedMessageIds,
    );
    final focusedMessage = visibleMessages.where((message) {
      return message.id == focusedMessageId;
    }).firstOrNull;
    _syncDetailPreviewScroll(focusedMessage?.id);

    return AlertDialog(
      title: const Text('上下文过滤'),
      content: SizedBox(
        width: 920,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '关闭某条消息后，它会保留在当前对话中，但不会继续发给模型。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              visibleMessages.isEmpty
                  ? '当前分支还没有消息。'
                  : '当前分支已排除 ${stats.excludedCount} / ${visibleMessages.length} 条消息。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (visibleMessages.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '发送字数：${stats.includedChars} / ${stats.totalChars} 字',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 420,
              child: AdaptiveMasterDetailLayout(
                breakpoint: 760,
                masterWidth: 320,
                minHeight: 420,
                compactChild: _buildCompactList(
                  context,
                  messages: visibleMessages,
                  excludedMessageIds: excludedMessageIds,
                  excludedCount: stats.excludedCount,
                  isBusy: isBusy,
                  scrollController: _compactScrollController,
                ),
                master: _buildMasterPane(
                  context,
                  messages: visibleMessages,
                  excludedMessageIds: excludedMessageIds,
                  isBusy: isBusy,
                  excludedCount: stats.excludedCount,
                  focusedMessageId: focusedMessageId,
                  scrollController: _masterScrollController,
                ),
                detail: _buildDetailPane(
                  context,
                  message: focusedMessage,
                  excluded: focusedMessage != null
                      ? excludedMessageIds.contains(focusedMessage.id)
                      : false,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  void _syncDetailPreviewScroll(String? messageId) {
    if (_lastPreviewMessageId == messageId) {
      return;
    }
    _lastPreviewMessageId = messageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_detailPreviewScrollController.hasClients) {
        return;
      }
      _detailPreviewScrollController.jumpTo(0);
    });
  }

  String? _resolveFocusedMessageId({
    required List<ChatMessage> messages,
    required Set<String> excludedMessageIds,
  }) {
    if (_focusedMessageId != null &&
        messages.any((message) => message.id == _focusedMessageId)) {
      return _focusedMessageId;
    }

    final firstExcluded = messages.where((message) {
      return excludedMessageIds.contains(message.id);
    }).firstOrNull;
    return firstExcluded?.id ?? messages.lastOrNull?.id;
  }

  Widget _buildCompactList(
    BuildContext context, {
    required List<ChatMessage> messages,
    required Set<String> excludedMessageIds,
    required int excludedCount,
    required bool isBusy,
    required ScrollController scrollController,
  }) {
    if (messages.isEmpty) {
      return const Center(child: Text('当前分支还没有消息。'));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: messages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: isBusy || excludedCount == 0
                    ? null
                    : () => _setMessagesExcluded(
                        messageIds: messages.map((message) => message.id),
                        excluded: false,
                      ),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('恢复当前分支'),
              ),
            );
          }

          final message = messages[index - 1];
          return SwitchListTile.adaptive(
            value: !excludedMessageIds.contains(message.id),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(_messageTitle(message)),
            subtitle: Text(
              _messageSummary(message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: isBusy
                ? null
                : (included) {
                    _setMessagesExcluded(
                      messageIds: [message.id],
                      excluded: !included,
                    );
                  },
          );
        },
      ),
    );
  }

  Widget _buildMasterPane(
    BuildContext context, {
    required List<ChatMessage> messages,
    required Set<String> excludedMessageIds,
    required bool isBusy,
    required int excludedCount,
    required String? focusedMessageId,
    required ScrollController scrollController,
  }) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.24,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前分支', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            excludedCount == 0
                                ? '当前没有排除消息。'
                                : '当前已排除 $excludedCount 条消息。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: isBusy || excludedCount == 0
                          ? null
                          : () => _setMessagesExcluded(
                              messageIds: messages.map((message) => message.id),
                              excluded: false,
                            ),
                      child: const Text('恢复当前分支'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (messages.isEmpty)
              const Expanded(child: Center(child: Text('当前分支还没有消息。')))
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isExcluded = excludedMessageIds.contains(message.id);
                    final isFocused = message.id == focusedMessageId;
                    return _MessageFilterSelectionTile(
                      message: message,
                      focused: isFocused,
                      excluded: isExcluded,
                      onFocus: () {
                        setState(() {
                          _focusedMessageId = message.id;
                        });
                      },
                      onChanged: isBusy
                          ? null
                          : (included) {
                              _setMessagesExcluded(
                                messageIds: [message.id],
                                excluded: !included,
                              );
                            },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane(
    BuildContext context, {
    required ChatMessage? message,
    required bool excluded,
  }) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: message == null
          ? Center(
              child: Text(
                '选择一条消息后，这里会显示完整预览。',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _messageTitle(message),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (excluded)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withValues(
                              alpha: 0.72,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Text(
                              '不发送',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: SizedBox.expand(
                          key: const ValueKey(
                            'message-filter-preview-container',
                          ),
                          child: Scrollbar(
                            key: const ValueKey(
                              'message-filter-preview-scrollbar',
                            ),
                            controller: _detailPreviewScrollController,
                            interactive: true,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _detailPreviewScrollController,
                              primary: false,
                              key: ValueKey(
                                'message-filter-preview-${message.id}',
                              ),
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                message.content.isEmpty
                                    ? '空内容。'
                                    : message.content,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _setMessagesExcluded({
    required Iterable<String> messageIds,
    required bool excluded,
  }) {
    return ref
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: messageIds, excluded: excluded);
  }
}

class _MessageFilterStats {
  const _MessageFilterStats({
    required this.excludedCount,
    required this.totalChars,
    required this.includedChars,
  });

  final int excludedCount;
  final int totalChars;
  final int includedChars;

  /// 统一在单次遍历中完成弹窗头部统计，避免重复扫描列表。
  static _MessageFilterStats compute({
    required List<ChatMessage> messages,
    required Set<String> excludedMessageIds,
  }) {
    var excludedCount = 0;
    var totalChars = 0;
    var includedChars = 0;

    for (final message in messages) {
      final length = countChatWords(message.content);
      totalChars += length;
      if (excludedMessageIds.contains(message.id)) {
        excludedCount += 1;
        continue;
      }
      includedChars += length;
    }

    return _MessageFilterStats(
      excludedCount: excludedCount,
      totalChars: totalChars,
      includedChars: includedChars,
    );
  }
}

class _MessageFilterSelectionTile extends StatelessWidget {
  const _MessageFilterSelectionTile({
    required this.message,
    required this.focused,
    required this.excluded,
    required this.onFocus,
    this.onChanged,
  });

  final ChatMessage message;
  final bool focused;
  final bool excluded;
  final VoidCallback onFocus;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: focused
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.52)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onFocus,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _messageTitle(message),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _messageSummary(message),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: !excluded, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

String _messageTitle(ChatMessage message) {
  return switch (message.role) {
    ChatMessageRole.user => '用户消息',
    ChatMessageRole.assistant => '模型回复',
    ChatMessageRole.system => '系统消息',
  };
}

String _messageSummary(ChatMessage message, {int maxChars = 120}) {
  final preview = message.content.trim();
  if (preview.isEmpty) {
    return '空内容。';
  }
  if (preview.length <= maxChars) {
    return preview;
  }
  return '${preview.substring(0, maxChars)}…';
}
