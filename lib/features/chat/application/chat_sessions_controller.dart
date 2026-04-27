import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/chat_defaults_controller.dart';
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
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
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

    state = state.copyWith(activeConversationId: id, clearErrorMessage: true);
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

  Future<void> renameConversation({
    required String conversationId,
    required String title,
  }) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }

    final targetConversation = state.conversations.where((conversation) {
      return conversation.id == conversationId;
    }).firstOrNull;
    if (targetConversation == null) {
      return;
    }

    state = state.copyWith(
      conversations: _replaceConversation(
        targetConversation.copyWith(
          title: nextTitle,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    await _saveAll();
  }

  Future<void> deleteConversations(Set<String> conversationIds) async {
    if (conversationIds.isEmpty || state.isStreaming) {
      return;
    }

    final remainingConversations = state.conversations
        .where((conversation) {
          return !conversationIds.contains(conversation.id);
        })
        .toList(growable: false);

    final fallbackConversation =
        remainingConversations.firstOrNull ?? _createConversation();

    state = state.copyWith(
      conversations: remainingConversations.isEmpty
          ? [fallbackConversation]
          : remainingConversations,
      activeConversationId:
          remainingConversations.any((conversation) {
            return conversation.id == state.activeConversationId;
          })
          ? state.activeConversationId
          : fallbackConversation.id,
      clearErrorMessage: true,
    );
    await _saveAll();
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

  Future<void> selectMessageVersion({
    required String parentId,
    required String messageId,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final currentConversation = state.activeConversation;
    final tree = _resolveTreeState(currentConversation);
    final siblings = tree.nodes.where((node) {
      return (node.parentId ?? rootConversationParentId) == parentId;
    }).toList(growable: false);
    final hasTarget = siblings.any((node) => node.id == messageId);
    if (!hasTarget) {
      return;
    }

    final nextSelections = Map<String, String>.from(tree.selections);
    nextSelections[parentId] = messageId;
    await _updateActiveConversation(
      currentConversation.copyWith(
        messageNodes: tree.nodes,
        selectedChildByParentId: nextSelections,
        updatedAt: DateTime.now(),
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
    final tree = _resolveTreeState(currentConversation);
    final targetMessage = tree.nodes
        .where((message) {
          return message.id == messageId && message.role == ChatMessageRole.user;
        })
        .firstOrNull;
    if (targetMessage == null) {
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重算：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    final branchUserMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: DateTime.now(),
      parentId: targetMessage.parentId,
    );
    final nextNodes = [...tree.nodes, branchUserMessage];
    final nextSelections = Map<String, String>.from(tree.selections);
    final branchParentId = targetMessage.parentId ?? rootConversationParentId;
    nextSelections[branchParentId] = branchUserMessage.id;
    final rebuiltConversation = currentConversation.copyWith(
      messageNodes: nextNodes,
      selectedChildByParentId: nextSelections,
      updatedAt: DateTime.now(),
    );
    await _streamAssistantReply(
      conversation: rebuiltConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: rebuiltConversation.messages,
      parentMessageId: branchUserMessage.id,
      reasoningEnabled: rebuiltConversation.reasoningEnabled,
      reasoningEffort: rebuiltConversation.reasoningEffort,
    );
  }

  Future<void> retryLatestAssistant() async {
    if (state.isStreaming) {
      return;
    }

    final currentConversation = state.activeConversation;
    final activePath = currentConversation.messages;
    final latestAssistantIndex = activePath.lastIndexWhere((message) {
      return message.role == ChatMessageRole.assistant;
    });
    if (latestAssistantIndex == -1 ||
        latestAssistantIndex != activePath.length - 1) {
      _setErrorMessage('只能重试当前对话中的最新模型回复。');
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重试：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    final tree = _resolveTreeState(currentConversation);
    final latestAssistant = activePath[latestAssistantIndex];
    final parentId = latestAssistant.parentId ?? rootConversationParentId;
    final requestMessages = activePath
        .take(latestAssistantIndex)
        .toList(growable: false);
    final nextSelections = Map<String, String>.from(tree.selections);
    nextSelections.remove(parentId);
    final baseConversation = currentConversation.copyWith(
      messageNodes: tree.nodes,
      selectedChildByParentId: nextSelections,
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
      requestConversationMessages: requestMessages,
      parentMessageId: parentId == rootConversationParentId ? null : parentId,
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
    final tree = _resolveTreeState(currentConversation);
    final activePath = currentConversation.messages;
    final parentId = activePath.lastOrNull?.id;
    final userMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: timestamp,
      parentId: parentId ?? rootConversationParentId,
    );
    final pendingNodes = [...tree.nodes, userMessage];
    final pendingSelections = Map<String, String>.from(tree.selections);
    pendingSelections[parentId ?? rootConversationParentId] = userMessage.id;

    final pendingConversation = currentConversation.copyWith(
      messageNodes: pendingNodes,
      selectedChildByParentId: pendingSelections,
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
      requestConversationMessages: pendingConversation.messages,
      parentMessageId: userMessage.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
  }

  ChatConversation _createConversation() {
    final now = DateTime.now();
    final chatDefaults = ref.read(chatDefaultsProvider);
    return ChatConversation(
      id: generateEntityId(),
      messages: const [],
      createdAt: now,
      updatedAt: now,
      selectedModelId: chatDefaults.defaultModelId,
      selectedPromptTemplateId: chatDefaults.defaultPromptTemplateId,
      reasoningEffort: ReasoningEffort.medium,
    );
  }

  Future<void> _handleStreamingFailure({
    required String assistantMessageId,
    required String errorMessage,
  }) async {
    final currentConversation = state.activeConversation;
    final tree = _resolveTreeState(currentConversation);
    final failedAssistantMessage = tree.nodes
        .where((message) => message.id == assistantMessageId)
        .firstOrNull;
    final hasPartialContent =
        failedAssistantMessage != null &&
        (failedAssistantMessage.content.trim().isNotEmpty ||
            failedAssistantMessage.reasoningContent.trim().isNotEmpty);

    final nextTree = hasPartialContent
        ? _replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: assistantMessageId,
            nextContent: failedAssistantMessage.content,
            nextReasoningContent: failedAssistantMessage.reasoningContent,
            isStreaming: false,
          )
        : _removeNodeFromTree(treeState: tree, nodeId: assistantMessageId);

    final nextConversation = currentConversation.copyWith(
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
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
    state = state.copyWith(conversations: _replaceConversation(conversation));
    await _saveAll();
  }

  Future<ChatConversation?> _streamAssistantReply({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required List<ChatMessage> requestConversationMessages,
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
  }) async {
    final timestamp = DateTime.now();
    final tree = _resolveTreeState(conversation);
    final assistantParentId = parentMessageId ?? rootConversationParentId;
    final assistantMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: timestamp.add(const Duration(milliseconds: 1)),
      parentId: assistantParentId,
      isStreaming: true,
    );
    final initialTree = _appendNodeToTree(
      treeState: tree,
      node: assistantMessage,
      parentId: assistantParentId,
    );
    var streamingConversation = conversation.copyWith(
      messageNodes: initialTree.nodes,
      selectedChildByParentId: initialTree.selections,
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
      final reasoningBuffer = StringBuffer();
      await for (final chunk in _chatClient.streamCompletion(
        modelConfig: modelConfig,
        messages: _buildRequestMessages(
          promptTemplate: promptTemplate,
          conversationMessages: requestConversationMessages,
        ),
        reasoningEffort: reasoningEnabled && modelConfig.supportsReasoning
            ? reasoningEffort
            : null,
      )) {
        if (chunk.isEmpty) {
          continue;
        }

        responseBuffer.write(chunk.contentDelta);
        reasoningBuffer.write(chunk.reasoningDelta);
        final nextTree = _replaceAssistantMessageInTree(
          treeState: _resolveTreeState(streamingConversation),
          assistantMessageId: assistantMessage.id,
          nextContent: responseBuffer.toString(),
          nextReasoningContent: reasoningBuffer.toString(),
          isStreaming: true,
        );
        streamingConversation = streamingConversation.copyWith(
          messageNodes: nextTree.nodes,
          selectedChildByParentId: nextTree.selections,
          updatedAt: DateTime.now(),
        );
        _replaceConversationInMemory(streamingConversation);
      }

      final completedTree = _replaceAssistantMessageInTree(
        treeState: _resolveTreeState(streamingConversation),
        assistantMessageId: assistantMessage.id,
        nextContent: responseBuffer.toString(),
        nextReasoningContent: reasoningBuffer.toString(),
        isStreaming: false,
      );
      final completedConversation = streamingConversation.copyWith(
        messageNodes: completedTree.nodes,
        selectedChildByParentId: completedTree.selections,
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
    state = state.copyWith(conversations: _replaceConversation(conversation));
  }

  List<ChatConversation> _replaceConversation(ChatConversation conversation) {
    final conversations = [...state.conversations];
    final index = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );

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

    if (promptTemplate != null &&
        promptTemplate.systemPrompt.trim().isNotEmpty) {
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

  _TreeState _resolveTreeState(ChatConversation conversation) {
    if (conversation.messageNodes.isNotEmpty) {
      return _TreeState(
        nodes: List<ChatMessage>.from(conversation.messageNodes),
        selections: Map<String, String>.from(
          conversation.selectedChildByParentId,
        ),
      );
    }

    final nodes = <ChatMessage>[];
    final selections = <String, String>{};
    var parentId = rootConversationParentId;
    for (final message in conversation.messages) {
      final node = message.copyWith(parentId: parentId);
      nodes.add(node);
      selections[parentId] = node.id;
      parentId = node.id;
    }
    return _TreeState(nodes: nodes, selections: selections);
  }

  _TreeState _appendNodeToTree({
    required _TreeState treeState,
    required ChatMessage node,
    required String parentId,
  }) {
    final nextNodes = [...treeState.nodes, node];
    final nextSelections = Map<String, String>.from(treeState.selections);
    nextSelections[parentId] = node.id;
    return _TreeState(nodes: nextNodes, selections: nextSelections);
  }

  _TreeState _replaceAssistantMessageInTree({
    required _TreeState treeState,
    required String assistantMessageId,
    required String nextContent,
    required String nextReasoningContent,
    required bool isStreaming,
  }) {
    final nextNodes = treeState.nodes
        .map((message) {
          if (message.id != assistantMessageId) {
            return message;
          }

          return message.copyWith(
            content: nextContent,
            reasoningContent: nextReasoningContent,
            isStreaming: isStreaming,
          );
        })
        .toList(growable: false);
    return _TreeState(
      nodes: nextNodes,
      selections: Map<String, String>.from(treeState.selections),
    );
  }

  _TreeState _removeNodeFromTree({
    required _TreeState treeState,
    required String nodeId,
  }) {
    final childIdsByParent = <String, List<String>>{};
    for (final node in treeState.nodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      childIdsByParent.putIfAbsent(parentId, () => <String>[]).add(node.id);
    }

    final removedNodeIds = <String>{};
    final queue = <String>[nodeId];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      if (!removedNodeIds.add(currentId)) {
        continue;
      }
      queue.addAll(childIdsByParent[currentId] ?? const []);
    }

    final nextNodes = treeState.nodes
        .where((node) => !removedNodeIds.contains(node.id))
        .toList(growable: false);
    final nextSelections = Map<String, String>.from(treeState.selections)
      ..removeWhere((key, value) {
        return removedNodeIds.contains(key) || removedNodeIds.contains(value);
      });
    return _TreeState(nodes: nextNodes, selections: nextSelections);
  }

  Future<void> _saveAll() {
    return _repository.saveAll(
      state.conversations
          .where((conversation) {
            return conversation.hasMessages ||
                (conversation.title?.trim().isNotEmpty ?? false);
          })
          .toList(growable: false),
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

class _TreeState {
  const _TreeState({required this.nodes, required this.selections});

  final List<ChatMessage> nodes;
  final Map<String, String> selections;
}
