import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/fixed_prompt_sequences_controller.dart';
import '../../domain/models/fixed_prompt_sequence.dart';
import 'settings_empty_state.dart';

/// 固定顺序提示词列表，负责展示、编辑和删除序列。
class FixedPromptSequencesList extends ConsumerWidget {
  const FixedPromptSequencesList({
    required this.sequences,
    required this.onEditRequested,
    super.key,
  });

  final List<FixedPromptSequence> sequences;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
  /// 构建序列列表；空列表时显示空状态提示。
  Widget build(BuildContext context, WidgetRef ref) {
    if (sequences.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.playlist_play_rounded,
        title: '还没有固定顺序提示词',
        description: '添加后，聊天页就可以按步骤填入或发送这些预设的用户提示词。',
      );
    }

    return Column(
      children: [
        for (final sequence in sequences)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FixedPromptSequenceTile(
              sequence: sequence,
              onEditRequested: onEditRequested,
            ),
          ),
      ],
    );
  }
}

/// 单个固定顺序提示词序列卡片。
class _FixedPromptSequenceTile extends ConsumerWidget {
  const _FixedPromptSequenceTile({
    required this.sequence,
    required this.onEditRequested,
  });

  final FixedPromptSequence sequence;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
  /// 构建序列摘要、步骤预览和操作按钮。
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sequence.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(sequence.summary),
            if (sequence.steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (
                var index = 0;
                index < sequence.steps.length && index < 3;
                index++
              )
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${index + 1}. ${_summarize(sequence.steps[index].content)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditRequested(sequence),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(fixedPromptSequencesProvider.notifier)
                        .deleteById(sequence.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('固定顺序提示词已删除')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 把长文本截断为适合列表显示的摘要。
  String _summarize(String content) {
    final normalized = content.trim().replaceAll('\n', ' ');
    if (normalized.length <= 30) {
      return normalized;
    }

    return '${normalized.substring(0, 30)}...';
  }
}
