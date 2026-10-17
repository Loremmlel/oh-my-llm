import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 标签始终位于字段上方；不随焦点浮动，也不切开输入边框。
class AppInputLabel extends StatelessWidget {
  const AppInputLabel({
    required this.decoration,
    required this.child,
    this.expands = false,
    this.onLabelTap,
    super.key,
  });
  final InputDecoration decoration;
  final Widget child;
  final bool expands;
  final VoidCallback? onLabelTap;

  static InputDecoration fieldDecoration(InputDecoration value) =>
      InputDecoration(
        hintText: value.hintText,
        hintStyle: value.hintStyle,
        helperText: value.helperText,
        helperMaxLines: value.helperMaxLines,
        errorText: value.errorText,
        errorMaxLines: value.errorMaxLines,
        prefixIcon: value.prefixIcon,
        suffixIcon: value.suffixIcon,
        prefixIconConstraints: value.prefixIconConstraints,
        suffixIconConstraints: value.suffixIconConstraints,
        prefixText: value.prefixText,
        suffixText: value.suffixText,
        counterText: value.counterText,
        filled: value.filled,
        fillColor: value.fillColor,
        isDense: value.isDense,
        isCollapsed: value.isCollapsed,
        contentPadding: value.contentPadding,
        border: value.border,
        enabledBorder: value.enabledBorder,
        disabledBorder: value.disabledBorder,
        focusedBorder: value.focusedBorder,
        errorBorder: value.errorBorder,
        focusedErrorBorder: value.focusedErrorBorder,
        enabled: value.enabled,
        constraints: value.constraints,
      );

  @override
  Widget build(BuildContext context) {
    final label = decoration.labelText;
    if (label == null) return child;
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expands ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: GestureDetector(
              onTap: onLabelTap,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          // 键盘改变约束时只调整 fit，保留字段的元素身份与组合输入。
          Flexible(fit: expands ? FlexFit.tight : FlexFit.loose, child: child),
        ],
      ),
    );
  }
}
