import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_conversation_repository.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
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
    final promptTemplates = ref.read(promptTemplatesProvider);
    final rememberedModelId =
        modelConfigs.any(
          (config) => config.id == rememberedSelections.defaultModelId,
        )
        ? rememberedSelections.defaultModelId
        : modelConfigs.firstOrNull?.id;
    final rememberedPromptTemplateId =
        promptTemplates.any(
          (template) =>
              template.id == rememberedSelections.defaultPromptTemplateId,
        )
        ? rememberedSelections.defaultPromptTemplateId
        : null;
    return ChatConversation(
      id: generateEntityId(),
      messages: const [],
      createdAt: now,
      updatedAt: now,
      selectedModelId: rememberedModelId,
      selectedPromptTemplateId: rememberedPromptTemplateId,
      reasoningEffort: ReasoningEffort.medium,
    );
  }

  Future<void> updateActiveConversation(ChatConversation conversation) async {
    state = state.copyWith(
      conversations: replaceConversation(conversation),
      incrementHistoryRevision: true,
    );
    await saveAllConversations();
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

  Future<void> saveAllConversations() {
    return repository.saveAll(
      state.conversations
          .where((conversation) {
            return conversation.hasMessages ||
                conversation.checkpoints.isNotEmpty ||
                (conversation.title?.trim().isNotEmpty ?? false);
          })
          .toList(growable: false),
    );
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

  PromptTemplate? resolvePromptTemplate(ChatConversation conversation) {
    final promptTemplates = ref.read(promptTemplatesProvider);
    if (promptTemplates.isEmpty) {
      return null;
    }

    if (conversation.selectedPromptTemplateId == noPromptTemplateSelectedId) {
      return null;
    }

    final conversationSelected = promptTemplates.where((template) {
      return template.id == conversation.selectedPromptTemplateId;
    }).firstOrNull;
    if (conversationSelected != null) {
      return conversationSelected;
    }

    final defaultPromptTemplateId = ref
        .read(chatDefaultsProvider)
        .defaultPromptTemplateId;
    return promptTemplates.where((template) {
      return template.id == defaultPromptTemplateId;
    }).firstOrNull;
  }

  void setErrorMessage(String message) {
    state = state.copyWith(errorMessage: message, errorMessageAssistantId: null);
  }
}
