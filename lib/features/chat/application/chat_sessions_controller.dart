import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_completion_client.dart';
import '../data/chat_conversation_repository.dart';
import '../data/openai_compatible_chat_client.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

final chatSessionsProvider =
    NotifierProvider<ChatSessionsController, ChatSessionsState>(
      ChatSessionsController.new,
    );

class ChatSessionsState extends Equatable {
  const ChatSessionsState({
    required this.conversations,
    required this.activeConversationId,
    this.isStreaming = false,
    this.errorMessage,
  });

  final List<ChatConversation> conversations;
  final String activeConversationId;
  final bool isStreaming;
  final String? errorMessage;

  ChatConversation get activeConversation {
    return conversations.firstWhere(
      (conversation) => conversation.id == activeConversationId,
      orElse: () => conversations.first,
    );
  }

  ChatSessionsState copyWith({
    List<ChatConversation>? conversations,
    String? activeConversationId,
    bool? isStreaming,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ChatSessionsState(
      conversations: conversations ?? this.conversations,
      activeConversationId: activeConversationId ?? this.activeConversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        conversations,
        activeConversationId,
        isStreaming,
        errorMessage,
      ];
}

class ChatSessionsController extends Notifier<ChatSessionsState> {
  ChatConversationRepository get _repository =>
      ref.read(chatConversationRepositoryProvider);

  ChatCompletionClient get _chatClient =>
      ref.read(chatCompletionClientProvider);

  @override
  ChatSessionsState build() {
    final conversations = _sort(_repository.loadAll());
    final initialConversation = conversations.isEmpty
        ? _createConversation()
        : conversations.first;

    return ChatSessionsState(
      conversations: conversations.isEmpty
          ? [initialConversation]
          : List.unmodifiable(conversations),
      activeConversationId: initialConversation.id,
    );
  }

  Future<void> createConversation() async {
    final currentConversation = state.activeConversation;
    if (!currentConversation.hasMessages) {
      return;
    }

    final nextConversation = _createConversation();
    state = state.copyWith(
      conversations: [nextConversation, ...state.conversations],
      activeConversationId: nextConversation.id,
      clearErrorMessage: true,
    );
    await _saveAll();
  }

  void selectConversation(String id) {
    final hasMatch = state.conversations.any((conversation) {
      return conversation.id == id;
    });
    if (!hasMatch || state.activeConversationId == id) {
      return;
    }

    state = state.copyWith(
      activeConversationId: id,
      clearErrorMessage: true,
    );
  }

  Future<void> renameActiveConversation(String title) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }

    await _updateActiveConversation(
      state.activeConversation.copyWith(
        title: nextTitle,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateActiveConversationPreferences({
    String? selectedModelId,
    String? selectedPromptTemplateId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool clearSelectedPromptTemplateId = false,
  }) {
    return _updateActiveConversation(
      state.activeConversation.copyWith(
        selectedModelId: selectedModelId,
        selectedPromptTemplateId: selectedPromptTemplateId,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: reasoningEffort,
        clearSelectedPromptTemplateId: clearSelectedPromptTemplateId,
      ),
    );
  }

  Future<void> editMessage({
    required String messageId,
    required String nextContent,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final trimmedContent = nextContent.trim();
    if (trimmedContent.isEmpty) {
      return;
    }

    final currentConversation = state.activeConversation;
    final targetIndex = currentConversation.messages.indexWhere((message) {
      return message.id == messageId && message.role == ChatMessageRole.user;
    });
    if (targetIndex == -1) {
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重算：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    final targetMessage = currentConversation.messages[targetIndex];
    final rebuiltUserMessages = [
      targetMessage.copyWith(content: trimmedContent),
      ...currentConversation.messages.skip(targetIndex + 1).where((message) {
        return message.role == ChatMessageRole.user;
      }),
    ];

    var rebuiltConversation = currentConversation.copyWith(
      messages: currentConversation.messages.take(targetIndex).toList(
            growable: false,
          ),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      conversations: _replaceConversation(rebuiltConversation),
      clearErrorMessage: true,
    );
    await _saveAll();

    for (final userMessage in rebuiltUserMessages) {
      rebuiltConversation = rebuiltConversation.copyWith(
        messages: [...rebuiltConversation.messages, userMessage],
        updatedAt: DateTime.now(),
      );

      final nextConversation = await _streamAssistantReply(
        conversation: rebuiltConversation,
        modelConfig: modelConfig,
        promptTemplate: promptTemplate,
        reasoningEnabled: rebuiltConversation.reasoningEnabled,
        reasoningEffort: rebuiltConversation.reasoningEffort,
      );
      if (nextConversation == null) {
        return;
      }

      rebuiltConversation = nextConversation;
    }
  }

  Future<void> retryLatestAssistant() async {
    if (state.isStreaming) {
      return;
    }

    final currentConversation = state.activeConversation;
    final latestAssistantIndex = currentConversation.messages.lastIndexWhere((
      message,
    ) {
      return message.role == ChatMessageRole.assistant;
    });
    if (latestAssistantIndex == -1 ||
        latestAssistantIndex != currentConversation.messages.length - 1) {
      _setErrorMessage('只能重试当前对话中的最新模型回复。');
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重试：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    final baseConversation = currentConversation.copyWith(
      messages: currentConversation.messages.take(latestAssistantIndex).toList(
            growable: false,
          ),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      conversations: _replaceConversation(baseConversation),
      clearErrorMessage: true,
    );
    await _saveAll();

    await _streamAssistantReply(
      conversation: baseConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      reasoningEnabled: baseConversation.reasoningEnabled,
      reasoningEffort: baseConversation.reasoningEffort,
    );
  }

  void clearError() {
    if (state.errorMessage == null) {
      return;
    }

    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> sendMessage({
    required String content,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      return;
    }

    final currentConversation = state.activeConversation;
    final timestamp = DateTime.now();
    final userMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: timestamp,
    );

    final pendingConversation = currentConversation.copyWith(
      messages: [...currentConversation.messages, userMessage],
      updatedAt: timestamp,
      selectedModelId: modelConfig.id,
      selectedPromptTemplateId: promptTemplate?.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
    await _streamAssistantReply(
      conversation: pendingConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
  }

  ChatConversation _createConversation() {
    final now = DateTime.now();
    return ChatConversation(
      id: generateEntityId(),
      messages: const [],
      createdAt: now,
      updatedAt: now,
      reasoningEffort: ReasoningEffort.medium,
    );
  }

  Future<void> _handleStreamingFailure({
    required String assistantMessageId,
    required String errorMessage,
  }) async {
    final currentConversation = state.activeConversation;
    final failedAssistantMessage = currentConversation.messages
        .where((message) => message.id == assistantMessageId)
        .firstOrNull;
    final hasPartialContent =
        failedAssistantMessage != null &&
        failedAssistantMessage.content.trim().isNotEmpty;

    final nextMessages = hasPartialContent
        ? _replaceAssistantMessage(
            messages: currentConversation.messages,
            assistantMessageId: assistantMessageId,
            nextContent: failedAssistantMessage.content,
            isStreaming: false,
          )
        : currentConversation.messages
            .where((message) => message.id != assistantMessageId)
            .toList(growable: false);

    final nextConversation = currentConversation.copyWith(
      messages: nextMessages,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      conversations: _replaceConversation(nextConversation),
      isStreaming: false,
      errorMessage: errorMessage,
    );
    await _saveAll();
  }

  Future<void> _updateActiveConversation(ChatConversation conversation) async {
    state = state.copyWith(
      conversations: _replaceConversation(conversation),
    );
    await _saveAll();
  }

  Future<ChatConversation?> _streamAssistantReply({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
  }) async {
    final timestamp = DateTime.now();
    final assistantMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: timestamp.add(const Duration(milliseconds: 1)),
      isStreaming: true,
    );

    var streamingConversation = conversation.copyWith(
      messages: [...conversation.messages, assistantMessage],
      updatedAt: timestamp,
      selectedModelId: modelConfig.id,
      selectedPromptTemplateId: promptTemplate?.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );

    state = state.copyWith(
      conversations: _replaceConversation(streamingConversation),
      isStreaming: true,
      clearErrorMessage: true,
    );
    await _saveAll();

    try {
      final responseBuffer = StringBuffer();
      await for (final chunk in _chatClient.streamCompletion(
        modelConfig: modelConfig,
        messages: _buildRequestMessages(
          promptTemplate: promptTemplate,
          conversationMessages: conversation.messages,
        ),
        reasoningEffort:
            reasoningEnabled && modelConfig.supportsReasoning
                ? reasoningEffort
                : null,
      )) {
        if (chunk.isEmpty) {
          continue;
        }

        responseBuffer.write(chunk);
        streamingConversation = streamingConversation.copyWith(
          messages: _replaceAssistantMessage(
            messages: streamingConversation.messages,
            assistantMessageId: assistantMessage.id,
            nextContent: responseBuffer.toString(),
            isStreaming: true,
          ),
          updatedAt: DateTime.now(),
        );
        _replaceConversationInMemory(streamingConversation);
      }

      final completedConversation = streamingConversation.copyWith(
        messages: _replaceAssistantMessage(
          messages: streamingConversation.messages,
          assistantMessageId: assistantMessage.id,
          nextContent: responseBuffer.toString(),
          isStreaming: false,
        ),
        updatedAt: DateTime.now(),
      );

      state = state.copyWith(
        conversations: _replaceConversation(completedConversation),
        isStreaming: false,
      );
      await _saveAll();
      return completedConversation;
    } on ChatCompletionException catch (error) {
      await _handleStreamingFailure(
        assistantMessageId: assistantMessage.id,
        errorMessage: error.message,
      );
    } catch (_) {
      await _handleStreamingFailure(
        assistantMessageId: assistantMessage.id,
        errorMessage: '请求未完成，请检查网络、API URL 或模型配置。',
      );
    }

    return null;
  }

  void _replaceConversationInMemory(ChatConversation conversation) {
    state = state.copyWith(
      conversations: _replaceConversation(conversation),
    );
  }

  List<ChatConversation> _replaceConversation(ChatConversation conversation) {
    final conversations = [...state.conversations];
    final index = conversations.indexWhere((item) => item.id == conversation.id);

    if (index == -1) {
      conversations.add(conversation);
    } else {
      conversations[index] = conversation;
    }

    return _sort(conversations);
  }

  List<ChatConversation> _sort(List<ChatConversation> conversations) {
    final sortedConversations = [...conversations];
    sortedConversations.sort((left, right) {
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return List.unmodifiable(sortedConversations);
  }

  List<ChatCompletionRequestMessage> _buildRequestMessages({
    required PromptTemplate? promptTemplate,
    required List<ChatMessage> conversationMessages,
  }) {
    final requestMessages = <ChatCompletionRequestMessage>[];

    if (promptTemplate != null && promptTemplate.systemPrompt.trim().isNotEmpty) {
      requestMessages.add(
        ChatCompletionRequestMessage(
          role: ChatMessageRole.system,
          content: promptTemplate.systemPrompt.trim(),
        ),
      );
    }

    if (promptTemplate != null) {
      requestMessages.addAll(
        promptTemplate.messages.map((message) {
          return ChatCompletionRequestMessage(
            role: message.role == PromptMessageRole.user
                ? ChatMessageRole.user
                : ChatMessageRole.assistant,
            content: message.content,
          );
        }),
      );
    }

    requestMessages.addAll(
      conversationMessages.map((message) {
        return ChatCompletionRequestMessage(
          role: message.role,
          content: message.content,
        );
      }),
    );

    return List.unmodifiable(requestMessages);
  }

  List<ChatMessage> _replaceAssistantMessage({
    required List<ChatMessage> messages,
    required String assistantMessageId,
    required String nextContent,
    required bool isStreaming,
  }) {
    return messages.map((message) {
      if (message.id != assistantMessageId) {
        return message;
      }

      return message.copyWith(
        content: nextContent,
        isStreaming: isStreaming,
      );
    }).toList(growable: false);
  }

  Future<void> _saveAll() {
    return _repository.saveAll(
      state.conversations.where((conversation) {
        return conversation.hasMessages ||
            (conversation.title?.trim().isNotEmpty ?? false);
      }).toList(growable: false),
    );
  }

  LlmModelConfig? _resolveModelConfig(ChatConversation conversation) {
    final modelConfigs = ref.read(llmModelConfigsProvider);
    if (modelConfigs.isEmpty) {
      return null;
    }

    return modelConfigs.where((config) {
          return config.id == conversation.selectedModelId;
        }).firstOrNull ??
        modelConfigs.first;
  }

  PromptTemplate? _resolvePromptTemplate(ChatConversation conversation) {
    final promptTemplates = ref.read(promptTemplatesProvider);
    if (promptTemplates.isEmpty) {
      return null;
    }

    return promptTemplates.where((template) {
      return template.id == conversation.selectedPromptTemplateId;
    }).firstOrNull;
  }

  void _setErrorMessage(String message) {
    state = state.copyWith(errorMessage: message);
  }
}
