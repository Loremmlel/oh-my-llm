import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 提示词记录按自然高度排列，操作紧邻标题，不为短内容预留卡片高度。
class SettingsEntityRow extends StatelessWidget {
  const SettingsEntityRow({
    required this.title,
    required this.body,
    required this.actions,
    super.key,
  });
  final String title;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ...actions,
            ],
          ),
          ...body,
        ],
      ),
    ),
  );
}
