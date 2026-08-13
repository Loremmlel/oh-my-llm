import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import '../composer/chat_composer_card.dart';
import '../messages/chat_messages_panel.dart';
import 'chat_workspace_bindings.dart';
import '../../../application/workspace/chat_workspace_view_state.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({required this.state, required this.bindings, super.key});

  final ChatWorkspaceViewState state;
  final ChatWorkspaceBindings bindings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ChatMessagesPanel(
            conversation: state.messages.conversation,
            messages: state.messages.messages,
            userMessages: state.messages.userMessages,
            hasModels: state.messages.hasModels,
            activeAnchorMessageIdListenable:
                bindings.scroll.activeAnchorMessageIdListenable,
            messageItemScrollController:
                bindings.scroll.messageItemScrollController,
            messageItemPositionsListener:
                bindings.scroll.messageItemPositionsListener,
            isBusy: state.messages.isBusy,
            errorMessage: state.messages.errorMessage,
            errorMessageAssistantId: state.messages.errorMessageAssistantId,
            emptyReplyAssistantId: state.messages.emptyReplyAssistantId,
            errorModelDisplayName: state.messages.errorModelDisplayName,
            showScrollToBottomListenable:
                bindings.scroll.showScrollToBottomListenable,
            autoRetryCount: state.messages.autoRetryCount,
            onEditMessage: bindings.messages.onEditMessage,
            onRetryLatestAssistant: bindings.messages.onRetryLatestAssistant,
            onDeleteMessage: bindings.messages.onDeleteMessage,
            onToggleRequestExclusion:
                bindings.messages.onToggleRequestExclusion,
            onScrollToBottomPressed: bindings.scroll.onScrollToBottomPressed,
            onSelectMessage: bindings.scroll.onSelectMessage,
            onSelectMessageVersion: bindings.messages.onSelectMessageVersion,
            onFavoritePressed: bindings.messages.onFavoritePressed,
            favoritedAssistantContents:
                state.messages.favoritedAssistantContents,
          ),
        ),
        SizedBox(height: AppBreakpoints.isCompactShell(context) ? 8 : 12),
        ChatComposerCard(state: state.composer, bindings: bindings.composer),
      ],
    );
  }
}
