import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/utils/id_generator.dart';
import '../application/settings_import_deduplicator.dart';
import '../application/fixed_prompt_sequences_controller.dart';
import '../application/llm_model_configs_controller.dart';
import '../application/memory_prompts_controller.dart';
import '../application/prompt_templates_controller.dart';
import '../application/template_prompts_controller.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import '../domain/models/llm_provider_config.dart';
import '../domain/models/memory_prompt.dart';
import '../domain/models/prompt_template.dart';
import '../domain/models/settings_export_data.dart';
import '../domain/models/template_prompt.dart';
import 'widgets/import_confirm_dialog.dart';
import 'widgets/settings_widgets.dart';

/// 设置页入口，集中管理服务商、前置 Prompt、模板提示词和固定序列。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _importDeduplicator = SettingsImportDeduplicator();
  static const _savedAllConfigMessage = '已复制全部配置到剪贴板';
  static const _duplicateImportMessage = '剪贴板中的配置在本地均已存在，无需导入';
  static const _importSuccessMessage = '配置已成功导入';

  @override
  /// 构建设置页的各类配置区域，顶部附导出/导入操作栏。
  Widget build(BuildContext context, WidgetRef ref) {
    final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
    final modelProviders = ref.watch(llmProviderConfigsProvider);
    final memoryPrompts = ref.watch(memoryPromptsProvider);
    final promptTemplates = ref.watch(promptTemplatesProvider);
    final templatePrompts = ref.watch(templatePromptsProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置页',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 导出按钮：将三类配置序列化为 JSON 并写入剪贴板
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _exportToClipboard(context, ref),
              icon: const Icon(Icons.upload_rounded),
              label: const Text('导出全部配置'),
            ),
          ),
          const SizedBox(height: 12),
          ModelProvidersSection(
            providers: modelProviders,
            onAddPressed: () => _handleAddPressed(
              context,
              ref,
              () => _showModelProviderDialog(context, ref),
            ),
            onEditProviderRequested: (provider) {
              _showModelProviderDialog(context, ref, initialValue: provider);
            },
            onAddModelRequested: (provider) {
              _showModelConfigDialog(context, ref, provider: provider);
            },
            onEditModelRequested: (provider, model) {
              _showModelConfigDialog(
                context,
                ref,
                provider: provider,
                initialValue: model,
              );
            },
          ),
          const SizedBox(height: 16),
          MemoryPromptsSection(
            memoryPrompts: memoryPrompts,
            onAddPressed: () => _handleAddPressed(
              context,
              ref,
              () => _showMemoryPromptDialog(context, ref),
            ),
            onEditRequested: (memoryPrompt) {
              _showMemoryPromptDialog(context, ref, initialValue: memoryPrompt);
            },
          ),
          const SizedBox(height: 16),
          PromptTemplatesSection(
            templates: promptTemplates,
            onAddPressed: () => _handleAddPressed(
              context,
              ref,
              () => _showPromptTemplateDialog(context, ref),
            ),
            onEditRequested: (template) {
              _showPromptTemplateDialog(context, ref, initialValue: template);
            },
          ),
          const SizedBox(height: 16),
          TemplatePromptsSection(
            templatePrompts: templatePrompts,
            onAddPressed: () => _handleAddPressed(
              context,
              ref,
              () => _showTemplatePromptDialog(context, ref),
            ),
            onEditRequested: (templatePrompt) {
              _showTemplatePromptDialog(
                context,
                ref,
                initialValue: templatePrompt,
              );
            },
          ),
          const SizedBox(height: 16),
          FixedPromptSequencesSection(
            sequences: fixedPromptSequences,
            onAddPressed: () => _handleAddPressed(
              context,
              ref,
              () => _showFixedPromptSequenceDialog(context, ref),
            ),
            onEditRequested: (sequence) {
              _showFixedPromptSequenceDialog(
                context,
                ref,
                initialValue: sequence,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 将当前全部配置序列化为 JSON 并复制到剪贴板。
  Future<void> _exportToClipboard(BuildContext context, WidgetRef ref) async {
    final modelProviders = ref.read(llmProviderConfigsProvider);
    final memoryPrompts = ref.read(memoryPromptsProvider);
    final promptTemplates = ref.read(promptTemplatesProvider);
    final templatePrompts = ref.read(templatePromptsProvider);
    final fixedPromptSequences = ref.read(fixedPromptSequencesProvider);

    final exportData = SettingsExportData(
      modelProviders: modelProviders,
      memoryPrompts: memoryPrompts,
      promptTemplates: promptTemplates,
      templatePrompts: templatePrompts,
      fixedPromptSequences: fixedPromptSequences,
    );

    await Clipboard.setData(ClipboardData(text: exportData.toJsonString()));

    if (context.mounted) {
      _showSettingsSnackBar(context, _savedAllConfigMessage);
    }
  }

  Future<void> _handleAddPressed(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() openDialog,
  ) async {
    final handled = await _tryImportFromClipboard(context, ref);
    if (!handled && context.mounted) {
      await openDialog();
    }
  }

  /// 读取剪贴板，检测是否含有本应用的配置导出数据。
  ///
  /// 若检测到，先去重过滤掉本地已存在的内容相同的条目，再弹出 [ImportConfirmDialog]；
  /// 确认后批量写入并返回 true。若未检测到、全部重复或用户取消，则返回 false，
  /// 调用方继续显示常规表单。
  Future<bool> _tryImportFromClipboard(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // 仅读取一次剪贴板，不在 build 或监听器中重复读取
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final exportData = SettingsExportData.tryParseJson(clipboardData?.text);

    if (exportData == null || !exportData.hasContent) {
      return false;
    }

    // 去重：过滤掉与本地内容等价的条目
    final existingProviders = ref.read(llmProviderConfigsProvider);
    final existingMemoryPrompts = ref.read(memoryPromptsProvider);
    final existingTemplates = ref.read(promptTemplatesProvider);
    final existingTemplatePrompts = ref.read(templatePromptsProvider);
    final existingSequences = ref.read(fixedPromptSequencesProvider);
    final dedupedData = _importDeduplicator.deduplicate(
      data: exportData,
      existingProviders: existingProviders,
      existingMemoryPrompts: existingMemoryPrompts,
      existingTemplates: existingTemplates,
      existingTemplatePrompts: existingTemplatePrompts,
      existingSequences: existingSequences,
    );

    if (!context.mounted) {
      return false;
    }

    // 全部重复时不弹对话框，提示用户后返回 true（视为已处理，不打开表单）
    if (!dedupedData.hasContent) {
      _showSettingsSnackBar(context, _duplicateImportMessage);
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ImportConfirmDialog(exportData: dedupedData);
      },
    );

    if (confirmed == true && context.mounted) {
      _showSettingsSnackBar(context, _importSuccessMessage);
    }

    // 无论确认还是取消，只要弹过对话框就算"已处理"，不再打开表单
    return true;
  }

  /// 弹出服务商对话框，并把提交结果写回控制器。
  Future<void> _showModelProviderDialog(
    BuildContext context,
    WidgetRef ref, {
    LlmProviderConfig? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ModelProviderFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '服务商已保存',
              updatedMessage: '服务商已更新',
              onSave: () {
                final provider = LlmProviderConfig(
                  id: initialValue?.id ?? generateEntityId(),
                  name: formData.name,
                  apiUrl: formData.apiUrl,
                  apiKey: formData.apiKey,
                  models: initialValue?.models ?? const [],
                );

                return ref
                    .read(llmProviderConfigsProvider.notifier)
                    .upsertProvider(provider);
              },
            );
          },
        );
      },
    );
  }

  /// 弹出模型对话框，并把提交结果写回指定服务商。
  Future<void> _showModelConfigDialog(
    BuildContext context,
    WidgetRef ref, {
    required LlmProviderConfig provider,
    LlmProviderModelConfig? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ModelConfigFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '模型已保存',
              updatedMessage: '模型已更新',
              onSave: () {
                final model = LlmProviderModelConfig(
                  id: initialValue?.id ?? generateEntityId(),
                  displayName: formData.displayName,
                  modelName: formData.modelName,
                  supportsReasoning: formData.supportsReasoning,
                );

                return ref
                    .read(llmProviderConfigsProvider.notifier)
                    .upsertModel(providerId: provider.id, model: model);
              },
            );
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
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: 'Prompt 模板已保存',
              updatedMessage: 'Prompt 模板已更新',
              onSave: () {
                final template = PromptTemplate(
                  id: initialValue?.id ?? generateEntityId(),
                  name: formData.name,
                  systemPrompt: formData.systemPrompt,
                  messages: formData.messages,
                  updatedAt: DateTime.now(),
                );

                return ref
                    .read(promptTemplatesProvider.notifier)
                    .upsert(template);
              },
            );
          },
        );
      },
    );
  }

  /// 弹出记忆总结提示词对话框，并把提交结果写回控制器。
  Future<void> _showMemoryPromptDialog(
    BuildContext context,
    WidgetRef ref, {
    MemoryPrompt? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return MemoryPromptFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '记忆总结提示词已保存',
              updatedMessage: '记忆总结提示词已更新',
              onSave: () {
                final memoryPrompt = MemoryPrompt(
                  id: initialValue?.id ?? generateEntityId(),
                  name: formData.name,
                  content: formData.content,
                  updatedAt: DateTime.now(),
                );

                return ref
                    .read(memoryPromptsProvider.notifier)
                    .upsert(memoryPrompt);
              },
            );
          },
        );
      },
    );
  }

  /// 弹出模板提示词对话框，并把提交结果写回控制器。
  Future<void> _showTemplatePromptDialog(
    BuildContext context,
    WidgetRef ref, {
    TemplatePrompt? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return TemplatePromptFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '模板提示词已保存',
              updatedMessage: '模板提示词已更新',
              onSave: () {
                final templatePrompt = TemplatePrompt(
                  id: initialValue?.id ?? generateEntityId(),
                  title: formData.title,
                  content: formData.content,
                  variables: formData.variables,
                  updatedAt: DateTime.now(),
                );

                return ref
                    .read(templatePromptsProvider.notifier)
                    .upsert(templatePrompt);
              },
            );
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
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '固定顺序提示词已保存',
              updatedMessage: '固定顺序提示词已更新',
              onSave: () {
                final sequence = FixedPromptSequence(
                  id: initialValue?.id ?? generateEntityId(),
                  name: formData.name,
                  steps: formData.steps,
                  updatedAt: DateTime.now(),
                );

                return ref
                    .read(fixedPromptSequencesProvider.notifier)
                    .upsert(sequence);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveSettingsItem(
    BuildContext context, {
    required bool isEditing,
    required String createdMessage,
    required String updatedMessage,
    required Future<void> Function() onSave,
  }) async {
    await onSave();
    if (context.mounted) {
      _showSettingsSnackBar(
        context,
        isEditing ? updatedMessage : createdMessage,
      );
    }
  }

  void _showSettingsSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
