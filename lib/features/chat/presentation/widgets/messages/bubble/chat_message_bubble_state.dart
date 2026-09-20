import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../navigation/message_version_info.dart';

/// 缓存只比较显示值，避免每次 build 生成的回调使历史 Markdown 失效。
class ChatMessageBubbleState extends Equatable {
  const ChatMessageBubbleState({
    this.canEdit = false,
    this.canRetry = false,
    this.isExcludedFromRequest = false,
    this.isFavorited = false,
    this.inlineErrorMessage,
    this.autoRetryCount = 0,
    this.isEmptyReply = false,
    this.versionInfo,
  });

  final bool canEdit;
  final bool canRetry;
  final bool isExcludedFromRequest;
  final bool isFavorited;
  final String? inlineErrorMessage;
  final int autoRetryCount;
  final bool isEmptyReply;
  final MessageVersionInfo? versionInfo;

  @override
  List<Object?> get props => [
    canEdit,
    canRetry,
    isExcludedFromRequest,
    isFavorited,
    inlineErrorMessage,
    autoRetryCount,
    isEmptyReply,
    versionInfo,
  ];
}

/// 动作留在 presentation；由消息面板绑定当前页面的操作。
class ChatMessageBubbleActions {
  const ChatMessageBubbleActions({
    this.onEditPressed,
    this.onRetryPressed,
    this.onDeletePressed,
    this.onToggleRequestExclusionPressed,
    this.onFavoritePressed,
    this.onSwitchVersion,
  });

  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onToggleRequestExclusionPressed;
  final VoidCallback? onFavoritePressed;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;
}
