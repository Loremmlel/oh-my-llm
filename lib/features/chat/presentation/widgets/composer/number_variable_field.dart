import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 紧凑的数字变量输入框，支持上下箭头 +1/-1。
///
/// 布局为 `[⬆️] [TextField] [⬇️]`，不独占一行，适合短数字场景。
/// 支持负数输入，无下限限制。空值时回退为 1。
class NumberVariableField extends StatelessWidget {
  const NumberVariableField({
    required this.controller,
    required this.labelText,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;

  static const _fallbackValue = 1;

  void _increment() {
    final current = int.tryParse(controller.text) ?? _fallbackValue;
    controller.text = '${current + 1}';
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  void _decrement() {
    final current = int.tryParse(controller.text) ?? _fallbackValue;
    controller.text = '${current - 1}';
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 165,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ArrowButton(
            icon: Icons.keyboard_arrow_up_rounded,
            onTap: _increment,
            color: theme.colorScheme.primary,
          ),
          Expanded(
            child: TextField(
              key: ValueKey('template-variable-$labelText'),
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^-?\d*'),
                ),
              ],
              decoration: InputDecoration(
                labelText: labelText,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), // 取消 isDense 后保持略紧凑的行高
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _ArrowButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: _decrement,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
