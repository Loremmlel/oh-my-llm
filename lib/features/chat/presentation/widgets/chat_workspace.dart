import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../../../settings/domain/models/llm_model_config.dart';
import '../../../settings/domain/models/llm_provider_config.dart';
import '../../../settings/domain/models/prompt_template.dart';
import '../../../settings/domain/models/template_prompt.dart';
import 'cached_chat_message_bubble.dart';
import 'empty_conversation_view.dart';
import 'message_anchor_rail.dart';
import 'message_version_info.dart';
import 'thinking_toggle.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  static const _transientErrorMessageId = '__transient_error_message__';
  static const _compactComposerBreakpoint = 680.0;

  const ChatWorkspace({
    required this.conversation,
    required this.messages,
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.promptTemplates,
    required this.selectedPromptTemplate,
    required this.userMessages,
    required this.activeAnchorMessageId,
    required this.messageController,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.isStreaming,
    required this.errorMessage,
    required this.errorModelDisplayName,
    required this.showScrollToBottom,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onPromptTemplateSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
    required this.onStopStreaming,
    this.onFavoritePressed,
    this.favoritedAssistantContents = const {},
    super.key,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<PromptTemplate> promptTemplates;
  final PromptTemplate? selectedPromptTemplate;
  final List<ChatMessage> userMessages;
  final String? activeAnchorMessageId;
  final TextEditingController messageController;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool isStreaming;
  final String? errorMessage;
  final String errorModelDisplayName;
  final bool showScrollToBottom;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onPromptTemplateSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  /// 点击收藏按钮时的回调（仅助手消息），为 null 则不显示收藏按钮。
  final ValueChanged<ChatMessage>? onFavoritePressed;

  /// 已收藏的助手消息内容集合，用于显示收藏高亮状态。
  final Set<String> favoritedAssistantContents;

  @override
  /// 构建消息区、错误提示和输入区的整体布局。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final messagesCard = _buildMessagesCard(theme);
        final composerCard = _buildComposerCard(context, theme);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: messagesCard),
            const SizedBox(height: 12),
            composerCard,
          ],
        );
      },
    );
  }

  /// 构建消息列表卡片，并把版本信息和锚点条组装进去。
  Widget _buildMessagesCard(ThemeData theme) {
    final displayMessages = _buildDisplayMessages();
    final latestAssistantMessage =
        displayMessages.lastOrNull?.role == ChatMessageRole.assistant
        ? displayMessages.lastOrNull
        : null;
    final versionInfoByMessageId = _buildMessageVersionInfoMap();

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorRightPadding = userMessages.isEmpty ? 14.0 : 52.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (messages.isEmpty)
                EmptyConversationView(hasModels: hasModels)
              else
                ScrollablePositionedList.separated(
                  itemScrollController: messageItemScrollController,
                  itemPositionsListener: messageItemPositionsListener,
                  padding: EdgeInsets.fromLTRB(14, 14, anchorRightPadding, 14),
                  itemCount: displayMessages.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) {
                    final message = displayMessages[index];
                    final isTransientError =
                        message.id == _transientErrorMessageId;

                    return KeyedSubtree(
                      key: ValueKey(message.id),
                      child: CachedChatMessageBubble(
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
                        onRetryPressed: latestAssistantMessage?.id == message.id
                            ? () {
                                onRetryLatestAssistant();
                              }
                            : null,
                        onDeletePressed: !isStreaming && !isTransientError
                            ? () {
                                onDeleteMessage(message);
                              }
                            : null,
                        onFavoritePressed:
                            !isTransientError &&
                                message.role == ChatMessageRole.assistant &&
                                onFavoritePressed != null
                            ? () => onFavoritePressed!(message)
                            : null,
                        isFavorited:
                            !isTransientError &&
                            message.role == ChatMessageRole.assistant &&
                            favoritedAssistantContents.contains(
                              message.content,
                            ),
                        versionInfo: versionInfoByMessageId[message.id],
                        onSwitchVersion: (targetMessageId) async {
                          final versionInfo =
                              versionInfoByMessageId[message.id];
                          if (versionInfo == null) {
                            return;
                          }
                          await onSelectMessageVersion(
                            versionInfo.parentId,
                            targetMessageId,
                          );
                        },
                      ),
                    );
                  },
                ),
              if (userMessages.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MessageAnchorRail(
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

  /// 把临时错误拼接为一条助手样式消息，仅用于 UI 展示，不写入会话树。
  List<ChatMessage> _buildDisplayMessages() {
    final normalizedError = errorMessage?.trim();
    if (normalizedError == null || normalizedError.isEmpty) {
      return messages;
    }
    return [
      ...messages,
      ChatMessage(
        id: _transientErrorMessageId,
        role: ChatMessageRole.assistant,
        content: normalizedError,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        parentId: messages.lastOrNull?.id ?? rootConversationParentId,
        assistantModelDisplayName: errorModelDisplayName,
      ),
    ];
  }

  /// 为每条消息计算可切换的版本信息。
  Map<String, MessageVersionInfo> _buildMessageVersionInfoMap() {
    if (conversation.messageNodes.isEmpty) {
      return const {};
    }

    final siblingsByParent = <String, List<ChatMessage>>{};
    for (final node in conversation.messageNodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      siblingsByParent.putIfAbsent(parentId, () => <ChatMessage>[]).add(node);
    }

    final result = <String, MessageVersionInfo>{};
    for (final message in messages) {
      final parentId = message.parentId ?? rootConversationParentId;
      final siblings = siblingsByParent[parentId] ?? const <ChatMessage>[];
      if (siblings.length <= 1) {
        continue;
      }
      final index = siblings.indexWhere((item) => item.id == message.id);
      if (index == -1) {
        continue;
      }
      result[message.id] = MessageVersionInfo(
        parentId: parentId,
        currentIndex: index,
        siblings: siblings,
      );
    }
    return result;
  }

  /// 构建消息输入区、模型 / Prompt 选择控件与发送按钮。
  Widget _buildComposerCard(BuildContext context, ThemeData theme) {
    if (isComposerCollapsed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.keyboard_arrow_up_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text('输入区已隐藏', style: theme.textTheme.bodyMedium),
              ),
              Tooltip(
                message: '展开输入区',
                child: OutlinedButton.icon(
                  onPressed: onToggleComposerCollapsed,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  label: const Text('展开'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < _compactComposerBreakpoint;

          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTemplateHeader(),
                if (selectedTemplatePrompt != null) ...[
                  const SizedBox(height: 12),
                  if (selectedTemplatePrompt!.inputVariables.isEmpty)
                    Text('当前模板没有额外变量。', style: theme.textTheme.bodySmall)
                  else
                    _buildTemplateVariableFields(),
                  if (!selectedTemplatePrompt!.containsBodyVariable) ...[
                    const SizedBox(height: 4),
                    Text(
                      '正文会在发送时插入模板提示词上方。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _buildMessageComposerField(),
                const SizedBox(height: 10),
                _buildProviderAndModelRow(isCompact: isCompact),
                const SizedBox(height: 8),
                if (isCompact)
                  _buildCompactActionRow(context, theme)
                else
                  _buildDesktopSecondarySettingsRow(context, theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTemplateHeader() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('template-prompt-selector'),
            initialValue: selectedTemplatePrompt?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '模板提示词'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('不使用模板提示词'),
              ),
              ...templatePrompts.map((templatePrompt) {
                return DropdownMenuItem<String?>(
                  value: templatePrompt.id,
                  child: Text(templatePrompt.title),
                );
              }),
            ],
            onChanged: isStreaming ? null : onTemplatePromptSelected,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: onToggleComposerCollapsed,
          tooltip: '收起输入区',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      ],
    );
  }

  Widget _buildMessageComposerField() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
        ): () =>
            onSendPressed?.call(),
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
        ): () =>
            onSendPressed?.call(),
      },
      child: TextField(
        key: const ValueKey('chat-message-composer'),
        controller: messageController,
        minLines: 3,
        maxLines: 10,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: '正文',
          hintText: selectedTemplatePrompt == null
              ? '输入你的问题、指令或待处理内容。'
              : '输入要注入模板的正文内容。',
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  Widget _buildProviderAndModelRow({required bool isCompact}) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-provider-selector'),
            isExpanded: true,
            initialValue: selectedProviderId,
            decoration: InputDecoration(
              labelText: '服务商',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isCompact ? 10 : 12,
              ),
              hintText: hasModels ? null : '请先在设置页新增服务商与模型',
            ),
            items: modelProviders
                .map((provider) {
                  return DropdownMenuItem<String>(
                    value: provider.id,
                    child: Text(provider.name, overflow: TextOverflow.ellipsis),
                  );
                })
                .toList(growable: false),
            onChanged: isStreaming || modelProviders.isEmpty
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onProviderSelected(value);
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-model-selector'),
            initialValue: selectedModel?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '模型',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isCompact ? 10 : 12,
              ),
              hintText: !hasModels
                  ? '请先在设置页新增服务商与模型'
                  : selectedProviderId == null
                  ? '请先选择服务商'
                  : modelConfigs.isEmpty
                  ? '当前服务商还没有模型'
                  : null,
            ),
            items: modelConfigs
                .map((config) {
                  return DropdownMenuItem<String>(
                    value: config.id,
                    child: Text(
                      config.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                })
                .toList(growable: false),
            onChanged: isStreaming || modelConfigs.isEmpty
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onModelSelected(value);
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSecondarySettingsRow(
    BuildContext context,
    ThemeData theme,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ThinkingToggle(
          enabled: supportsReasoning,
          value: supportsReasoning && reasoningEnabled,
          onChanged: onReasoningEnabledChanged,
        ),
        if (supportsReasoning && reasoningEnabled)
          _buildEffortPill(context, theme),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 260),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-prompt-selector'),
            initialValue:
                selectedPromptTemplate?.id ?? noPromptTemplateSelectedId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '前置 Prompt',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: noPromptTemplateSelectedId,
                child: Text('不使用前置 Prompt'),
              ),
              ...promptTemplates.map((template) {
                return DropdownMenuItem<String>(
                  value: template.id,
                  child: Text(template.name, overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            onChanged: isStreaming
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onPromptTemplateSelected(
                      value == noPromptTemplateSelectedId ? null : value,
                    );
                  },
          ),
        ),
        Tooltip(
          message: '固定顺序提示词',
          child: OutlinedButton.icon(
            onPressed: onOpenFixedPromptSequenceRunner,
            icon: const Icon(Icons.playlist_play_rounded),
            label: const Text('固定顺序提示词'),
          ),
        ),
        _buildSendButton(theme, expandLabel: false),
      ],
    );
  }

  Widget _buildCompactActionRow(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('chat-secondary-settings-button'),
            onPressed: isStreaming
                ? null
                : () {
                    _showCompactSecondarySettingsSheet(context, theme);
                  },
            icon: const Icon(Icons.tune_rounded),
            label: Text(_compactSettingsSummary()),
          ),
        ),
        const SizedBox(width: 8),
        _buildSendButton(theme, expandLabel: true),
      ],
    );
  }

  Widget _buildTemplateVariableFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 220.0;
        const gap = 8.0;
        final crossAxisCount =
            ((constraints.maxWidth + gap) / (minItemWidth + gap)).floor().clamp(
              1,
              3,
            );
        final itemWidth = crossAxisCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (crossAxisCount - 1)) /
                  crossAxisCount;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final variable in selectedTemplatePrompt!.inputVariables)
              SizedBox(
                width: itemWidth,
                child: TextField(
                  key: ValueKey('template-variable-${variable.name}'),
                  controller: templateVariableControllers[variable.name],
                  decoration: InputDecoration(
                    labelText: variable.name,
                    hintText: variable.defaultValue.isEmpty
                        ? '未设置默认值'
                        : variable.defaultValue,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 构建思考强度 pill 选择器。
  ///
  /// 样式与 [ThinkingToggle] 一致，使用 [PopupMenuButton] 包裹，
  /// 点击后展示 low / med / high / xhigh 四个选项。
  /// 当深度思考未启用时，pill 变灰且不可交互。
  Widget _buildEffortPill(BuildContext context, ThemeData theme) {
    final isActive = supportsReasoning && reasoningEnabled;
    final backgroundColor = !supportsReasoning
        ? theme.colorScheme.surfaceContainerLow
        : isActive
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = isActive
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    // PopupMenuButton 作为父容器，点击 pill 即可展开菜单
    return PopupMenuButton<ReasoningEffort>(
      enabled: isActive,
      initialValue: reasoningEffort,
      tooltip: '思考强度',
      onSelected: (value) => onReasoningEffortChanged?.call(value),
      itemBuilder: (context) => ReasoningEffort.values
          .map(
            (effort) =>
                PopupMenuItem(value: effort, child: Text(_effortLabel(effort))),
          )
          .toList(growable: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 167),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _effortLabel(reasoningEffort),
              style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: labelColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme, {required bool expandLabel}) {
    return FilledButton.icon(
      onPressed: isStreaming
          ? () {
              onStopStreaming?.call();
            }
          : !hasModels
          ? null
          : () {
              onSendPressed?.call();
            },
      style: FilledButton.styleFrom(
        minimumSize: Size(expandLabel ? 112 : 60, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: isStreaming ? theme.colorScheme.error : null,
        foregroundColor: isStreaming ? theme.colorScheme.onError : null,
      ),
      icon: Icon(isStreaming ? Icons.stop_rounded : Icons.send_rounded),
      label: Text(isStreaming ? '终止回答' : '发送'),
    );
  }

  String _compactSettingsSummary() {
    final parts = <String>[];
    parts.add(supportsReasoning && reasoningEnabled ? _effortLabel(reasoningEffort) : '思考关');
    parts.add(selectedPromptTemplate?.name ?? '无 Prompt');
    return '更多设置 · ${parts.join(' · ')}';
  }

  Future<void> _showCompactSecondarySettingsSheet(
    BuildContext context,
    ThemeData theme,
  ) {
    var localReasoningEnabled = supportsReasoning && reasoningEnabled;
    var localEffort = reasoningEffort;

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('更多设置', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    ThinkingToggle(
                      enabled: supportsReasoning,
                      value: localReasoningEnabled,
                      onChanged: supportsReasoning
                          ? (value) {
                              setModalState(() {
                                localReasoningEnabled = value;
                              });
                              onReasoningEnabledChanged?.call(value);
                            }
                          : null,
                    ),
                    if (supportsReasoning && localReasoningEnabled) ...[
                      const SizedBox(height: 12),
                      Text('思考强度', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final effort in ReasoningEffort.values)
                            ChoiceChip(
                              label: Text(_effortLabel(effort)),
                              selected: localEffort == effort,
                              onSelected: (_) {
                                setModalState(() {
                                  localEffort = effort;
                                });
                                onReasoningEffortChanged?.call(effort);
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('chat-prompt-selector'),
                      initialValue:
                          selectedPromptTemplate?.id ?? noPromptTemplateSelectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '前置 Prompt'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: noPromptTemplateSelectedId,
                          child: Text('不使用前置 Prompt'),
                        ),
                        ...promptTemplates.map((template) {
                          return DropdownMenuItem<String>(
                            value: template.id,
                            child: Text(
                              template.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: isStreaming
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              onPromptTemplateSelected(
                                value == noPromptTemplateSelectedId
                                    ? null
                                    : value,
                              );
                            },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Tooltip(
                        message: '固定顺序提示词',
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(bottomSheetContext).pop();
                            await onOpenFixedPromptSequenceRunner();
                          },
                          icon: const Icon(Icons.playlist_play_rounded),
                          label: const Text('固定顺序提示词'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 把枚举值转换为更短的显示文本。
  String _effortLabel(ReasoningEffort effort) {
    return switch (effort) {
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'med',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh => 'xhigh',
    };
  }
}
