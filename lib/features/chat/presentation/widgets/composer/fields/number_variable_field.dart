import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter/services.dart';

/// 紧凑的数字变量输入框，支持上下箭头 +1/-1。
///
/// 布局为 `[⬇️] [TextField] [⬆️]`，不独占一行，适合短数字场景。
/// 支持负数输入，无下限限制。空值时回退为 1。
class NumberVariableField extends StatelessWidget {
  const NumberVariableField({
    required this.controller,
    required this.labelText,
    this.errorText,
    this.width = 165,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final double width;

  /// 值错误信息（如「必须是整数」），附着在字段下方 inline 展示。
  final String? errorText;

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
      width: width,
      child: AppTextField(
        key: ValueKey('template-variable-$labelText'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        decoration: InputDecoration(
          labelText: labelText,
          errorText: errorText,
          isDense: true,
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 32,
            height: 48,
          ),
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 32,
            height: 48,
          ),
          // 按钮随输入区域居中，外置标签与错误提示不参与对齐。
          prefixIcon: IconButton(
            padding: EdgeInsets.zero,
            tooltip: '减少$labelText',
            onPressed: _decrement,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          suffixIcon: IconButton(
            padding: EdgeInsets.zero,
            tooltip: '增加$labelText',
            onPressed: _increment,
            icon: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 12,
          ),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
