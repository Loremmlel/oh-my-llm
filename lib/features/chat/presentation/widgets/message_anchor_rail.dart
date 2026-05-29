import 'package:flutter/material.dart';

import '../../domain/models/chat_message.dart';

/// 右侧消息锚点条，用于快速跳转到用户消息。
///
/// 紧凑模式下显示指示点列表，展开模式下可显示消息预览气泡（由 Task 6/7 触发）。
class MessageAnchorRail extends StatefulWidget {
  const MessageAnchorRail({
    required this.userMessages,
    required this.activeMessageId,
    required this.maxHeight,
    required this.onSelectMessage,
    this.onScroll,
    super.key,
  });

  final List<ChatMessage> userMessages;
  final String? activeMessageId;
  final double maxHeight;
  final ValueChanged<String> onSelectMessage;
  final VoidCallback? onScroll;

  @override
  State<MessageAnchorRail> createState() => _MessageAnchorRailState();

  // ── 预览文本提取 ────────────────────────────────────────────

  /// 提取消息锚点预览文本。
  ///
  /// 1. 移除 Markdown 语法标记（**、__、#、>）
  /// 2. 在第一个常见标点符号/空格/换行处截断
  /// 3. 最多保留 15 个字符
  static String extractPreviewText(String rawContent) {
    // 步骤 1: 移除 Markdown 语法标记
    final cleaned = rawContent
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('#', '')
        .replaceAll('>', '')
        .trim();

    if (cleaned.isEmpty) return '';

    // 步骤 2 & 3: 在第一个标点符号处截断，最多 15 字符
    const punctuation = '.。！？，,﹖﹔；：!?,;: +\n';
    const limit = 15;
    for (int i = 0; i < cleaned.length && i < limit; i++) {
      if (punctuation.contains(cleaned[i])) {
        if (i == 0) return '';
        return cleaned.substring(0, i);
      }
    }

    // 无标点时取前 15 字符
    return cleaned.substring(0, limit.clamp(0, cleaned.length));
  }
}

class _MessageAnchorRailState extends State<MessageAnchorRail> {
  // ── 状态 ────────────────────────────────────────────────────

  bool _isExpanded = false;
  String? _expandedMessageId;

  // ── 展开/折叠 ──────────────────────────────────────────────

  /// 切换指定消息的展开状态。
  ///
  /// 再次点击同一条已展开消息时折叠，否则切换到新消息展开。
  void _toggleExpand(String messageId) {
    // ≤3 条消息时不展开，保持紧凑模式
    if (widget.userMessages.length <= 3) return;
    setState(() {
      if (_expandedMessageId == messageId && _isExpanded) {
        _isExpanded = false;
        _expandedMessageId = null;
      } else {
        _expandedMessageId = messageId;
        _isExpanded = true;
      }
    });
  }

  /// 折叠当前展开的消息。
  void _collapseExpand() {
    if (!_isExpanded) return;
    setState(() {
      _isExpanded = false;
      _expandedMessageId = null;
    });
  }

  // ── 生命周期 ────────────────────────────────────────────────

  @override
  void didUpdateWidget(covariant MessageAnchorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级重建（如 ChatScreen setState 触发）意味着用户可能正在滚动，
    // 此时应折叠展开状态以保持紧凑模式体验
    _collapseExpand();
  }

  // ── 预览气泡 ────────────────────────────────────────────────

  /// 构建毛玻璃预览气泡。
  ///
  /// 在指示器左侧显示消息预览文本，通过 [AnimatedOpacity] 实现展开/折叠动画。
  Widget _buildPreviewBubble(
    BuildContext context,
    String content,
    String messageId,
  ) {
    final theme = Theme.of(context);
    final previewText = MessageAnchorRail.extractPreviewText(content);
    if (previewText.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 24,
      child: AnimatedOpacity(
        key: ValueKey('preview-bubble-$messageId'),
        opacity: _isExpanded ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 167),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: Text(
            previewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
    );
  }

  // ── 构建 ────────────────────────────────────────────────────

  @override
  /// 构建紧凑模式的锚点指示器列表。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight,
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
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: ListView.separated(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: widget.userMessages.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 8);
              },
              itemBuilder: (context, index) {
                final message = widget.userMessages[index];
                final isActive = message.id == widget.activeMessageId;

                return GestureDetector(
                  onLongPress: () => _toggleExpand(message.id),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildPreviewBubble(
                        context,
                        message.content,
                        message.id,
                      ),
                      MouseRegion(
                        onEnter: (_) => _toggleExpand(message.id),
                        onExit: (_) => _collapseExpand(),
                        child: Semantics(
                          button: true,
                          selected: isActive,
                          label: '定位到第 ${index + 1} 条用户消息',
                          child: InkWell(
                            key: ValueKey('message-anchor-item-${index + 1}'),
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => widget.onSelectMessage(message.id),
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
                        ),
                      ),
                    ],
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
