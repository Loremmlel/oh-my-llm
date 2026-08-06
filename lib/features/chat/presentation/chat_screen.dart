import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_data.dart';
import 'package:oh_my_llm/features/settings/application/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import '../application/chat_message_tree.dart';
import '../application/chat_sessions_controller.dart';
import '../application/chat_sidebar_controller.dart';
import '../application/composer_collapsed_controller.dart';
import '../application/composer_draft_controller.dart';
import '../application/templated_user_message_builder.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/chat_message_parent.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import '../application/chat_favorites_facade.dart';
import 'chat_scroll_controller.dart';
import 'widgets/widgets.dart';

/// 聊天页入口，负责把会话状态、输入框和侧栏组合成完整页面。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ComposerSnapshot {
  const _ComposerSnapshot._({
    required this.bodyText,
    required this.templatePromptId,
    required this.templateVariableValues,
    required this.isComposerCollapsed,
  });

  factory _ComposerSnapshot({
    required String bodyText,
    required String? templatePromptId,
    required Map<String, String> templateVariableValues,
    required bool isComposerCollapsed,
  }) {
    return _ComposerSnapshot._(
      bodyText: bodyText,
      templatePromptId: templatePromptId,
      templateVariableValues: Map.unmodifiable(templateVariableValues),
      isComposerCollapsed: isComposerCollapsed,
    );
  }

  final String bodyText;
  final String? templatePromptId;
  final Map<String, String> templateVariableValues;
  final bool isComposerCollapsed;
}

