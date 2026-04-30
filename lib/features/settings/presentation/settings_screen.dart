import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../domain/models/settings_export_data.dart';
import 'widgets/import_confirm_dialog.dart';
import 'widgets/settings_widgets.dart';

/// 设置页入口，集中管理模型配置、Prompt 模板和聊天默认项。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  /// 构建设置页的三块配置区域，顶部附导出/导入操作栏。
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
            description: '管理 OpenAI 兼容模型配置，默认模型会从下方"聊天默认项"中指定。',
            action: FilledButton.icon(
              onPressed: () async {
                // 先检测剪贴板是否有可导入的配置数据，避免用户错过导入机会
                final handled = await _tryImportFromClipboard(context, ref);
                if (!handled && context.mounted) {
                  _showModelConfigDialog(context, ref);
                }
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
            description: '配置会在每次对话时被插入到历史最前面，默认模板同样从"聊天默认项"中指定。',
            action: FilledButton.icon(
              onPressed: () async {
                final handled = await _tryImportFromClipboard(context, ref);
                if (!handled && context.mounted) {
                  _showPromptTemplateDialog(context, ref);
                }
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
              onPressed: () async {
                final handled = await _tryImportFromClipboard(context, ref);
                if (!handled && context.mounted) {
                  _showFixedPromptSequenceDialog(context, ref);
                }
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

  /// 将当前全部配置序列化为 JSON 并复制到剪贴板。
  Future<void> _exportToClipboard(BuildContext context, WidgetRef ref) async {
    final modelConfigs = ref.read(llmModelConfigsProvider);
    final promptTemplates = ref.read(promptTemplatesProvider);
    final fixedPromptSequences = ref.read(fixedPromptSequencesProvider);

    final exportData = SettingsExportData(
      modelConfigs: modelConfigs,
      promptTemplates: promptTemplates,
      fixedPromptSequences: fixedPromptSequences,
    );

    await Clipboard.setData(ClipboardData(text: exportData.toJsonString()));

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制全部配置到剪贴板')));
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
    final existingModels = ref.read(llmModelConfigsProvider);
    final existingTemplates = ref.read(promptTemplatesProvider);
    final existingSequences = ref.read(fixedPromptSequencesProvider);
    final dedupedData = _deduplicateExportData(
      exportData,
      existingModels: existingModels,
      existingTemplates: existingTemplates,
      existingSequences: existingSequences,
    );

    if (!context.mounted) {
      return false;
    }

    // 全部重复时不弹对话框，提示用户后返回 true（视为已处理，不打开表单）
    if (!dedupedData.hasContent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('剪贴板中的配置在本地均已存在，无需导入')));
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ImportConfirmDialog(exportData: dedupedData);
      },
    );

    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置已成功导入')));
    }

    // 无论确认还是取消，只要弹过对话框就算"已处理"，不再打开表单
    return true;
  }

  /// 从待导入数据中过滤掉与本地已有条目内容等价的项，返回仅含新增内容的数据包。
  ///
  /// 去重规则：
  /// - 模型配置：`apiUrl`、`apiKey`、`modelName` 三字段全部相同即视为重复。
  /// - Prompt 模板：`systemPrompt` 相同且所有附加消息（role + content 有序）相同。
  /// - 固定顺序提示词：所有步骤内容（content 有序）相同。
  ///
  /// 不使用抽样比较：Dart 的 `String ==` 在 C 层实现，10K 字符级别 < 0.1ms，
  /// 一次性导入操作无需额外优化，而抽样有误判（假阴性）风险。
  SettingsExportData _deduplicateExportData(
    SettingsExportData data, {
    required List<LlmModelConfig> existingModels,
    required List<PromptTemplate> existingTemplates,
    required List<FixedPromptSequence> existingSequences,
  }) {
    final newModels = data.modelConfigs
        .where((incoming) {
          return !existingModels.any(
            (e) =>
                e.apiUrl == incoming.apiUrl &&
                e.apiKey == incoming.apiKey &&
                e.modelName == incoming.modelName,
          );
        })
        .toList(growable: false);

    final newTemplates = data.promptTemplates
        .where((incoming) {
          return !existingTemplates.any(
            (e) => _promptTemplatesContentEqual(e, incoming),
          );
        })
        .toList(growable: false);

    final newSequences = data.fixedPromptSequences
        .where((incoming) {
          return !existingSequences.any(
            (e) => _sequencesContentEqual(e, incoming),
          );
        })
        .toList(growable: false);

    return SettingsExportData(
      modelConfigs: newModels,
      promptTemplates: newTemplates,
      fixedPromptSequences: newSequences,
    );
  }

  /// 判断两个 Prompt 模板内容是否等价（忽略 id、name、updatedAt）。
  bool _promptTemplatesContentEqual(PromptTemplate a, PromptTemplate b) {
    if (a.systemPrompt.length != b.systemPrompt.length) return false;
    if (a.systemPrompt != b.systemPrompt) return false;
    if (a.messages.length != b.messages.length) return false;
    for (var i = 0; i < a.messages.length; i++) {
      final ma = a.messages[i];
      final mb = b.messages[i];
      if (ma.role != mb.role) return false;
      if (ma.placement != mb.placement) return false;
      if (ma.content.length != mb.content.length) return false;
      if (ma.content != mb.content) return false;
    }
    return true;
  }

  /// 判断两个固定顺序提示词序列内容是否等价（忽略 id、name、updatedAt）。
  bool _sequencesContentEqual(FixedPromptSequence a, FixedPromptSequence b) {
    if (a.steps.length != b.steps.length) return false;
    for (var i = 0; i < a.steps.length; i++) {
      final sa = a.steps[i];
      final sb = b.steps[i];
      if (sa.content.length != sb.content.length) return false;
      if (sa.content != sb.content) return false;
    }
    return true;
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
