import 'package:flutter/material.dart';

import 'composer_pill_toggle.dart';

/// 控制聊天页是否启用自动重试的开关。
class AutoRetryToggle extends StatelessWidget {
  const AutoRetryToggle({
    required this.enabled,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ComposerPillToggle(
      enabled: enabled,
      value: value,
      icon: Icons.schedule_rounded,
      label: '自动重试',
      onChanged: onChanged,
    );
  }
}
