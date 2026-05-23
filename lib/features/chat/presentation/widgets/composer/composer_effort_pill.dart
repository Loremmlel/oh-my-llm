import 'package:flutter/material.dart';

import '../../../domain/models/chat_message.dart';
import 'composer_helpers.dart';

class ComposerEffortPill extends StatelessWidget {
  const ComposerEffortPill({
    required this.theme,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.onReasoningEffortChanged,
    super.key,
  });

  final ThemeData theme;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = supportsReasoning && reasoningEnabled;
    final backgroundColor = !supportsReasoning
        ? theme.colorScheme.surfaceContainerLow
        : isActive
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = isActive
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return PopupMenuButton<ReasoningEffort>(
      enabled: isActive,
      initialValue: reasoningEffort,
      tooltip: '思考强度',
      onSelected: (value) => onReasoningEffortChanged?.call(value),
      itemBuilder: (context) => ReasoningEffort.values
          .map(
            (effort) =>
                PopupMenuItem(value: effort, child: Text(effortLabel(effort))),
          )
          .toList(growable: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 167),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              effortLabel(reasoningEffort),
              style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: labelColor),
          ],
        ),
      ),
    );
  }
}
