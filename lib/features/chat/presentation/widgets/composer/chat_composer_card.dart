import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import '../../../domain/models/chat_message.dart';
import '../workspace/chat_workspace_bindings.dart';
import '../../../application/workspace/chat_workspace_view_state.dart';
import 'controls/auto_retry_toggle.dart';
import 'controls/thinking_toggle.dart';
import 'layout/composer_compact_action_row.dart';
import 'layout/composer_desktop_settings_row.dart';
import 'composer_helpers.dart';
import 'fields/composer_message_field.dart';
import 'layout/composer_provider_model_row.dart';
import 'layout/composer_template_header.dart';
import 'fields/composer_template_variable_fields.dart';

/// 聊天工作区中的输入与设置面板。
class ChatComposerCard extends StatelessWidget {
  const ChatComposerCard({
    required this.state,
    required this.bindings,
    super.key,
  });

  final ChatWorkspaceComposerState state;
  final ChatWorkspaceComposerBindings bindings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 用 AnimatedCrossFade 同步驱动高度过渡与内容淡入淡出，避免
    // AnimatedSize+AnimatedSwitcher 组合时 fade 期间旧 child 仍占满高度、
    // 高度动画延迟到 fade 结束才触发的「dead zone」中间态。
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      firstChild: _buildCollapsed(context, theme),
      secondChild: _buildExpanded(theme),
      crossFadeState: state.isComposerCollapsed
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      sizeCurve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
    );
  }

  /// 折叠态：仅显示一行提示与展开按钮。
  Widget _buildCollapsed(BuildContext context, ThemeData theme) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppBreakpoints.isCompactShell(context) ? 10 : 14,
          vertical: AppBreakpoints.isCompactShell(context) ? 8 : 10,
        ),
        child: Row(
          children: [
            const Icon(Icons.keyboard_arrow_up_rounded),
            const SizedBox(width: 8),
            Expanded(child: Text('输入区已隐藏', style: theme.textTheme.bodyMedium)),
            Tooltip(
              message: '展开输入区',
              child: OutlinedButton.icon(
                onPressed: bindings.onToggleComposerCollapsed,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text('展开'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 展开态：完整的模板/输入框/操作行。
  Widget _buildExpanded(ThemeData theme) {
    // 是否有可用模型决定「去设置新增」还是「请先选择服务商」的提示。
    // 可选模型列表非空即等价于已配置任何模型（模型总被归入某服务商）。
    final hasModels = state.modelConfigs.isNotEmpty;
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // isCompactComposer 是输入区自身的 formActions（680）断点，决定操作行
          // 紧凑/桌面布局；与 isCompactShell（720，影响 padding）含义不同，不可混用。
          final isCompactComposer = AppBreakpoints.useCompactFormActions(
            constraints.maxWidth,
          );

          return Padding(
            padding: EdgeInsets.all(
              AppBreakpoints.isCompactShell(context) ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.isEditingMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '正在编辑消息…',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: '取消编辑',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: bindings.onCancelEdit,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ComposerTemplateHeader(
                  selectedTemplatePrompt: state.selectedTemplatePrompt,
                  templatePrompts: state.templatePrompts,
                  onTemplatePromptSelected: bindings.onTemplatePromptSelected,
                  onToggleComposerCollapsed: bindings.onToggleComposerCollapsed,
                ),
                if (state.selectedTemplatePrompt != null) ...[
                  const SizedBox(height: 10),
                  if (state.selectedTemplatePrompt!.inputVariables.isEmpty)
                    Text('当前模板没有额外变量。', style: theme.textTheme.bodySmall)
                  else
                    ComposerTemplateVariableFields(
                      selectedTemplatePrompt: state.selectedTemplatePrompt!,
                      templateVariableControllers:
                          bindings.templateVariableControllers,
                    ),
                  if (!state.selectedTemplatePrompt!.containsBodyVariable) ...[
                    const SizedBox(height: 4),
                    Text('正文会在发送时插入模板提示词上方。', style: theme.textTheme.bodySmall),
                  ],
                ],
                const SizedBox(height: 10),
                ComposerMessageField(
                  messageController: bindings.messageController,
                  messageFocusNode: bindings.messageFocusNode,
                  selectedTemplatePrompt: state.selectedTemplatePrompt,
                  onSendPressed: bindings.onSendPressed,
                ),
                const SizedBox(height: 8),
                ComposerProviderModelRow(
                  hasModels: hasModels,
                  modelProviders: state.modelProviders,
                  modelConfigs: state.modelConfigs,
                  selectedProviderId: state.selectedProviderId,
                  selectedModel: state.selectedModel,
                  onProviderSelected: bindings.onProviderSelected,
                  onModelSelected: bindings.onModelSelected,
                ),
                const SizedBox(height: 6),
                if (isCompactComposer)
                  ComposerCompactActionRow(
                    hasModels: hasModels,
                    isBusy: state.isBusy,
                    isStreaming: state.isStreaming,
                    isAutoRetryWaiting: state.isAutoRetryWaiting,
                    supportsReasoning: state.supportsReasoning,
                    reasoningEnabled: state.reasoningEnabled,
                    reasoningEffort: state.reasoningEffort,
                    autoRetryEnabled: state.autoRetryEnabled,
                    excludedMessageCount: state.excludedMessageCount,
                    onOpenSettings: () {
                      _showCompactSecondarySettingsSheet(context, theme);
                    },
                    onSendPressed: bindings.onSendPressed,
                    onStopStreaming: bindings.onStopStreaming,
                  )
                else
                  ComposerDesktopSettingsRow(
                    theme: theme,
                    hasModels: hasModels,
                    supportsReasoning: state.supportsReasoning,
                    reasoningEnabled: state.reasoningEnabled,
                    reasoningEffort: state.reasoningEffort,
                    autoRetryEnabled: state.autoRetryEnabled,
                    isBusy: state.isBusy,
                    isStreaming: state.isStreaming,
                    isAutoRetryWaiting: state.isAutoRetryWaiting,
                    onReasoningEnabledChanged:
                        bindings.onReasoningEnabledChanged,
                    onReasoningEffortChanged: bindings.onReasoningEffortChanged,
                    onAutoRetryEnabledChanged:
                        bindings.onAutoRetryEnabledChanged,
                    onOpenFixedPromptSequenceRunner:
                        bindings.onOpenFixedPromptSequenceRunner,
                    onOpenMessageFilter: bindings.onOpenMessageFilter,
                    excludedMessageCount: state.excludedMessageCount,
                    onSendPressed: bindings.onSendPressed,
                    onStopStreaming: bindings.onStopStreaming,
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
    var localReasoningEnabled =
        state.supportsReasoning && state.reasoningEnabled;
    var localEffort = state.reasoningEffort;
    var localAutoRetryEnabled = state.autoRetryEnabled;

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
                    // 深度思考与自动重试自适应分布，不独占整行
                    Row(
                      children: [
                        Flexible(
                          child: ThinkingToggle(
                            enabled: state.supportsReasoning,
                            value: localReasoningEnabled,
                            onChanged: state.supportsReasoning
                                ? (value) {
                                    setModalState(() {
                                      localReasoningEnabled = value;
                                    });
                                    bindings.onReasoningEnabledChanged?.call(
                                      value,
                                    );
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: AutoRetryToggle(
                            enabled: true,
                            value: localAutoRetryEnabled,
                            onChanged: (value) {
                              setModalState(() {
                                localAutoRetryEnabled = value;
                              });
                              bindings.onAutoRetryEnabledChanged?.call(value);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (state.supportsReasoning && localReasoningEnabled) ...[
                      const SizedBox(height: 12),
                      Text('思考强度', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final effort in ReasoningEffort.values)
                            ChoiceChip(
                              // 关闭 checkmark：其 150ms 宽度动画会让 Wrap 在窄屏
                              // 跨越换行阈值，导致弹窗高度随选中项跳变；
                              // 选中态改由背景色与边框区分。
                              showCheckmark: false,
                              label: Text(effortLabel(effort)),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              selected: localEffort == effort,
                              onSelected: (_) {
                                setModalState(() {
                                  localEffort = effort;
                                });
                                bindings.onReasoningEffortChanged?.call(effort);
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
                            await bindings.onOpenFixedPromptSequenceRunner();
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
                          await bindings.onOpenMessageFilter();
                        },
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: Text(
                          messageFilterLabel(state.excludedMessageCount),
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
