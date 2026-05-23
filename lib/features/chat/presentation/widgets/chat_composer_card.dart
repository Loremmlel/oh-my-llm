import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../../../settings/domain/models/llm_model_config.dart';
import '../../../settings/domain/models/llm_provider_config.dart';
import '../../../settings/domain/models/prompt_template.dart';
import '../../../settings/domain/models/template_prompt.dart';
import 'auto_retry_toggle.dart';
import 'thinking_toggle.dart';

/// 聊天工作区中的输入与设置面板。
class ChatComposerCard extends StatelessWidget {
  static const compactComposerBreakpoint = 680.0;

  const ChatComposerCard({
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.promptTemplates,
    required this.selectedPromptTemplate,
    required this.messageController,
    required this.messageFocusNode,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.isBusy,
    required this.isStreaming,
    required this.excludedMessageCount,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onPromptTemplateSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    required this.autoRetryEnabled,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<PromptTemplate> promptTemplates;
  final PromptTemplate? selectedPromptTemplate;
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool isBusy;
  final bool isStreaming;
  final int excludedMessageCount;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onPromptTemplateSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final bool autoRetryEnabled;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          final isCompact = constraints.maxWidth < compactComposerBreakpoint;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TemplateHeader(
                  selectedTemplatePrompt: selectedTemplatePrompt,
                  templatePrompts: templatePrompts,
                  isBusy: isBusy,
                  onTemplatePromptSelected: onTemplatePromptSelected,
                  onToggleComposerCollapsed: onToggleComposerCollapsed,
                ),
                if (selectedTemplatePrompt != null) ...[
                  const SizedBox(height: 10),
                  if (selectedTemplatePrompt!.inputVariables.isEmpty)
                    Text('当前模板没有额外变量。', style: theme.textTheme.bodySmall)
                  else
                    _TemplateVariableFields(
                      selectedTemplatePrompt: selectedTemplatePrompt!,
                      templateVariableControllers: templateVariableControllers,
                    ),
                  if (!selectedTemplatePrompt!.containsBodyVariable) ...[
                    const SizedBox(height: 4),
                    Text('正文会在发送时插入模板提示词上方。', style: theme.textTheme.bodySmall),
                  ],
                ],
                const SizedBox(height: 10),
                _MessageComposerField(
                  messageController: messageController,
                  messageFocusNode: messageFocusNode,
                  selectedTemplatePrompt: selectedTemplatePrompt,
                  onSendPressed: onSendPressed,
                ),
                const SizedBox(height: 8),
                _ProviderAndModelRow(
                  hasModels: hasModels,
                  modelProviders: modelProviders,
                  modelConfigs: modelConfigs,
                  selectedProviderId: selectedProviderId,
                  selectedModel: selectedModel,
                  isBusy: isBusy,
                  onProviderSelected: onProviderSelected,
                  onModelSelected: onModelSelected,
                ),
                const SizedBox(height: 6),
                if (isCompact)
                  _CompactActionRow(
                    hasModels: hasModels,
                    isBusy: isBusy,
                    isStreaming: isStreaming,
                    supportsReasoning: supportsReasoning,
                    reasoningEnabled: reasoningEnabled,
                    reasoningEffort: reasoningEffort,
                    autoRetryEnabled: autoRetryEnabled,
                    selectedPromptTemplate: selectedPromptTemplate,
                    excludedMessageCount: excludedMessageCount,
                    onOpenSettings: () {
                      _showCompactSecondarySettingsSheet(context, theme);
                    },
                    onSendPressed: onSendPressed,
                    onStopStreaming: onStopStreaming,
                  )
                else
                  _DesktopSecondarySettingsRow(
                    theme: theme,
                    hasModels: hasModels,
                    supportsReasoning: supportsReasoning,
                    reasoningEnabled: reasoningEnabled,
                    reasoningEffort: reasoningEffort,
                    autoRetryEnabled: autoRetryEnabled,
                    promptTemplates: promptTemplates,
                    selectedPromptTemplate: selectedPromptTemplate,
                    isBusy: isBusy,
                    isStreaming: isStreaming,
                    onReasoningEnabledChanged: onReasoningEnabledChanged,
                    onReasoningEffortChanged: onReasoningEffortChanged,
                    onAutoRetryEnabledChanged: onAutoRetryEnabledChanged,
                    onPromptTemplateSelected: onPromptTemplateSelected,
                    onOpenFixedPromptSequenceRunner:
                        onOpenFixedPromptSequenceRunner,
                    onOpenMessageFilter: onOpenMessageFilter,
                    excludedMessageCount: excludedMessageCount,
                    onSendPressed: onSendPressed,
                    onStopStreaming: onStopStreaming,
                  ),
              ],
            ),
          );
        },
      ),
    );
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
                    const SizedBox(height: 8),
                    AutoRetryToggle(
                      enabled: true,
                      value: autoRetryEnabled,
                      onChanged: onAutoRetryEnabledChanged,
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
                          selectedPromptTemplate?.id ??
                          noPromptTemplateSelectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '预设 Prompt'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: noPromptTemplateSelectedId,
                          child: Text('不使用预设 Prompt'),
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
                      onChanged: isBusy
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
                          onPressed: isBusy
                              ? null
                              : () async {
                                  Navigator.of(bottomSheetContext).pop();
                                  await onOpenFixedPromptSequenceRunner();
                                },
                          icon: const Icon(Icons.playlist_play_rounded),
                          label: const Text('固定顺序提示词'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('chat-message-filter-button'),
                        onPressed: isBusy
                            ? null
                            : () async {
                                Navigator.of(bottomSheetContext).pop();
                                await onOpenMessageFilter();
                              },
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: Text(_messageFilterLabel(excludedMessageCount)),
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
}

class _TemplateHeader extends StatelessWidget {
  const _TemplateHeader({
    required this.selectedTemplatePrompt,
    required this.templatePrompts,
    required this.isBusy,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
  });

  final TemplatePrompt? selectedTemplatePrompt;
  final List<TemplatePrompt> templatePrompts;
  final bool isBusy;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;

  @override
  Widget build(BuildContext context) {
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
            onChanged: isBusy ? null : onTemplatePromptSelected,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.outlined(
          onPressed: onToggleComposerCollapsed,
          tooltip: '收起输入区',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      ],
    );
  }
}

