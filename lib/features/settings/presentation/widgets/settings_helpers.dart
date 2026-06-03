import 'package:flutter/material.dart';

/// 设置页通用的 SnackBar 辅助函数。
void showSettingsSnackbar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
