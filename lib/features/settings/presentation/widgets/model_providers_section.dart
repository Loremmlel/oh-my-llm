import 'package:flutter/material.dart';

import '../../domain/models/llm_provider_config.dart';
import 'model_configs_list.dart';
import 'settings_section_card.dart';

/// 设置页中的服务商与模型配置分区。
class ModelProvidersSection extends StatelessWidget {
  const ModelProvidersSection({
    required this.providers,
    required this.onAddPressed,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
    super.key,
  });

  final List<LlmProviderConfig> providers;
  final VoidCallback onAddPressed;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '服务商设置',
      description: '管理服务商与其下模型。聊天页会记住最近一次使用的模型。',
      action: FilledButton.icon(
        onPressed: onAddPressed,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增服务商'),
      ),
      child: ModelConfigsList(
        providers: providers,
        onEditProviderRequested: onEditProviderRequested,
        onAddModelRequested: onAddModelRequested,
        onEditModelRequested: onEditModelRequested,
      ),
    );
  }
}