class _MessageComposerField extends StatelessWidget {
  const _MessageComposerField({
    required this.messageController,
    required this.messageFocusNode,
    required this.selectedTemplatePrompt,
    required this.onSendPressed,
  });

  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final TemplatePrompt? selectedTemplatePrompt;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: messageFocusNode,
      builder: (context, child) {
        final isFocused = messageFocusNode.hasFocus;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                onSendPressed?.call(),
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                onSendPressed?.call(),
          },
          child: TextField(
            key: const ValueKey('chat-message-composer'),
            controller: messageController,
            focusNode: messageFocusNode,
            minLines: 2,
            maxLines: isFocused ? 5 : 2,
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
      },
    );
  }
}

class _ProviderAndModelRow extends StatelessWidget {
  const _ProviderAndModelRow({
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.isBusy,
    required this.onProviderSelected,
    required this.onModelSelected,
  });

  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final bool isBusy;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-provider-selector'),
            isExpanded: true,
            initialValue: selectedProviderId,
            decoration: InputDecoration(
              labelText: '服务商',
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
            onChanged: isBusy || modelProviders.isEmpty
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onProviderSelected(value);
                  },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-model-selector'),
            initialValue: selectedModel?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '模型',
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
            onChanged: isBusy || modelConfigs.isEmpty
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
}

class _DesktopSecondarySettingsRow extends StatelessWidget {
  const _DesktopSecondarySettingsRow({
    required this.theme,
    required this.hasModels,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.autoRetryEnabled,
    required this.promptTemplates,
    required this.selectedPromptTemplate,
    required this.isBusy,
    required this.isStreaming,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onAutoRetryEnabledChanged,
    required this.onPromptTemplateSelected,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    required this.excludedMessageCount,
    required this.onSendPressed,
    required this.onStopStreaming,
  });