/// 聊天页状态层，处理滚动同步、锚点定位和编辑弹窗等页面级交互。
class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TextEditingController _messageController;
  late final FocusNode _messageFocusNode;
  late final ChatScrollController _scroll;
  final Map<String, TextEditingController> _templateVariableControllers = {};

  String? _selectedFixedPromptSequenceId;
  int _selectedFixedPromptStepIndex = 0;

  /// 正在以编程方式把 composer draft 投影到 body/variable controllers，
  /// 期间抑制 listener 回写，避免 build/恢复时把 input 值写回 provider。
  bool _isApplyingComposerDraft = false;

  String? _editingMessageId;
  _ComposerSnapshot? _preEditSnapshot;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageFocusNode = FocusNode();
    _scroll = ChatScrollController();
    _scroll.itemPositionsListener.itemPositions.addListener(
      _scroll.handleVisibleItemsChanged,
    );
    _messageController.addListener(_onBodyChanged);
    // 会话切换时把目标 draft 投影到 page controllers。fireImmediately 统一首次
    // 挂载与会话切换为一个路径；controller 赋值需在首帧后（避免帧内副作用），
    // 用带 mounted 与 conversationId 校验的 post-frame 调度。
    ref.listenManual<String>(activeConversationIdProvider, (prev, next) {
      if (prev != next) {
        // 切换会话时退出编辑模式，避免上一个会话的编辑状态残留到新会话。
        _editingMessageId = null;
        _preEditSnapshot = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentId = ref.read(activeConversationIdProvider);
        if (currentId != next) return; // 会话已再次切换，丢弃
        _applyDraftToControllers(_restoreDraftFor(next));
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onBodyChanged);
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

  /// 从 Provider 读回内存草稿（仅恢复用）。
  ComposerDraft _restoreDraftFor(String conversationId) {
    return ref.read(composerDraftProvider.notifier).draftFor(conversationId);
  }

  /// 进入会话时把 [effectiveDraft] 投影到 body/template variable controllers。
  ///
  /// 编程赋值期间用一个 guard 抑制所有 listener 回写 Provider，避免帧内副作用。
  void _applyDraftToControllers(ComposerDraft effectiveDraft) {
    _isApplyingComposerDraft = true;
    _messageController.text = effectiveDraft.body;
    _messageController.selection = TextSelection.collapsed(
      offset: effectiveDraft.body.length,
    );
    final template = _resolveSelectedTemplatePrompt(
      ref.read(templatePromptsProvider),
      effectiveDraft.selectedTemplatePromptId,
    );
    _syncTemplateVariableControllers(template, draft: effectiveDraft);
    _isApplyingComposerDraft = false;
  }

  void _onBodyChanged() {
    if (_isApplyingComposerDraft) return;
    final conversationId = _activeConversationIdOrNull();
    if (conversationId == null) return;
    ref
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, _messageController.text);
  }

  String? _activeConversationIdOrNull() {
    final id = ref.read(activeConversationIdProvider);
    return id.isEmpty ? null : id;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  /// 构建聊天页的整体布局与交互入口。
  Widget build(BuildContext context) {
    // 工作区只读快照：消息面板与 composer 的全部展示值由 read-model 派生，
    // 页面不再各自 watch 二十多个 provider，也不再维护 preset/template 本地镜像。
    final readModel = ref.watch(chatWorkspaceReadModelProvider);
    final conversation = readModel.messages.conversation;
    final conversationSummaries = ref.watch(chatConversationSummariesProvider);
    final activeConversationId = ref.watch(activeConversationIdProvider);
    final isBusy = readModel.messages.isBusy;
    final selectedModel = readModel.composer.selectedModel;
    final supportsReasoning = readModel.composer.supportsReasoning;
    final activeMessages = readModel.messages.messages;
    final userMessages = readModel.messages.userMessages;
    final isStreaming = readModel.composer.isStreaming;
    final selectedTemplatePrompt = readModel.composer.selectedTemplatePrompt;
    // 预设 Prompt 只用于动作区/对话框（检查点、发送），不属于 read-model，
    // 仍在页面按 build 快照解析，避免回调触发时使用与 build 时不同的预设。
    final presetPrompts = ref.watch(presetPromptsProvider);
    final selectedPresetPrompt = _resolveSelectedPresetPrompt(
      presetPrompts,
      conversation,
    );
    // 页面本地编辑草稿在编辑开始前为空；isEditingMessage 单独来自页面编辑态。
    // 页面编辑草稿引入后，此处改为读取真实草稿以在编辑时覆盖模板选择。
    final editingDraft = ComposerDraft.empty;
    final workspaceState = ChatWorkspaceViewState.compose(
      readModel: readModel,
      editingDraft: editingDraft,
      isEditingMessage: _editingMessageId != null,
      templatePrompts: readModel.composer.templatePrompts,
    );
    final workspaceBindings = _buildWorkspaceBindings(
      conversation: conversation,
      readModel: readModel,
      selectedPresetPrompt: selectedPresetPrompt,
    );

    _syncTemplateVariableControllers(
      selectedTemplatePrompt,
      draft: ref
          .read(composerDraftProvider.notifier)
          .draftFor(activeConversationId),
    );
    _scroll.cacheVisibleMessageMetadata(activeMessages, userMessages);
    final pendingScrollId = ref.watch(
      chatSessionsProvider.select((state) => state.pendingScrollToMessageId),
    );
    _scroll.scheduleScrollSync(
      conversationId: conversation.id,
      messages: activeMessages,
      isStreaming: isStreaming,
      skipJumpToBottom: pendingScrollId != null,
    );

    if (pendingScrollId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _scroll.scrollToMessage(pendingScrollId);
        if (!mounted) return;
        ref.read(chatSessionsProvider.notifier).clearPendingScrollToMessageId();
      });
    }

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
        workspaceState: workspaceState,
        workspaceBindings: workspaceBindings,
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
            selectedPresetPromptId: ref
                .read(activeChatConversationProvider)
                .selectedPresetPromptId,
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
    required ChatWorkspaceViewState workspaceState,
    required ChatWorkspaceBindings workspaceBindings,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 MediaQuery 获取窗口物理宽度，与 AppShellScaffold 的
        // LayoutBuilder 判断保持一致，避免因 NavigationRail 占位导致
        // 内层宽度缩水 69px 而产生判断偏差。
        final showSidePanels =
            MediaQuery.of(context).size.width >= AppBreakpoints.compact;
        // 移动端（紧凑布局）缩小四周 Padding，给消息区与输入区让出更多宽度。
        final isCompact = !showSidePanels;

        return Padding(
          padding: EdgeInsets.all(isCompact ? 6 : 12),
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
                child: ChatWorkspace(
                  state: workspaceState,
                  bindings: workspaceBindings,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 把工作区 UI 回调与资源按 [ChatWorkspaceBindings] 三分组归拢。
  ///
  /// bindings 只在 build 时组合、不持久化；每次 build 重建以捕获最新
  /// 编辑态/会话引用。发送、服务商/模型选择、reasoning/auto-retry 等逻辑
  /// 与既往一致，仅按分组放置。
  ChatWorkspaceBindings _buildWorkspaceBindings({
    required ChatConversation conversation,
    required ChatWorkspaceReadModel readModel,
    required PresetPrompt? selectedPresetPrompt,
  }) {
    final selectedModel = readModel.composer.selectedModel;
    final supportsReasoning = readModel.composer.supportsReasoning;
    final isBusy = readModel.messages.isBusy;
    final isStreaming = readModel.composer.isStreaming;
    final isAutoRetryWaiting = readModel.composer.isAutoRetryWaiting;
    final selectableProviders = readModel.composer.modelProviders;
    final selectedTemplatePrompt = readModel.composer.selectedTemplatePrompt;

    return ChatWorkspaceBindings(
      messages: ChatWorkspaceMessageBindings(
        onEditMessage: (message) {
          _enterEditMode(message);
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
        onSelectMessageVersion: (parentId, messageId) async {
          await ref
              .read(chatSessionsProvider.notifier)
              .selectMessageVersion(parentId: parentId, messageId: messageId);
        },
        onFavoritePressed: (message) =>
            _showAddToFavoritesDialog(context, message, conversation),
      ),
      composer: ChatWorkspaceComposerBindings(
        messageController: _messageController,
        messageFocusNode: _messageFocusNode,
        templateVariableControllers: _templateVariableControllers,
        onProviderSelected: (providerId) {
          _handleProviderSelected(providerId, selectableProviders);
        },
        onModelSelected: _handleModelSelected,
        onTemplatePromptSelected: (templatePromptId) {
          _handleTemplatePromptSelected(templatePromptId);
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
              .updateActiveConversationPreferences(autoRetryEnabled: value);
        },
        onOpenFixedPromptSequenceRunner: () async {
          await _showFixedPromptSequenceRunnerDialog(
            context,
            fixedPromptSequences: readModel.composer.fixedPromptSequences,
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

                if (_editingMessageId != null) {
                  final editId = _editingMessageId!;
                  setState(() {
                    _editingMessageId = null;
                    _preEditSnapshot = null;
                  });
                  await ref
                      .read(chatSessionsProvider.notifier)
                      .editMessage(
                        messageId: editId,
                        nextContent: templatedMessage.content,
                        userMessageSegments:
                            templatedMessage.userMessageSegments,
                        templatePromptId: selectedTemplatePrompt?.id,
                        templateVariableValues: _resolveTemplatePromptValues(
                          selectedTemplatePrompt,
                        ),
                      );
                } else {
                  await _sendMessageContent(
                    content: templatedMessage.content,
                    userMessageSegments: templatedMessage.userMessageSegments,
                    modelConfig: selectedModel,
                    presetPrompt: selectedPresetPrompt,
                    conversation: conversation,
                    supportsReasoning: supportsReasoning,
                    isBusy: isBusy,
                    templatePromptId: selectedTemplatePrompt?.id,
                    templateVariableValues: _resolveTemplatePromptValues(
                      selectedTemplatePrompt,
                    ),
                  );
                }
              },
        onStopStreaming: isStreaming || isAutoRetryWaiting
            ? () async {
                await _showStopStreamingDialog(context);
              }
            : null,
        onCancelEdit: _editingMessageId != null ? _cancelEditMode : null,
      ),
      scroll: ChatWorkspaceScrollBindings(
        activeAnchorMessageIdListenable: _scroll.activeAnchorMessageIdNotifier,
        showScrollToBottomListenable: _scroll.showScrollToBottomNotifier,
        messageItemScrollController: _scroll.itemScrollController,
        messageItemPositionsListener: _scroll.itemPositionsListener,
        onScrollToBottomPressed: _scroll.scrollToBottom,
        onSelectMessage: _scroll.scrollToMessage,
      ),
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
        selectedPresetPromptId: ref
            .read(activeChatConversationProvider)
            .selectedPresetPromptId,
        onPresetPromptSelected: _handlePresetPromptSelected,
      ),
    };
  }

  // ── Resolvers ──────────────────────────────────────────────────────────────

  /// 解析当前会话应使用的预设 Prompt。
  ///
  /// 预设选择只读 conversation 持久字段，不再维护本地镜像，避免双写不同步。
  PresetPrompt? _resolveSelectedPresetPrompt(
    List<PresetPrompt> presetPrompts,
    ChatConversation conversation,
  ) {
    final effectiveId = conversation.selectedPresetPromptId;
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

  void _syncTemplateVariableControllers(
    TemplatePrompt? template, {
    required ComposerDraft draft,
  }) {
    final activeNames =
        template?.inputVariables.map((v) => v.name).toSet() ?? const <String>{};
    final removedNames = _templateVariableControllers.keys
        .where((name) => !activeNames.contains(name))
        .toList(growable: false);
    for (final name in removedNames) {
      _templateVariableControllers.remove(name)?.dispose();
    }

    if (template == null) {
      return;
    }

    final controllerRef = ref.read(composerDraftProvider.notifier);
    final conversationId = _activeConversationIdOrNull();
    for (final variable in template.inputVariables) {
      final templateId = template.id;
      // 已存在也必须按当前会话 draft 重赋值，不能因 key 存在直接 continue，
      // 否则同名模板变量会跨会话泄漏。
      final savedValue = conversationId == null
          ? null
          : draft.templateVariableValuesByTemplateId[templateId]?[variable
                .name];
      final existing = _templateVariableControllers[variable.name];
      if (existing == null) {
        final controller = TextEditingController(
          text: savedValue ?? variable.defaultValue,
        );
        controller.addListener(() {
          if (_isApplyingComposerDraft) return;
          final cid = _activeConversationIdOrNull();
          if (cid == null) return;
          controllerRef.setTemplateVariable(
            cid,
            templateId,
            variable.name,
            controller.text,
          );
        });
        _templateVariableControllers[variable.name] = controller;
      } else {
        // 目标会话没有该变量草稿值时必须回落到模板默认值，不能只覆盖「有值」的情况，
        // 否则 B 选了同名模板但未输入时，字段会残留 A 会话上一次的值（跨会话泄漏）。
        final targetValue = savedValue ?? variable.defaultValue;
        if (existing.text != targetValue) {
          _isApplyingComposerDraft = true;
          existing.text = targetValue;
          _isApplyingComposerDraft = false;
        }
      }
    }
  }

  void _handleTemplatePromptSelected(String? templatePromptId) {
    final conversationId = _activeConversationIdOrNull();
    if (conversationId == null) return;
    final controllerRef = ref.read(composerDraftProvider.notifier);
    controllerRef.selectTemplate(conversationId, templatePromptId);
    _syncTemplateVariableControllers(
      _resolveSelectedTemplatePrompt(
        ref.read(templatePromptsProvider),
        templatePromptId,
      ),
      draft: controllerRef.draftFor(conversationId),
    );
  }

  void _toggleComposerCollapsed() {
    // 编辑中且当前展开时禁止折叠，避免输入区被收起后看不到编辑内容。
    if (_editingMessageId != null && !ref.read(composerCollapsedProvider)) {
      return;
    }
    ref.read(composerCollapsedProvider.notifier).toggle();
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
    // 只写 conversation 持久字段，不维护本地镜像；UI 由 conversation 驱动重建。
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

  // ── Edit Mode ──────────────────────────────────────────────────────────────

  void _enterEditMode(ChatMessage message) {
    final templatePrompts = ref.read(templatePromptsProvider);
    final currentBody = _messageController.text;
    final conversationId = _activeConversationIdOrNull();
    final currentTemplateId = conversationId == null
        ? null
        : ref
              .read(composerDraftProvider.notifier)
              .draftFor(conversationId)
              .selectedTemplatePromptId;
    final currentVariableValues = <String, String>{};
    if (currentTemplateId != null) {
      final currentTemplate = _resolveSelectedTemplatePrompt(
        templatePrompts,
        currentTemplateId,
      );
      if (currentTemplate != null) {
        currentVariableValues.addAll(
          _resolveTemplatePromptValues(currentTemplate),
        );
      }
    }

    setState(() {
      _preEditSnapshot = _ComposerSnapshot(
        bodyText: currentBody,
        templatePromptId: currentTemplateId,
        templateVariableValues: currentVariableValues,
        isComposerCollapsed: ref.read(composerCollapsedProvider),
      );
      _editingMessageId = message.id;
    });

    final msgTemplateId = message.templatePromptId;
    if (msgTemplateId != null) {
      final templateExists = templatePrompts.any((t) => t.id == msgTemplateId);
      if (templateExists) {
        _handleTemplatePromptSelected(msgTemplateId);
        final template = _resolveSelectedTemplatePrompt(
          templatePrompts,
          msgTemplateId,
        );
        if (template != null) {
          for (final variable in template.inputVariables) {
            final savedValue = message.templateVariableValues[variable.name];
            final controller = _templateVariableControllers[variable.name];
            if (controller != null && savedValue != null) {
              controller.text = savedValue;
            }
          }
        }
      } else {
        _handleTemplatePromptSelected(null);
      }
    } else {
      _handleTemplatePromptSelected(null);
    }

    final segments = message.userMessageSegments;
    String bodyText;
    if (segments.isNotEmpty) {
      final bodyParts = segments
          .where((s) => s.kind == UserMessageSegmentKind.body)
          .map((s) => s.text);
      bodyText = bodyParts.join();
    } else {
      bodyText = message.content;
    }
    _messageController
      ..text = bodyText
      ..selection = TextSelection.collapsed(offset: bodyText.length);

    final conversation = ref.read(activeChatConversationProvider);
    ref.read(composerDraftProvider.notifier).setBody(conversation.id, bodyText);

    _messageFocusNode.requestFocus();
  }

  void _cancelEditMode() {
    final snapshot = _preEditSnapshot;
    if (snapshot == null) return;

    setState(() {
      _editingMessageId = null;
      _preEditSnapshot = null;
    });

    _handleTemplatePromptSelected(snapshot.templatePromptId);
    if (snapshot.templatePromptId != null) {
      final template = _resolveSelectedTemplatePrompt(
        ref.read(templatePromptsProvider),
        snapshot.templatePromptId,
      );
      if (template != null) {
        for (final variable in template.inputVariables) {
          final savedValue = snapshot.templateVariableValues[variable.name];
          final controller = _templateVariableControllers[variable.name];
          if (controller != null && savedValue != null) {
            controller.text = savedValue;
          }
        }
      }
    }

    _messageController
      ..text = snapshot.bodyText
      ..selection = TextSelection.collapsed(offset: snapshot.bodyText.length);

    final conversation = ref.read(activeChatConversationProvider);
    ref
        .read(composerDraftProvider.notifier)
        .setBody(conversation.id, snapshot.bodyText);

    // 直接恢复到快照值，语义清晰且不绕过编辑保护逻辑。
    ref
        .read(composerCollapsedProvider.notifier)
        .setCollapsed(snapshot.isComposerCollapsed);
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
    String? templatePromptId,
    Map<String, String> templateVariableValues = const {},
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
          templatePromptId: templatePromptId,
          templateVariableValues: templateVariableValues,
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
    final favoritesFacade = ref.read(chatFavoritesFacadeProvider);
    final favoriteSnapshot = favoritesFacade.snapshot;
    final existing = favoriteSnapshot.findByAssistantContent(
      assistantMessage.content,
    );
    if (existing != null) {
      // 找到并删除对应收藏
      final removedFavorite = existing;
      favoritesFacade.remove(existing.id);

      if (!context.mounted) return;
      ref
          .read(notificationBubblesProvider.notifier)
          .show(
            message: '已取消收藏',
            action: NotificationBubbleAction(
              label: '撤销',
              onPressed: () => favoritesFacade.add(removedFavorite.draft),
            ),
          );
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
      builder: (context) => AddToFavoritesDialog(
        collections: favoriteSnapshot.collections,
        onCreateCollection: favoritesFacade.createCollection,
      ),
    );

    if (selectedCollectionId == null || !mounted) {
      return;
    }

    favoritesFacade.add(
      ChatFavoriteDraft(
        userMessageContent: userMessage?.content ?? '',
        assistantContent: assistantMessage.content,
        assistantReasoningContent: assistantMessage.reasoningContent,
        assistantModelDisplayName:
            assistantMessage.resolvedAssistantModelDisplayName,
        // '' 表示用户选择了未分类
        collectionId: selectedCollectionId.isEmpty
            ? null
            : selectedCollectionId,
        sourceAssistantMessageId: assistantMessage.id,
        sourceConversationId: conversation.id,
        sourceConversationTitle: conversation.resolvedTitle,
      ),
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

    // 新建会话显式重置其整个草稿（正文/模板/变量），避免残留到新会话。
    final activeId = ref.read(activeConversationIdProvider);
    ref.read(composerDraftProvider.notifier).clearDraft(activeId);
    _messageController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.scrollToBottom(jump: true);
    });
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
