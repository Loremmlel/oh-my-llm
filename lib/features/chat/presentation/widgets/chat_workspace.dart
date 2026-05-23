import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../../../settings/domain/models/llm_model_config.dart';
import '../../../settings/domain/models/llm_provider_config.dart';
import '../../../settings/domain/models/prompt_template.dart';
import '../../../settings/domain/models/template_prompt.dart';
import 'chat_composer_card.dart';
import 'chat_messages_panel.dart';
import 'composer_data.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({
    required this.conversation,
    required this.messages,
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.promptTemplates,
    required this.selectedPromptTemplate,
    required this.userMessages,
    required this.activeAnchorMessageId,
    required this.messageController,
    required this.messageFocusNode,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.errorMessage,
    required this.errorMessageAssistantId,
    required this.errorModelDisplayName,
    required this.showScrollToBottom,
    required this.autoRetryCount,
    required this.excludedMessageCount,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onToggleRequestExclusion,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onPromptTemplateSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
    required this.onStopStreaming,
    this.onFavoritePressed,
    this.favoritedAssistantContents = const {},
    super.key,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<PromptTemplate> promptTemplates;
  final PromptTemplate? selectedPromptTemplate;
  final List<ChatMessage> userMessages;
  final String? activeAnchorMessageId;
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final String? errorMessage;
  final String? errorMessageAssistantId;
  final String errorModelDisplayName;
  final bool showScrollToBottom;
  final int autoRetryCount;
  final int excludedMessageCount;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<ChatMessage> onToggleRequestExclusion;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onPromptTemplateSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  /// 点击收藏按钮时的回调（仅助手消息），为 null 则不显示收藏按钮。
  final ValueChanged<ChatMessage>? onFavoritePressed;

  /// 已收藏的助手消息内容集合，用于显示收藏高亮状态。
  final Set<String> favoritedAssistantContents;

  @override
  /// 构建消息区、错误提示和输入区的整体布局。
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ChatMessagesPanel(
            conversation: conversation,
            messages: messages,
            userMessages: userMessages,
            hasModels: hasModels,
            activeAnchorMessageId: activeAnchorMessageId,
            messageItemScrollController: messageItemScrollController,
            messageItemPositionsListener: messageItemPositionsListener,
            isBusy: isBusy,
            errorMessage: errorMessage,
            errorMessageAssistantId: errorMessageAssistantId,
            errorModelDisplayName: errorModelDisplayName,
            showScrollToBottom: showScrollToBottom,
            autoRetryCount: autoRetryCount,
            onEditMessage: onEditMessage,
            onRetryLatestAssistant: onRetryLatestAssistant,
            onDeleteMessage: onDeleteMessage,
            onToggleRequestExclusion: onToggleRequestExclusion,
            onScrollToBottomPressed: onScrollToBottomPressed,
            onSelectMessage: onSelectMessage,
            onSelectMessageVersion: onSelectMessageVersion,
            onFavoritePressed: onFavoritePressed,
            favoritedAssistantContents: favoritedAssistantContents,
          ),
        ),
        const SizedBox(height: 12),
        ChatComposerCard(
          data: ComposerData(
            hasModels: hasModels,
            modelProviders: modelProviders,
            modelConfigs: modelConfigs,
            selectedProviderId: selectedProviderId,
            selectedModel: selectedModel,
            promptTemplates: promptTemplates,
            selectedPromptTemplate: selectedPromptTemplate,
            templatePrompts: templatePrompts,
            selectedTemplatePrompt: selectedTemplatePrompt,
            templateVariableControllers: templateVariableControllers,
            isComposerCollapsed: isComposerCollapsed,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            supportsReasoning: supportsReasoning,
            autoRetryEnabled: autoRetryEnabled,
            isBusy: isBusy,
            isStreaming: isStreaming,
            excludedMessageCount: excludedMessageCount,
          ),
          callbacks: ComposerCallbacks(
            onProviderSelected: onProviderSelected,
            onModelSelected: onModelSelected,
            onPromptTemplateSelected: onPromptTemplateSelected,
            onTemplatePromptSelected: onTemplatePromptSelected,
            onToggleComposerCollapsed: onToggleComposerCollapsed,
            onReasoningEnabledChanged: onReasoningEnabledChanged,
            onReasoningEffortChanged: onReasoningEffortChanged,
            onAutoRetryEnabledChanged: onAutoRetryEnabledChanged,
            onOpenFixedPromptSequenceRunner: onOpenFixedPromptSequenceRunner,
            onOpenMessageFilter: onOpenMessageFilter,
            onSendPressed: onSendPressed,
            onStopStreaming: onStopStreaming,
          ),
          messageController: messageController,
          messageFocusNode: messageFocusNode,
        ),
      ],
    );
  }
}
