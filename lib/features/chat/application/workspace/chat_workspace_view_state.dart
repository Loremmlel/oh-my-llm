import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/application/preferences/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../favorites/chat_favorites_facade.dart';
import '../sessions/chat_sessions_controller.dart';
import '../composer/composer_collapsed_controller.dart';
import '../composer/composer_draft_controller.dart';

/// 消息面板的不可变显示快照，只含既有 owner 的投影值。
class ChatWorkspaceMessagesState extends Equatable {
  const ChatWorkspaceMessagesState({
    required this.conversation,
    required this.messages,
    required this.userMessages,
    required this.hasModels,
    required this.isBusy,
    required this.errorMessage,
    required this.errorMessageAssistantId,
    required this.emptyReplyAssistantId,
    required this.errorModelDisplayName,
    required this.autoRetryCount,
    required this.favoritedAssistantContents,
  });

  final ChatConversation conversation;

  /// activeConversation 已合并 streaming reply 的可见消息。
  final List<ChatMessage> messages;
  final List<ChatMessage> userMessages;
  final bool hasModels;
  final bool isBusy;
  final String? errorMessage;
  final String? errorMessageAssistantId;
  final String? emptyReplyAssistantId;
  final String errorModelDisplayName;
  final int autoRetryCount;
  final Set<String> favoritedAssistantContents;

  @override
  List<Object?> get props => [
    conversation,
    messages,
    userMessages,
    hasModels,
    isBusy,
    errorMessage,
    errorMessageAssistantId,
    emptyReplyAssistantId,
    errorModelDisplayName,
    autoRetryCount,
    favoritedAssistantContents,
  ];
}

/// composer 的不可变显示快照（read-model 层，不含编辑覆盖）。
class ChatWorkspaceComposerReadModel extends Equatable {
  const ChatWorkspaceComposerReadModel({
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.fixedPromptSequences,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.excludedMessageCount,
  });

  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final List<FixedPromptSequence> fixedPromptSequences;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final int excludedMessageCount;

  @override
  List<Object?> get props => [
    modelProviders,
    modelConfigs,
    selectedProviderId,
    selectedModel,
    templatePrompts,
    selectedTemplatePrompt,
    fixedPromptSequences,
    isComposerCollapsed,
    reasoningEnabled,
    reasoningEffort,
    supportsReasoning,
    autoRetryEnabled,
    isBusy,
    isStreaming,
    isAutoRetryWaiting,
    excludedMessageCount,
  ];
}

/// 交给 composer widget 的 effective composer 状态（可能在编辑时被页面覆盖）。
class ChatWorkspaceComposerState extends ChatWorkspaceComposerReadModel {
  const ChatWorkspaceComposerState({
    required super.modelProviders,
    required super.modelConfigs,
    required super.selectedProviderId,
    required super.selectedModel,
    required super.templatePrompts,
    required super.selectedTemplatePrompt,
    required super.fixedPromptSequences,
    required super.isComposerCollapsed,
    required super.reasoningEnabled,
    required super.reasoningEffort,
    required super.supportsReasoning,
    required super.autoRetryEnabled,
    required super.isBusy,
    required super.isStreaming,
    required super.isAutoRetryWaiting,
    required super.excludedMessageCount,
    required this.isEditingMessage,
  });

  final bool isEditingMessage;

  factory ChatWorkspaceComposerState.fromReadModel(
    ChatWorkspaceComposerReadModel readModel, {
    required TemplatePrompt? selectedTemplatePrompt,
    required bool isEditingMessage,
  }) {
    return ChatWorkspaceComposerState(
      modelProviders: readModel.modelProviders,
      modelConfigs: readModel.modelConfigs,
      selectedProviderId: readModel.selectedProviderId,
      selectedModel: readModel.selectedModel,
      templatePrompts: readModel.templatePrompts,
      // 传入值即最终值：编辑无模板消息时必须显式为 null，不能回退 read-model 的
      // normal selection，否则 UI 展示会话模板的变量输入框而提交时这些值会被丢弃。
      selectedTemplatePrompt: selectedTemplatePrompt,
      fixedPromptSequences: readModel.fixedPromptSequences,
      isComposerCollapsed: readModel.isComposerCollapsed,
      reasoningEnabled: readModel.reasoningEnabled,
      reasoningEffort: readModel.reasoningEffort,
      supportsReasoning: readModel.supportsReasoning,
      autoRetryEnabled: readModel.autoRetryEnabled,
      isBusy: readModel.isBusy,
      isStreaming: readModel.isStreaming,
      isAutoRetryWaiting: readModel.isAutoRetryWaiting,
      excludedMessageCount: readModel.excludedMessageCount,
      isEditingMessage: isEditingMessage,
    );
  }

