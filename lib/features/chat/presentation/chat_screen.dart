import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/fixed_prompt_sequences_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/fixed_prompt_sequence.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import '../application/chat_sessions_controller.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import '../../favorites/application/favorites_controller.dart';
import 'widgets/widgets.dart';

/// 聊天页入口，负责把会话状态、输入框和侧栏组合成完整页面。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// 聊天页状态层，处理滚动同步、锚点定位和编辑弹窗等页面级交互。
class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TextEditingController _messageController;
  final ItemScrollController _messageItemScrollController =
      ItemScrollController();
  final ItemPositionsListener _messageItemPositionsListener =
      ItemPositionsListener.create();

  bool _showScrollToBottom = false;
  String? _lastConversationId;
  String? _lastRenderSignature;
  String? _activeAnchorMessageId;
  String? _selectedFixedPromptSequenceId;
  int _selectedFixedPromptStepIndex = 0;
  List<ChatMessage> _latestMessages = const <ChatMessage>[];
  List<ChatMessage> _latestUserMessages = const <ChatMessage>[];
  List<int> _latestUserMessageIndexes = const <int>[];
  Map<String, int> _latestMessageIndexById = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageItemPositionsListener.itemPositions.addListener(
      _handleVisibleItemsChanged,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageItemPositionsListener.itemPositions.removeListener(
      _handleVisibleItemsChanged,
    );
    super.dispose();
  }

  @override
  /// 构建聊天页的整体布局与交互入口。
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    final conversations = ref.watch(chatConversationsProvider);
    final activeConversationId = ref.watch(activeConversationIdProvider);
    final isStreaming = ref.watch(isChatStreamingProvider);
    final errorMessage = ref.watch(chatErrorMessageProvider);
    final chatDefaults = ref.watch(chatDefaultsProvider);
    final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
    final modelConfigs = ref.watch(llmModelConfigsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);
    final activeMessages = conversation.messages;
    final favorites = ref.watch(favoritesProvider);
    final favoritedContents = favorites.map((f) => f.assistantContent).toSet();

    final selectedModel = _resolveSelectedModel(
      modelConfigs,
      conversation.selectedModelId,
      chatDefaults.defaultModelId,
    );
    final selectedPromptTemplate = _resolveSelectedPromptTemplate(
      promptTemplates,
      conversation.selectedPromptTemplateId,
      chatDefaults.defaultPromptTemplateId,
    );
    final supportsReasoning = selectedModel?.supportsReasoning ?? false;
    final userMessages = activeMessages
        .where((message) {
          return message.role == ChatMessageRole.user;
        })
        .toList(growable: false);
    _cacheVisibleMessageMetadata(activeMessages, userMessages);

    _scheduleScrollSync(
      conversationId: conversation.id,
      messages: activeMessages,
      isStreaming: isStreaming,
    );

    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: conversation.resolvedTitle,
      endDrawer: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConversationHistoryPanel(
            groups: _buildConversationGroups(conversations),
            activeConversationId: activeConversationId,
            hasDraftConversation: !conversation.hasMessages,
            onCreateConversation: isStreaming
                ? null
                : () => _createConversationAndScroll(),
            onConversationSelected: (conversationId) {
              if (isStreaming) {
                return;
              }
              ref
                  .read(chatSessionsProvider.notifier)
                  .selectConversation(conversationId);
            },
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: isStreaming ? null : _createConversationAndScroll,
          tooltip: '新建对话',
          icon: const Icon(Icons.add_comment_outlined),
        ),
        IconButton(
          onPressed: () =>
              _showRenameDialog(context, conversation.resolvedTitle),
          tooltip: '修改对话标题',
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidePanels =
              constraints.maxWidth >= AppBreakpoints.expanded;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSidePanels) ...[
                  SizedBox(
                    width: 220,
                    child: ConversationHistoryPanel(
                      groups: _buildConversationGroups(conversations),
                      activeConversationId: activeConversationId,
                      hasDraftConversation: !conversation.hasMessages,
                      onCreateConversation: isStreaming
                          ? null
                          : () => _createConversationAndScroll(),
                      onConversationSelected: (conversationId) {
                        if (isStreaming) {
                          return;
                        }
                        ref
                            .read(chatSessionsProvider.notifier)
                            .selectConversation(conversationId);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ChatWorkspace(
                    conversation: conversation,
                    messages: activeMessages,
                    hasModels: modelConfigs.isNotEmpty,
                    userMessages: userMessages,
                    activeAnchorMessageId: _activeAnchorMessageId,
                    messageController: _messageController,
                    messageItemScrollController: _messageItemScrollController,
                    messageItemPositionsListener: _messageItemPositionsListener,
                    reasoningEnabled:
                        supportsReasoning && conversation.reasoningEnabled,
                    reasoningEffort: conversation.reasoningEffort,
                    supportsReasoning: supportsReasoning,
                    isStreaming: isStreaming,
                    errorMessage: errorMessage,
                    showScrollToBottom: _showScrollToBottom,
                    onDismissError: () {
                      ref.read(chatSessionsProvider.notifier).clearError();
                    },
                    onEditMessage: (message) async {
                      await _showEditMessageDialog(
                        context,
                        messageId: message.id,
                        initialContent: message.content,
                      );
                    },
                    onRetryLatestAssistant: () async {
                      await ref
                          .read(chatSessionsProvider.notifier)
                          .retryLatestAssistant();
                    },
                    onReasoningEnabledChanged: supportsReasoning
                        ? (value) {
                            ref
                                .read(chatSessionsProvider.notifier)
                                .updateActiveConversationPreferences(
                                  reasoningEnabled: value,
                                );
                          }
                        : null,
                    onReasoningEffortChanged: supportsReasoning
                        ? (value) {
                            ref
                                .read(chatSessionsProvider.notifier)
                                .updateActiveConversationPreferences(
                                  reasoningEffort: value,
                                );
                          }
                        : null,
                    onOpenFixedPromptSequenceRunner: () async {
                      await _showFixedPromptSequenceRunnerDialog(
                        context,
                        fixedPromptSequences: fixedPromptSequences,
                        selectedModel: selectedModel,
                        selectedPromptTemplate: selectedPromptTemplate,
                        conversation: conversation,
                        supportsReasoning: supportsReasoning,
                        isStreaming: isStreaming,
                      );
                    },
                    onScrollToBottomPressed: _scrollToBottom,
                    onSelectMessage: _scrollToMessage,
                    onSelectMessageVersion: (parentId, messageId) async {
                      await ref
                          .read(chatSessionsProvider.notifier)
                          .selectMessageVersion(
                            parentId: parentId,
                            messageId: messageId,
                          );
                    },
                    onSendPressed: selectedModel == null || isStreaming
                        ? null
                        : () async {
                            final content = _messageController.text.trim();
                            if (content.isEmpty) {
                              return;
                            }

                            _messageController.clear();
                            await _sendMessageContent(
                              content: content,
                              modelConfig: selectedModel,
                              promptTemplate: selectedPromptTemplate,
                              conversation: conversation,
                              supportsReasoning: supportsReasoning,
                              isStreaming: isStreaming,
                            );
                          },
                    onFavoritePressed: (message) => _showAddToFavoritesDialog(
                      context,
                      message,
                      conversation,
                    ),
                    favoritedAssistantContents: favoritedContents,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 过滤出可展示的会话分组，隐藏空草稿会话。
  List<ChatConversationGroup> _buildConversationGroups(
    List<ChatConversation> conversations,
  ) {
    final visibleConversations = conversations
        .where((conversation) {
          return conversation.hasMessages;
        })
        .toList(growable: false);
    return groupConversationsByUpdatedAt(visibleConversations);
  }

  /// 解析当前会话应使用的模型配置，并在缺省时回退到默认项。
  LlmModelConfig? _resolveSelectedModel(
    List<LlmModelConfig> modelConfigs,
    String? selectedModelId,
    String? defaultModelId,
  ) {
    if (modelConfigs.isEmpty) {
      return null;
    }

    final defaultSelected = modelConfigs.where((config) {
      return config.id == defaultModelId;
    }).firstOrNull;

    if (defaultSelected != null) {
      return defaultSelected;
    }

    return modelConfigs.where((config) {
          return config.id == selectedModelId;
        }).firstOrNull ??
        modelConfigs.first;
  }

  /// 解析当前会话应使用的 Prompt 模板，并在缺省时回退到默认项。
  PromptTemplate? _resolveSelectedPromptTemplate(
    List<PromptTemplate> promptTemplates,
    String? selectedPromptTemplateId,
    String? defaultPromptTemplateId,
  ) {
    final selected = promptTemplates.where((template) {
      return template.id == selectedPromptTemplateId;
    }).firstOrNull;

    if (selected != null) {
      return selected;
    }

    return promptTemplates.where((template) {
      return template.id == defaultPromptTemplateId;
    }).firstOrNull;
  }

  /// 弹出固定顺序提示词运行器，并在关闭后同步输入框或直接发送当前步骤。
  Future<void> _showFixedPromptSequenceRunnerDialog(
    BuildContext context, {
    required List<FixedPromptSequence> fixedPromptSequences,
    required LlmModelConfig? selectedModel,
    required PromptTemplate? selectedPromptTemplate,
    required ChatConversation conversation,
    required bool supportsReasoning,
    required bool isStreaming,
  }) async {
    final result = await showDialog<FixedPromptSequenceRunnerResult>(
      context: context,
      builder: (context) {
        return FixedPromptSequenceRunnerDialog(
          sequences: fixedPromptSequences,
          initialSelectedSequenceId: _selectedFixedPromptSequenceId,
          initialStepIndex: _selectedFixedPromptStepIndex,
          canSendDirectly: selectedModel != null && !isStreaming,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedFixedPromptSequenceId = result.selectedSequenceId;
      _selectedFixedPromptStepIndex = result.nextStepIndex;
    });

    switch (result.action) {
      case FixedPromptSequenceRunnerAction.fillComposer:
        _messageController
          ..text = result.content
          ..selection = TextSelection.collapsed(offset: result.content.length);
      case FixedPromptSequenceRunnerAction.sendStep:
        if (_messageController.text.trim() == result.content.trim()) {
          _messageController.clear();
        }
        await _sendMessageContent(
          content: result.content,
          modelConfig: selectedModel,
          promptTemplate: selectedPromptTemplate,
          conversation: conversation,
          supportsReasoning: supportsReasoning,
          isStreaming: isStreaming,
        );
      case FixedPromptSequenceRunnerAction.none:
        return;
    }
  }

  /// 复用当前会话配置发送一条用户消息。
  Future<void> _sendMessageContent({
    required String content,
    required LlmModelConfig? modelConfig,
    required PromptTemplate? promptTemplate,
    required ChatConversation conversation,
    required bool supportsReasoning,
    required bool isStreaming,
  }) async {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty || modelConfig == null || isStreaming) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: trimmedContent,
          modelConfig: modelConfig,
          promptTemplate: promptTemplate,
          reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
          reasoningEffort: conversation.reasoningEffort,
        );
  }

  /// 弹出添加到收藏夹对话框，并在用户确认后执行收藏。
  Future<void> _showAddToFavoritesDialog(
    BuildContext context,
    ChatMessage assistantMessage,
    ChatConversation conversation,
  ) async {
    // 如果已收藏，提示取消
    final favoritesController = ref.read(favoritesProvider.notifier);
    if (favoritesController.isFavorited(assistantMessage.content)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已取消收藏'),
          action: SnackBarAction(label: '撤销', onPressed: () {}),
        ),
      );
      // 找到并删除对应收藏
      final allFavorites = ref.read(favoritesProvider);
      final existing = allFavorites
          .where((f) => f.assistantContent == assistantMessage.content)
          .firstOrNull;
      if (existing != null) {
        favoritesController.remove(existing.id);
      }
      return;
    }

    // 查找上一条用户消息
    final messages = conversation.messages;
    final assistantIndex = messages.indexWhere(
      (m) => m.id == assistantMessage.id,
    );
    final userMessage = assistantIndex > 0
        ? messages
              .sublist(0, assistantIndex)
              .lastWhere(
                (m) => m.role == ChatMessageRole.user,
                orElse: () => messages[0],
              )
        : null;

    if (!context.mounted) return;
    final selectedCollectionId = await showDialog<String>(
      context: context,
      builder: (context) =>
          AddToFavoritesDialog(assistantContent: assistantMessage.content),
    );

    if (selectedCollectionId == null || !mounted) {
      return;
    }

    favoritesController.add(
      userMessageContent: userMessage?.content ?? '',
      assistantContent: assistantMessage.content,
      assistantReasoningContent: assistantMessage.reasoningContent,
      assistantModelDisplayName:
          assistantMessage.resolvedAssistantModelDisplayName,
      // '' 表示用户选择了未分类
      collectionId: selectedCollectionId.isEmpty ? null : selectedCollectionId,
      sourceConversationId: conversation.id,
      sourceConversationTitle: conversation.resolvedTitle,
    );

    if (!mounted) return;
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已收藏')));
  }

  /// 弹出会话重命名对话框并提交新标题。
  Future<void> _showRenameDialog(
    BuildContext context,
    String initialTitle,
  ) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return RenameConversationDialog(initialTitle: initialTitle);
      },
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation(nextTitle.trim());
  }

  /// 新建会话后把输入框清空，并把视图滚回底部。
  Future<void> _createConversationAndScroll() async {
    await ref.read(chatSessionsProvider.notifier).createConversation();
    if (!mounted) {
      return;
    }

    _messageController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(jump: true);
    });
  }

  /// 根据会话内容变化决定是否自动滚动到末尾。
  void _scheduleScrollSync({
    required String conversationId,
    required List<ChatMessage> messages,
    required bool isStreaming,
  }) {
    final signature = [
      conversationId,
      messages.length,
      messages.lastOrNull?.content.length ?? 0,
      messages.lastOrNull?.reasoningContent.length ?? 0,
      isStreaming,
    ].join('|');

    if (_lastConversationId != conversationId) {
      _lastConversationId = conversationId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToBottom(jump: true);
      });
    } else if (_lastRenderSignature != signature) {
      final shouldAutoScroll = !_showScrollToBottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (shouldAutoScroll) {
          _scrollToBottom();
        }
      });
    }

    _lastRenderSignature = signature;
  }

  /// 缓存当前可见列表所需的索引信息，避免滚动监听里重复全量计算。
  void _cacheVisibleMessageMetadata(
    List<ChatMessage> messages,
    List<ChatMessage> userMessages,
  ) {
    _latestMessages = messages;
    _latestUserMessages = userMessages;
    _latestMessageIndexById = <String, int>{
      for (var index = 0; index < messages.length; index += 1)
        messages[index].id: index,
    };
    _latestUserMessageIndexes = <int>[
      for (var index = 0; index < messages.length; index += 1)
        if (messages[index].role == ChatMessageRole.user) index,
    ];
  }

  /// 滚动到消息列表底部；可选择直接跳转或平滑动画。
  Future<void> _scrollToBottom({bool jump = false}) async {
    if (_latestMessages.isEmpty || !_messageItemScrollController.isAttached) {
      return;
    }

    final targetIndex = _latestMessages.length - 1;
    if (jump) {
      _messageItemScrollController.jumpTo(index: targetIndex, alignment: 0);
      _scheduleVisibleItemsSync();
      return;
    }

    await _messageItemScrollController.scrollTo(
      index: targetIndex,
      alignment: 0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    _scheduleVisibleItemsSync();
  }

  /// 滚动到某条指定消息，并刷新当前激活锚点。
  Future<void> _scrollToMessage(String messageId) async {
    final targetIndex = _latestMessageIndexById[messageId];
    if (targetIndex == null || !_messageItemScrollController.isAttached) {
      return;
    }

    await _messageItemScrollController.scrollTo(
      index: targetIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  /// 根据当前可见项更新“滚到底部”按钮和激活锚点。
  void _handleVisibleItemsChanged() {
    if (!mounted) {
      return;
    }

    final positions =
        _messageItemPositionsListener.itemPositions.value
            .where((position) {
              return position.index >= 0 &&
                  position.index < _latestMessages.length;
            })
            .toList(growable: false)
          ..sort((left, right) => left.index.compareTo(right.index));
    final nextShowScrollToBottom = _resolveShowScrollToBottom(positions);
    final nextActiveAnchorMessageId = _resolveActiveAnchorMessageId(positions);

    if (_showScrollToBottom == nextShowScrollToBottom &&
        _activeAnchorMessageId == nextActiveAnchorMessageId) {
      return;
    }

    setState(() {
      _showScrollToBottom = nextShowScrollToBottom;
      _activeAnchorMessageId = nextActiveAnchorMessageId;
    });
  }

  /// 在主动滚动后补一次可见项同步，避免按钮状态滞后到下一次滚动事件。
  void _scheduleVisibleItemsSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _handleVisibleItemsChanged();
    });
  }

  /// 根据可见项判断当前是否已经接近列表底部。
  bool _resolveShowScrollToBottom(List<ItemPosition> positions) {
    if (_latestMessages.isEmpty || positions.isEmpty) {
      return false;
    }

    final lastVisiblePosition = positions.where((position) {
      return position.index == _latestMessages.length - 1;
    }).firstOrNull;
    if (lastVisiblePosition == null) {
      return true;
    }

    return lastVisiblePosition.itemTrailingEdge > 1.01;
  }

  /// 根据当前可见消息位置推导出最合适的用户消息锚点。
  String? _resolveActiveAnchorMessageId(List<ItemPosition> positions) {
    if (_latestUserMessages.isEmpty || positions.isEmpty) {
      return null;
    }

    var bestVisibleAnchorId = '';
    var bestVisibleDistance = double.infinity;

    for (final position in positions) {
      final message = _latestMessages[position.index];
      if (message.role != ChatMessageRole.user) {
        continue;
      }

      final center = (position.itemLeadingEdge + position.itemTrailingEdge) / 2;
      final distance = (center - 0.5).abs();
      if (distance < bestVisibleDistance) {
        bestVisibleDistance = distance;
        bestVisibleAnchorId = message.id;
      }
    }

    if (bestVisibleAnchorId.isNotEmpty) {
      return bestVisibleAnchorId;
    }

    final firstVisibleIndex = positions.first.index;
    final lastVisibleIndex = positions.last.index;
    final nearestAboveIndex = _latestUserMessageIndexes.lastWhere(
      (index) => index <= firstVisibleIndex,
      orElse: () => -1,
    );
    if (nearestAboveIndex >= 0) {
      return _latestMessages[nearestAboveIndex].id;
    }

    final nearestBelowIndex = _latestUserMessageIndexes.firstWhere(
      (index) => index >= lastVisibleIndex,
      orElse: () => -1,
    );
    if (nearestBelowIndex >= 0) {
      return _latestMessages[nearestBelowIndex].id;
    }

    return _latestUserMessages.first.id;
  }

  /// 弹出消息编辑对话框并把修改后的内容交给控制器重算。
  Future<void> _showEditMessageDialog(
    BuildContext context, {
    required String messageId,
    required String initialContent,
  }) async {
    final nextContent = await showDialog<String>(
      context: context,
      builder: (context) {
        return EditMessageDialog(initialContent: initialContent);
      },
    );

    if (!mounted || nextContent == null || nextContent.trim().isEmpty) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: messageId, nextContent: nextContent.trim());
  }
}
