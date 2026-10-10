import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/utils/text_formatting.dart';

import '../../../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../shared/settings_empty_state.dart';
import '../../shared/settings_entity_row.dart';
import '../../shared/settings_helpers.dart';

/// 固定顺序提示词列表，负责展示、编辑和删除序列。
class FixedPromptSequencesList extends StatelessWidget {
  const FixedPromptSequencesList({
    required this.sequences,
    required this.onEditRequested,
    required this.onDelete,
    super.key,
  });

  final List<FixedPromptSequence> sequences;
  final ValueChanged<FixedPromptSequence> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
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
          _FixedPromptSequenceTile(
            sequence: sequence,
            onEditRequested: onEditRequested,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

/// 单个固定顺序提示词序列记录。
class _FixedPromptSequenceTile extends StatelessWidget {
  const _FixedPromptSequenceTile({
    required this.sequence,
    required this.onEditRequested,
    required this.onDelete,
  });

  final FixedPromptSequence sequence;
  final ValueChanged<FixedPromptSequence> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsEntityRow(
      title: sequence.name,
      body: [
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
                '${index + 1}. ${sequence.steps[index].title.isEmpty ? summarizeText(sequence.steps[index].content) : sequence.steps[index].title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
      actions: editDeleteActions(
        onEdit: () => onEditRequested(sequence),
        onDelete: () {
          onDelete(sequence.id).then((_) {
            if (context.mounted) {
              showSettingsSnackbar(context, '固定顺序提示词已删除');
            }
          });
        },
      ),
    );
  }
}
