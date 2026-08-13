import 'package:flutter/material.dart';

import 'composer_pill_toggle.dart';

/// 控制聊天页是否启用深度思考的开关。
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

  @override
  Widget build(BuildContext context) {
    return ComposerPillToggle(
      enabled: enabled,
      value: value,
      icon: Icons.psychology_rounded,
      label: '深度思考',
      onChanged: onChanged,
    );
  }
}
