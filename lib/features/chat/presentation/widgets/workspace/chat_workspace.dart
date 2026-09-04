import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

import '../composer/chat_composer_card.dart';
import '../messages/chat_messages_panel.dart';
import 'chat_workspace_bindings.dart';
import '../../../application/workspace/chat_workspace_view_state.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({
    required this.composerState,
    required this.bindings,
    super.key,
  });

  final ChatWorkspaceComposerState composerState;
  final ChatWorkspaceBindings bindings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _ChatWorkspaceMessages(bindings: bindings)),
        SizedBox(height: AppBreakpoints.isCompactShell(context) ? 8 : 12),
        ChatComposerCard(state: composerState, bindings: bindings.composer),
      ],
    );
  }
}

/// 流式消息的独立重建边界；父级工作区和 composer 不监听消息正文。
class _ChatWorkspaceMessages extends ConsumerWidget {
  const _ChatWorkspaceMessages({required this.bindings});

  final ChatWorkspaceBindings bindings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatWorkspaceMessagesStateProvider);
    return ChatMessagesPanel(
      conversation: state.conversation,
      structureConversation: state.structureConversation,
      messages: state.messages,
      userMessages: state.userMessages,
      hasModels: state.hasModels,
      activeAnchorMessageIdListenable:
          bindings.scroll.activeAnchorMessageIdListenable,
      messageItemScrollController: bindings.scroll.messageItemScrollController,
      messageItemPositionsListener:
          bindings.scroll.messageItemPositionsListener,
      isBusy: state.isBusy,
      errorMessage: state.errorMessage,
      errorMessageAssistantId: state.errorMessageAssistantId,
      emptyReplyAssistantId: state.emptyReplyAssistantId,
      errorModelDisplayName: state.errorModelDisplayName,
      showScrollToBottomListenable:
          bindings.scroll.showScrollToBottomListenable,
      autoRetryCount: state.autoRetryCount,
      onEditMessage: bindings.messages.onEditMessage,
      onRetryLatestAssistant: bindings.messages.onRetryLatestAssistant,
      onDeleteMessage: bindings.messages.onDeleteMessage,
      onToggleRequestExclusion: bindings.messages.onToggleRequestExclusion,
      onScrollToBottomPressed: bindings.scroll.onScrollToBottomPressed,
      onSelectMessage: bindings.scroll.onSelectMessage,
      onSelectMessageVersion: bindings.messages.onSelectMessageVersion,
      onFavoritePressed: bindings.messages.onFavoritePressed,
      favoritedAssistantContents: state.favoritedAssistantContents,
    );
  }
}
