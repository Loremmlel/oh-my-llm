import 'package:flutter/material.dart';

import '../../domain/models/chat_message.dart';
import 'auto_retry_toggle.dart';
import 'composer/composer_compact_action_row.dart';
import 'composer/composer_desktop_settings_row.dart';
import 'composer/composer_helpers.dart';
import 'composer/composer_message_field.dart';
import 'composer/composer_provider_model_row.dart';
import 'composer/composer_template_header.dart';
import 'composer/composer_template_variable_fields.dart';
import 'composer_data.dart';
import 'thinking_toggle.dart';

/// 聊天工作区中的输入与设置面板。
class ChatComposerCard extends StatelessWidget {
  static const compactComposerBreakpoint = 680.0;

  const ChatComposerCard({
    required this.data,
    required this.callbacks,
    required this.messageController,
    required this.messageFocusNode,
    super.key,
  });

  final ComposerData data;
  final ComposerCallbacks callbacks;
  final TextEditingController messageController;
  final FocusNode messageFocusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.isComposerCollapsed) {
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
                  onPressed: callbacks.onToggleComposerCollapsed,
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
                ComposerTemplateHeader(
                  selectedTemplatePrompt: data.selectedTemplatePrompt,
                  templatePrompts: data.templatePrompts,
                  onTemplatePromptSelected: callbacks.onTemplatePromptSelected,
                  onToggleComposerCollapsed:
                      callbacks.onToggleComposerCollapsed,
                ),
                if (data.selectedTemplatePrompt != null) ...[
                  const SizedBox(height: 10),
                  if (data.selectedTemplatePrompt!.inputVariables.isEmpty)
                    Text('当前模板没有额外变量。', style: theme.textTheme.bodySmall)
                  else
                    ComposerTemplateVariableFields(
                      selectedTemplatePrompt: data.selectedTemplatePrompt!,
                      templateVariableControllers:
                          data.templateVariableControllers,
                    ),
                  if (!data.selectedTemplatePrompt!.containsBodyVariable) ...[
                    const SizedBox(height: 4),
                    Text('正文会在发送时插入模板提示词上方。', style: theme.textTheme.bodySmall),
                  ],
                ],
                const SizedBox(height: 10),
                ComposerMessageField(
                  messageController: messageController,
                  messageFocusNode: messageFocusNode,
                  selectedTemplatePrompt: data.selectedTemplatePrompt,
                  onSendPressed: callbacks.onSendPressed,
                ),
                const SizedBox(height: 8),
                ComposerProviderModelRow(
                  hasModels: data.hasModels,
                  modelProviders: data.modelProviders,
                  modelConfigs: data.modelConfigs,
                  selectedProviderId: data.selectedProviderId,
                  selectedModel: data.selectedModel,
                  onProviderSelected: callbacks.onProviderSelected,
                  onModelSelected: callbacks.onModelSelected,
                ),
                const SizedBox(height: 6),
                if (isCompact)
                  ComposerCompactActionRow(
                    hasModels: data.hasModels,
                    isBusy: data.isBusy,
                    isStreaming: data.isStreaming,
                    isAutoRetryWaiting: data.isAutoRetryWaiting,
                    supportsReasoning: data.supportsReasoning,
                    reasoningEnabled: data.reasoningEnabled,
                    reasoningEffort: data.reasoningEffort,
                    autoRetryEnabled: data.autoRetryEnabled,
                    excludedMessageCount: data.excludedMessageCount,
                    onOpenSettings: () {
                      _showCompactSecondarySettingsSheet(context, theme);
                    },
                    onSendPressed: callbacks.onSendPressed,
                    onStopStreaming: callbacks.onStopStreaming,
                  )
                else
                  ComposerDesktopSettingsRow(
                    theme: theme,
                    hasModels: data.hasModels,
                    supportsReasoning: data.supportsReasoning,
                    reasoningEnabled: data.reasoningEnabled,
                    reasoningEffort: data.reasoningEffort,
                    autoRetryEnabled: data.autoRetryEnabled,
                    isBusy: data.isBusy,
                    isStreaming: data.isStreaming,
                    isAutoRetryWaiting: data.isAutoRetryWaiting,
                    onReasoningEnabledChanged:
                        callbacks.onReasoningEnabledChanged,
                    onReasoningEffortChanged:
                        callbacks.onReasoningEffortChanged,
                    onAutoRetryEnabledChanged:
                        callbacks.onAutoRetryEnabledChanged,
                    onOpenFixedPromptSequenceRunner:
                        callbacks.onOpenFixedPromptSequenceRunner,
                    onOpenMessageFilter: callbacks.onOpenMessageFilter,
                    excludedMessageCount: data.excludedMessageCount,
                    onSendPressed: callbacks.onSendPressed,
                    onStopStreaming: callbacks.onStopStreaming,
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
    var localReasoningEnabled = data.supportsReasoning && data.reasoningEnabled;
    var localEffort = data.reasoningEffort;
    var localAutoRetryEnabled = data.autoRetryEnabled;

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
                      enabled: data.supportsReasoning,
                      value: localReasoningEnabled,
                      onChanged: data.supportsReasoning
                          ? (value) {
                              setModalState(() {
                                localReasoningEnabled = value;
                              });
                              callbacks.onReasoningEnabledChanged?.call(value);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    AutoRetryToggle(
                      enabled: true,
                      value: localAutoRetryEnabled,
                      onChanged: (value) {
                        setModalState(() {
                          localAutoRetryEnabled = value;
                        });
                        callbacks.onAutoRetryEnabledChanged?.call(value);
                      },
                    ),
                    if (data.supportsReasoning && localReasoningEnabled) ...[
                      const SizedBox(height: 12),
                      Text('思考强度', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final effort in ReasoningEffort.values)
                            ChoiceChip(
                              label: Text(effortLabel(effort)),
                              selected: localEffort == effort,
                              onSelected: (_) {
                                setModalState(() {
                                  localEffort = effort;
                                });
                                callbacks.onReasoningEffortChanged?.call(
                                  effort,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Tooltip(
                        message: '固定顺序提示词',
                        child: OutlinedButton.icon(
                          // 流式中仍可打开：仅对话框内「发送当前步骤」按 !isBusy 锁定。
                          onPressed: () async {
                            Navigator.of(bottomSheetContext).pop();
                            await callbacks.onOpenFixedPromptSequenceRunner();
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
                        // 上下文过滤只影响下次发送，流式中无需锁定。
                        onPressed: () async {
                          Navigator.of(bottomSheetContext).pop();
                          await callbacks.onOpenMessageFilter();
                        },
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: Text(
                          messageFilterLabel(data.excludedMessageCount),
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
}
