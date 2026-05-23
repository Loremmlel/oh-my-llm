import 'package:flutter/material.dart';

import '../../../domain/models/llm_provider_config.dart';
import 'provider_info_body.dart';

class ProviderInfo extends StatelessWidget {
  const ProviderInfo({required this.provider, super.key});

  final LlmProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(provider.name, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ProviderInfoBody(provider: provider),
      ],
    );
  }
}
