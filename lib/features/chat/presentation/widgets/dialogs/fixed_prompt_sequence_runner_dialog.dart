import 'package:flutter/material.dart';

import '../../../../settings/domain/models/fixed_prompt_sequence.dart';

/// 固定顺序提示词运行器关闭后要执行的动作。
enum FixedPromptSequenceRunnerAction { none, fillComposer, sendStep }

/// 固定顺序提示词运行器的返回结果。
class FixedPromptSequenceRunnerResult {
  const FixedPromptSequenceRunnerResult({
    required this.action,
    required this.content,
    required this.nextStepIndex,
    this.selectedSequenceId,
  });

  final FixedPromptSequenceRunnerAction action;
  final String? selectedSequenceId;
  final String content;
  final int nextStepIndex;
}

/// 聊天页中的固定顺序提示词运行器弹窗。
class FixedPromptSequenceRunnerDialog extends StatefulWidget {
  const FixedPromptSequenceRunnerDialog({
    required this.sequences,
    required this.initialSelectedSequenceId,
    required this.initialStepIndex,
    required this.canSendDirectly,
    super.key,
  });

  final List<FixedPromptSequence> sequences;
  final String? initialSelectedSequenceId;
  final int initialStepIndex;
  final bool canSendDirectly;

  @override
  State<FixedPromptSequenceRunnerDialog> createState() =>
      _FixedPromptSequenceRunnerDialogState();
}

/// 固定顺序提示词运行器的本地选择状态。
class _FixedPromptSequenceRunnerDialogState
    extends State<FixedPromptSequenceRunnerDialog> {
  late String? _selectedSequenceId;
  late int _stepIndex;

  FixedPromptSequence? get _selectedSequence {
    if (widget.sequences.isEmpty) {
      return null;
    }

    return widget.sequences
            .where((sequence) => sequence.id == _selectedSequenceId)
            .firstOrNull ??
        widget.sequences.first;
  }

  FixedPromptSequenceStep? get _currentStep {
    final sequence = _selectedSequence;
    if (sequence == null || sequence.steps.isEmpty) {
      return null;
    }

    final safeIndex = _normalizeStepIndex(_stepIndex, sequence.steps.length);
    return sequence.steps[safeIndex];
  }

  @override
  void initState() {
    super.initState();
    _selectedSequenceId = widget.initialSelectedSequenceId;
    final initialSequence =
        widget.sequences
            .where(
              (sequence) => sequence.id == widget.initialSelectedSequenceId,
            )
            .firstOrNull ??
        widget.sequences.firstOrNull;
    _stepIndex = _normalizeStepIndex(
      widget.initialStepIndex,
      initialSequence?.steps.length ?? 0,
    );
  }

  @override
  /// 构建序列选择、步骤预览和动作按钮。
  Widget build(BuildContext context) {
    final sequence = _selectedSequence;
    final currentStep = _currentStep;

    return AlertDialog(
      title: const Text('固定顺序提示词'),
      content: SizedBox(
        width: 680,
        child: widget.sequences.isEmpty
            ? const Text('还没有可用的固定顺序提示词，请先去设置页添加。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: sequence?.id,
                    isExpanded: true,
                    items: widget.sequences
                        .map((item) {
                          return DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        })
                        .toList(growable: false),
                    onChanged: (value) {
                      setState(() {
                        _selectedSequenceId = value;
                        _stepIndex = 0;
                      });
                    },
                    decoration: const InputDecoration(labelText: '选择序列'),
                  ),
                  const SizedBox(height: 12),
                  if (sequence != null && sequence.steps.isNotEmpty) ...[
                    Row(
                      children: [
                        Chip(
                          label: Text(
                            '步骤 ${_stepIndex + 1} / ${sequence.steps.length}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _stepIndex,
                            isExpanded: true,
                            items: [
                              for (
                                var index = 0;
                                index < sequence.steps.length;
                                index += 1
                              )
                                DropdownMenuItem(
                                  value: index,
                                  child: Text(
                                    '跳到步骤 ${index + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _stepIndex = value;
                              });
                            },
                            decoration: const InputDecoration(labelText: '定位'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前步骤内容',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: SingleChildScrollView(
                            child: SelectableText(currentStep?.content ?? ''),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '你可以先填入输入框再改，也可以直接发送当前步骤；发送后只会把当前位置前进到下一步，不会自动连发。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else ...[
                    const Text('这个序列还没有步骤，请先去设置页补充内容。'),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              FixedPromptSequenceRunnerResult(
                action: FixedPromptSequenceRunnerAction.none,
                content: '',
                nextStepIndex: _stepIndex,
                selectedSequenceId: _selectedSequence?.id,
              ),
            );
          },
          child: const Text('关闭'),
        ),
        if (currentStep != null) ...[
          OutlinedButton.icon(
            onPressed: _stepIndex > 0
                ? () {
                    setState(() {
                      _stepIndex -= 1;
                    });
                  }
                : null,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('上一步'),
          ),
          OutlinedButton.icon(
            onPressed: _stepIndex < (_selectedSequence?.steps.length ?? 0) - 1
                ? () {
                    setState(() {
                      _stepIndex += 1;
                    });
                  }
                : null,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('下一步'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop(
                FixedPromptSequenceRunnerResult(
                  action: FixedPromptSequenceRunnerAction.fillComposer,
                  content: currentStep.content,
                  nextStepIndex: _stepIndex,
                  selectedSequenceId: _selectedSequence?.id,
                ),
              );
            },
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('填入输入框'),
          ),
          FilledButton.icon(
            onPressed: widget.canSendDirectly
                ? () {
                    Navigator.of(context).pop(
                      FixedPromptSequenceRunnerResult(
                        action: FixedPromptSequenceRunnerAction.sendStep,
                        content: currentStep.content,
                        nextStepIndex: _resolveNextStepIndex(),
                        selectedSequenceId: _selectedSequence?.id,
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('发送当前步骤'),
          ),
        ],
      ],
    );
  }

  /// 规范化步骤索引，避免序列切换或步骤变更后越界。
  int _normalizeStepIndex(int rawIndex, int stepCount) {
    if (stepCount <= 0) {
      return 0;
    }

    if (rawIndex < 0) {
      return 0;
    }

    if (rawIndex >= stepCount) {
      return stepCount - 1;
    }

    return rawIndex;
  }

  /// 计算发送当前步骤后应该停留的下一步索引。
  int _resolveNextStepIndex() {
    final stepCount = _selectedSequence?.steps.length ?? 0;
    if (stepCount <= 0) {
      return 0;
    }

    return _stepIndex >= stepCount - 1 ? _stepIndex : _stepIndex + 1;
  }
}
