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
    this.titleStyle,
    this.maxWidth = AppContentWidths.wide,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? action;
  final TextStyle? titleStyle;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final heading = description != null
                        ? AppHelpTitle(
                            title: title,
                            message: description!,
                            style: titleStyle ?? theme.textTheme.titleMedium,
                          )
                        : Text(
                            title,
                            style: titleStyle ?? theme.textTheme.titleMedium,
                          );
                    if (action == null) return heading;
                    return OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: AppSpacing.xs,
                      overflowSpacing: AppSpacing.xs,
                      children: [heading, action!],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
