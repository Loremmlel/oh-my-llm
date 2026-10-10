import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 设置记录共用列对齐和行分隔；窄屏由所属列表提供保留全部操作的替代布局。
class SettingsTableRow extends StatelessWidget {
  const SettingsTableRow({
    required this.cells,
    required this.flexes,
    this.header = false,
    super.key,
  });
  final List<Widget> cells;
  final List<int> flexes;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: header ? theme.colorScheme.surfaceContainer : null,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: DefaultTextStyle.merge(
          style: header
              ? theme.textTheme.labelLarge
              : theme.textTheme.bodyMedium,
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flexes[i],
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: cells[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
