import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/features/chat/application/composer/template_prompt_compilation_provider.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';
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

/// 一次模板校验的展示结果：编译/值错误、活跃变量与发送可用性。
class _ComposerTemplateValidation {
  const _ComposerTemplateValidation({
    required this.sendAllowed,
    this.compileErrorText,
    this.program,
    this.activeInputVariableNames = const {},
    this.valueErrorsByVariable = const {},
  });

  final bool sendAllowed;

  /// 编译失败时的首个诊断消息（模板区域 inline 展示）。
  final String? compileErrorText;

  /// 有效编译的程序；编译失败时为 null（不渲染字段）。
  final TemplatePromptProgram? program;
  final Set<String> activeInputVariableNames;
  final Map<String, TemplatePromptValueError> valueErrorsByVariable;
}

/// 聊天工作区中的输入与设置面板。
class ChatComposerCard extends ConsumerWidget {
  const ChatComposerCard({
    required this.state,
    required this.bindings,
    super.key,
  });

  final ChatWorkspaceComposerState state;
  final ChatWorkspaceComposerBindings bindings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedTemplate = state.selectedTemplatePrompt;
    // 选中的模板经唯一编译缓存边界编译一次，值变化只重新求值。
    final compilation = selectedTemplate == null
        ? null
        : ref.watch(templatePromptCompilationProvider(selectedTemplate));
    // 用 AnimatedCrossFade 同步驱动高度过渡与内容淡入淡出，避免
    // AnimatedSize+AnimatedSwitcher 组合时 fade 期间旧 child 仍占满高度、
    // 高度动画延迟到 fade 结束才触发的「dead zone」中间态。
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      firstChild: _buildCollapsed(context, theme),
      secondChild: _buildExpanded(context, theme, compilation),
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
  Widget _buildExpanded(
    BuildContext context,
    ThemeData theme,
    TemplatePromptCompilation? compilation,
  ) {
    // 是否有可用模型决定「去设置新增」还是「请先选择服务商」的提示。
    // 可选模型列表非空即等价于已配置任何模型（模型总被归入某服务商）。
    final hasModels = state.modelConfigs.isNotEmpty;
    final selectedTemplate = state.selectedTemplatePrompt;
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
            // 变量/正文控制器变化不经过 Riverpod，用 ListenableBuilder 合并监听：
            // 任一变化都重新求值可见分支与值错误，并联动发送可用性。
            child: ListenableBuilder(
              listenable: Listenable.merge([
                bindings.messageController,
                ...bindings.templateVariableControllers.values,
              ]),
              builder: (context, _) {
                final validation = _resolveTemplateValidation(compilation);
                final effectiveOnSend = validation.sendAllowed
                    ? bindings.onSendPressed
                    : null;

                return Column(
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
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
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
                                      color: theme
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ComposerTemplateHeader(
                      selectedTemplatePrompt: selectedTemplate,
                      templatePrompts: state.templatePrompts,
                      onTemplatePromptSelected:
                          bindings.onTemplatePromptSelected,
                      onToggleComposerCollapsed:
                          bindings.onToggleComposerCollapsed,
                    ),
                    if (selectedTemplate != null) ...[
                      const SizedBox(height: 10),
                      // program 为 null 也并入诊断分支：不依赖「编译失败必有
                      // 诊断」的编译器不变量，编译器违约时同样不触碰 program
                      // 字段，消除空安全 NPE 风险。
                      if (validation.compileErrorText != null ||
                          validation.program == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '模板语法无效，请到设置中修正：${validation.compileErrorText}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        )
                      else if (validation.program!.inputVariables.isEmpty)
                        Text('当前模板没有额外变量。', style: theme.textTheme.bodySmall)
                      else
                        ComposerTemplateVariableFields(
                          program: validation.program!,
                          activeInputVariableNames:
                              validation.activeInputVariableNames,
                          templateVariableControllers:
                              bindings.templateVariableControllers,
                          valueErrorsByVariable:
                              validation.valueErrorsByVariable,
                        ),
                      if (!selectedTemplate.containsBodyVariable) ...[
                        const SizedBox(height: 4),
                        Text(
                          '正文会在发送时插入模板提示词上方。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    ComposerMessageField(
                      messageController: bindings.messageController,
                      messageFocusNode: bindings.messageFocusNode,
                      selectedTemplatePrompt: selectedTemplate,
                      onSendPressed: effectiveOnSend,
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
                        onSendPressed: effectiveOnSend,
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
                        onReasoningEffortChanged:
                            bindings.onReasoningEffortChanged,
                        onAutoRetryEnabledChanged:
                            bindings.onAutoRetryEnabledChanged,
                        onOpenFixedPromptSequenceRunner:
                            bindings.onOpenFixedPromptSequenceRunner,
                        onOpenMessageFilter: bindings.onOpenMessageFilter,
                        excludedMessageCount: state.excludedMessageCount,
                        onSendPressed: effectiveOnSend,
                        onStopStreaming: bindings.onStopStreaming,
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 由当前编译结果与控制器值求一次校验快照。
  ///
  /// 求值只用于字段可见性/校验，不产生预览字符串；发送边界仍由
  /// Task 3 的 command 权威校验。
  _ComposerTemplateValidation _resolveTemplateValidation(
    TemplatePromptCompilation? compilation,
  ) {
    if (compilation == null) {
      return const _ComposerTemplateValidation(sendAllowed: true);
    }
    final program = compilation.program;
    if (!compilation.isValid || program == null) {
      final message = compilation.diagnostics.isEmpty
          ? null
          : compilation.diagnostics.first.message;
      return _ComposerTemplateValidation(
        sendAllowed: false,
        compileErrorText: message,
      );
    }
    final rawValues = {
      for (final variable in program.inputVariables)
        variable.name:
            bindings.templateVariableControllers[variable.name]?.text ?? '',
    };
    final evaluation = evaluateTemplatePrompt(
      program: program,
      body: bindings.messageController.text,
      variableValues: rawValues,
    );
    return _ComposerTemplateValidation(
      sendAllowed: evaluation.isValid,
      program: program,
      activeInputVariableNames: evaluation.activeInputVariableNames.toSet(),
      valueErrorsByVariable: {
        for (final error in evaluation.valueErrors) error.variableName: error,
      },
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
