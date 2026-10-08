import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 用标题和留白划分设置区域，避免为每层配置重复添加卡片。
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    this.description,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppContentWidths.wide),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (description case final description?)
                      AppHelpTitle(
                        title: title,
                        message: description,
                        style: theme.textTheme.titleMedium,
                      )
                    else
                      Text(title, style: theme.textTheme.titleMedium),
                    ?action,
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
