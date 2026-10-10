import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../../domain/models/providers/llm_provider_config.dart';

class ProviderInfoBody extends StatelessWidget {
  const ProviderInfoBody({
    required this.provider,
    required this.onEdit,
    super.key,
  });
  final LlmProviderConfig provider;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('API 地址', style: Theme.of(context).textTheme.labelLarge),
        SelectableText(provider.apiUrl),
        Text('API Key：${provider.apiKey.trim().isEmpty ? '未设置' : '已保存'}'),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('编辑连接'),
        ),
      ],
    ),
  );
}