  @override
  List<Object?> get props => [...super.props, isEditingMessage];
}

/// read-model provider 的产物：只含既有 owner 的快照，不含 UI controller。
class ChatWorkspaceReadModel extends Equatable {
  const ChatWorkspaceReadModel({
    required this.messages,
    required this.composer,
  });

  final ChatWorkspaceMessagesState messages;
  final ChatWorkspaceComposerReadModel composer;

  @override
  List<Object?> get props => [messages, composer];
}

/// 页面最终交给 workspace 的 view-state：read-model + 页面瞬态 overlay。
class ChatWorkspaceViewState extends Equatable {
  const ChatWorkspaceViewState({
    required this.messages,
    required this.composer,
  });

  final ChatWorkspaceMessagesState messages;
  final ChatWorkspaceComposerState composer;

  /// 由 [ChatScreen] 用纯 factory 生成：编辑时用页面本地 [editingDraft] 的
  /// template selection 覆盖 read-model 的 normal selection，并显式传
  /// [isEditingMessage]。read-model 不变，仅有效值变化。
  ///
  /// 编辑无模板消息时 effective 为 null（不回落会话级模板）：UI 与提交解析
  /// 共用同一 seam，避免 UI 展示的变量输入框在提交时被静默丢弃。
  factory ChatWorkspaceViewState.compose({
    required ChatWorkspaceReadModel readModel,
    required ComposerDraft editingDraft,
    required bool isEditingMessage,
    required List<TemplatePrompt> templatePrompts,
  }) {
    final editingTemplateId = editingDraft.selectedTemplatePromptId;
    final effectiveTemplate = isEditingMessage
        ? (editingTemplateId != null
              ? templatePrompts
                    .where((t) => t.id == editingTemplateId)
                    .firstOrNull
              : null)
        : readModel.composer.selectedTemplatePrompt;
    return ChatWorkspaceViewState(
      messages: readModel.messages,
      composer: ChatWorkspaceComposerState.fromReadModel(
        readModel.composer,
        selectedTemplatePrompt: effectiveTemplate,
        isEditingMessage: isEditingMessage,
      ),
    );
  }

  @override
  List<Object?> get props => [messages, composer];
}

// ── 纯 resolver（可单测）───────────────────────────────────────────────────

/// conversation 选中模型 → remembered default → 首模型 的 fallback 顺序。
LlmModelConfig? resolveSelectedModel({
  required List<LlmModelConfig> modelConfigs,
  required String? selectedModelId,
  required String? rememberedModelId,
}) {
  if (modelConfigs.isEmpty) return null;
  final conversationSelected = modelConfigs
      .where((config) => config.id == selectedModelId)
      .firstOrNull;
  if (conversationSelected != null) return conversationSelected;
  final rememberedSelected = modelConfigs
      .where((config) => config.id == rememberedModelId)
      .firstOrNull;
  if (rememberedSelected != null) return rememberedSelected;
  return modelConfigs.first;
}

String? resolveSelectedProviderId({
  required List<LlmProviderConfig> providers,
  required LlmModelConfig? selectedModel,
}) {
  if (providers.isEmpty) return null;
  if (selectedModel != null &&
      providers.any((p) => p.id == selectedModel.providerId)) {
    return selectedModel.providerId;
  }
  return providers.first.id;
}

TemplatePrompt? resolveSelectedTemplatePrompt(
  List<TemplatePrompt> templatePrompts,
  String? selectedTemplatePromptId,
) {
  if (selectedTemplatePromptId == null) return null;
  return templatePrompts
      .where((templatePrompt) => templatePrompt.id == selectedTemplatePromptId)
      .firstOrNull;
}

/// 预设 Prompt 解析：null / sentinel / ID 无效均视为未选。
PresetPrompt? resolveSelectedPresetPrompt(
  List<PresetPrompt> presetPrompts,
  String? selectedPresetPromptId,
) {
  if (selectedPresetPromptId == null ||
      selectedPresetPromptId == noPresetPromptSelectedId) {
    return null;
  }
  return presetPrompts
      .where((prompt) => prompt.id == selectedPresetPromptId)
      .firstOrNull;
}

// ── derived provider ───────────────────────────────────────────────────────

