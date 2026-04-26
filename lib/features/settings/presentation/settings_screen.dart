import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/utils/id_generator.dart';
import '../application/chat_defaults_controller.dart';
import '../application/llm_model_configs_controller.dart';
import '../application/prompt_templates_controller.dart';
import '../domain/models/llm_model_config.dart';
import '../domain/models/prompt_template.dart';
import 'widgets/model_config_form_dialog.dart';
import 'widgets/prompt_template_form_dialog.dart';
import 'widgets/settings_section_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String noPromptTemplateValue = '__no_prompt_template__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatDefaults = ref.watch(chatDefaultsProvider);
    final modelConfigs = ref.watch(llmModelConfigsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置页',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: '聊天默认项',
            description: '统一指定默认模型和默认 Prompt。聊天页会直接使用这里的配置，不再单独选择。',
            child: _ChatDefaultsSection(
              modelConfigs: modelConfigs,
              promptTemplates: promptTemplates,
              defaultModelId: chatDefaults.defaultModelId,
              defaultPromptTemplateId: chatDefaults.defaultPromptTemplateId,
            ),
          ),
          const SizedBox(height: 16),
          SettingsSectionCard(
            title: '模型设置',
            description: '管理 OpenAI 兼容模型配置，默认模型会从下方“聊天默认项”中指定。',
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
                _showModelConfigDialog(context, ref, initialValue: config);
              },
            ),
          ),
          const SizedBox(height: 16),
          SettingsSectionCard(
            title: '前置 Prompt 设置',
            description: '配置会在每次对话时被插入到历史最前面，默认模板同样从“聊天默认项”中指定。',
            action: FilledButton.icon(
              onPressed: () {
                _showPromptTemplateDialog(context, ref);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增模板'),
            ),
            child: _PromptTemplatesList(
              templates: promptTemplates,
              onEditRequested: (template) {
                _showPromptTemplateDialog(context, ref, initialValue: template);
              },
            ),
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
                  content: Text(initialValue == null ? '模型配置已保存' : '模型配置已更新'),
                ),
              );
            }
          },
        );
      },
    );
  }

  Future<void> _showPromptTemplateDialog(
    BuildContext context,
    WidgetRef ref, {
    PromptTemplate? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return PromptTemplateFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            final template = PromptTemplate(
              id: initialValue?.id ?? generateEntityId(),
              name: formData.name,
              systemPrompt: formData.systemPrompt,
              messages: formData.messages,
              updatedAt: DateTime.now(),
            );

            await ref.read(promptTemplatesProvider.notifier).upsert(template);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    initialValue == null ? 'Prompt 模板已保存' : 'Prompt 模板已更新',
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

class _ModelConfigTile extends ConsumerWidget {
  const _ModelConfigTile({required this.config, required this.onEditRequested});

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

  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}

class _PromptTemplatesList extends ConsumerWidget {
  const _PromptTemplatesList({
    required this.templates,
    required this.onEditRequested,
  });

  final List<PromptTemplate> templates;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templates.isEmpty) {
      return const _EmptyState(
        icon: Icons.notes_rounded,
        title: '还没有 Prompt 模板',
        description: '添加模板后，聊天页就可以把它们作为 system / few-shot 上下文插入到对话最前面。',
      );
    }

    return Column(
      children: [
        for (final template in templates)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PromptTemplateTile(
              template: template,
              onEditRequested: onEditRequested,
            ),
          ),
      ],
    );
  }
}

class _PromptTemplateTile extends ConsumerWidget {
  const _PromptTemplateTile({
    required this.template,
    required this.onEditRequested,
  });

  final PromptTemplate template;
  final ValueChanged<PromptTemplate> onEditRequested;

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
            Text(template.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(template.summary),
            const SizedBox(height: 4),
            Text(
              'System：${_summarize(template.systemPrompt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (template.messages.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final message in template.messages.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${message.role.label}：${_summarize(message.content)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditRequested(template),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(promptTemplatesProvider.notifier)
                        .deleteById(template.id);
                    await ref
                        .read(chatDefaultsProvider.notifier)
                        .clearDefaultPromptTemplateIdIfMatches(template.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Prompt 模板已删除')),
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

  String _summarize(String content) {
    final normalized = content.trim().replaceAll('\n', ' ');
    if (normalized.length <= 30) {
      return normalized;
    }

    return '${normalized.substring(0, 30)}...';
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

class _ChatDefaultsSection extends ConsumerWidget {
  const _ChatDefaultsSection({
    required this.modelConfigs,
    required this.promptTemplates,
    required this.defaultModelId,
    required this.defaultPromptTemplateId,
  });

  final List<LlmModelConfig> modelConfigs;
  final List<PromptTemplate> promptTemplates;
  final String? defaultModelId;
  final String? defaultPromptTemplateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedModelId =
        modelConfigs.any((config) {
          return config.id == defaultModelId;
        })
        ? defaultModelId
        : modelConfigs.firstOrNull?.id;
    final resolvedPromptValue =
        promptTemplates.any((template) {
          return template.id == defaultPromptTemplateId;
        })
        ? defaultPromptTemplateId
        : SettingsScreen.noPromptTemplateValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(resolvedModelId),
          initialValue: resolvedModelId,
          isExpanded: true,
          items: modelConfigs
              .map((config) {
                return DropdownMenuItem(
                  value: config.id,
                  child: Text(
                    config.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              })
              .toList(growable: false),
          onChanged: modelConfigs.isEmpty
              ? null
              : (value) async {
                  await ref
                      .read(chatDefaultsProvider.notifier)
                      .setDefaultModelId(value);
                },
          decoration: const InputDecoration(
            labelText: '默认模型',
            helperText: '会用于新建对话或未指定模型的对话。',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(resolvedPromptValue),
          initialValue: resolvedPromptValue,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: SettingsScreen.noPromptTemplateValue,
              child: Text('不使用'),
            ),
            ...promptTemplates.map((template) {
              return DropdownMenuItem(
                value: template.id,
                child: Text(template.name, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: (value) async {
            await ref
                .read(chatDefaultsProvider.notifier)
                .setDefaultPromptTemplateId(
                  value == SettingsScreen.noPromptTemplateValue ? null : value,
                );
          },
          decoration: const InputDecoration(
            labelText: '默认 Prompt',
            helperText: '会在聊天发送时自动插入到历史最前面。',
          ),
        ),
      ],
    );
  }
}
