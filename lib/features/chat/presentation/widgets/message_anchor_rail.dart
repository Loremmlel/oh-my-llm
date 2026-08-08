import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_animations.dart';
import '../../domain/models/chat_message.dart';

/// 右侧消息锚点条，用于快速跳转到用户消息。
///
/// 紧凑模式下显示指示点列表，展开模式下可显示消息预览气泡。
class MessageAnchorRail extends StatefulWidget {
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
    const punctuation = '.。！？，,﹖﹔；：!?,;:+\n';
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
  final ScrollController _scrollController = ScrollController();

  /// rail 祖先焦点节点：只观察 descendant focus（InkWell 的标准焦点
  /// 生命周期），自身不可请求焦点，避免消息增删时维护错位的 FocusNode 列表。
  final FocusNode _railFocusNode = FocusNode(canRequestFocus: false);

  // ── 生命周期 ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _railFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 将锚点列表滚动到底部（最新消息）。
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  // ── 展开/折叠 ──────────────────────────────────────────────

  /// 展开锚点条。
  void _toggleExpand() {
    // ≤3 条消息时不展开，保持紧凑模式
    if (widget.userMessages.length <= 3) return;
    setState(() {
      _isExpanded = true;
    });
  }

  /// 折叠当前展开的锚点条。
  void _collapseExpand() {
    if (!_isExpanded) return;
    setState(() {
      _isExpanded = false;
    });
  }

  @override
  void didUpdateWidget(covariant MessageAnchorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级重建（如 ChatScreen setState 触发）时，若键盘焦点仍在 rail 内
    // 则保持展开，避免打断正在键盘操作的用户；无焦点时沿用旧行为折叠。
    if (!_railFocusNode.hasFocus) {
      _collapseExpand();
    }
  }

  // ── 构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: _railFocusNode,
      // 键盘焦点进入 rail（任一锚点）时展开；完全离开时折叠。
      // 锚点间移动时 hasFocus 保持 true，不会中途触发折叠。
      onFocusChange: (focused) {
        if (focused) {
          _toggleExpand();
        } else {
          _collapseExpand();
        }
      },
      child: GestureDetector(
        onLongPress: () => _toggleExpand(),
        child: Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            onEnter: (_) => _toggleExpand(),
            onExit: (_) {
              // 鼠标移出但键盘焦点仍在 rail 内时不折叠
              if (!_railFocusNode.hasFocus) _collapseExpand();
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: SizedBox(
                width: _isExpanded ? 228 : 28,
                child: DecoratedBox(
                  key: const ValueKey('message-anchor-rail'), // test-key
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView.separated(
                        controller: _scrollController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: widget.userMessages.length,
                        separatorBuilder: (context, index) {
                          return const SizedBox(height: 8);
                        },
                        itemBuilder: (context, index) {
                          final message = widget.userMessages[index];
                          final isActive = message.id == widget.activeMessageId;
                          final previewText =
                              MessageAnchorRail.extractPreviewText(
                                message.content,
                              );

                          return Semantics(
                            button: true,
                            selected: isActive,
                            value:
                                '${index + 1} / ${widget.userMessages.length}',
                            label: previewText.isEmpty
                                ? '第 ${index + 1} 条用户消息'
                                : '第 ${index + 1} 条用户消息：$previewText',
                            child: InkWell(
                              key: ValueKey('message-anchor-item-${index + 1}'),
                              borderRadius: BorderRadius.circular(999),
                              focusColor: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              onTap: () => widget.onSelectMessage(message.id),
                              child: SizedBox(
                                height: 18,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isExpanded && previewText.isNotEmpty)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          // 预览文本只负责视觉；语义由父节点
                                          // 的 label 提供，避免展开后重复播报。
                                          child: ExcludeSemantics(
                                            child: Text(
                                              previewText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: 20,
                                      height: 18,
                                      child: Center(
                                        child: AnimatedContainer(
                                          duration:
                                              AppAnimations.quickTransition,
                                          width: isActive ? 14 : 10,
                                          height: isActive ? 6 : 4,
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.outline,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
