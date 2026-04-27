import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'widgets/widgets.dart';

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
          child: ConversationHistoryPanel(
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
                    child: ConversationHistoryPanel(
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
                  child: ChatWorkspace(
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
