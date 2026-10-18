import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

/// 用标题和留白划分设置区域，避免为每层配置重复添加卡片。
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    this.description,
    required this.child,
    this.action,
    this.titleStyle,
    this.maxWidth = AppContentWidths.wide,
    this.useSideHeader = false,
    this.status,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? action;
  final TextStyle? titleStyle;
  final double maxWidth;
  final bool useSideHeader;
  final Widget? status;

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
            child: LayoutBuilder(
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
                if (useSideHeader &&
                    constraints.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) >=
                        AppBreakpoints.contentMasterDetail) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 208,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            if (status != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              status!,
                            ],
                            if (action != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              action!,
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: child),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (action == null)
                      heading
                    else
                      OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: AppSpacing.xs,
                        overflowSpacing: AppSpacing.xs,
                        children: [heading, action!],
                      ),
                    ?status,
                    SizedBox(
                      height: status == null ? AppSpacing.xs : AppSpacing.sm,
                    ),
                    child,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
