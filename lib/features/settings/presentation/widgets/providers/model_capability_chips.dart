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
      FilterChip(
        label: const Text('深度思考'),
        avatar: Icon(
          supportsReasoning ? Icons.check : Icons.psychology_outlined,
          size: 18,
        ),
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        tooltip: '声明模型支持深度思考',
        selected: supportsReasoning,
        onSelected: onReasoningChanged,
      ),
      FilterChip(
        label: const Text('图像'),
        avatar: Icon(
          supportsImageInput ? Icons.check : Icons.image_outlined,
          size: 18,
        ),
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        tooltip: '多模态：允许模型接收图像输入',
        selected: supportsImageInput,
        onSelected: onImageInputChanged,
      ),
    ],
  );
}
