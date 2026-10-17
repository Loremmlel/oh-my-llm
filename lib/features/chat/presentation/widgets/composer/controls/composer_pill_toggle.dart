import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_animations.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 聊天工具栏的轻量切换按钮。
///
/// 选中背景表达状态，未选中时融入工具栏，不为每项设置再套独立边框。
class ComposerPillToggle extends StatelessWidget {
  const ComposerPillToggle({
    required this.enabled,
    required this.value,
    required this.icon,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final bool value;
  final IconData icon;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 禁用视觉、Semantics enabled/action 与 InkWell onTap 必须同源，
    // 禁止出现视觉可用但实际是 no-op 的可聚焦 InkWell。
    final isInteractive = enabled && onChanged != null;
    final labelColor = isInteractive && value
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final iconColor = isInteractive && value
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return AnimatedContainer(
      duration: AppAnimations.quickTransition,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      // Material 承载 hover 与焦点反馈，裁剪保持控件圆角边界。
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          label: label,
          toggled: value,
          enabled: isInteractive,
          button: true,
          child: InkWell(
            onTap: isInteractive ? () => onChanged!.call(!value) : null,
            focusColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 视觉 icon/text 只负责外观，状态由 toggled/enabled 表达
                  ExcludeSemantics(
                    child: Icon(icon, size: 14, color: iconColor),
                  ),
                  const SizedBox(width: 4),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: labelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
