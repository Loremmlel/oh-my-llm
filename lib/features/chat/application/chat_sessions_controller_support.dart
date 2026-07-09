import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/preset_prompts_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/preset_prompt.dart';
import '../data/chat_conversation_repository.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import 'checkpoint_request_context.dart';
import 'chat_sessions_state.dart';

/// 为 [ChatSessionsController] 提供会话持久化与配置解析辅助。
mixin ChatSessionsControllerSupport on Notifier<ChatSessionsState> {
  ChatConversationRepository get repository;

  ChatConversation buildEmptyConversation() {
    final now = DateTime.now();
    final rememberedSelections = ref.read(chatDefaultsProvider);
    final modelConfigs = ref.read(llmModelConfigsProvider);
    final presetPrompts = ref.read(presetPromptsProvider);
    final rememberedModelId =
        modelConfigs.any(
          (config) => config.id == rememberedSelections.defaultModelId,
        )
        ? rememberedSelections.defaultModelId
        : modelConfigs.firstOrNull?.id;
    final rememberedPresetPromptId =
        presetPrompts.any(
          (template) =>
              template.id == rememberedSelections.defaultPresetPromptId,
        )
        ? rememberedSelections.defaultPresetPromptId
        : null;
    return ChatConversation(
      id: generateEntityId(),
      createdAt: now,
      updatedAt: now,
      selectedModelId: rememberedModelId,
      selectedPresetPromptId: rememberedPresetPromptId,
      reasoningEffort: ReasoningEffort.medium,
    );
  }

  void updateActiveConversation(
    ChatConversation conversation, {
    bool incrementHistoryRevision = true,
  }) {
    state = state.copyWith(
      conversations: replaceConversation(conversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(conversation),
      ),
      incrementHistoryRevision: incrementHistoryRevision,
    );
    saveConversation(conversation);
  }

  /// 把流式结果（消息树）合并进当前活动会话，保留用户在流式期间
  /// 对模型/预设/思考偏好等配置的修改。
  ///
  /// 流式发送时以快照 [streamingConversation] 为基底构建消息树，但流式期间
  /// 用户可能解锁了配置下拉并改动了 [state.activeConversation] 的 modelId/
  /// presetId/reasoning 等字段。落盘时若直接用 [streamingConversation] 覆盖，
  /// 会丢失这些改动。因此以当前活动会话为基底，只替换消息树与时间戳。
  ///
  /// 调用契约：[streamingConversation] 必须是发起流式时的活动会话，且流式
  /// 期间活动会话不可被切换（由 [ChatSessionsController] 的会话切换守卫
  /// 保证）。下方 assert 仅在 debug 模式校验此契约；若 release 下违反，
  /// 消息树会写入当前活动会话（可能非流式发起方），属调用方 bug。
  ChatConversation mergeStreamingResultIntoActive({
    required ChatConversation streamingConversation,
    required List<ChatMessage> messageNodes,
    required Map<String, String> selectedChildByParentId,
  }) {
    final active = state.activeConversation;
    assert(
      streamingConversation.id == active.id,
      'streamingConversation 必须属于当前活动会话；'
      '流式期间切换活动会话会导致消息树写入错误会话',
    );
    return active.copyWith(
      messageNodes: messageNodes,
      selectedChildByParentId: selectedChildByParentId,
      updatedAt: DateTime.now(),
    );
  }

  List<ChatConversation> replaceConversation(ChatConversation conversation) {
    final conversations = [...state.conversations];
    final index = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );

    if (index == -1) {
      conversations.add(conversation);
    } else {
      conversations[index] = conversation;
    }

    return sortConversations(conversations);
  }

  List<ChatConversation> sortConversations(
    List<ChatConversation> conversations,
  ) {
    final sortedConversations = [...conversations];
    sortedConversations.sort((left, right) {
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return List.unmodifiable(sortedConversations);
  }

  /// 保存单个会话到持久层。
  ///
  /// 空会话（无消息、无检查点、无标题）将被跳过，详见
  /// [BackgroundChatConversationRepository.saveConversation]。
  void saveConversation(ChatConversation conversation) {
    repository.saveConversation(conversation);
  }

  CheckpointRequestContext resolveCheckpointContext({
    required ChatConversation conversation,
    required List<ChatMessage> conversationMessages,
  }) {
    return resolveCheckpointRequestContext(
      checkpoints: conversation.checkpoints,
      selectedCheckpointId: conversation.selectedCheckpointId,
      conversationMessages: conversationMessages,
    );
  }

  String buildNextCheckpointTitle(List<ChatCheckpoint> checkpoints) {
    return '检查点 ${checkpoints.length + 1}';
  }

  LlmModelConfig? resolveModelConfig(ChatConversation conversation) {
    final modelConfigs = ref.read(llmModelConfigsProvider);
    if (modelConfigs.isEmpty) {
      return null;
    }

    final conversationSelected = modelConfigs.where((config) {
      return config.id == conversation.selectedModelId;
    }).firstOrNull;
    if (conversationSelected != null) {
      return conversationSelected;
    }

    final defaultModelId = ref.read(chatDefaultsProvider).defaultModelId;
    final defaultModel = modelConfigs.where((config) {
      return config.id == defaultModelId;
    }).firstOrNull;
    if (defaultModel != null) {
      return defaultModel;
    }

    return modelConfigs.first;
  }

  PresetPrompt? resolvePresetPrompt(ChatConversation conversation) {
    final presetPrompts = ref.read(presetPromptsProvider);
    if (presetPrompts.isEmpty) {
      return null;
    }

    if (conversation.selectedPresetPromptId == noPresetPromptSelectedId) {
      return null;
    }

    final conversationSelected = presetPrompts.where((template) {
      return template.id == conversation.selectedPresetPromptId;
    }).firstOrNull;
    if (conversationSelected != null) {
      return conversationSelected;
    }

    final defaultPresetPromptId = ref
        .read(chatDefaultsProvider)
        .defaultPresetPromptId;
    return presetPrompts.where((template) {
      return template.id == defaultPresetPromptId;
    }).firstOrNull;
  }

  void setErrorMessage(String message) {
    state = state.copyWith(
      errorMessage: message,
      errorMessageAssistantId: null,
    );
  }

  ChatConversationSummary summaryFromConversation(ChatConversation conv) {
    final userMessages = conv.messages
        .where((m) => m.role == ChatMessageRole.user)
        .toList();
    return ChatConversationSummary(
      id: conv.id,
      title: conv.title,
      updatedAt: conv.updatedAt,
      firstUserMessagePreview: userMessages.firstOrNull?.content ?? '',
      latestUserMessagePreview: userMessages.lastOrNull?.content ?? '',
    );
  }

  List<ChatConversationSummary> replaceOrAddSummary(
    List<ChatConversationSummary> summaries,
    ChatConversationSummary summary,
  ) {
    final result = [...summaries];
    final index = result.indexWhere((s) => s.id == summary.id);
    if (index == -1) {
      result.add(summary);
    } else {
      result[index] = summary;
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(result);
  }
}
