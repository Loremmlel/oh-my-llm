import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_message.dart';

/// 消息面板的 UI 回调分组。
class ChatWorkspaceMessageBindings {
  const ChatWorkspaceMessageBindings({
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onToggleRequestExclusion,
    required this.onSelectMessageVersion,
    this.onFavoritePressed,
  });

  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<ChatMessage> onToggleRequestExclusion;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final ValueChanged<ChatMessage>? onFavoritePressed;
}

/// composer 的 UI 资源与回调分组。
class ChatWorkspaceComposerBindings {
  const ChatWorkspaceComposerBindings({
    required this.messageController,
    required this.messageFocusNode,
    required this.templateVariableControllers,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    this.onReasoningEnabledChanged,
    this.onReasoningEffortChanged,
    this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    this.onSendPressed,
    this.onStopStreaming,
    this.onCancelEdit,
  });

  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final Map<String, TextEditingController> templateVariableControllers;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;
  final VoidCallback? onCancelEdit;
}

/// 滚动/锚点的 UI 资源与回调分组。
class ChatWorkspaceScrollBindings {
  const ChatWorkspaceScrollBindings({
    required this.activeAnchorMessageIdListenable,
    required this.showScrollToBottomListenable,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
  });

  final ValueListenable<String?> activeAnchorMessageIdListenable;
  final ValueListenable<bool> showScrollToBottomListenable;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
}

/// workspace 的 UI bindings 根；只在 presentation 组合，不持久化、不进 state。
class ChatWorkspaceBindings {
  const ChatWorkspaceBindings({
    required this.messages,
    required this.composer,
    required this.scroll,
  });

  final ChatWorkspaceMessageBindings messages;
  final ChatWorkspaceComposerBindings composer;
  final ChatWorkspaceScrollBindings scroll;
}
