import 'package:flutter/material.dart';

import 'notification_bubble_data.dart';

/// 通知气泡的视觉内容：图标 + 文字 + 操作按钮 + 关闭按钮。
///
/// 纯 UI 组件，不包含动画。动画由外部容器（[NotificationBubbleStack] 的 AnimatedList）
/// 统一管理，以确保插入/移除的时序一致。
class NotificationBubbleContent extends StatelessWidget {
  const NotificationBubbleContent({
    super.key,
    required this.data,
    required this.onDismiss,
    this.showCloseButton = true,
  });

  /// 通知数据。
  final NotificationBubbleData data;

  /// 关闭回调（点击 ✕ 或操作按钮后触发）。
  final VoidCallback onDismiss;

  /// 是否显示关闭按钮。退出动画期间应设为 false 避免死点击区。
  final bool showCloseButton;

  void _handleAction() {
    data.action?.onPressed();
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = data.type.iconColor(cs);
    final hasAction = data.action != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: cs.inverseSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: hasAction ? 10 : 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(data.type.icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  data.message,
                  style: TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasAction) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _handleAction,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                  child: Text(data.action!.label),
                ),
              ],
              if (showCloseButton) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, size: 16),
                    color: cs.onInverseSurface.withValues(alpha: 0.6),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
