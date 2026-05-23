import 'package:flutter/material.dart';

class CheckpointSelectionHeader extends StatelessWidget {
  const CheckpointSelectionHeader({
    required this.isBusy,
    required this.usingFullContext,
    required this.onClearSelection,
    super.key,
  });

  final bool isBusy;
  final bool usingFullContext;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('不使用检查点', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    usingFullContext ? '当前使用完整上下文。' : '切换回完整上下文。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: isBusy ? null : onClearSelection,
              child: const Text('使用完整上下文'),
            ),
          ],
        ),
      ),
    );
  }
}
