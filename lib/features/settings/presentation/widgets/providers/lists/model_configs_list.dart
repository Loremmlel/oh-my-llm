import 'package:flutter/material.dart';

import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_empty_state.dart';
import 'provider_tile.dart';

/// 服务商配置列表，负责展示服务商信息和其下模型。
class ModelConfigsList extends StatelessWidget {
  const ModelConfigsList({
    required this.providers,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
    this.onBatchAddModelsRequested,
    super.key,
  });

  final List<LlmProviderConfig> providers;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final ValueChanged<LlmProviderConfig>? onBatchAddModelsRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.hub_outlined,
        title: '还没有服务商配置',
        description: '先添加一个服务商，再在服务商下添加模型，聊天页才能真正发起对话请求。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in providers)
          Padding(
            key: ValueKey(provider.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: ProviderTile(
              provider: provider,
              onEditProviderRequested: onEditProviderRequested,
              onAddModelRequested: onAddModelRequested,
              onBatchAddModelsRequested: onBatchAddModelsRequested,
              onEditModelRequested: onEditModelRequested,
            ),
          ),
      ],
    );
  }
}
