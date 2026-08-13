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

    // 整条通知是一个完整自足的 live status 节点；装饰 icon 与可见 message
    // 排除重复语义，action/close 作为独立子节点继续可达。
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: '${data.type.semanticLabel}：${data.message}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              // 跟随主题方向的浮层表面色：light 浅底 / dark 深底，与主应用明暗一致。
              // 不用 inverseSurface——那是 SnackBar 式「反色浮层」，会与主应用色调相反。
              color: cs.surfaceContainerHighest,
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
                ExcludeSemantics(
                  child: Icon(data.type.icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 10),
                // Flexible 必须直接挂在 Row 下才能接收 FlexParentData，
                // 语义排除只能包在它内部。
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      data.message,
                      style: TextStyle(color: cs.onSurface, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                    // 用 Semantics 携带 tooltip 而非 IconButton.tooltip：后者会构建
                    // Tooltip 组件，要求 Overlay 祖先，而气泡渲染在 MaterialApp.builder
                    // 层（Navigator 之外），会触发 No Overlay found 崩溃。注解放在
                    // IconButton 内部（包住 Icon），语义与按钮节点合并而非新建节点。
                    child: IconButton(
                      onPressed: onDismiss,
                      icon: Semantics(
                        tooltip: '关闭通知',
                        child: const Icon(Icons.close, size: 16),
                      ),
                      color: cs.onSurface.withValues(alpha: 0.6),
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
      ),
    );
  }
}
