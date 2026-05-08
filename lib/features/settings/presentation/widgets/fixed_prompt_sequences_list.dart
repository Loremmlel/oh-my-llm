import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../application/fixed_prompt_sequences_controller.dart';
import '../../domain/models/fixed_prompt_sequence.dart';
import 'settings_empty_state.dart';

/// 固定顺序提示词列表，负责展示、编辑和删除序列。
class FixedPromptSequencesList extends ConsumerStatefulWidget {
  const FixedPromptSequencesList({
    required this.sequences,
    required this.onEditRequested,
    super.key,
  });

  final List<FixedPromptSequence> sequences;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
  ConsumerState<FixedPromptSequencesList> createState() =>
      _FixedPromptSequencesListState();
}

class _FixedPromptSequencesListState
    extends ConsumerState<FixedPromptSequencesList> {
  String? _selectedSequenceId;

  @override
  void initState() {
    super.initState();
    _selectedSequenceId = widget.sequences.isEmpty
        ? null
        : widget.sequences.first.id;
  }

  @override
  void didUpdateWidget(covariant FixedPromptSequencesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sequences.isEmpty) {
      _selectedSequenceId = null;
      return;
    }
    final stillExists = widget.sequences.any(
      (item) => item.id == _selectedSequenceId,
    );
    if (!stillExists) {
      _selectedSequenceId = widget.sequences.first.id;
    }
  }

  FixedPromptSequence get _selectedSequence {
    return widget.sequences.firstWhere(
      (item) => item.id == _selectedSequenceId,
      orElse: () => widget.sequences.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sequences.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.playlist_play_rounded,
        title: '还没有固定顺序提示词',
        description: '添加后，聊天页就可以按步骤填入或发送这些预设的用户提示词。',
      );
    }

    return AdaptiveMasterDetailLayout(
      key: const ValueKey('fixed-sequences-master-detail'),
      breakpoint: 860,
      masterWidth: 300,
      minHeight: 420,
      compactChild: LayoutBuilder(
        builder: (context, constraints) {
          const minItemWidth = 280.0;
          const gap = 12.0;
          final crossAxisCount =
              ((constraints.maxWidth + gap) / (minItemWidth + gap))
                  .floor()
                  .clamp(1, 3);
          return _buildCompactGrid(
            widget.sequences,
            crossAxisCount,
            gap,
            constraints.maxWidth,
          );
        },
      ),
      master: _FixedPromptSequenceMasterPane(
        sequences: widget.sequences,
        selectedSequenceId: _selectedSequence.id,
        onSelected: (sequence) {
          setState(() {
            _selectedSequenceId = sequence.id;
          });
        },
      ),
      detail: _FixedPromptSequenceDetailPane(
        sequence: _selectedSequence,
        onEditRequested: widget.onEditRequested,
      ),
    );
  }

  Widget _buildCompactGrid(
    List<FixedPromptSequence> items,
    int crossAxisCount,
    double gap,
    double availableWidth,
  ) {
    if (crossAxisCount == 1) {
      return Column(
        children: [
          for (final sequence in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FixedPromptSequenceCompactTile(
                sequence: sequence,
                onEditRequested: widget.onEditRequested,
              ),
            ),
        ],
      );
    }

    final itemWidth =
        (availableWidth - gap * (crossAxisCount - 1)) / crossAxisCount;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += crossAxisCount) {
      final rowItems = items.skip(i).take(crossAxisCount).toList();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) SizedBox(width: gap),
                SizedBox(
                  width: itemWidth,
                  child: _FixedPromptSequenceCompactTile(
                    sequence: rowItems[j],
                    onEditRequested: widget.onEditRequested,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _FixedPromptSequenceMasterPane extends StatelessWidget {
  const _FixedPromptSequenceMasterPane({
    required this.sequences,
    required this.selectedSequenceId,
    required this.onSelected,
  });

  final List<FixedPromptSequence> sequences;
  final String selectedSequenceId;
  final ValueChanged<FixedPromptSequence> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView.separated(
          itemCount: sequences.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final sequence = sequences[index];
            return _FixedPromptSequenceSelectionTile(
              sequence: sequence,
              selected: sequence.id == selectedSequenceId,
              onTap: () => onSelected(sequence),
            );
          },
        ),
      ),
    );
  }
}

class _FixedPromptSequenceSelectionTile extends StatelessWidget {
  const _FixedPromptSequenceSelectionTile({
    required this.sequence,
    required this.selected,
    required this.onTap,
  });

  final FixedPromptSequence sequence;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.72)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sequence.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                sequence.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${sequence.steps.length} 步',
                style: theme.textTheme.labelMedium,
              ),
              if (sequence.steps.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '1. ${_summarizeFixedSequence(sequence.steps.first.content)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FixedPromptSequenceDetailPane extends ConsumerWidget {
  const _FixedPromptSequenceDetailPane({
    required this.sequence,
    required this.onEditRequested,
  });

  final FixedPromptSequence sequence;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sequence.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sequence.summary,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '共 ${sequence.steps.length} 步，聊天页会逐步填入或发送，不会自动整组连发。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
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
              const SizedBox(height: 20),
              for (var index = 0; index < sequence.steps.length; index++) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '步骤 ${index + 1}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(sequence.steps[index].content),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 窄屏下沿用摘要卡片布局。
class _FixedPromptSequenceCompactTile extends ConsumerWidget {
  const _FixedPromptSequenceCompactTile({
    required this.sequence,
    required this.onEditRequested,
  });

  final FixedPromptSequence sequence;
  final ValueChanged<FixedPromptSequence> onEditRequested;

  @override
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
                    '${index + 1}. ${_summarizeFixedSequence(sequence.steps[index].content)}',
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
}

String _summarizeFixedSequence(String content) {
  final normalized = content.trim().replaceAll('\n', ' ');
  if (normalized.length <= 30) {
    return normalized;
  }

  return '${normalized.substring(0, 30)}...';
}
