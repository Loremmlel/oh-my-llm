import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_bubble_provider.dart';
import '../widgets/notification_bubble_data.dart';

/// BuildContext 扩展：快捷显示通知气泡。
///
/// 适用于无法直接拿到 `ref` 的位置（如 Mixin、纯函数等），内部通过
/// `ProviderScope.containerOf` 获取 Provider。
extension NotificationBubbleContextExt on BuildContext {
  /// 显示一条通知气泡。
  ///
  /// 用法：`context.showBubble('已复制消息内容')`
  void showBubble(
    String message, {
    NotificationBubbleType type = NotificationBubbleType.info,
    NotificationBubbleAction? action,
    Duration? duration,
  }) {
    ProviderScope.containerOf(this)
        .read(notificationBubblesProvider.notifier)
        .show(message: message, type: type, action: action, duration: duration);
  }

  /// 显示成功通知。
  void showSuccessBubble(String message, {Duration? duration}) {
    showBubble(message, type: NotificationBubbleType.success, duration: duration);
  }

  /// 显示错误通知。
  void showErrorBubble(String message, {Duration? duration}) {
    showBubble(message, type: NotificationBubbleType.error, duration: duration);
  }

  /// 显示警告通知。
  void showWarningBubble(String message, {Duration? duration}) {
    showBubble(message, type: NotificationBubbleType.warning, duration: duration);
  }
}
