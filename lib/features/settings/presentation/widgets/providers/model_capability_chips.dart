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
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: supportsReasoning,
            semanticLabel: '深度思考',
            onChanged: onReasoningChanged == null
                ? null
                : (value) => onReasoningChanged!(value!),
          ),
          const ExcludeSemantics(child: Text('深度思考')),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: supportsImageInput,
            semanticLabel: '图像',
            onChanged: onImageInputChanged == null
                ? null
                : (value) => onImageInputChanged!(value!),
          ),
          const ExcludeSemantics(child: Text('图像')),
        ],
      ),
    ],
  );
}
