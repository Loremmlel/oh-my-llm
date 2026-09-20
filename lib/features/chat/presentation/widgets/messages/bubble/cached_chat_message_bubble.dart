import 'package:flutter/material.dart';

import '../../../../domain/models/chat_message.dart';
import 'chat_message_bubble.dart';
import 'chat_message_bubble_state.dart';

/// 为稳定消息缓存气泡子树，避免流式期间重复重建历史 Markdown。
class CachedChatMessageBubble extends StatefulWidget {
  const CachedChatMessageBubble({
    required this.message,
    required this.state,
    required this.actions,
    super.key,
  });

  final ChatMessage message;
  final ChatMessageBubbleState state;
  final ChatMessageBubbleActions actions;

  @override
  State<CachedChatMessageBubble> createState() =>
      _CachedChatMessageBubbleState();
}

class _CachedChatMessageBubbleState extends State<CachedChatMessageBubble> {
  late Widget _cachedChild;

  @override
  void initState() {
    super.initState();
    _cachedChild = _buildChild();
  }

  // 不在 didChangeDependencies 里无条件重建缓存子树。
  // 缓存的 widget 实例仍挂在树中，Theme/MediaQuery 等 InheritedWidget
  // 变化时子树自身会收到通知并重建，无需此处主动失效缓存；
  // 否则每次父级 rebuild（如流式消息刷新）都会绕过 _canReuseChild 让缓存形同虚设。

  @override
  void didUpdateWidget(covariant CachedChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_canReuseChild(oldWidget)) {
      return;
    }

    _cachedChild = _buildChild();
  }

  bool _canReuseChild(CachedChatMessageBubble oldWidget) {
    return oldWidget.message == widget.message &&
        oldWidget.state == widget.state;
  }

  Widget _buildChild() {
    return ChatMessageBubble(
      message: widget.message,
      state: widget.state,
      actions: widget.actions,
    );
  }

  @override
  Widget build(BuildContext context) => _cachedChild;
}
