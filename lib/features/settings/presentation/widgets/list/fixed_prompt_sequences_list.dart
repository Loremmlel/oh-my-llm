import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/text_formatting.dart';
import '../../../application/fixed_prompt_sequences_controller.dart';
import '../../../domain/models/fixed_prompt_sequence.dart';
import '../settings_card_grid.dart';
import '../settings_empty_state.dart';
import '../settings_entity_card.dart';
import '../settings_helpers.dart';

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
  Widget build(BuildContext context, WidgetRef ref) {
    if (sequences.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.playlist_play_rounded,
        title: '还没有固定顺序提示词',
        description: '添加后，聊天页就可以按步骤填入或发送这些预设的用户提示词。',
      );
    }

    return SettingsCardGrid(
      children: [
        for (final sequence in sequences)
          _FixedPromptSequenceTile(
            sequence: sequence,
            onEditRequested: onEditRequested,
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
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsEntityCard(
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
      actions: [
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
            // ignore: use_build_context_synchronously
            showSettingsSnackbar(context, '固定顺序提示词已删除');
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除'),
        ),
      ],
    );
  }
}
