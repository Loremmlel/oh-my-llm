import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../../core/providers/notification_bubble_provider.dart';
import '../../../core/widgets/notification_bubble_data.dart';
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
import '../application/chat_template_prompt_selection_controller.dart';
import '../application/chat_sidebar_controller.dart';
import '../application/composer_draft_controller.dart';
import '../application/templated_user_message_builder.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/chat_message_parent.dart';
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
  String? _selectedPresetPromptId;
  int _selectedFixedPromptStepIndex = 0;
  bool _isComposerCollapsed = false;
  bool _presetPromptNeedsInit = true;

  /// 当前正文草稿归属的会话 ID，草稿按会话隔离持久化。
  String? _draftConversationId;

  /// 已完成草稿恢复的会话 ID，避免流式重建时反复覆盖输入框。
  String? _restoredDraftForConversationId;

  /// 正在以编程方式恢复草稿，期间抑制回写，避免 build 中修改 provider。
  bool _isRestoringDraft = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageFocusNode = FocusNode();
    _scroll = ChatScrollController();
    _scroll.itemPositionsListener.itemPositions.addListener(
      _scroll.handleVisibleItemsChanged,
    );
    _messageController.addListener(_persistBodyDraft);
  }

  @override
  void dispose() {
    _messageController.removeListener(_persistBodyDraft);
    _messageFocusNode.dispose();
    _messageController.dispose();
    for (final controller in _templateVariableControllers.values) {
      controller.dispose();
    }
    _scroll.itemPositionsListener.itemPositions.removeListener(
      _scroll.handleVisibleItemsChanged,
    );
    _scroll.dispose();
    super.dispose();
  }

  /// 将当前正文写入内存草稿，供跨页面切换恢复。
  void _persistBodyDraft() {
    if (_isRestoringDraft) return;
    final conversationId = _draftConversationId;
    if (conversationId == null) return;
    ref
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, _messageController.text);
  }

  /// 会话首次挂载或切换时，从内存草稿恢复正文；流式重建（同一会话）时跳过。
  void _restoreBodyDraftIfNeeded(String? conversationId) {
    if (conversationId == null) return;
    if (_restoredDraftForConversationId == conversationId) return;
    _restoredDraftForConversationId = conversationId;
    _draftConversationId = conversationId;
    final draftBody =
        ref.read(composerDraftProvider.notifier).readBody(conversationId) ?? '';
    if (_messageController.text == draftBody) return;
    _isRestoringDraft = true;
    _messageController
      ..text = draftBody
      ..selection = TextSelection.collapsed(offset: draftBody.length);
    _isRestoringDraft = false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  /// 构建聊天页的整体布局与交互入口。
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    // 页面重入（导航切换）时本地状态会丢失，需从 conversation 恢复。
    // ref.listen 仅在 ID 变化时触发，无法覆盖「回到同一会话」的场景。
    if (_presetPromptNeedsInit) {
      _presetPromptNeedsInit = false;
      final convPresetId = conversation.selectedPresetPromptId;
      if (convPresetId != null && convPresetId != noPresetPromptSelectedId) {
        _selectedPresetPromptId = convPresetId;
      }
    }
    final conversationSummaries = ref.watch(chatConversationSummariesProvider);
    final activeConversationId = ref.watch(activeConversationIdProvider);
    // 草稿恢复会写 _messageController.text，禁止在 build 期直接执行（帧内副作用）。
    // 改为帧后回调；_restoreBodyDraftIfNeeded 自身幂等，重复调度无害。
    if (_restoredDraftForConversationId != activeConversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreBodyDraftIfNeeded(activeConversationId);
      });
    }
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
    // 模板提示词选择走全局内存级 provider，跨页面切换不丢失。
    final selectedTemplatePromptId = ref.watch(
      chatTemplatePromptSelectionProvider,
    );
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
      conversation,
    );
    final selectedTemplatePrompt = _resolveSelectedTemplatePrompt(
      templatePrompts,
      selectedTemplatePromptId,
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

    // 监听对话切换，同步本地 _selectedPresetPromptId
    ref.listen<String?>(activeConversationIdProvider, (prev, next) {
      if (prev != next && next != null) {
        final nextConversation = ref.read(activeChatConversationProvider);
        final id = nextConversation.selectedPresetPromptId;
        setState(() {
          _selectedPresetPromptId = id == noPresetPromptSelectedId ? null : id;
        });
        // 切换会话时清空模板提示词选择，避免上一会话的模板残留到新会话。
        ref.read(chatTemplatePromptSelectionProvider.notifier).clear();
      }
    });

    final sidebarState = ref.watch(chatSidebarProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: conversation.resolvedTitle,
      endDrawer: _buildEndDrawer(
        conversationSummaries: conversationSummaries,
        activeConversationId: activeConversationId,
        hasDraft: !conversation.hasMessages,
        isBusy: isBusy,
      ),
      actions: _buildActions(
        isBusy: isBusy,
        selectedModel: selectedModel,
        selectedPresetPrompt: selectedPresetPrompt,
        supportsReasoning: supportsReasoning,
        conversation: conversation,
      ),
      body: _buildBody(
        sidebarState: sidebarState,
        conversationSummaries: conversationSummaries,
        activeConversationId: activeConversationId,
        hasDraft: !conversation.hasMessages,
        isBusy: isBusy,
        conversation: conversation,
        activeMessages: activeMessages,
        modelConfigs: modelConfigs,
        selectableProviders: selectableProviders,
        selectableModels: selectableModels,
        selectedProviderId: selectedProviderId,
        selectedModel: selectedModel,
        userMessages: userMessages,
        selectedPresetPrompt: selectedPresetPrompt,
        selectedTemplatePrompt: selectedTemplatePrompt,
        templatePrompts: templatePrompts,
        supportsReasoning: supportsReasoning,
        isStreaming: isStreaming,
        isAutoRetryWaiting: isAutoRetryWaiting,
        errorMessage: errorMessage,
        errorMessageAssistantId: errorMessageAssistantId,
        emptyReplyAssistantId: emptyReplyAssistantId,
        autoRetryCount: autoRetryCount,
        excludedVisibleMessageCount: excludedVisibleMessageCount,
        fixedPromptSequences: fixedPromptSequences,
        favoritedContents: favoritedContents,
      ),
    );
  }

  /// 构建紧凑模式下的 endDrawer，包含历史会话面板和预设 Prompt 面板。
  Widget _buildEndDrawer({
    required List<ChatConversationSummary> conversationSummaries,
    required String activeConversationId,
    required bool hasDraft,
    required bool isBusy,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ChatCompactPanel(
          historyPanel: _buildHistoryPanel(
            conversationSummaries,
            activeConversationId: activeConversationId,
            hasDraftConversation: hasDraft,
            isBusy: isBusy,
          ),
          presetPanel: PresetPromptPanel(
            selectedPresetPromptId: _selectedPresetPromptId,
            onPresetPromptSelected: _handlePresetPromptSelected,
          ),
        ),
      ),
    );
  }

  /// 构建 AppBar 操作按钮区：新建对话、检查点、重命名。
  List<Widget> _buildActions({
    required bool isBusy,
    required LlmModelConfig? selectedModel,
    required PresetPrompt? selectedPresetPrompt,
    required bool supportsReasoning,
    required ChatConversation conversation,
  }) {
    return [
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
    ];
  }

  /// 构建页面主体布局：根据视口宽度决定侧栏显窄，并在宽屏模式下
  /// 通过 LayoutBuilder 保持与 AppShellScaffold 断点判定一致。
  Widget _buildBody({
    required ChatSidebarState sidebarState,
    required List<ChatConversationSummary> conversationSummaries,
    required String activeConversationId,
    required bool hasDraft,
    required bool isBusy,
    required ChatConversation conversation,
    required List<ChatMessage> activeMessages,
    required List<LlmModelConfig> modelConfigs,
    required List<LlmProviderConfig> selectableProviders,
    required List<LlmModelConfig> selectableModels,
    required String? selectedProviderId,
    required LlmModelConfig? selectedModel,
    required List<ChatMessage> userMessages,
    required PresetPrompt? selectedPresetPrompt,
    required TemplatePrompt? selectedTemplatePrompt,
    required List<TemplatePrompt> templatePrompts,
    required bool supportsReasoning,
    required bool isStreaming,
    required bool isAutoRetryWaiting,
    required String? errorMessage,
    required String? errorMessageAssistantId,
    required String? emptyReplyAssistantId,
    required int autoRetryCount,
    required int excludedVisibleMessageCount,
    required List<FixedPromptSequence> fixedPromptSequences,
    required Set<String> favoritedContents,
  }) {
    return LayoutBuilder(
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
                  content: _buildSidebarContent(
                    sidebarState.activeFunction ?? ChatSidebarFunction.history,
                    conversationSummaries: conversationSummaries,
                    activeConversationId: activeConversationId,
                    hasDraftConversation: hasDraft,
                    isBusy: isBusy,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _buildWorkspace(
                  conversation: conversation,
                  activeMessages: activeMessages,
                  modelConfigs: modelConfigs,
                  selectableProviders: selectableProviders,
                  selectableModels: selectableModels,
                  selectedProviderId: selectedProviderId,
                  selectedModel: selectedModel,
                  userMessages: userMessages,
                  selectedPresetPrompt: selectedPresetPrompt,
                  selectedTemplatePrompt: selectedTemplatePrompt,
                  templatePrompts: templatePrompts,
                  supportsReasoning: supportsReasoning,
                  isStreaming: isStreaming,
                  isAutoRetryWaiting: isAutoRetryWaiting,
                  errorMessage: errorMessage,
                  errorMessageAssistantId: errorMessageAssistantId,
                  emptyReplyAssistantId: emptyReplyAssistantId,
                  autoRetryCount: autoRetryCount,
                  excludedVisibleMessageCount: excludedVisibleMessageCount,
                  fixedPromptSequences: fixedPromptSequences,
                  favoritedContents: favoritedContents,
                  isBusy: isBusy,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建聊天主工作区，包含消息列表、输入框和所有消息操作回调。
  ///
  /// 将 [selectedPresetPrompt] 以 build 时快照传入，避免回调触发时
  /// 因外部 preset 列表变化而导致发送使用了与 build 时不同的 preset。
  Widget _buildWorkspace({
    required ChatConversation conversation,
    required List<ChatMessage> activeMessages,
    required List<LlmModelConfig> modelConfigs,
    required List<LlmProviderConfig> selectableProviders,
    required List<LlmModelConfig> selectableModels,
    required String? selectedProviderId,
    required LlmModelConfig? selectedModel,
    required List<ChatMessage> userMessages,
    required PresetPrompt? selectedPresetPrompt,
    required TemplatePrompt? selectedTemplatePrompt,
    required List<TemplatePrompt> templatePrompts,
    required bool supportsReasoning,
    required bool isStreaming,
    required bool isAutoRetryWaiting,
    required String? errorMessage,
    required String? errorMessageAssistantId,
    required String? emptyReplyAssistantId,
    required int autoRetryCount,
    required int excludedVisibleMessageCount,
    required List<FixedPromptSequence> fixedPromptSequences,
    required Set<String> favoritedContents,
    required bool isBusy,
  }) {
    return ChatWorkspace(
      conversation: conversation,
      messages: activeMessages,
      hasModels: modelConfigs.isNotEmpty,
      modelProviders: selectableProviders,
      modelConfigs: selectableModels,
      selectedProviderId: selectedProviderId,
      selectedModel: selectedModel,
      userMessages: userMessages,
      activeAnchorMessageIdListenable: _scroll.activeAnchorMessageIdNotifier,
      messageController: _messageController,
      messageFocusNode: _messageFocusNode,
      templatePrompts: templatePrompts,
      selectedTemplatePrompt: selectedTemplatePrompt,
      templateVariableControllers: _templateVariableControllers,
      messageItemScrollController: _scroll.itemScrollController,
      messageItemPositionsListener: _scroll.itemPositionsListener,
      isComposerCollapsed: _isComposerCollapsed,
      reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
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
      showScrollToBottomListenable: _scroll.showScrollToBottomNotifier,
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
        await ref.read(chatSessionsProvider.notifier).retryLatestAssistant();
      },
      onDeleteMessage: (message) async {
        await _showDeleteMessageDialog(context, message);
      },
      onToggleRequestExclusion: (message) {
        ref
            .read(chatSessionsProvider.notifier)
            .setMessagesExcluded(
              messageIds: [message.id],
              excluded: !conversation.isMessageExcluded(message.id),
            );
      },
      onProviderSelected: (providerId) {
        _handleProviderSelected(providerId, selectableProviders);
      },
      onModelSelected: _handleModelSelected,
      onTemplatePromptSelected: (templatePromptId) {
        _handleTemplatePromptSelected(templatePromptId, templatePrompts);
      },
      onToggleComposerCollapsed: _toggleComposerCollapsed,
      onReasoningEnabledChanged: supportsReasoning
          ? (value) {
              ref
                  .read(chatSessionsProvider.notifier)
                  .updateActiveConversationPreferences(reasoningEnabled: value);
            }
          : null,
      onReasoningEffortChanged: supportsReasoning
          ? (value) {
              ref
                  .read(chatSessionsProvider.notifier)
                  .updateActiveConversationPreferences(reasoningEffort: value);
            }
          : null,
      onAutoRetryEnabledChanged: (value) {
        ref
            .read(chatSessionsProvider.notifier)
            .updateActiveConversationPreferences(autoRetryEnabled: value);
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
            .selectMessageVersion(parentId: parentId, messageId: messageId);
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
              ref
                  .read(composerDraftProvider.notifier)
                  .clearBody(conversation.id);
              await _sendMessageContent(
                content: templatedMessage.content,
                userMessageSegments: templatedMessage.userMessageSegments,
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
      onFavoritePressed: (message) =>
          _showAddToFavoritesDialog(context, message, conversation),
      favoritedAssistantContents: favoritedContents,
    );
  }

  // ── Panels ─────────────────────────────────────────────────────────────────

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
      onCreateConversation: isBusy
          ? null
          : () => _createConversationAndScroll(),
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

  /// 根据当前激活的侧栏功能，构建对应的内容面板。
  Widget _buildSidebarContent(
    ChatSidebarFunction function, {
    required List<ChatConversationSummary> conversationSummaries,
    required String activeConversationId,
    required bool hasDraftConversation,
    required bool isBusy,
  }) {
    return switch (function) {
      ChatSidebarFunction.history => _buildHistoryPanel(
        conversationSummaries,
        activeConversationId: activeConversationId,
        hasDraftConversation: hasDraftConversation,
        isBusy: isBusy,
      ),
      ChatSidebarFunction.preset => PresetPromptPanel(
        selectedPresetPromptId: _selectedPresetPromptId,
        onPresetPromptSelected: _handlePresetPromptSelected,
      ),
    };
  }

  // ── Resolvers ──────────────────────────────────────────────────────────────

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

  /// 解析当前会话应使用的预设 Prompt。
  ///
  /// 优先使用本地状态，其次回退到会话级记录，
  /// 以保证直接写入 conversation 的代码路径（如测试、或历史恢复）也能正确解析。
  PresetPrompt? _resolveSelectedPresetPrompt(
    List<PresetPrompt> presetPrompts,
    ChatConversation conversation,
  ) {
    final effectiveId =
        _selectedPresetPromptId ?? conversation.selectedPresetPromptId;
    if (effectiveId == null || effectiveId == noPresetPromptSelectedId) {
      return null;
    }
    return presetPrompts.where((p) => p.id == effectiveId).firstOrNull;
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

    final draftController = ref.read(composerDraftProvider.notifier);
    final templateId = templatePrompt.id;
    for (final variable in templatePrompt.inputVariables) {
      if (_templateVariableControllers.containsKey(variable.name)) {
        continue;
      }
      final draftValue = draftController.readTemplateVariable(
        templateId,
        variable.name,
      );
      final controller = TextEditingController(
        text: draftValue ?? variable.defaultValue,
      );
      controller.addListener(() {
        draftController.setTemplateVariable(
          templateId,
          variable.name,
          controller.text,
        );
      });
      _templateVariableControllers[variable.name] = controller;
    }
  }

  void _handleTemplatePromptSelected(
    String? templatePromptId,
    List<TemplatePrompt> templatePrompts,
  ) {
    ref
        .read(chatTemplatePromptSelectionProvider.notifier)
        .select(templatePromptId);
    _syncTemplateVariableControllers(
      _resolveSelectedTemplatePrompt(templatePrompts, templatePromptId),
    );
  }

  void _toggleComposerCollapsed() {
    setState(() {
      _isComposerCollapsed = !_isComposerCollapsed;
    });
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
    setState(() {
      _selectedPresetPromptId = presetPromptId;
    });
    // 写入 conversation，保证 editMessage/retry/checkpoint 等内部操作能读取到。
    // 当预设 ID 与 conversation 中已持久化的值相同时，ChatConversation 和
    // ChatSessionsState 的 Equatable 判定相等，Riverpod 可能不触发重建，
    // 因此需要 setState 保证 UI 更新。
    ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: presetPromptId ?? noPresetPromptSelectedId,
        );
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

  // ── Dialogs & Actions ──────────────────────────────────────────────────────

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
      // 找到并删除对应收藏
      final allFavorites = ref.read(favoritesProvider);
      final existing = allFavorites
          .where((f) => f.assistantContent == assistantMessage.content)
          .firstOrNull;
      if (existing != null) {
        // 删除前保存数据供撤销使用
        final removedFavorite = existing;
        favoritesController.remove(existing.id);

        if (!context.mounted) return;
        ref
            .read(notificationBubblesProvider.notifier)
            .show(
              message: '已取消收藏',
              action: NotificationBubbleAction(
                label: '撤销',
                onPressed: () {
                  // 重新添加被删除的收藏
                  favoritesController.add(
                    userMessageContent: removedFavorite.userMessageContent,
                    assistantContent: removedFavorite.assistantContent,
                    assistantReasoningContent:
                        removedFavorite.assistantReasoningContent,
                    assistantModelDisplayName:
                        removedFavorite.assistantModelDisplayName,
                    collectionId: removedFavorite.collectionId,
                    sourceConversationId: removedFavorite.sourceConversationId,
                    sourceConversationTitle:
                        removedFavorite.sourceConversationTitle,
                  );
                },
              ),
            );
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
    ref
        .read(notificationBubblesProvider.notifier)
        .show(message: '已收藏', type: NotificationBubbleType.success);
  }

  /// 弹出会话重命名对话框并提交新标题。
  Future<void> _showRenameDialog(
    BuildContext context,
    String initialTitle,
  ) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return RenameConversationDialog(
          initialTitle: initialTitle,
          title: '修改对话标题',
          labelText: '对话标题',
        );
      },
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation(nextTitle);
  }

  /// 新建会话后把输入框清空，并把视图滚回底部。
  Future<void> _createConversationAndScroll() async {
    await ref.read(chatSessionsProvider.notifier).createConversation();
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPresetPromptId = null;
    });
    // 新建会话清空模板提示词选择。
    ref.read(chatTemplatePromptSelectionProvider.notifier).clear();
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
    final parentId = message.effectiveParentId;
    final siblingCount = tree.nodes.where((node) {
      return node.effectiveParentId == parentId;
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
