import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 能力在列表与批量导入中同排呈现，保留 Material 的键盘、选中态与触摸命中区。
class ModelCapabilityChips extends StatelessWidget {
  const ModelCapabilityChips({
    required this.supportsReasoning,
    required this.supportsImageInput,
    required this.onReasoningChanged,
    required this.onImageInputChanged,
    super.key,
  });

  final bool supportsReasoning;
  final bool supportsImageInput;
  final ValueChanged<bool>? onReasoningChanged;
  final ValueChanged<bool>? onImageInputChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    children: [
      _option('深度思考', supportsReasoning, onReasoningChanged),
      _option('图像', supportsImageInput, onImageInputChanged),
    ],
  );

  Widget _option(String label, bool value, ValueChanged<bool>? onChanged) =>
      InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        // 原生复选框独占键盘与语义，外层只扩大指针命中区。
        canRequestFocus: false,
        excludeFromSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              semanticLabel: label,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged(value!),
            ),
            ExcludeSemantics(child: Text(label)),
          ],
        ),
      );
}
