import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/fixed_prompt_sequences_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/preset_prompts_controller.dart';
import '../../settings/application/template_prompts_controller.dart';
import '../../settings/domain/models/fixed_prompt_sequence.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/llm_provider_config.dart';
import '../../settings/domain/models/preset_prompt.dart';
import '../../settings/domain/models/template_prompt.dart';
import '../application/chat_message_tree.dart';
import '../application/chat_sessions_controller.dart';
import '../application/templated_user_message_builder.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import '../../favorites/application/favorites_controller.dart';
import 'chat_scroll_controller.dart';
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
  late final FocusNode _messageFocusNode;
  late final ChatScrollController _scroll;
  final Map<String, TextEditingController> _templateVariableControllers = {};

  String? _selectedFixedPromptSequenceId;
  String? _selectedTemplatePromptId;
  int _selectedFixedPromptStepIndex = 0;
  bool _isComposerCollapsed = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageFocusNode = FocusNode();
    _scroll = ChatScrollController(
      onStateChange: () => setState(() {}),
      isMounted: () => mounted,
      onScroll: _handleScroll,
    );
    _scroll.itemPositionsListener.itemPositions.addListener(
      _scroll.handleVisibleItemsChanged,
    );
  }

  @override
  void dispose() {
    _messageFocusNode.dispose();
    _messageController.dispose();
    for (final controller in _templateVariableControllers.values) {
      controller.dispose();
    }
    _scroll.itemPositionsListener.itemPositions.removeListener(
      _scroll.handleVisibleItemsChanged,
    );
    super.dispose();
  }

  @override
  /// 构建聊天页的整体布局与交互入口。
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    final conversationSummaries = ref.watch(chatConversationSummariesProvider);
    final activeConversationId = ref.watch(activeConversationIdProvider);
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
    final presetPrompts = ref.watch(presetPromptsProvider);
    final templatePrompts = ref.watch(templatePromptsProvider);
    final activeMessages = conversation.messages;
    final excludedVisibleMessageCount = activeMessages.where((message) {
      return conversation.isMessageExcluded(message.id);
    }).length;
    final favorites = ref.watch(favoritesProvider);
    final favoritedContents = favorites.map((f) => f.assistantContent).toSet();

    final selectedModel = _resolveSelectedModel(
      modelConfigs,
      conversation.selectedModelId,
      rememberedSelections.defaultModelId,
    );
    final selectableProviders = modelProviders
        .where((provider) => provider.models.isNotEmpty)
        .toList(growable: false);
    final selectedProviderId = _resolveSelectedProviderId(
      selectableProviders,
      selectedModel,
    );
    final selectableModels = selectedProviderId == null
        ? const <LlmModelConfig>[]
        : modelConfigs
              .where((config) {
                return config.providerId == selectedProviderId;
              })
              .toList(growable: false);
    final selectedPresetPrompt = _resolveSelectedPresetPrompt(
      presetPrompts,
      conversation.selectedPresetPromptId,
      rememberedSelections.defaultPresetPromptId,
    );
    final selectedTemplatePrompt = _resolveSelectedTemplatePrompt(
      templatePrompts,
      _selectedTemplatePromptId,
    );
    _syncTemplateVariableControllers(selectedTemplatePrompt);
    final supportsReasoning = selectedModel?.supportsReasoning ?? false;
    final userMessages = activeMessages
        .where((message) {
          return message.role == ChatMessageRole.user;
        })
        .toList(growable: false);
    _scroll.cacheVisibleMessageMetadata(activeMessages, userMessages);
    _scroll.scheduleScrollSync(
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
          child: _buildHistoryPanel(
            conversationSummaries,
            activeConversationId: activeConversationId,
            hasDraftConversation: !conversation.hasMessages,
            isBusy: isBusy,
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: isBusy ? null : _createConversationAndScroll,
          tooltip: '新建对话',
          icon: const Icon(Icons.add_comment_outlined),
        ),
        IconButton(
          onPressed: isBusy
              ? null
              : () => _showCheckpointsDialog(
                  context,
                  selectedModel: selectedModel,
                  selectedPresetPrompt: selectedPresetPrompt,
                  supportsReasoning: supportsReasoning,
                ),
          tooltip: '对话检查点',
          icon: const Icon(Icons.memory_rounded),
        ),
        IconButton(
          onPressed: isBusy
              ? null
              : () => _showRenameDialog(context, conversation.resolvedTitle),
          tooltip: '修改对话标题',
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 使用 MediaQuery 获取窗口物理宽度，与 AppShellScaffold 的
          // LayoutBuilder 判断保持一致，避免因 NavigationRail 占位导致
          // 内层宽度缩水 69px 而产生判断偏差。
          final showSidePanels =
              MediaQuery.of(context).size.width >= AppBreakpoints.compact;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSidePanels) ...[
                  const ChatActivityBar(),
                  ChatSidebarPanel(
                    content: _buildHistoryPanel(
                      conversationSummaries,
                      activeConversationId: activeConversationId,
                      hasDraftConversation: !conversation.hasMessages,
                      isBusy: isBusy,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ChatWorkspace(
                    conversation: conversation,
                    messages: activeMessages,
                    hasModels: modelConfigs.isNotEmpty,
                    modelProviders: selectableProviders,
                    modelConfigs: selectableModels,
                    selectedProviderId: selectedProviderId,
                    selectedModel: selectedModel,
                    presetPrompts: presetPrompts,
                    selectedPresetPrompt: selectedPresetPrompt,
                    userMessages: userMessages,
                    activeAnchorMessageId: _scroll.activeAnchorMessageId,
                    messageController: _messageController,
                    messageFocusNode: _messageFocusNode,
                    templatePrompts: templatePrompts,
                    selectedTemplatePrompt: selectedTemplatePrompt,
                    templateVariableControllers: _templateVariableControllers,
                    messageItemScrollController: _scroll.itemScrollController,
                    messageItemPositionsListener: _scroll.itemPositionsListener,
                    isComposerCollapsed: _isComposerCollapsed,
                    reasoningEnabled:
                        supportsReasoning && conversation.reasoningEnabled,
                    reasoningEffort: conversation.reasoningEffort,
                    supportsReasoning: supportsReasoning,
                    autoRetryEnabled: conversation.autoRetryEnabled,
                    isBusy: isBusy,
                    isStreaming: isStreaming,
                    isAutoRetryWaiting: isAutoRetryWaiting,
                    errorMessage: errorMessage,
                    errorMessageAssistantId: errorMessageAssistantId,
                    emptyReplyAssistantId: emptyReplyAssistantId,
                    errorModelDisplayName: selectedModel?.displayName ?? '模型',
                    showScrollToBottom: _scroll.showScrollToBottom,
                    autoRetryCount: autoRetryCount,
                    excludedMessageCount: excludedVisibleMessageCount,
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
                    onDeleteMessage: (message) async {
                      await _showDeleteMessageDialog(context, message);
                    },
                    onToggleRequestExclusion: (message) {
                      ref
                          .read(chatSessionsProvider.notifier)
                          .setMessagesExcluded(
                            messageIds: [message.id],
                            excluded: !conversation.isMessageExcluded(
                              message.id,
                            ),
                          );
                    },
                    onProviderSelected: (providerId) {
                      _handleProviderSelected(providerId, selectableProviders);
                    },
                    onModelSelected: (modelId) {
                      _handleModelSelected(modelId);
                    },
                    onPresetPromptSelected: (presetPromptId) {
                      _handlePresetPromptSelected(presetPromptId);
                    },
                    onTemplatePromptSelected: (templatePromptId) {
                      _handleTemplatePromptSelected(
                        templatePromptId,
                        templatePrompts,
                      );
                    },
                    onToggleComposerCollapsed: _toggleComposerCollapsed,
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
                    onAutoRetryEnabledChanged: (value) {
                      ref
                          .read(chatSessionsProvider.notifier)
                          .updateActiveConversationPreferences(
                            autoRetryEnabled: value,
                          );
                    },
                    onOpenFixedPromptSequenceRunner: () async {
                      await _showFixedPromptSequenceRunnerDialog(
                        context,
                        fixedPromptSequences: fixedPromptSequences,
                        selectedModel: selectedModel,
                        selectedPresetPrompt: selectedPresetPrompt,
                        conversation: conversation,
                        supportsReasoning: supportsReasoning,
                        isBusy: isBusy,
                      );
                    },
                    onOpenMessageFilter: () async {
                      await _showMessageRequestFilterDialog(context);
                    },
                    onScrollToBottomPressed: _scroll.scrollToBottom,
                    onSelectMessage: _scroll.scrollToMessage,
                    onSelectMessageVersion: (parentId, messageId) async {
                      await ref
                          .read(chatSessionsProvider.notifier)
                          .selectMessageVersion(
                            parentId: parentId,
                            messageId: messageId,
                          );
                    },
                    onSendPressed: selectedModel == null || isBusy
                        ? null
                        : () async {
                            final templatedMessage = buildTemplatedUserMessage(
                              body: _messageController.text,
                              templatePrompt: selectedTemplatePrompt,
                              variableValues: _resolveTemplatePromptValues(
                                selectedTemplatePrompt,
                              ),
                            );
                            if (templatedMessage.content.trim().isEmpty) {
                              return;
                            }

                            _messageController.clear();
                            await _sendMessageContent(
                              content: templatedMessage.content,
                              userMessageSegments:
                                  templatedMessage.userMessageSegments,
                              modelConfig: selectedModel,
                              presetPrompt: selectedPresetPrompt,
                              conversation: conversation,
                              supportsReasoning: supportsReasoning,
                              isBusy: isBusy,
                            );
                          },
                    onStopStreaming: isStreaming || isAutoRetryWaiting
                        ? () async {
                            await _showStopStreamingDialog(context);
                          }
                        : null,
                    onFavoritePressed: (message) => _showAddToFavoritesDialog(
                      context,
                      message,
                      conversation,
                    ),
                    favoritedAssistantContents: favoritedContents,
                    onScroll: _handleScroll,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 按时间分组会话摘要，供侧栏渲染。
  List<ChatConversationSummaryGroup> _buildConversationGroups(
    List<ChatConversationSummary> summaries,
  ) {
    return groupConversationSummariesByUpdatedAt(summaries);
  }

  /// 构建历史会话面板，供 endDrawer（紧凑模式）和 ChatSidebarPanel
  /// （宽屏模式）共享使用。
  Widget _buildHistoryPanel(
    List<ChatConversationSummary> conversationSummaries, {
    required String activeConversationId,
    required bool hasDraftConversation,
    required bool isBusy,
  }) {
    return ConversationHistoryPanel(
      groups: _buildConversationGroups(conversationSummaries),
      activeConversationId: activeConversationId,
      hasDraftConversation: hasDraftConversation,
      onCreateConversation:
          isBusy ? null : () => _createConversationAndScroll(),
      onConversationSelected: (conversationId) {
        if (isBusy) {
          return;
        }
        ref
            .read(chatSessionsProvider.notifier)
            .selectConversation(conversationId);
      },
    );
  }

  /// 解析当前会话应使用的模型配置，并在缺省时回退到默认项。
  LlmModelConfig? _resolveSelectedModel(
    List<LlmModelConfig> modelConfigs,
    String? selectedModelId,
    String? rememberedModelId,
  ) {
    if (modelConfigs.isEmpty) {
      return null;
    }

    final conversationSelected = modelConfigs.where((config) {
      return config.id == selectedModelId;
    }).firstOrNull;
    if (conversationSelected != null) {
      return conversationSelected;
    }

    final rememberedSelected = modelConfigs.where((config) {
      return config.id == rememberedModelId;
    }).firstOrNull;

    if (rememberedSelected != null) {
      return rememberedSelected;
    }

    return modelConfigs.first;
  }

  String? _resolveSelectedProviderId(
    List<LlmProviderConfig> providers,
    LlmModelConfig? selectedModel,
  ) {
    if (providers.isEmpty) {
      return null;
    }
    if (selectedModel != null &&
        providers.any((provider) => provider.id == selectedModel.providerId)) {
      return selectedModel.providerId;
    }
    return providers.first.id;
  }

  /// 解析当前会话应使用的前置 Prompt，并在缺省时回退到最近一次选择。
  PresetPrompt? _resolveSelectedPresetPrompt(
    List<PresetPrompt> presetPrompts,
    String? selectedPresetPromptId,
    String? rememberedPresetPromptId,
  ) {
    if (selectedPresetPromptId == noPresetPromptSelectedId) {
      return null;
    }

    final conversationSelected = presetPrompts.where((template) {
      return template.id == selectedPresetPromptId;
    }).firstOrNull;
    if (conversationSelected != null) {
      return conversationSelected;
    }

    return presetPrompts.where((template) {
      return template.id == rememberedPresetPromptId;
    }).firstOrNull;
  }

  TemplatePrompt? _resolveSelectedTemplatePrompt(
    List<TemplatePrompt> templatePrompts,
    String? selectedTemplatePromptId,
  ) {
    if (selectedTemplatePromptId == null) {
      return null;
    }
    return templatePrompts.where((templatePrompt) {
      return templatePrompt.id == selectedTemplatePromptId;
    }).firstOrNull;
  }

  void _syncTemplateVariableControllers(TemplatePrompt? templatePrompt) {
    final activeNames =
        templatePrompt?.inputVariables
            .map((variable) => variable.name)
            .toSet() ??
        const <String>{};
    final removedNames = _templateVariableControllers.keys
        .where((name) => !activeNames.contains(name))
        .toList(growable: false);
    for (final name in removedNames) {
      _templateVariableControllers.remove(name)?.dispose();
    }

    if (templatePrompt == null) {
      return;
    }

    for (final variable in templatePrompt.inputVariables) {
      _templateVariableControllers.putIfAbsent(
        variable.name,
        () => TextEditingController(),
      );
    }
  }

  void _handleTemplatePromptSelected(
    String? templatePromptId,
    List<TemplatePrompt> templatePrompts,
  ) {
    setState(() {
      _selectedTemplatePromptId = templatePromptId;
      _syncTemplateVariableControllers(
        _resolveSelectedTemplatePrompt(templatePrompts, templatePromptId),
      );
    });
  }

  void _toggleComposerCollapsed() {
    setState(() {
      _isComposerCollapsed = !_isComposerCollapsed;
    });
  }

  void _handleScroll() {
    setState(() {});
  }

  void _handleModelSelected(String modelId) {
    ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(selectedModelId: modelId);
    ref.read(chatDefaultsProvider.notifier).rememberModelId(modelId);
  }

  void _handleProviderSelected(
    String providerId,
    List<LlmProviderConfig> providers,
  ) {
    final provider = providers
        .where((item) => item.id == providerId)
        .firstOrNull;
    final targetModelId = provider?.models.firstOrNull?.id;
    if (targetModelId == null) {
      return;
    }
    _handleModelSelected(targetModelId);
  }

  void _handlePresetPromptSelected(String? presetPromptId) {
    ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId:
              presetPromptId ?? noPresetPromptSelectedId,
        );
    ref
        .read(chatDefaultsProvider.notifier)
        .rememberPresetPromptId(presetPromptId);
  }

  Map<String, String> _resolveTemplatePromptValues(
    TemplatePrompt? templatePrompt,
  ) {
    if (templatePrompt == null) {
      return const {};
    }

    return {
      for (final variable in templatePrompt.inputVariables)
        variable.name: (() {
          final typedValue =
              _templateVariableControllers[variable.name]?.text.trim() ?? '';
          return typedValue.isEmpty ? variable.defaultValue : typedValue;
        })(),
    };
  }

  /// 弹出固定顺序提示词运行器，并在关闭后同步输入框或直接发送当前步骤。
  Future<void> _showFixedPromptSequenceRunnerDialog(
    BuildContext context, {
    required List<FixedPromptSequence> fixedPromptSequences,
    required LlmModelConfig? selectedModel,
    required PresetPrompt? selectedPresetPrompt,
    required ChatConversation conversation,
    required bool supportsReasoning,
    required bool isBusy,
  }) async {
    final result = await showDialog<FixedPromptSequenceRunnerResult>(
      context: context,
      builder: (context) {
        return FixedPromptSequenceRunnerDialog(
          sequences: fixedPromptSequences,
          initialSelectedSequenceId: _selectedFixedPromptSequenceId,
          initialStepIndex: _selectedFixedPromptStepIndex,
          canSendDirectly: selectedModel != null && !isBusy,
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
          presetPrompt: selectedPresetPrompt,
          conversation: conversation,
          supportsReasoning: supportsReasoning,
          isBusy: isBusy,
        );
      case FixedPromptSequenceRunnerAction.none:
        return;
    }
  }

  /// 复用当前会话配置发送一条用户消息。
  Future<void> _sendMessageContent({
    required String content,
    required LlmModelConfig? modelConfig,
    required PresetPrompt? presetPrompt,
    required ChatConversation conversation,
    required bool supportsReasoning,
    required bool isBusy,
    List<UserMessageSegment> userMessageSegments = const [],
  }) async {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty || modelConfig == null || isBusy) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: trimmedContent,
          userMessageSegments: userMessageSegments,
          modelConfig: modelConfig,
          presetPrompt: presetPrompt,
          reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
          reasoningEffort: conversation.reasoningEffort,
        );
  }

  Future<void> _showCheckpointsDialog(
    BuildContext context, {
    required LlmModelConfig? selectedModel,
    required PresetPrompt? selectedPresetPrompt,
    required bool supportsReasoning,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return ConversationCheckpointsDialog(
          selectedModel: selectedModel,
          selectedPresetPrompt: selectedPresetPrompt,
          supportsReasoning: supportsReasoning,
        );
      },
    );
  }

  Future<void> _showMessageRequestFilterDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return const MessageRequestFilterDialog();
      },
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
    final messenger = ScaffoldMessenger.of(context);
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
    messenger.showSnackBar(const SnackBar(content: Text('已收藏')));
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
      _scroll.scrollToBottom(jump: true);
    });
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

  Future<void> _showStopStreamingDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return const StopStreamingConfirmDialog();
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await ref.read(chatSessionsProvider.notifier).stopStreaming();
  }

  Future<void> _showDeleteMessageDialog(
    BuildContext context,
    ChatMessage message,
  ) async {
    final tree = resolveMessageTreeState(
      ref.read(activeChatConversationProvider),
    );
    final parentId = message.parentId ?? rootConversationParentId;
    final siblingCount = tree.nodes.where((node) {
      return (node.parentId ?? rootConversationParentId) == parentId;
    }).length;
    final scope = await showDialog<ChatMessageDeletionScope>(
      context: context,
      builder: (context) {
        return DeleteMessageDialog(
          role: message.role,
          siblingCount: siblingCount,
        );
      },
    );

    if (!mounted || scope == null) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .deleteMessage(messageId: message.id, scope: scope);
  }
}
