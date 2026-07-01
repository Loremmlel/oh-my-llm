import 'package:flutter/material.dart';

import '../../../../core/widgets/notification_bubble_context_ext.dart';

/// 设置页通用的通知气泡辅助函数。
///
/// 内部调用新的右上角气泡通知系统，替换了旧的 SnackBar。
void showSettingsSnackbar(BuildContext context, String message) {
  if (!context.mounted) return;
  context.showBubble(message);
}
