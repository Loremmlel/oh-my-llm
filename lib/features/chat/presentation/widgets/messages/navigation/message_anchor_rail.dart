import 'dart:async';

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_animations.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../../domain/models/chat_message.dart';

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
  /// 3. 最多保留 18 个字符，纯标点消息保留原样
  static String extractPreviewText(String rawContent) {
    // 步骤 1: 移除 Markdown 语法标记
    final cleaned = rawContent
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('#', '')
        .replaceAll('>', '')
        .trim();

    if (cleaned.isEmpty) return '';

    // 按字素截断，避免拆开 emoji；开头标点不再生成空预览。
    const punctuation = '.。！？，,﹖﹔；：!?,;:+\n';
    final characters = cleaned.characters.take(18).toList();
    for (var i = 1; i < characters.length; i++) {
      if (punctuation.contains(characters[i])) return characters.take(i).join();
    }
    return characters.join();
  }
}

class _MessageAnchorRailState extends State<MessageAnchorRail> {
  // ── 状态 ────────────────────────────────────────────────────

  bool _isExpanded = false;
  bool _touchExpanded = false;
  Timer? _collapseTimer;
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
    _collapseTimer?.cancel();
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
    _collapseTimer?.cancel();
    _touchExpanded = false;
    if (!_isExpanded) return;
    setState(() {
      _isExpanded = false;
    });
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    if (_touchExpanded) {
      _collapseTimer = Timer(const Duration(seconds: 2), _collapseExpand);
    }
  }

  @override
  void didUpdateWidget(covariant MessageAnchorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userMessages.length <= 3) {
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
        onLongPress: () {
          _touchExpanded = true;
          _toggleExpand();
        },
        onLongPressEnd: (_) => _scheduleCollapse(),
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
              child: TapRegion(
                onTapOutside: (_) => _collapseExpand(),
                child: Listener(
                  onPointerDown: (_) => _collapseTimer?.cancel(),
                  onPointerUp: (_) => _scheduleCollapse(),
                  onPointerCancel: (_) => _scheduleCollapse(),
                  child: SizedBox(
                    width: _isExpanded ? 264 : 28,
                    child: DecoratedBox(
                      key: const ValueKey('message-anchor-rail'), // test-key
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        color: _isExpanded ? theme.colorScheme.surface : null,
                        border: _isExpanded
                            ? Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.4),
                              )
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
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
                              final isActive =
                                  message.id == widget.activeMessageId;
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
                                  key: ValueKey(
                                    'message-anchor-item-${index + 1}',
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.tag,
                                  ),
                                  focusColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  onTap: () {
                                    widget.onSelectMessage(message.id);
                                    if (_touchExpanded) _collapseExpand();
                                  },
                                  child: SizedBox(
                                    height: 18,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (_isExpanded &&
                                            previewText.isNotEmpty)
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      theme.textTheme.bodySmall,
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
                                                borderRadius:
                                                    BorderRadius.circular(14),
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
        ),
      ),
    );
  }
}