/// workspace 的不可变只读快照；只 watch 输入并调用纯函数。
final chatWorkspaceReadModelProvider = Provider<ChatWorkspaceReadModel>((ref) {
  final conversation = ref.watch(activeChatConversationProvider);
  final isStreaming = ref.watch(isChatStreamingProvider);
  final isAutoRetryWaiting = ref.watch(
    chatSessionsProvider.select((state) => state.isAutoRetryWaiting),
  );
  final isBusy = ref.watch(isChatBusyProvider);
  final autoRetryCount = ref.watch(
    chatSessionsProvider.select((state) => state.autoRetryCount),
  );
  final errorMessage = ref.watch(chatErrorMessageProvider);
  final errorMessageAssistantId = ref.watch(
    chatErrorMessageAssistantIdProvider,
  );
  final emptyReplyAssistantId = ref.watch(
    chatSessionsProvider.select((state) => state.emptyReplyAssistantId),
  );
  final rememberedSelections = ref.watch(chatDefaultsProvider);
  final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
  final modelProviders = ref.watch(llmProviderConfigsProvider);
  final modelConfigs = ref.watch(llmModelConfigsProvider);
  final templatePrompts = ref.watch(templatePromptsProvider);
  final activeConversationId = ref.watch(activeConversationIdProvider);
  final selectedTemplatePromptId = ref.watch(
    composerTemplateSelectionProvider(activeConversationId),
  );
  final isComposerCollapsed = ref.watch(composerCollapsedProvider);
  // watch facade（内部依赖收藏 revision）建立失效依赖，
  // 再按当前会话的 assistant 消息定向查询收藏身份，不加载全量 catalog。
  final facade = ref.watch(chatFavoritesFacadeProvider);
  final favorites = facade.snapshotFor({
    for (final message in conversation.messages)
      if (message.role == ChatMessageRole.assistant) message.content,
  });

  final selectedModel = resolveSelectedModel(
    modelConfigs: modelConfigs,
    selectedModelId: conversation.selectedModelId,
    rememberedModelId: rememberedSelections.defaultModelId,
  );
  final selectableProviders = modelProviders
      .where((provider) => provider.models.isNotEmpty)
      .toList(growable: false);
  final selectedProviderId = resolveSelectedProviderId(
    providers: selectableProviders,
    selectedModel: selectedModel,
  );
  final selectableModels = selectedProviderId == null
      ? const <LlmModelConfig>[]
      : modelConfigs
            .where((config) => config.providerId == selectedProviderId)
            .toList(growable: false);
  final selectedTemplatePrompt = resolveSelectedTemplatePrompt(
    templatePrompts,
    selectedTemplatePromptId,
  );
  final activeMessages = conversation.messages;
  final userMessages = activeMessages
      .where((message) => message.role == ChatMessageRole.user)
      .toList(growable: false);
  final excludedVisibleMessageCount = activeMessages
      .where((message) => conversation.isMessageExcluded(message.id))
      .length;
  final supportsReasoning = selectedModel?.supportsReasoning ?? false;

  return ChatWorkspaceReadModel(
    messages: ChatWorkspaceMessagesState(
      conversation: conversation,
      messages: List.unmodifiable(activeMessages),
      userMessages: List.unmodifiable(userMessages),
      hasModels: modelConfigs.isNotEmpty,
      isBusy: isBusy,
      errorMessage: errorMessage,
      errorMessageAssistantId: errorMessageAssistantId,
      emptyReplyAssistantId: emptyReplyAssistantId,
      errorModelDisplayName: selectedModel?.displayName ?? '模型',
      autoRetryCount: autoRetryCount,
      favoritedAssistantContents: Set.unmodifiable(
        favorites.favoritedAssistantContents,
      ),
    ),
    composer: ChatWorkspaceComposerReadModel(
      modelProviders: List.unmodifiable(selectableProviders),
      modelConfigs: List.unmodifiable(selectableModels),
      selectedProviderId: selectedProviderId,
      selectedModel: selectedModel,
      templatePrompts: List.unmodifiable(templatePrompts),
      selectedTemplatePrompt: selectedTemplatePrompt,
      fixedPromptSequences: List.unmodifiable(fixedPromptSequences),
      isComposerCollapsed: isComposerCollapsed,
      reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
      reasoningEffort: conversation.reasoningEffort,
      supportsReasoning: supportsReasoning,
      autoRetryEnabled: conversation.autoRetryEnabled,
      isBusy: isBusy,
      isStreaming: isStreaming,
      isAutoRetryWaiting: isAutoRetryWaiting,
      excludedMessageCount: excludedVisibleMessageCount,
    ),
  );
});
