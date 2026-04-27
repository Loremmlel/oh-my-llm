import 'package:flutter/material.dart';

import '../../domain/models/chat_message.dart';
import 'chat_message_bubble.dart';
import 'message_version_info.dart';

/// 为稳定消息缓存气泡子树，避免流式期间重复重建历史 Markdown。
class CachedChatMessageBubble extends StatefulWidget {
  const CachedChatMessageBubble({
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedChild = _buildChild();
  }

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
        oldWidget.canEdit == widget.canEdit &&
        oldWidget.canRetry == widget.canRetry &&
        _sameVersionInfo(oldWidget.versionInfo, widget.versionInfo);
  }

  bool _sameVersionInfo(
    MessageVersionInfo? previous,
    MessageVersionInfo? next,
  ) {
    if (identical(previous, next)) {
      return true;
    }
    if (previous == null || next == null) {
      return previous == next;
    }

    if (previous.parentId != next.parentId ||
        previous.currentIndex != next.currentIndex ||
        previous.siblings.length != next.siblings.length) {
      return false;
    }

    for (var index = 0; index < previous.siblings.length; index += 1) {
      if (previous.siblings[index] != next.siblings[index]) {
        return false;
      }
    }
    return true;
  }

  Widget _buildChild() {
    return ChatMessageBubble(
      message: widget.message,
      canEdit: widget.canEdit,
      canRetry: widget.canRetry,
      onEditPressed: widget.onEditPressed,
      onRetryPressed: widget.onRetryPressed,
      versionInfo: widget.versionInfo,
      onSwitchVersion: widget.onSwitchVersion,
    );
  }

  @override
  Widget build(BuildContext context) => _cachedChild;
}
