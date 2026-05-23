import 'package:flutter/material.dart';

import '../../../domain/models/llm_provider_config.dart';
import 'provider_model_info_body.dart';

class ProviderModelInfo extends StatelessWidget {
  const ProviderModelInfo({required this.model, super.key});

  final LlmProviderModelConfig model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(model.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        ProviderModelInfoBody(model: model),
      ],
    );
  }
}
