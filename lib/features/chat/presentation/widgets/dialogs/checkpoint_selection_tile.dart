import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/theme/app_ui_colors.dart';

import '../../../domain/models/chat_checkpoint.dart';

class CheckpointSelectionTile extends StatelessWidget {
  const CheckpointSelectionTile({
    required this.checkpoint,
    required this.meta,
    required this.selected,
    required this.applied,
    required this.compatible,
    required this.onFocus,
    this.onApply,
    super.key,
  });

  final ChatCheckpoint checkpoint;
  final String meta;
  final bool selected;
  final bool applied;
  final bool compatible;
  final VoidCallback onFocus;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final applyLabel = applied ? '当前启用' : '启用';

    return Material(
      color: selected
          ? Theme.of(context).uiColors.selection
          : Colors.transparent,
      child: InkWell(
        onTap: onFocus,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                applied
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: applied ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            checkpoint.title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: onApply,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(applyLabel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: compatible
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!compatible)
                      Text(
                        '可查看详情，但当前分支无法启用。',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
