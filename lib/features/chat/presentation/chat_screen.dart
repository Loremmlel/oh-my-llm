import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import '../application/chat_sessions_controller.dart';
import '../domain/chat_conversation_groups.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

const String _noPromptTemplateValue = '__no_prompt_template__';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TextEditingController _messageController;
  late final ScrollController _messageScrollController;

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  bool _showScrollToBottom = false;
  String? _lastConversationId;
  String? _lastRenderSignature;

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
    final modelConfigs = ref.watch(llmModelConfigsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);

    final selectedModel = _resolveSelectedModel(
      modelConfigs,
      conversation.selectedModelId,
    );
    final selectedPromptTemplate = _resolveSelectedPromptTemplate(
      promptTemplates,
      conversation.selectedPromptTemplateId,
    );
    final supportsReasoning = selectedModel?.supportsReasoning ?? false;

    _scheduleScrollSync(
      conversation: conversation,
      isStreaming: chatState.isStreaming,
    );

    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: '对话页',
      endDrawer: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              ref.read(chatSessionsProvider.notifier).selectConversation(
                    conversationId,
                  );
            },
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: chatState.isStreaming ? null : _createConversationAndScroll,
          tooltip: '新建对话',
          icon: const Icon(Icons.add_comment_outlined),
        ),
        IconButton(
          onPressed: () => _showRenameDialog(context, conversation.resolvedTitle),
          tooltip: '修改对话标题',
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidePanels =
              constraints.maxWidth >= AppBreakpoints.expanded;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSidePanels) ...[
                  SizedBox(
                    width: 300,
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
                        ref.read(chatSessionsProvider.notifier).selectConversation(
                              conversationId,
                            );
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
                Expanded(
                  child: _ChatWorkspace(
                    conversation: conversation,
                    selectedModel: selectedModel,
                    selectedPromptTemplate: selectedPromptTemplate,
                    modelConfigs: modelConfigs,
                    promptTemplates: promptTemplates,
                    messageController: _messageController,
                    messageScrollController: _messageScrollController,
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
                    onModelChanged: (value) {
                      final nextModel = modelConfigs.where((config) {
                        return config.id == value;
                      }).firstOrNull;
                      final keepReasoning =
                          nextModel?.supportsReasoning ?? false;

                      ref
                          .read(chatSessionsProvider.notifier)
                          .updateActiveConversationPreferences(
                            selectedModelId: value,
                            reasoningEnabled: keepReasoning
                                ? conversation.reasoningEnabled
                                : false,
                          );
                    },
                    onPromptTemplateChanged: (value) {
                      ref
                          .read(chatSessionsProvider.notifier)
                          .updateActiveConversationPreferences(
                            selectedPromptTemplateId:
                                value == _noPromptTemplateValue ? null : value,
                            clearSelectedPromptTemplateId:
                                value == _noPromptTemplateValue,
                          );
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
                    onSendPressed: selectedModel == null || chatState.isStreaming
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
                if (showSidePanels) ...[
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 180,
                    child: _MessageAnchorPanel(
                      userMessages: conversation.messages
                          .where(
                            (message) => message.role == ChatMessageRole.user,
                          )
                          .toList(growable: false),
                      onSelectMessage: _scrollToMessage,
                    ),
                  ),
                ],
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
    final visibleConversations = conversations.where((conversation) {
      return conversation.hasMessages;
    }).toList(growable: false);
    return groupConversationsByUpdatedAt(visibleConversations);
  }

  LlmModelConfig? _resolveSelectedModel(
    List<LlmModelConfig> modelConfigs,
    String? selectedModelId,
  ) {
    if (modelConfigs.isEmpty) {
      return null;
    }

    final selected = modelConfigs.where((config) {
      return config.id == selectedModelId;
    }).firstOrNull;

    return selected ?? modelConfigs.first;
  }

  PromptTemplate? _resolveSelectedPromptTemplate(
    List<PromptTemplate> promptTemplates,
    String? selectedPromptTemplateId,
  ) {
    if (promptTemplates.isEmpty) {
      return null;
    }

    return promptTemplates.where((template) {
      return template.id == selectedPromptTemplateId;
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
      return;
    }

    setState(() {
      _showScrollToBottom = shouldShow;
    });
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
      return;
    }

    await _messageScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
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

    await ref.read(chatSessionsProvider.notifier).editMessage(
          messageId: messageId,
          nextContent: nextContent.trim(),
        );
  }
}

class _ChatWorkspace extends StatelessWidget {
  const _ChatWorkspace({
    required this.conversation,
    required this.selectedModel,
    required this.selectedPromptTemplate,
    required this.modelConfigs,
    required this.promptTemplates,
    required this.messageController,
    required this.messageScrollController,
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
    required this.onModelChanged,
    required this.onPromptTemplateChanged,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onScrollToBottomPressed,
    required this.onSendPressed,
  });

  final ChatConversation conversation;
  final LlmModelConfig? selectedModel;
  final PromptTemplate? selectedPromptTemplate;
  final List<LlmModelConfig> modelConfigs;
  final List<PromptTemplate> promptTemplates;
  final TextEditingController messageController;
  final ScrollController messageScrollController;
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
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String?> onPromptTemplateChanged;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final VoidCallback onScrollToBottomPressed;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promptSelectionValue =
        selectedPromptTemplate?.id ?? _noPromptTemplateValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.compact ||
            constraints.maxHeight < 900;
        final headerCard = _buildHeaderCard(theme);
        final messagesCard = _buildMessagesCard();
        final composerCard = _buildComposerCard(theme, promptSelectionValue);

        if (compact) {
          return ListView(
            children: [
              headerCard,
              const SizedBox(height: 16),
              SizedBox(height: 420, child: messagesCard),
              const SizedBox(height: 16),
              composerCard,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerCard,
            const SizedBox(height: 16),
            Expanded(child: messagesCard),
            const SizedBox(height: 16),
            composerCard,
          ],
        );
      },
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation.resolvedTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '标题默认取首条用户消息前 15 个字，你也可以随时从右上角手动修改。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(
                    selectedModel?.displayName ?? '请先到设置页添加模型',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.notes_rounded, size: 18),
                  label: Text(
                    selectedPromptTemplate?.name ?? '未使用前置 Prompt',
                  ),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.psychology_alt_outlined,
                    size: 18,
                  ),
                  label: Text(
                    supportsReasoning && reasoningEnabled
                        ? '深度思考：${reasoningEffort.apiValue}'
                        : '深度思考：关闭',
                  ),
                ),
                if (isStreaming)
                  const Chip(
                    avatar: Icon(Icons.sync_rounded, size: 18),
                    label: Text('流式生成中'),
                  ),
              ],
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Material(
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesCard() {
    final latestAssistantMessage = conversation.messages.lastOrNull?.role ==
            ChatMessageRole.assistant
        ? conversation.messages.lastOrNull
        : null;

    return Card(
      child: Stack(
        children: [
          if (conversation.messages.isEmpty)
            _EmptyConversationView(hasModels: modelConfigs.isNotEmpty)
          else
            SingleChildScrollView(
              controller: messageScrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final message in conversation.messages) ...[
                    KeyedSubtree(
                      key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
                      child: _ChatMessageBubble(
                        message: message,
                        canEdit: !isStreaming &&
                            message.role == ChatMessageRole.user,
                        canRetry: !isStreaming &&
                            latestAssistantMessage?.id == message.id,
                        onEditPressed: message.role == ChatMessageRole.user
                            ? () {
                                onEditMessage(message);
                              }
                            : null,
                        onRetryPressed: latestAssistantMessage?.id == message.id
                            ? () {
                                onRetryLatestAssistant();
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
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
  }

  Widget _buildComposerCard(ThemeData theme, String promptSelectionValue) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;

                if (compact) {
                  return Column(
                    children: [
                      _buildModelSelector(),
                      const SizedBox(height: 12),
                      _buildPromptSelector(promptSelectionValue),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: _buildModelSelector()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPromptSelector(promptSelectionValue),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: supportsReasoning && reasoningEnabled,
              onChanged: onReasoningEnabledChanged,
              title: const Text('深度思考'),
              subtitle: Text(
                supportsReasoning
                    ? '当前模型支持思考参数，可以控制推理负担。'
                    : '当前模型未开启深度思考能力。',
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ReasoningEffort>(
                segments: ReasoningEffort.values.map((effort) {
                  return ButtonSegment<ReasoningEffort>(
                    value: effort,
                    label: Text(effort.apiValue),
                  );
                }).toList(growable: false),
                selected: {reasoningEffort},
                onSelectionChanged: supportsReasoning
                    ? (selection) {
                        if (selection.isNotEmpty) {
                          onReasoningEffortChanged?.call(selection.first);
                        }
                      }
                    : null,
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '输入消息',
                hintText: '输入你的问题、指令或待处理内容。',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    modelConfigs.isEmpty
                        ? '需要至少配置一个模型后才能发送消息。'
                        : isStreaming
                            ? '正在流式接收模型回复。你可以手动滚动查看历史，或点右下角按钮回到底部。'
                            : '已接入 OpenAI 兼容流式回复，弱网或配置错误时会在顶部显示错误提示。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: modelConfigs.isEmpty || isStreaming
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

  Widget _buildModelSelector() {
    return DropdownButtonFormField<String>(
      key: ValueKey(selectedModel?.id),
      initialValue: selectedModel?.id,
      items: modelConfigs.map((config) {
        return DropdownMenuItem(
          value: config.id,
          child: Text(config.displayName),
        );
      }).toList(growable: false),
      onChanged: modelConfigs.isEmpty ? null : onModelChanged,
      decoration: const InputDecoration(
        labelText: '模型选择器',
      ),
    );
  }

  Widget _buildPromptSelector(String promptSelectionValue) {
    return DropdownButtonFormField<String>(
      key: ValueKey(promptSelectionValue),
      initialValue: promptSelectionValue,
      items: [
        const DropdownMenuItem(
          value: _noPromptTemplateValue,
          child: Text('不使用前置 Prompt'),
        ),
        ...promptTemplates.map((template) {
          return DropdownMenuItem(
            value: template.id,
            child: Text(template.name),
          );
        }),
      ],
      onChanged: onPromptTemplateChanged,
      decoration: const InputDecoration(
        labelText: '前置 Prompt 选择器',
      ),
    );
  }
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({
    required this.initialTitle,
  });

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
        decoration: const InputDecoration(
          labelText: '对话标题',
        ),
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
  const _EditMessageDialog({
    required this.initialContent,
  });

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
  });

  final ChatMessage message;
  final bool canEdit;
  final bool canRetry;
  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyConversationView extends StatelessWidget {
  const _EmptyConversationView({
    required this.hasModels,
  });

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
                        ? '输入你的第一条消息后，这里会显示真实的流式回复，同时左侧历史列表和右侧定位条会一起工作。'
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
                  child: Text(
                    '历史会话面板',
                    style: theme.textTheme.titleLarge,
                  ),
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
              '按更新时间分组展示对话，点击即可切换到对应会话。',
              style: theme.textTheme.bodyMedium,
            ),
            if (hasDraftConversation) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '当前是未发送消息的新对话草稿。发送后会自动进入历史列表。',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: groups.isEmpty
                  ? const Center(
                      child: Text('还没有已保存的会话记录。'),
                    )
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
                                  tileColor: conversation.id ==
                                          activeConversationId
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerLow,
                                  title: Text(
                                    conversation.resolvedTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    conversation.messages
                                            .lastOrNull
                                            ?.content
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

class _MessageAnchorPanel extends StatelessWidget {
  const _MessageAnchorPanel({
    required this.userMessages,
    required this.onSelectMessage,
  });

  final List<ChatMessage> userMessages;
  final ValueChanged<String> onSelectMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '消息定位条',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              userMessages.isEmpty
                  ? '发送用户消息后，这里会按顺序出现可点击锚点。'
                  : '悬浮或长按查看消息前 10 个字，点击即可跳转到对应位置。',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: userMessages.isEmpty
                  ? const Center(
                      child: Text('暂无锚点'),
                    )
                  : ListView.separated(
                      itemCount: userMessages.length,
                      separatorBuilder: (context, index) {
                        return const SizedBox(height: 12);
                      },
                      itemBuilder: (context, index) {
                        final message = userMessages[index];
                        final preview = message.content.trim().characters
                            .take(10)
                            .toString();

                        return Tooltip(
                          message: preview,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onSelectMessage(message.id),
                            child: Container(
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '— ${index + 1}',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
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
