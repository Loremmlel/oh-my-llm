import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import '../application/chat_sessions_controller.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TextEditingController _messageController;
  late final ScrollController _messageScrollController;
  final GlobalKey _messagesViewportKey = GlobalKey();

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  bool _showScrollToBottom = false;
  bool _anchorRefreshQueued = false;
  String? _lastConversationId;
  String? _lastRenderSignature;
  String? _activeAnchorMessageId;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageScrollController = ScrollController()
      ..addListener(_handleMessageScrollChanged);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController
      ..removeListener(_handleMessageScrollChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatSessionsProvider);
    final conversation = chatState.activeConversation;
    final chatDefaults = ref.watch(chatDefaultsProvider);
    final modelConfigs = ref.watch(llmModelConfigsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);

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
    final userMessages = conversation.messages
        .where((message) {
          return message.role == ChatMessageRole.user;
        })
        .toList(growable: false);

    _scheduleScrollSync(
      conversation: conversation,
      isStreaming: chatState.isStreaming,
    );
    _scheduleAnchorRefresh();

    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: conversation.resolvedTitle,
      endDrawer: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _ConversationHistoryPanel(
            groups: _buildConversationGroups(chatState.conversations),
            activeConversationId: conversation.id,
            hasDraftConversation: !conversation.hasMessages,
            onCreateConversation: chatState.isStreaming
                ? null
                : () => _createConversationAndScroll(),
            onConversationSelected: (conversationId) {
              if (chatState.isStreaming) {
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
          onPressed: chatState.isStreaming
              ? null
              : _createConversationAndScroll,
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
                    child: _ConversationHistoryPanel(
                      groups: _buildConversationGroups(chatState.conversations),
                      activeConversationId: conversation.id,
                      hasDraftConversation: !conversation.hasMessages,
                      onCreateConversation: chatState.isStreaming
                          ? null
                          : () => _createConversationAndScroll(),
                      onConversationSelected: (conversationId) {
                        if (chatState.isStreaming) {
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
                  child: _ChatWorkspace(
                    conversation: conversation,
                    hasModels: modelConfigs.isNotEmpty,
                    userMessages: userMessages,
                    activeAnchorMessageId: _activeAnchorMessageId,
                    messageController: _messageController,
                    messageScrollController: _messageScrollController,
                    messagesViewportKey: _messagesViewportKey,
                    messageKeys: _messageKeys,
                    reasoningEnabled:
                        supportsReasoning && conversation.reasoningEnabled,
                    reasoningEffort: conversation.reasoningEffort,
                    supportsReasoning: supportsReasoning,
                    isStreaming: chatState.isStreaming,
                    errorMessage: chatState.errorMessage,
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
                     onSendPressed:
                         selectedModel == null || chatState.isStreaming
                         ? null
                        : () async {
                            final content = _messageController.text.trim();
                            if (content.isEmpty) {
                              return;
                            }

                            _messageController.clear();
                            await ref
                                .read(chatSessionsProvider.notifier)
                                .sendMessage(
                                  content: content,
                                  modelConfig: selectedModel,
                                  promptTemplate: selectedPromptTemplate,
                                  reasoningEnabled:
                                      supportsReasoning &&
                                      conversation.reasoningEnabled,
                                  reasoningEffort: conversation.reasoningEffort,
                                );
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

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

  LlmModelConfig? _resolveSelectedModel(
    List<LlmModelConfig> modelConfigs,
    String? selectedModelId,
    String? defaultModelId,
  ) {
    if (modelConfigs.isEmpty) {
      return null;
    }

    final selected = modelConfigs.where((config) {
      return config.id == selectedModelId;
    }).firstOrNull;

    if (selected != null) {
      return selected;
    }

    final defaultSelected = modelConfigs.where((config) {
      return config.id == defaultModelId;
    }).firstOrNull;

    return defaultSelected ?? modelConfigs.first;
  }

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

  Future<void> _showRenameDialog(
    BuildContext context,
    String initialTitle,
  ) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return _RenameConversationDialog(initialTitle: initialTitle);
      },
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation(nextTitle.trim());
  }

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

  void _scheduleScrollSync({
    required ChatConversation conversation,
    required bool isStreaming,
  }) {
    final signature = [
      conversation.id,
      conversation.messages.length,
      conversation.messages.lastOrNull?.content.length ?? 0,
      isStreaming,
    ].join('|');

    if (_lastConversationId != conversation.id) {
      _lastConversationId = conversation.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToBottom(jump: true);
      });
    } else if (_lastRenderSignature != signature) {
      final shouldAutoScroll = _isNearBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_messageScrollController.hasClients) {
          return;
        }
        if (shouldAutoScroll) {
          _scrollToBottom();
        }
      });
    }

    _lastRenderSignature = signature;
  }

  void _handleMessageScrollChanged() {
    final shouldShow = !_isNearBottom();
    if (shouldShow == _showScrollToBottom) {
      _scheduleAnchorRefresh();
    } else {
      setState(() {
        _showScrollToBottom = shouldShow;
      });
      _scheduleAnchorRefresh();
    }
  }

  bool _isNearBottom() {
    if (!_messageScrollController.hasClients) {
      return true;
    }

    final position = _messageScrollController.position;
    return position.maxScrollExtent - position.pixels < 120;
  }

  Future<void> _scrollToBottom({bool jump = false}) async {
    if (!_messageScrollController.hasClients) {
      return;
    }

    final target = _messageScrollController.position.maxScrollExtent;
    if (jump) {
      _messageScrollController.jumpTo(target);
      _scheduleAnchorRefresh();
      return;
    }

    await _messageScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    _scheduleAnchorRefresh();
  }

  Future<void> _scrollToMessage(String messageId) async {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
    _scheduleAnchorRefresh();
  }

  void _scheduleAnchorRefresh() {
    if (_anchorRefreshQueued) {
      return;
    }

    _anchorRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorRefreshQueued = false;
      _refreshActiveAnchor();
    });
  }

  void _refreshActiveAnchor() {
    if (!mounted) {
      return;
    }

    final viewportContext = _messagesViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize) {
      _setActiveAnchorMessage(null);
      return;
    }

    final userMessages = ref
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .where((message) => message.role == ChatMessageRole.user)
        .toList(growable: false);
    if (userMessages.isEmpty) {
      _setActiveAnchorMessage(null);
      return;
    }

    final viewportOffset = viewportRenderObject.localToGlobal(Offset.zero);
    final viewportRect = viewportOffset & viewportRenderObject.size;
    final viewportCenterY = viewportRect.center.dy;

    String? bestVisibleMessageId;
    var bestVisibleDistance = double.infinity;
    String? nearestAboveMessageId;
    var nearestAboveCenterY = double.negativeInfinity;
    String? nearestBelowMessageId;
    var nearestBelowCenterY = double.infinity;

    for (final message in userMessages) {
      final messageRenderObject = _messageKeys[message.id]?.currentContext
          ?.findRenderObject();
      if (messageRenderObject is! RenderBox ||
          !messageRenderObject.attached ||
          !messageRenderObject.hasSize) {
        continue;
      }

      final messageOffset = messageRenderObject.localToGlobal(Offset.zero);
      final messageRect = messageOffset & messageRenderObject.size;
      final messageCenterY = messageRect.center.dy;
      final intersectsViewport =
          messageRect.bottom >= viewportRect.top &&
          messageRect.top <= viewportRect.bottom;

      if (intersectsViewport) {
        final distance = (messageCenterY - viewportCenterY).abs();
        if (distance < bestVisibleDistance) {
          bestVisibleDistance = distance;
          bestVisibleMessageId = message.id;
        }
      }

      if (messageCenterY <= viewportCenterY &&
          messageCenterY > nearestAboveCenterY) {
        nearestAboveCenterY = messageCenterY;
        nearestAboveMessageId = message.id;
      }

      if (messageCenterY > viewportCenterY &&
          messageCenterY < nearestBelowCenterY) {
        nearestBelowCenterY = messageCenterY;
        nearestBelowMessageId = message.id;
      }
    }

    _setActiveAnchorMessage(
      bestVisibleMessageId ??
          nearestAboveMessageId ??
          nearestBelowMessageId ??
          userMessages.first.id,
    );
  }

  void _setActiveAnchorMessage(String? messageId) {
    if (_activeAnchorMessageId == messageId) {
      return;
    }

    setState(() {
      _activeAnchorMessageId = messageId;
    });
  }

  Future<void> _showEditMessageDialog(
    BuildContext context, {
    required String messageId,
    required String initialContent,
  }) async {
    final nextContent = await showDialog<String>(
      context: context,
      builder: (context) {
        return _EditMessageDialog(initialContent: initialContent);
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

class _ChatWorkspace extends StatelessWidget {
  const _ChatWorkspace({
    required this.conversation,
    required this.hasModels,
    required this.userMessages,
    required this.activeAnchorMessageId,
    required this.messageController,
    required this.messageScrollController,
    required this.messagesViewportKey,
    required this.messageKeys,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.isStreaming,
    required this.errorMessage,
    required this.showScrollToBottom,
    required this.onDismissError,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
  });

  final ChatConversation conversation;
  final bool hasModels;
  final List<ChatMessage> userMessages;
  final String? activeAnchorMessageId;
  final TextEditingController messageController;
  final ScrollController messageScrollController;
  final GlobalKey messagesViewportKey;
  final Map<String, GlobalKey> messageKeys;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool isStreaming;
  final String? errorMessage;
  final bool showScrollToBottom;
  final VoidCallback onDismissError;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final messagesCard = _buildMessagesCard(theme);
        final composerCard = _buildComposerCard(theme);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMessage != null) ...[
              _buildErrorBanner(theme),
              const SizedBox(height: 8),
            ],
            Expanded(child: messagesCard),
            const SizedBox(height: 12),
            composerCard,
          ],
        );
      },
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            title: Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            trailing: IconButton(
              onPressed: onDismissError,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              tooltip: '关闭错误提示',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesCard(ThemeData theme) {
    final latestAssistantMessage =
        conversation.messages.lastOrNull?.role == ChatMessageRole.assistant
        ? conversation.messages.lastOrNull
        : null;
    final versionInfoByMessageId = _buildMessageVersionInfoMap();

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorRightPadding = userMessages.isEmpty ? 14.0 : 52.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (conversation.messages.isEmpty)
                KeyedSubtree(
                  key: messagesViewportKey,
                  child: _EmptyConversationView(hasModels: hasModels),
                )
              else
                SingleChildScrollView(
                  key: messagesViewportKey,
                  controller: messageScrollController,
                  padding: EdgeInsets.fromLTRB(14, 14, anchorRightPadding, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final message in conversation.messages) ...[
                        KeyedSubtree(
                          key: messageKeys.putIfAbsent(
                            message.id,
                            GlobalKey.new,
                          ),
                          child: _ChatMessageBubble(
                            message: message,
                            canEdit:
                                !isStreaming &&
                                message.role == ChatMessageRole.user,
                            canRetry:
                                !isStreaming &&
                                latestAssistantMessage?.id == message.id,
                            onEditPressed: message.role == ChatMessageRole.user
                                ? () {
                                    onEditMessage(message);
                                  }
                                : null,
                            onRetryPressed:
                                latestAssistantMessage?.id == message.id
                                ? () {
                                    onRetryLatestAssistant();
                                  }
                                : null,
                            versionInfo: versionInfoByMessageId[message.id],
                            onSwitchVersion: (targetMessageId) async {
                              final versionInfo = versionInfoByMessageId[message.id];
                              if (versionInfo == null) {
                                return;
                              }
                              await onSelectMessageVersion(
                                versionInfo.parentId,
                                targetMessageId,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              if (userMessages.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _MessageAnchorRail(
                      userMessages: userMessages,
                      activeMessageId: activeAnchorMessageId,
                      maxHeight: constraints.maxHeight * 0.5,
                      onSelectMessage: onSelectMessage,
                    ),
                  ),
                ),
              if (showScrollToBottom)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    onPressed: onScrollToBottomPressed,
                    tooltip: '滚动到底部',
                    child: const Icon(Icons.arrow_downward_rounded),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Map<String, _MessageVersionInfo> _buildMessageVersionInfoMap() {
    if (conversation.messageNodes.isEmpty) {
      return const {};
    }

    final siblingsByParent = <String, List<ChatMessage>>{};
    for (final node in conversation.messageNodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      siblingsByParent.putIfAbsent(parentId, () => <ChatMessage>[]).add(node);
    }

    final result = <String, _MessageVersionInfo>{};
    for (final message in conversation.messages) {
      final parentId = message.parentId ?? rootConversationParentId;
      final siblings = siblingsByParent[parentId] ?? const <ChatMessage>[];
      if (siblings.length <= 1) {
        continue;
      }
      final index = siblings.indexWhere((item) => item.id == message.id);
      if (index == -1) {
        continue;
      }
      result[message.id] = _MessageVersionInfo(
        parentId: parentId,
        currentIndex: index,
        siblings: siblings,
      );
    }
    return result;
  }

  Widget _buildComposerCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: messageController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '输入消息',
                hintText: '输入你的问题、指令或待处理内容。',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ThinkingToggle(
                          enabled: supportsReasoning,
                          value: supportsReasoning && reasoningEnabled,
                          onChanged: onReasoningEnabledChanged,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 132,
                          child: _buildReasoningEffortSelector(compact: true),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: !hasModels || isStreaming
                      ? null
                      : () {
                          onSendPressed?.call();
                        },
                  icon: Icon(
                    isStreaming
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                  ),
                  label: Text(isStreaming ? '生成中' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasoningEffortSelector({bool compact = false}) {
    return DropdownButtonFormField<ReasoningEffort>(
      key: ValueKey(reasoningEffort),
      initialValue: reasoningEffort,
      isExpanded: true,
      items: ReasoningEffort.values
          .map((effort) {
            return DropdownMenuItem(
              value: effort,
              child: Text(_effortLabel(effort)),
            );
          })
          .toList(growable: false),
      onChanged: supportsReasoning && reasoningEnabled
          ? (value) {
              if (value != null) {
                onReasoningEffortChanged?.call(value);
              }
            }
          : null,
      decoration: InputDecoration(
        labelText: '思考负担',
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : null,
      ),
    );
  }

  String _effortLabel(ReasoningEffort effort) {
    return switch (effort) {
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'med',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh => 'xhigh',
    };
  }
}

class _ThinkingToggle extends StatelessWidget {
  const _ThinkingToggle({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = !enabled
        ? theme.colorScheme.surfaceContainerLow
        : value
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = value
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = enabled && value
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 167),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '深度思考',
              style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
            ),
            const SizedBox(width: 6),
            Theme(
              data: theme.copyWith(
                switchTheme: SwitchThemeData(
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return theme.colorScheme.surfaceContainerHighest;
                    }
                    if (states.contains(WidgetState.selected)) {
                      return theme.colorScheme.primary;
                    }
                    return theme.colorScheme.surfaceContainerHighest;
                  }),
                  trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.transparent;
                    }
                    return theme.colorScheme.outlineVariant;
                  }),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return theme.colorScheme.outline;
                    }
                    if (states.contains(WidgetState.selected)) {
                      return theme.colorScheme.onPrimary;
                    }
                    return theme.colorScheme.onSurfaceVariant;
                  }),
                ),
              ),
              child: Switch(
                value: enabled && value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改对话标题'),
      content: TextField(
        controller: _titleController,
        decoration: const InputDecoration(labelText: '对话标题'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final nextTitle = _titleController.text.trim();
            if (nextTitle.isEmpty) {
              return;
            }

            Navigator.of(context).pop(nextTitle);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialContent});

  final String initialContent;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑用户消息'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _contentController,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: '消息内容',
            alignLabelWithHint: true,
          ),
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final nextContent = _contentController.text.trim();
            if (nextContent.isEmpty) {
              return;
            }

            Navigator.of(context).pop(nextContent);
          },
          child: const Text('保存并重算'),
        ),
      ],
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.message,
    this.canEdit = false,
    this.canRetry = false,
    this.onEditPressed,
    this.onRetryPressed,
    this.versionInfo,
    this.onSwitchVersion,
  });

  final ChatMessage message;
  final bool canEdit;
  final bool canRetry;
  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;
  final _MessageVersionInfo? versionInfo;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制消息内容')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatMessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isUser ? '你' : '模型',
                      style: theme.textTheme.labelLarge,
                    ),
                    if (message.isStreaming) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        _copyMessage(context);
                      },
                      tooltip: '复制消息',
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    if (canEdit)
                      IconButton(
                        onPressed: onEditPressed,
                        tooltip: '编辑消息',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (canRetry)
                      IconButton(
                        onPressed: onRetryPressed,
                        tooltip: '重试回复',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
                if (!isUser && message.reasoningContent.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ReasoningPanel(content: message.reasoningContent),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 8),
                MarkdownBody(
                  data: message.content.isEmpty && message.isStreaming
                      ? '_正在等待模型返回内容..._'
                      : message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyLarge,
                    blockquote: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (versionInfo != null) ...[
                  const SizedBox(height: 8),
                  _MessageVersionNavigator(
                    currentIndex: versionInfo!.currentIndex,
                    total: versionInfo!.siblings.length,
                    onPrevious: versionInfo!.currentIndex > 0
                        ? () {
                            onSwitchVersion?.call(
                              versionInfo!
                                  .siblings[versionInfo!.currentIndex - 1]
                                  .id,
                            );
                          }
                        : null,
                    onNext:
                        versionInfo!.currentIndex < versionInfo!.siblings.length - 1
                        ? () {
                            onSwitchVersion?.call(
                              versionInfo!
                                  .siblings[versionInfo!.currentIndex + 1]
                                  .id,
                            );
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageVersionInfo {
  const _MessageVersionInfo({
    required this.parentId,
    required this.currentIndex,
    required this.siblings,
  });

  final String parentId;
  final int currentIndex;
  final List<ChatMessage> siblings;
}

class _MessageVersionNavigator extends StatelessWidget {
  const _MessageVersionNavigator({
    required this.currentIndex,
    required this.total,
    this.onPrevious,
    this.onNext,
  });

  final int currentIndex;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: '上一版本',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentIndex + 1}/$total',
          style: theme.textTheme.labelMedium,
        ),
        IconButton(
          onPressed: onNext,
          tooltip: '下一版本',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _ReasoningPanel extends StatefulWidget {
  const _ReasoningPanel({required this.content});

  final String content;

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '深度思考',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _expanded ? '收起' : '展开',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 167),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: MarkdownBody(
                      data: widget.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                        ),
                        code: theme.textTheme.bodySmall?.copyWith(
                          color: textColor,
                        ),
                        blockquote: theme.textTheme.bodySmall?.copyWith(
                          color: textColor,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversationView extends StatelessWidget {
  const _EmptyConversationView({required this.hasModels});

  final bool hasModels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasModels ? '开始一段新对话' : '先准备模型配置',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasModels
                        ? '输入你的第一条消息后，这里会显示真实的流式回复，同时左侧历史列表和右侧悬浮定位条会一起工作。'
                        : '你还没有配置模型。先去设置页添加一个 OpenAI 兼容模型，聊天页才能真正发起请求。',
                    textAlign: TextAlign.center,
                  ),
                  if (!hasModels) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go(AppDestination.settings.path),
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('前往设置页'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationHistoryPanel extends StatelessWidget {
  const _ConversationHistoryPanel({
    required this.groups,
    required this.activeConversationId,
    required this.hasDraftConversation,
    required this.onCreateConversation,
    required this.onConversationSelected,
  });

  final List<ChatConversationGroup> groups;
  final String activeConversationId;
  final bool hasDraftConversation;
  final VoidCallback? onCreateConversation;
  final ValueChanged<String> onConversationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('历史会话面板', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: onCreateConversation,
                  tooltip: '新建对话',
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasDraftConversation ? '当前包含未发送的新对话草稿。' : '按更新时间分组展示对话。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: groups.isEmpty
                  ? const Center(child: Text('还没有已保存的会话记录。'))
                  : ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (context, index) {
                        return const SizedBox(height: 16);
                      },
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.bucket.label,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            for (final conversation in group.conversations)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  tileColor:
                                      conversation.id == activeConversationId
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerLow,
                                  title: Text(
                                    conversation.resolvedTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    conversation.messages.lastOrNull?.content
                                            .trim()
                                            .replaceAll('\n', ' ') ??
                                        '暂无内容',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    onConversationSelected(conversation.id);
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageAnchorRail extends StatelessWidget {
  const _MessageAnchorRail({
    required this.userMessages,
    required this.activeMessageId,
    required this.maxHeight,
    required this.onSelectMessage,
  });

  final List<ChatMessage> userMessages;
  final String? activeMessageId;
  final double maxHeight;
  final ValueChanged<String> onSelectMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        minWidth: 28,
        maxWidth: 28,
      ),
      child: DecoratedBox(
        key: const ValueKey('message-anchor-rail'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Scrollbar(
            thumbVisibility: userMessages.length > 10,
            interactive: true,
            radius: const Radius.circular(999),
            thickness: 2.5,
            child: ListView.separated(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: userMessages.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 8);
              },
              itemBuilder: (context, index) {
                final message = userMessages[index];
                final isActive = message.id == activeMessageId;

                return Semantics(
                  button: true,
                  selected: isActive,
                  label: '定位到第 ${index + 1} 条用户消息',
                  child: InkWell(
                    key: ValueKey('message-anchor-item-${index + 1}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelectMessage(message.id),
                    child: SizedBox(
                      width: 20,
                      height: 18,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 167),
                          width: isActive ? 14 : 10,
                          height: isActive ? 6 : 4,
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
