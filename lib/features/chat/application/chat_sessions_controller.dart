import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
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
    final assistantMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: timestamp.add(const Duration(milliseconds: 1)),
      isStreaming: true,
    );

    final pendingConversation = currentConversation.copyWith(
      messages: [...currentConversation.messages, userMessage, assistantMessage],
      updatedAt: timestamp,
      selectedModelId: modelConfig.id,
      selectedPromptTemplateId: promptTemplate?.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );

    state = state.copyWith(
      conversations: _replaceConversation(pendingConversation),
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
          conversationMessages: [...currentConversation.messages, userMessage],
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
        _replaceConversationInMemory(
          pendingConversation.copyWith(
            messages: _replaceAssistantMessage(
              messages: pendingConversation.messages,
              assistantMessageId: assistantMessage.id,
              nextContent: responseBuffer.toString(),
              isStreaming: true,
            ),
            updatedAt: DateTime.now(),
          ),
        );
      }

      final completedConversation = state.activeConversation.copyWith(
        messages: _replaceAssistantMessage(
          messages: state.activeConversation.messages,
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
}