  final ThemeData theme;
  final bool hasModels;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool autoRetryEnabled;
  final List<PromptTemplate> promptTemplates;
  final PromptTemplate? selectedPromptTemplate;
  final bool isBusy;
  final bool isStreaming;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final ValueChanged<String?> onPromptTemplateSelected;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final int excludedMessageCount;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ThinkingToggle(
                enabled: supportsReasoning,
                value: supportsReasoning && reasoningEnabled,
                onChanged: onReasoningEnabledChanged,
              ),
              if (supportsReasoning && reasoningEnabled)
                _EffortPill(
                  theme: theme,
                  supportsReasoning: supportsReasoning,
                  reasoningEnabled: reasoningEnabled,
                  reasoningEffort: reasoningEffort,
                  onReasoningEffortChanged: onReasoningEffortChanged,
                ),
              AutoRetryToggle(
                enabled: true,
                value: autoRetryEnabled,
                onChanged: onAutoRetryEnabledChanged,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints.tightFor(width: 248),
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('chat-prompt-selector'),
                  initialValue:
                      selectedPromptTemplate?.id ?? noPromptTemplateSelectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '预设 Prompt'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: noPromptTemplateSelectedId,
                      child: Text('不使用预设 Prompt'),
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
                  onChanged: isBusy
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
              OutlinedButton.icon(
                key: const ValueKey('chat-message-filter-button'),
                onPressed: isBusy ? null : onOpenMessageFilter,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(_messageFilterLabel(excludedMessageCount)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Align(
          alignment: Alignment.topRight,
          child: _SendButton(
            theme: theme,
            isBusy: isBusy,
            isStreaming: isStreaming,
            hasModels: hasModels,
            expandLabel: false,
            onSendPressed: onSendPressed,
            onStopStreaming: onStopStreaming,
          ),
        ),
      ],
    );
  }
}

class _CompactActionRow extends StatelessWidget {
  const _CompactActionRow({
    required this.hasModels,
    required this.isBusy,
    required this.isStreaming,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.autoRetryEnabled,
    required this.selectedPromptTemplate,
    required this.excludedMessageCount,
    required this.onOpenSettings,
    required this.onSendPressed,
    required this.onStopStreaming,
  });

  final bool hasModels;
  final bool isBusy;
  final bool isStreaming;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool autoRetryEnabled;
  final PromptTemplate? selectedPromptTemplate;
  final int excludedMessageCount;
  final VoidCallback onOpenSettings;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('chat-secondary-settings-button'),
            onPressed: isBusy ? null : onOpenSettings,
            icon: const Icon(Icons.tune_rounded),
            label: Text(_compactSettingsSummary()),
          ),
        ),
        const SizedBox(width: 6),
        _SendButton(
          theme: Theme.of(context),
          isBusy: isBusy,
          isStreaming: isStreaming,
          hasModels: hasModels,
          expandLabel: true,
          onSendPressed: onSendPressed,
          onStopStreaming: onStopStreaming,
        ),
      ],
    );
  }

  String _compactSettingsSummary() {
    final parts = <String>[];
    parts.add(
      supportsReasoning && reasoningEnabled
          ? _effortLabel(reasoningEffort)
          : '思考关',
    );
    parts.add(autoRetryEnabled ? '重试开' : '重试关');
    parts.add(selectedPromptTemplate?.name ?? '无 Prompt');
    if (excludedMessageCount > 0) {
      parts.add('过滤 $excludedMessageCount 条');
    }
    return '更多设置 · ${parts.join(' · ')}';
  }
}

class _TemplateVariableFields extends StatelessWidget {
  const _TemplateVariableFields({
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
  });

  final TemplatePrompt selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 220.0;
        const gap = 6.0;
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
            for (final variable in selectedTemplatePrompt.inputVariables)
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
}

class _EffortPill extends StatelessWidget {
  const _EffortPill({
    required this.theme,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.onReasoningEffortChanged,
  });

  final ThemeData theme;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;

  @override
  Widget build(BuildContext context) {
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
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.theme,
    required this.isBusy,
    required this.isStreaming,
    required this.hasModels,
    required this.expandLabel,
    required this.onSendPressed,
    required this.onStopStreaming,
  });

  final ThemeData theme;
  final bool isBusy;
  final bool isStreaming;
  final bool hasModels;
  final bool expandLabel;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isStreaming
          ? () {
              onStopStreaming?.call();
            }
          : isBusy || !hasModels
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
}

String _effortLabel(ReasoningEffort effort) {
  return switch (effort) {
    ReasoningEffort.low => 'low',
    ReasoningEffort.medium => 'med',
    ReasoningEffort.high => 'high',
    ReasoningEffort.xhigh => 'xhigh',
  };
}

String _messageFilterLabel(int excludedMessageCount) {
  if (excludedMessageCount <= 0) {
    return '上下文过滤';
  }
  return '上下文过滤 · 已排除 $excludedMessageCount 条';
}
