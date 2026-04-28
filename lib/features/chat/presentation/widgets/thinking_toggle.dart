import 'package:flutter/material.dart';

/// 控制聊天页是否启用深度思考的开关。
///
/// 整个圆角矩形 pill 本身即为开关——根据背景颜色区分启用/禁用状态，
/// 不再内嵌 [Switch] 组件，以减少宽度并降低行高，配合单行输入区布局使用。
class ThinkingToggle extends StatelessWidget {
  const ThinkingToggle({
    required this.enabled,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 构建带状态样式的深度思考 pill 开关。
  ///
  /// 整个 pill 可点击，点击时翻转当前 [value]。[enabled] 为 false 时
  /// pill 变灰且不响应点击，表示当前模型不支持深度思考。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = !enabled
        ? theme.colorScheme.surfaceContainerLow
        : value
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = value
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = enabled && value
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final iconColor = enabled && value
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 167),
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
        child: InkWell(
          onTap: enabled ? () => onChanged?.call(!value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded, size: 14, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  '深度思考',
                  style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
