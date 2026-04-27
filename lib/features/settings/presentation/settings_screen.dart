import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/utils/id_generator.dart';
import '../application/chat_defaults_controller.dart';
import '../application/fixed_prompt_sequences_controller.dart';
import '../application/llm_model_configs_controller.dart';
import '../application/prompt_templates_controller.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import '../domain/models/llm_model_config.dart';
import '../domain/models/prompt_template.dart';
import 'widgets/settings_widgets.dart';

/// 设置页入口，集中管理模型配置、Prompt 模板和聊天默认项。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  /// 构建设置页的三块配置区域。
  Widget build(BuildContext context, WidgetRef ref) {
    final chatDefaults = ref.watch(chatDefaultsProvider);
    final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
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
            child: ChatDefaultsSection(
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
            child: ModelConfigsList(
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
            child: PromptTemplatesList(
              templates: promptTemplates,
              onEditRequested: (template) {
                _showPromptTemplateDialog(context, ref, initialValue: template);
              },
            ),
          ),
          const SizedBox(height: 16),
          SettingsSectionCard(
            title: '固定顺序提示词',
            description: '配置可逐步发送的用户提示词序列，适合做模型对比测试，不会自动整组连发。',
            action: FilledButton.icon(
              onPressed: () {
                _showFixedPromptSequenceDialog(context, ref);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增序列'),
            ),
            child: FixedPromptSequencesList(
              sequences: fixedPromptSequences,
              onEditRequested: (sequence) {
                _showFixedPromptSequenceDialog(
                  context,
                  ref,
                  initialValue: sequence,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出模型配置对话框，并把提交结果写回控制器。
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

  /// 弹出 Prompt 模板对话框，并把提交结果写回控制器。
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

  /// 弹出固定顺序提示词序列对话框，并把提交结果写回控制器。
  Future<void> _showFixedPromptSequenceDialog(
    BuildContext context,
    WidgetRef ref, {
    FixedPromptSequence? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return FixedPromptSequenceFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            final sequence = FixedPromptSequence(
              id: initialValue?.id ?? generateEntityId(),
              name: formData.name,
              steps: formData.steps,
              updatedAt: DateTime.now(),
            );

            await ref
                .read(fixedPromptSequencesProvider.notifier)
                .upsert(sequence);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    initialValue == null ? '固定顺序提示词已保存' : '固定顺序提示词已更新',
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
