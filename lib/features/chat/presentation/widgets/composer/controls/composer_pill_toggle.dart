import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_animations.dart';

/// 聊天 composer 区域的通用药丸切换按钮。
///
/// 整个圆角矩形 pill 本身即为开关——根据背景颜色区分启用/禁用状态，
/// 不再内嵌 [Switch] 组件，以减少宽度并降低行高，配合单行输入区布局使用。
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
    final backgroundColor = !isInteractive
        ? theme.colorScheme.surfaceContainerLow
        : value
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = value
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = isInteractive && value
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final iconColor = isInteractive && value
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return AnimatedContainer(
      duration: AppAnimations.quickTransition,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      // InkWell 挂在 Material 上以正确显示水波纹；clipBehavior 限定在圆角内
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
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
