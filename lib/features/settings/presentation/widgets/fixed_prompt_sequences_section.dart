import 'package:flutter/material.dart';

import '../../domain/models/fixed_prompt_sequence.dart';
import 'fixed_prompt_sequences_list.dart';
import 'settings_section_card.dart';

/// 设置页中的固定顺序提示词分区。
class FixedPromptSequencesSection extends StatelessWidget {
  const FixedPromptSequencesSection({
    required this.sequences,
    required this.onAddPressed,
    required this.onEditRequested,
    super.key,
  });

  final List<FixedPromptSequence> sequences;
  final VoidCallback onAddPressed;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '固定顺序提示词',
      description: '配置可逐步发送的用户提示词序列，适合做模型对比测试，不会自动整组连发。',
      action: FilledButton.icon(
        onPressed: onAddPressed,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增序列'),
      ),
      child: FixedPromptSequencesList(
        sequences: sequences,
        onEditRequested: onEditRequested,
      ),
    );
  }
}
