import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_data.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import '../application/chat_composer_command.dart';
import '../application/chat_message_tree.dart';
import '../application/chat_sessions_controller.dart';
import '../application/chat_sidebar_controller.dart';
import '../application/composer_collapsed_controller.dart';
import '../application/composer_draft_controller.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/chat_message_parent.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import '../application/chat_favorite_intent_command.dart';
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

  /// 模板变量字段当前绑定的模板 ID（变量名 -> templateId），用于判断是否需要重绑。
  final Map<String, String> _templateVariableTemplateIds = {};

  /// 模板变量字段当前的 listener（变量名 -> listener），重绑前先解绑旧的。
  final Map<String, VoidCallback> _templateVariableListeners = {};

  String? _selectedFixedPromptSequenceId;
  int _selectedFixedPromptStepIndex = 0;

  /// 正在以编程方式把 composer draft 投影到 body/variable controllers，
  /// 期间抑制 listener 回写，避免 build/恢复时把 input 值写回 provider。
  bool _isApplyingComposerDraft = false;

  String? _editingMessageId;

  /// 会话级草稿在进入编辑前的快照，取消编辑时投影回 controllers 恢复。
  /// 编辑事务为页面瞬态：取消/切换/销毁即丢弃，从不写回会话级草稿。
  ComposerDraft? _preEditDraft;

  /// 进入编辑前的折叠状态，取消编辑时恢复（绝不放进会话级 ComposerDraft）。
  bool _preEditCollapsed = false;

  /// 页面本地编辑草稿：编辑期间 body/模板/变量的唯一来源，独立于会话级 draft。
  ComposerDraft? _editingDraft;

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
    // 会话切换时丢弃页面编辑事务（旧会话 session draft 保持原值），再把目标
    // draft 投影到 page controllers。fireImmediately 统一首次挂载与会话切换为
    // 一个路径；controller 赋值需在首帧后（避免帧内副作用），用带 mounted 与
    // conversationId 校验的 post-frame 调度。
    ref.listenManual<String>(activeConversationIdProvider, (prev, next) {
      // 切换即丢弃编辑事务；旧会话的 session draft 从未被编辑写入，保持原值。
      setState(() {
        _editingMessageId = null;
        _editingDraft = null;
        _preEditDraft = null;
        _preEditCollapsed = false;
      });
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
    final template = resolveSelectedTemplatePrompt(
      ref.read(templatePromptsProvider),
      effectiveDraft.selectedTemplatePromptId,
    );
    _syncTemplateVariableControllers(template, draft: effectiveDraft);
    _isApplyingComposerDraft = false;
  }

  void _onBodyChanged() {
    if (_isApplyingComposerDraft) return;
    if (_editingMessageId != null) {
      // 编辑中只写页面本地草稿，绝不污染会话级 draft。
      setState(() {
        _editingDraft = (_editingDraft ?? ComposerDraft.empty).copyWith(
          body: _messageController.text,
        );
      });
      return;
    }
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
    // 预设 Prompt 只用于动作区/对话框（检查点、发送），不属于 read-model，
    // 仍在页面按 build 快照解析，避免回调触发时使用与 build 时不同的预设。
    final presetPrompts = ref.watch(presetPromptsProvider);
    final selectedPresetPrompt = resolveSelectedPresetPrompt(
      presetPrompts,
      conversation.selectedPresetPromptId,
    );
    // 页面编辑草稿为空时用会话级草稿；编辑中覆盖模板选择由 compose 完成。
    final editingDraft = _editingDraft ?? ComposerDraft.empty;
    final workspaceState = ChatWorkspaceViewState.compose(
      readModel: readModel,
      editingDraft: editingDraft,
      isEditingMessage: _editingMessageId != null,
      templatePrompts: readModel.composer.templatePrompts,
    );
    final workspaceBindings = _buildWorkspaceBindings(
      conversation: conversation,
      composer: workspaceState.composer,
      selectedPresetPrompt: selectedPresetPrompt,
    );

    // 模板变量输入框跟随 effective（编辑时被覆盖的）模板与对应草稿同步：
    // 编辑中读页面草稿，否则读会话级草稿，避免编辑期间的变量写入污染会话级 draft。
    _syncTemplateVariableControllers(
      workspaceState.composer.selectedTemplatePrompt,
      draft:
          _editingDraft ??
          ref
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
      // 显式消息编辑事务是页面本地返回目标：系统返回先取消编辑恢复草稿，
      // 而不是把编辑中的会话交还系统退出。普通 composer 草稿不拦返回。
      hasLocalBackTarget: _editingMessageId != null,
      onLocalBack: _cancelEditMode,
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
            onPresetPromptSelected: (id) =>
                ref.read(chatComposerCommandProvider).selectPreset(id),
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
        // 使用窗口级宽度与 AppShellScaffold 保持一致：父约束已被 NavigationRail
        // 缩窄，不能拿内层 LayoutBuilder 宽度再判一次 shell。
        final showSidePanels = !AppBreakpoints.isCompactShell(context);
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
    required ChatWorkspaceComposerState composer,
    required PresetPrompt? selectedPresetPrompt,
  }) {
    final selectedModel = composer.selectedModel;
    final supportsReasoning = composer.supportsReasoning;
    final isBusy = composer.isBusy;
    final isStreaming = composer.isStreaming;
    final isAutoRetryWaiting = composer.isAutoRetryWaiting;

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
        onProviderSelected: (providerId) =>
            ref.read(chatComposerCommandProvider).selectProvider(providerId),
        onModelSelected: (modelId) =>
            ref.read(chatComposerCommandProvider).selectModel(modelId),
        onTemplatePromptSelected: (templatePromptId) {
          _handleTemplatePromptSelected(templatePromptId);
        },
        onToggleComposerCollapsed: _toggleComposerCollapsed,
        onReasoningEnabledChanged: supportsReasoning
            ? (value) => ref
                  .read(chatComposerCommandProvider)
                  .setReasoningEnabled(value)
            : null,
        onReasoningEffortChanged: supportsReasoning
            ? (value) => ref
                  .read(chatComposerCommandProvider)
                  .setReasoningEffort(value)
            : null,
        onAutoRetryEnabledChanged: (value) =>
            ref.read(chatComposerCommandProvider).setAutoRetryEnabled(value),
        onOpenFixedPromptSequenceRunner: () async {
          await _showFixedPromptSequenceRunnerDialog(
            context,
            fixedPromptSequences: composer.fixedPromptSequences,
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
                await _handleSendPressed(composer);
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
        onPresetPromptSelected: (id) =>
            ref.read(chatComposerCommandProvider).selectPreset(id),
      ),
    };
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
      _templateVariableListeners.remove(name);
      _templateVariableTemplateIds.remove(name);
    }

    if (template == null) {
      return;
    }

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
        _bindTemplateVariableListener(templateId, variable.name, controller);
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
        // 同名变量可能来自不同模板：模板切换后必须重绑 listener 捕获当前
        // templateId，否则输入仍写进旧模板名下、发送时被静默替换为默认值。
        _bindTemplateVariableListener(templateId, variable.name, existing);
      }
    }
  }

  /// 绑定/重绑模板变量字段的 listener：同一变量名切到新模板时先解绑旧
  /// listener 再绑定当前 templateId，避免输入写进错误模板名下。
  void _bindTemplateVariableListener(
    String templateId,
    String variableName,
    TextEditingController controller,
  ) {
    if (_templateVariableTemplateIds[variableName] == templateId) return;
    final previous = _templateVariableListeners[variableName];
    if (previous != null) {
      controller.removeListener(previous);
    }
    void listener() =>
        _onTemplateVariableChanged(templateId, variableName, controller);
    controller.addListener(listener);
    _templateVariableListeners[variableName] = listener;
    _templateVariableTemplateIds[variableName] = templateId;
  }

  /// 模板变量输入的统一入口：编辑中写页面本地草稿，否则写会话级 draft。
  void _onTemplateVariableChanged(
    String templateId,
    String variableName,
    TextEditingController controller,
  ) {
    if (_isApplyingComposerDraft) return;
    if (_editingMessageId != null) {
      _updateEditingTemplateVariable(templateId, variableName, controller.text);
      return;
    }
    final cid = _activeConversationIdOrNull();
    if (cid == null) return;
    ref
        .read(composerDraftProvider.notifier)
        .setTemplateVariable(cid, templateId, variableName, controller.text);
  }

  void _handleTemplatePromptSelected(String? templatePromptId) {
    final template = resolveSelectedTemplatePrompt(
      ref.read(templatePromptsProvider),
      templatePromptId,
    );
    if (_editingMessageId != null) {
      // 编辑中只改页面本地草稿，不写会话级 draft。
      setState(() {
        _editingDraft = (_editingDraft ?? ComposerDraft.empty).copyWith(
          selectedTemplatePromptId: templatePromptId,
          clearTemplateSelection: templatePromptId == null,
        );
      });
      _syncTemplateVariableControllers(
        template,
        draft: _editingDraft ?? ComposerDraft.empty,
      );
      return;
    }
    final conversationId = _activeConversationIdOrNull();
    if (conversationId == null) return;
    ref
        .read(chatComposerCommandProvider)
        .selectTemplate(conversationId, templatePromptId);
    _syncTemplateVariableControllers(
      template,
      draft: ref.read(composerDraftProvider.notifier).draftFor(conversationId),
    );
  }

  void _toggleComposerCollapsed() {
    // 编辑中且当前展开时禁止折叠，避免输入区被收起后看不到编辑内容。
    if (_editingMessageId != null && !ref.read(composerCollapsedProvider)) {
      return;
    }
    ref.read(composerCollapsedProvider.notifier).toggle();
  }

  /// 编辑中更新页面本地草稿的模板变量值（controller listener 的编辑分支）。
  void _updateEditingTemplateVariable(
    String templateId,
    String variableName,
    String value,
  ) {
    setState(() {
      final current = _editingDraft ?? ComposerDraft.empty;
      final currentById = Map<String, Map<String, String>>.from(
        current.templateVariableValuesByTemplateId,
      );
      final templateVars = Map<String, String>.from(
        currentById[templateId] ?? const <String, String>{},
      );
      templateVars[variableName] = value;
      currentById[templateId] = Map<String, String>.unmodifiable(templateVars);
      _editingDraft = current.copyWith(
        templateVariableValuesByTemplateId: currentById,
      );
    });
  }

  /// 从草稿解析发送时的模板变量值：trim 后为空则回落模板默认值。
  Map<String, String> _resolveTemplatePromptValues(
    TemplatePrompt? templatePrompt,
    ComposerDraft draft,
  ) {
    if (templatePrompt == null) {
      return const {};
    }
    final saved =
        draft.templateVariableValuesByTemplateId[templatePrompt.id] ?? const {};
    return {
      for (final variable in templatePrompt.inputVariables)
        variable.name: (() {
          final typedValue = saved[variable.name]?.trim() ?? '';
          return typedValue.isEmpty ? variable.defaultValue : typedValue;
        })(),
    };
  }

  // ── Edit Mode ──────────────────────────────────────────────────────────────

  void _enterEditMode(ChatMessage message) {
    final conversation = ref.read(activeChatConversationProvider);
    final currentDraft = ref
        .read(composerDraftProvider.notifier)
        .draftFor(conversation.id);
    setState(() {
      _preEditDraft = currentDraft;
      _preEditCollapsed = ref.read(composerCollapsedProvider);
      _editingMessageId = message.id;
      _editingDraft = _buildEditingDraft(message, currentDraft);
    });
    _applyDraftToControllers(_editingDraft ?? ComposerDraft.empty);
    _messageFocusNode.requestFocus();
  }

  /// 从目标 user message 的 segments/模板构造页面本地编辑草稿。
  ComposerDraft _buildEditingDraft(
    ChatMessage message,
    ComposerDraft currentDraft,
  ) {
    final segments = message.userMessageSegments;
    final bodyText = segments.isNotEmpty
        ? segments
              .where((s) => s.kind == UserMessageSegmentKind.body)
              .map((s) => s.text)
              .join()
        : message.content;
    final templateVariables = <String, Map<String, String>>{};
    final templateId = message.templatePromptId;
    if (templateId != null && message.templateVariableValues.isNotEmpty) {
      templateVariables[templateId] = Map.unmodifiable(
        message.templateVariableValues,
      );
    }
    return ComposerDraft(
      body: bodyText,
      selectedTemplatePromptId: templateId,
      templateVariableValuesByTemplateId: templateVariables,
    );
  }

  void _cancelEditMode() {
    final preEditDraft = _preEditDraft;
    setState(() {
      _editingMessageId = null;
      _editingDraft = null;
      _preEditDraft = null;
    });
    // 会话级草稿从未被编辑写入，故只把快照投影回 controllers，不执行写回。
    if (preEditDraft != null) {
      _applyDraftToControllers(preEditDraft);
    }
    ref
        .read(composerCollapsedProvider.notifier)
        .setCollapsed(_preEditCollapsed);
    _preEditCollapsed = false;
  }

  /// 发送/提交编辑：构造 intent 委托 command，只有 accepted 才清输入、退编辑并
  /// await completion；rejected 原样保留输入内容与编辑 banner。
  Future<void> _handleSendPressed(ChatWorkspaceComposerState composer) async {
    final conversation = ref.read(activeChatConversationProvider);
    final editingDraft = _editingMessageId != null
        ? (_editingDraft ?? ComposerDraft.empty)
        : null;
    final body = editingDraft?.body ?? _messageController.text;
    final templatePrompt = editingDraft != null
        ? resolveSelectedTemplatePrompt(
            composer.templatePrompts,
            editingDraft.selectedTemplatePromptId,
          )
        : composer.selectedTemplatePrompt;
    // 编辑与普通发送共用同一模板拼接边界，避免 send 与 UI 展示分叉。
    final intent = ChatComposerSubmitIntent(
      conversationId: conversation.id,
      body: body,
      templatePrompt: templatePrompt,
      variableValues: editingDraft != null
          ? _resolveTemplatePromptValues(templatePrompt, editingDraft)
          : _resolveTemplatePromptValues(
              templatePrompt,
              ref
                  .read(composerDraftProvider.notifier)
                  .draftFor(conversation.id),
            ),
      selectedModel: composer.selectedModel,
      selectedPresetPrompt: resolveSelectedPresetPrompt(
        ref.read(presetPromptsProvider),
        conversation.selectedPresetPromptId,
      ),
      reasoningEnabled: composer.reasoningEnabled,
      reasoningEffort: composer.reasoningEffort,
      editingMessageId: _editingMessageId,
    );
    final result = ref.read(chatComposerCommandProvider).dispatch(intent);
    if (result is ChatComposerAccepted) {
      _messageController.clear();
      if (result.wasEdit) {
        setState(() {
          _editingMessageId = null;
          _editingDraft = null;
          _preEditDraft = null;
        });
      }
      await result.completion;
    }
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
        // 若普通正文草稿 trim 后恰好等于步骤 content 才清该正文；否则原草稿保留。
        if (_messageController.text.trim() == result.content.trim()) {
          _messageController.clear();
        }
        await ref
            .read(chatComposerCommandProvider)
            .dispatchDirect(
              ChatDirectSubmitIntent(
                conversationId: ref.read(activeConversationIdProvider),
                content: result.content,
                selectedModel: selectedModel,
                selectedPresetPrompt: selectedPresetPrompt,
                reasoningEnabled:
                    supportsReasoning && conversation.reasoningEnabled,
                reasoningEffort: conversation.reasoningEffort,
              ),
            );
      case FixedPromptSequenceRunnerAction.none:
        return;
    }
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
    // 收藏 toggle 的准备/移除/恢复/新增编排收敛到 intent command，
    // 页面只 pattern-match 其结果并驱动 dialog/notification。
    final command = ref.read(chatFavoriteIntentCommandProvider);
    final result = command.beginToggle(
      conversation: conversation,
      assistantMessage: assistantMessage,
    );
    if (!context.mounted) return;

    switch (result) {
      case ChatFavoriteRemoved(:final removedEntry):
        ref
            .read(notificationBubblesProvider.notifier)
            .show(
              message: '已取消收藏',
              action: NotificationBubbleAction(
                label: '撤销',
                onPressed: () => command.restore(removedEntry),
              ),
            );
      case ChatFavoriteNeedsCollection(
        :final draftWithoutCollection,
        :final collectionOptions,
      ):
        final selectedCollectionId = await showDialog<String>(
          context: context,
          builder: (context) => AddToFavoritesDialog(
            collections: collectionOptions,
            onCreateCollection: command.createCollection,
          ),
        );
        if (!mounted || selectedCollectionId == null) return;
        command.addToCollection(draftWithoutCollection, selectedCollectionId);
        if (!mounted) return;
        ref
            .read(notificationBubblesProvider.notifier)
            .show(message: '已收藏', type: NotificationBubbleType.success);
    }
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
    await ref
        .read(chatComposerCommandProvider)
        .createConversationAndResetDraft();
    if (!mounted) {
      return;
    }

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
