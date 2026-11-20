import 'package:material_ui/material_ui.dart';

import 'composer_pill_toggle.dart';

/// 控制当前对话是否启用末尾指令的开关。
class TrailingDirectiveToggle extends StatelessWidget {
  const TrailingDirectiveToggle({
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
    return Tooltip(
      excludeFromSemantics: true,
      message: enabled ? '末尾指令' : '末尾指令（请先在设置 → 其它中填写指令内容）',
      child: ComposerPillToggle(
        enabled: enabled,
        value: value,
        icon: Icons.add_comment_outlined,
        label: '末尾指令',
        onChanged: onChanged,
      ),
    );
  }
}
