import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../application/llm_model_configs_controller.dart';
import '../../domain/models/llm_provider_config.dart';
import 'settings_empty_state.dart';

/// 服务商配置列表，负责展示服务商信息和其下模型。
class ModelConfigsList extends ConsumerWidget {
  const ModelConfigsList({
    required this.providers,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
    super.key,
  });

  final List<LlmProviderConfig> providers;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (providers.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.hub_outlined,
        title: '还没有服务商配置',
        description: '先添加一个服务商，再在服务商下添加模型，聊天页才能真正发起对话请求。',
      );
    }

    return Column(
      children: [
        for (final provider in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProviderTile(
              provider: provider,
              onEditProviderRequested: onEditProviderRequested,
              onAddModelRequested: onAddModelRequested,
              onEditModelRequested: onEditModelRequested,
            ),
          ),
      ],
    );
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({
    required this.provider,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
  });

  final LlmProviderConfig provider;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('API URL：${provider.apiUrl}'),
                      const SizedBox(height: 4),
                      Text('API Key：${_maskApiKey(provider.apiKey)}'),
                      const SizedBox(height: 4),
                      Text('模型数量：${provider.models.length}'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onAddModelRequested(provider),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('新增模型'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onEditProviderRequested(provider),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑服务商'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(llmProviderConfigsProvider.notifier)
                            .deleteProviderById(provider.id);
                        for (final model in provider.models) {
                          await ref
                              .read(chatDefaultsProvider.notifier)
                              .clearRememberedModelIdIfMatches(model.id);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('服务商已删除')),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('删除服务商'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (provider.models.isEmpty)
              Text(
                '当前服务商下还没有模型。',
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                children: [
                  for (final model in provider.models)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ProviderModelTile(
                        provider: provider,
                        model: model,
                        onEditModelRequested: onEditModelRequested,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}

class _ProviderModelTile extends ConsumerWidget {
  const _ProviderModelTile({
    required this.provider,
    required this.model,
    required this.onEditModelRequested,
  });

  final LlmProviderConfig provider;
  final LlmProviderModelConfig model;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (model.supportsReasoning)
                        Chip(
                          avatar: const Icon(
                            Icons.psychology_alt_outlined,
                            size: 18,
                          ),
                          label: const Text('支持深度思考'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('API 模型名称：${model.modelName}'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditModelRequested(provider, model),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(llmProviderConfigsProvider.notifier).deleteModel(
                          providerId: provider.id,
                          modelId: model.id,
                        );
                    await ref
                        .read(chatDefaultsProvider.notifier)
                        .clearRememberedModelIdIfMatches(model.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('模型已删除')));
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
