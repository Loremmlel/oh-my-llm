import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/utils/id_generator.dart';
import '../application/llm_model_configs_controller.dart';
import '../domain/models/llm_model_config.dart';
import 'widgets/model_config_form_dialog.dart';
import 'widgets/settings_section_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelConfigs = ref.watch(llmModelConfigsProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置页',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsSectionCard(
            title: '模型设置',
            description: '管理 OpenAI 兼容模型配置，后续聊天页会直接从这里的列表中提供选择。',
            action: FilledButton.icon(
              onPressed: () {
                _showModelConfigDialog(context, ref);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增模型'),
            ),
            child: _ModelConfigsList(
              configs: modelConfigs,
              onEditRequested: (config) {
                _showModelConfigDialog(
                  context,
                  ref,
                  initialValue: config,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const SettingsSectionCard(
            title: '前置 Prompt 设置',
            description: '下一个能力块会在这里接入 system prompt 和多条 user/assistant 指令的编辑体验。',
            child: _PromptSettingsPreview(),
          ),
        ],
      ),
    );
  }

  Future<void> _showModelConfigDialog(
    BuildContext context,
    WidgetRef ref, {
    LlmModelConfig? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ModelConfigFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            final config = LlmModelConfig(
              id: initialValue?.id ?? generateEntityId(),
              displayName: formData.displayName,
              apiUrl: formData.apiUrl,
              apiKey: formData.apiKey,
              modelName: formData.modelName,
              supportsReasoning: formData.supportsReasoning,
            );

            await ref.read(llmModelConfigsProvider.notifier).upsert(config);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    initialValue == null
                        ? '模型配置已保存'
                        : '模型配置已更新',
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class _ModelConfigsList extends ConsumerWidget {
  const _ModelConfigsList({
    required this.configs,
    required this.onEditRequested,
  });

  final List<LlmModelConfig> configs;
  final ValueChanged<LlmModelConfig> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (configs.isEmpty) {
      return const _EmptyState(
        icon: Icons.smart_toy_outlined,
        title: '还没有模型配置',
        description: '先添加一个模型，后续聊天页才能选择并发起对话请求。',
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

class _ModelConfigTile extends ConsumerWidget {
  const _ModelConfigTile({
    required this.config,
    required this.onEditRequested,
  });

  final LlmModelConfig config;
  final ValueChanged<LlmModelConfig> onEditRequested;

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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('模型配置已删除')),
                      );
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

  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}

class _PromptSettingsPreview extends StatelessWidget {
  const _PromptSettingsPreview();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.notes_rounded,
      title: '前置 Prompt 编辑器待接入',
      description: '下一次提交会把 system prompt、多条 user/assistant 指令和本地持久化一起接进来。',
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
