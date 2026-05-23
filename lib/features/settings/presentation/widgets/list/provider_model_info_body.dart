import 'package:flutter/material.dart';

import '../../../domain/models/llm_provider_config.dart';
import 'provider_meta_chip.dart';

class ProviderModelInfoBody extends StatelessWidget {
  const ProviderModelInfoBody({required this.model, super.key});

  final LlmProviderModelConfig model;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ProviderMetaChip(
          icon: Icons.memory_rounded,
          label: 'API 模型名称：${model.modelName}',
        ),
        if (model.supportsReasoning)
          const ProviderMetaChip(
            icon: Icons.psychology_alt_outlined,
            label: '支持深度思考',
          ),
      ],
    );
  }
}
