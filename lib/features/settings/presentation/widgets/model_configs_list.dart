import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../application/llm_model_configs_controller.dart';
import '../../domain/models/llm_model_config.dart';
import 'settings_empty_state.dart';

/// 模型配置列表，负责展示、编辑和删除单个配置。
class ModelConfigsList extends ConsumerWidget {
  const ModelConfigsList({
    required this.configs,
    required this.onEditRequested,
    super.key,
  });

  final List<LlmModelConfig> configs;
  final ValueChanged<LlmModelConfig> onEditRequested;

  @override
  /// 构建模型列表；空列表时显示空状态提示。
  Widget build(BuildContext context, WidgetRef ref) {
    if (configs.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.smart_toy_outlined,
        title: '还没有模型配置',
        description: '先添加一个模型，聊天页才能真正发起对话请求。',
      );
    }

    return Column(
      children: [
        for (final config in configs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ModelConfigTile(
              config: config,
              onEditRequested: onEditRequested,
            ),
          ),
      ],
    );
  }
}

/// 单个模型配置卡片。
class _ModelConfigTile extends ConsumerWidget {
  const _ModelConfigTile({required this.config, required this.onEditRequested});

  final LlmModelConfig config;
  final ValueChanged<LlmModelConfig> onEditRequested;

  @override
  /// 构建模型配置详情和操作按钮。
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
              children: [
                Expanded(
                  child: Text(
                    config.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (config.supportsReasoning)
                  Chip(
                    avatar: const Icon(Icons.psychology_alt_outlined, size: 18),
                    label: const Text('支持深度思考'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('API URL：${config.apiUrl}'),
            const SizedBox(height: 4),
            Text('模型名称：${config.modelName}'),
            const SizedBox(height: 4),
            Text('API Key：${_maskApiKey(config.apiKey)}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    onEditRequested(config);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(llmModelConfigsProvider.notifier)
                        .deleteById(config.id);
                    await ref
                        .read(chatDefaultsProvider.notifier)
                        .clearDefaultModelIdIfMatches(config.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('模型配置已删除')));
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

  /// 把 API Key 截断为适合展示的掩码文本。
  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}
