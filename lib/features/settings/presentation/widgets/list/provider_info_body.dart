import 'package:flutter/material.dart';

import '../../../domain/models/llm_provider_config.dart';
import 'provider_meta_chip.dart';

class ProviderInfoBody extends StatelessWidget {
  const ProviderInfoBody({required this.provider, super.key});

  final LlmProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ProviderMetaChip(
              icon: Icons.hub_outlined,
              label: '模型数量：${provider.models.length}',
            ),
            Tooltip(
              message: provider.apiUrl,
              child: ProviderMetaChip(
                icon: Icons.link_rounded,
                label: 'API URL：${_buildApiUrlLabel(provider.apiUrl)}',
              ),
            ),
            ProviderMetaChip(
              icon: Icons.key_outlined,
              label: 'API Key：${_maskApiKey(provider.apiKey)}',
            ),
          ],
        ),
        if (provider.models.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '模型摘要：${_buildModelSummary(provider.models)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _buildApiUrlLabel(String apiUrl) {
    final uri = Uri.tryParse(apiUrl.trim());
    final host = uri?.host.trim() ?? '';
    return host.isNotEmpty ? host : apiUrl.trim();
  }

  String _buildModelSummary(List<LlmProviderModelConfig> models) {
    if (models.isEmpty) {
      return '无';
    }
    const previewLimit = 2;
    final preview = models
        .take(previewLimit)
        .map((model) => model.displayName)
        .join('、');
    final remainingCount = models.length - previewLimit;
    if (remainingCount <= 0) {
      return preview;
    }
    return '$preview 等 $remainingCount 个模型';
  }

  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}
