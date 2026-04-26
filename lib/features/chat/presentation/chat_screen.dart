import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../../core/utils/id_generator.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
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
  late ChatConversation _conversation;

  String? _selectedModelId;
  String? _selectedPromptTemplateId;
  bool _reasoningEnabled = true;
  ReasoningEffort _reasoningEffort = ReasoningEffort.medium;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    final now = DateTime.now();
    _conversation = ChatConversation(
      id: generateEntityId(),
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelConfigs = ref.watch(llmModelConfigsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);

    final selectedModel = _resolveSelectedModel(modelConfigs);
    final selectedPromptTemplate =
        _resolveSelectedPromptTemplate(promptTemplates);
    final supportsReasoning = selectedModel?.supportsReasoning ?? false;

    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: '对话页',
      endDrawer: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _ConversationHistoryPanel(
            conversation: _conversation,
            promptTemplateCount: promptTemplates.length,
            modelConfigCount: modelConfigs.length,
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => _showRenameDialog(context),
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
                    width: 280,
                    child: _ConversationHistoryPanel(
                      conversation: _conversation,
                      promptTemplateCount: promptTemplates.length,
                      modelConfigCount: modelConfigs.length,
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
                Expanded(
                  child: _ChatWorkspace(
                    conversation: _conversation,
                    selectedModel: selectedModel,
                    selectedPromptTemplate: selectedPromptTemplate,
                    modelConfigs: modelConfigs,
                    promptTemplates: promptTemplates,
                    messageController: _messageController,
                    reasoningEnabled: _reasoningEnabled,
                    reasoningEffort: _reasoningEffort,
                    supportsReasoning: supportsReasoning,
                    onModelChanged: (value) {
                      final nextModel = modelConfigs.where((config) {
                        return config.id == value;
                      }).firstOrNull;

                      setState(() {
                        _selectedModelId = value;
                        if (!(nextModel?.supportsReasoning ?? false)) {
                          _reasoningEnabled = false;
                        }
                      });
                    },
                    onPromptTemplateChanged: (value) {
                      setState(() {
                        _selectedPromptTemplateId =
                            value == _noPromptTemplateValue ? null : value;
                      });
                    },
                    onReasoningEnabledChanged: supportsReasoning
                        ? (value) {
                            setState(() {
                              _reasoningEnabled = value;
                            });
                          }
                        : null,
                    onReasoningEffortChanged: supportsReasoning
                        ? (value) {
                            setState(() {
                              _reasoningEffort = value;
                            });
                          }
                        : null,
                    onSendPressed: () {
                      _handleSendMessage(
                        selectedModel: selectedModel,
                        selectedPromptTemplate: selectedPromptTemplate,
                      );
                    },
                  ),
                ),
                if (showSidePanels) ...[
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 220,
                    child: _MessageAnchorPanel(
                      userMessages: _conversation.messages
                          .where(
                            (message) => message.role == ChatMessageRole.user,
                          )
                          .toList(growable: false),
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

  LlmModelConfig? _resolveSelectedModel(List<LlmModelConfig> modelConfigs) {
    if (modelConfigs.isEmpty) {
      return null;
    }

    final selected = modelConfigs.where((config) {
      return config.id == _selectedModelId;
    }).firstOrNull;

    return selected ?? modelConfigs.first;
  }

  PromptTemplate? _resolveSelectedPromptTemplate(
    List<PromptTemplate> promptTemplates,
  ) {
    if (promptTemplates.isEmpty) {
      return null;
    }

    final selected = promptTemplates.where((template) {
      return template.id == _selectedPromptTemplateId;
    }).firstOrNull;

    return selected;
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final titleController = TextEditingController(
      text: _conversation.resolvedTitle,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改对话标题'),
          content: TextField(
            controller: titleController,
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
                final nextTitle = titleController.text.trim();
                if (nextTitle.isEmpty) {
                  return;
                }

                setState(() {
                  _conversation = _conversation.copyWith(title: nextTitle);
                });
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
  }

  void _handleSendMessage({
    required LlmModelConfig? selectedModel,
    required PromptTemplate? selectedPromptTemplate,
  }) {
    final content = _messageController.text.trim();
    if (content.isEmpty || selectedModel == null) {
      return;
    }

    final timestamp = DateTime.now();
    final nextMessages = [
      ..._conversation.messages,
      ChatMessage(
        id: generateEntityId(),
        role: ChatMessageRole.user,
        content: content,
        createdAt: timestamp,
      ),
      ChatMessage(
        id: generateEntityId(),
        role: ChatMessageRole.assistant,
        content: _buildAssistantPreviewReply(
          userInput: content,
          selectedModel: selectedModel,
          selectedPromptTemplate: selectedPromptTemplate,
          enableReasoning:
              _reasoningEnabled && selectedModel.supportsReasoning,
          reasoningEffort: _reasoningEffort,
        ),
        createdAt: timestamp.add(const Duration(milliseconds: 200)),
      ),
    ];

    setState(() {
      _conversation = _conversation.copyWith(
        messages: nextMessages,
        updatedAt: timestamp,
      );
      _messageController.clear();
    });
  }

  String _buildAssistantPreviewReply({
    required String userInput,
    required LlmModelConfig selectedModel,
    required PromptTemplate? selectedPromptTemplate,
    required bool enableReasoning,
    required ReasoningEffort reasoningEffort,
  }) {
    final promptSummary = selectedPromptTemplate == null
        ? '未使用前置 Prompt'
        : '已附加模板 **${selectedPromptTemplate.name}**';
    final reasoningSummary = enableReasoning
        ? '开启，负担为 **${reasoningEffort.apiValue}**'
        : '关闭';

    return '''
### 已收到你的输入

- 当前模型：**${selectedModel.displayName}**
- 前置 Prompt：$promptSummary
- 深度思考：$reasoningSummary

> 这里先演示聊天页核心体验。下一步会把真实的 OpenAI 兼容接口和流式输出接进来。

你刚才输入的是：

```text
$userInput
```
''';
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
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.onModelChanged,
    required this.onPromptTemplateChanged,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onSendPressed,
  });

  final ChatConversation conversation;
  final LlmModelConfig? selectedModel;
  final PromptTemplate? selectedPromptTemplate;
  final List<LlmModelConfig> modelConfigs;
  final List<PromptTemplate> promptTemplates;
  final TextEditingController messageController;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String?> onPromptTemplateChanged;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final VoidCallback onSendPressed;

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
              SizedBox(height: 360, child: messagesCard),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesCard() {
    return Card(
      child: conversation.messages.isEmpty
          ? _EmptyConversationView(hasModels: modelConfigs.isNotEmpty)
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: conversation.messages.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 16);
              },
              itemBuilder: (context, index) {
                final message = conversation.messages[index];
                return _ChatMessageBubble(message: message);
              },
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
                        : '这一步先提供本地交互体验，真实流式回复会在下一能力块接入。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: modelConfigs.isEmpty ? null : onSendPressed,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('发送'),
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

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.message,
  });

  final ChatMessage message;

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
                Text(
                  isUser ? '你' : '模型',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                MarkdownBody(
                  data: message.content,
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
                        ? '输入你的第一条消息后，这里会显示左右分栏的对话记录，并自动生成会话标题。'
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
    required this.conversation,
    required this.modelConfigCount,
    required this.promptTemplateCount,
  });

  final ChatConversation conversation;
  final int modelConfigCount;
  final int promptTemplateCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '历史会话面板',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '历史页能力块完成前，这里先承载当前会话摘要和后续要接入的列表结构。',
            ),
            const SizedBox(height: 16),
            _InfoRow(label: '当前标题', value: conversation.resolvedTitle),
            _InfoRow(
              label: '消息数',
              value: '${conversation.messages.length} 条',
            ),
            _InfoRow(
              label: '模型配置',
              value: '$modelConfigCount 个',
            ),
            _InfoRow(
              label: 'Prompt 模板',
              value: '$promptTemplateCount 个',
            ),
            const SizedBox(height: 16),
            const Text('后续会在这里接入：'),
            const SizedBox(height: 8),
            const _PanelBullet(text: '按更新时间分组的会话列表'),
            const _PanelBullet(text: '最近、一日内、三日内等分段标题'),
            const _PanelBullet(text: '点击会话后切换到对应聊天内容'),
          ],
        ),
      ),
    );
  }
}

class _MessageAnchorPanel extends StatelessWidget {
  const _MessageAnchorPanel({
    required this.userMessages,
  });

  final List<ChatMessage> userMessages;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '消息定位条',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              userMessages.isEmpty
                  ? '发送消息后，这里会列出用户问题的短摘要。'
                  : '下一能力块会把这些锚点接成真正的快速定位入口。',
            ),
            const SizedBox(height: 16),
            if (userMessages.isEmpty)
              const _PanelBullet(text: '暂时还没有用户消息')
            else
              for (final message in userMessages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        message.content.characters.take(10).toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label：'),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PanelBullet extends StatelessWidget {
  const _PanelBullet({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
