import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import '../application/fixed_prompt_sequences_controller.dart';
import '../application/llm_model_configs_controller.dart';
import '../application/memory_prompts_controller.dart';
import '../application/model_catalog_workflow.dart';
import '../application/preset_prompts_controller.dart';
import '../application/settings_tab_preferences.dart';
import '../application/settings_transfer_workflow.dart';
import '../application/template_prompts_controller.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import '../domain/models/llm_provider_config.dart';
import '../domain/models/memory_prompt.dart';
import '../domain/models/preset_prompt.dart';
import '../domain/models/template_prompt.dart';
import 'widgets/import_confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/tab/network_settings_tab.dart';
import 'widgets/tab/other_settings_tab.dart';
import 'widgets/tab/output_processing_tab.dart';

const _tabProviders = 0;
const _tabPresets = 1;
const _tabPrompts = 2;
const _tabNetwork = 3;
const _tabOutputProcessing = 4;
const _tabOther = 5;

const _tabLabelProviders = '服务商';
const _tabLabelPresets = '预设 Prompt';
const _tabLabelPrompts = '提示词';
const _tabLabelOther = '其它设置';
const _tabLabelNetwork = '网络';
const _tabLabelOutputProcessing = '输出处理';

/// 设置页入口，使用标签页组织服务商、预设、提示词和其它设置。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  static final _presetPromptCopySuffixPattern = RegExp(r'^(.+?)（副本(?: \d+)?）$');

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      initialIndex: ref
          .read(settingsTabPreferencesProvider)
          .initialIndex(tabCount: 6),
      length: 6,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    unawaited(_migrateTabPreference());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {});
    if (!_tabController.indexIsChanging) {
      unawaited(_saveTabIndex());
    }
  }

  Future<void> _migrateTabPreference() async {
    await ref
        .read(settingsTabPreferencesProvider)
        .loadInitialIndex(tabCount: _tabController.length);
  }

  Future<void> _saveTabIndex() async {
    try {
      await ref
          .read(settingsTabPreferencesProvider)
          .saveIndex(_tabController.index);
    } catch (_) {
      // 标签切换不应因偏好写入失败而中断当前操作。
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
    final modelProviders = ref.watch(llmProviderConfigsProvider);
    final memoryPrompts = ref.watch(memoryPromptsProvider);
    final presetPrompts = ref.watch(presetPromptsProvider);
    final templatePrompts = ref.watch(templatePromptsProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置',
      actions: [
        IconButton(
          onPressed: () => _importToCurrentTab(),
          icon: const Icon(Icons.download_rounded),
          tooltip: '导入$_currentTabLabel',
        ),
        IconButton(
          onPressed: () => _exportCurrentTab(),
          icon: const Icon(Icons.upload_rounded),
          tooltip: '导出$_currentTabLabel',
        ),
      ],
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '服务商'),
              Tab(text: '预设'),
              Tab(text: '提示词'),
              Tab(text: '网络'),
              Tab(text: '输出处理'),
              Tab(text: '其它'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 服务商
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SettingsSectionCard(
                      title: '服务商设置',
                      description: '管理服务商与其下模型。聊天页会记住最近一次使用的模型。',
                      action: FilledButton.icon(
                        onPressed: () => _showModelProviderDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增服务商'),
                      ),
                      child: ModelConfigsList(
                        providers: modelProviders,
                        onEditProviderRequested: (provider) {
                          _showModelProviderDialog(
                            context,
                            ref,
                            initialValue: provider,
                          );
                        },
                        onAddModelRequested: (provider) {
                          _showModelConfigDialog(
                            context,
                            ref,
                            provider: provider,
                          );
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
                    ),
                  ],
                ),
                // 预设
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SettingsSectionCard(
                      title: '预设 Prompt',
                      description:
                          '配置可在聊天页选择的预设 Prompt，支持 system、前置、最新输入前与后置上下文，并记住最近一次使用的选择。',
                      action: FilledButton.icon(
                        onPressed: () => _showPresetPromptDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增预设'),
                      ),
                      child: PresetPromptsList(
                        templates: presetPrompts,
                        onDuplicateRequested: (template) {
                          return _duplicatePresetPrompt(context, ref, template);
                        },
                        onEditRequested: (template) {
                          _showPresetPromptDialog(
                            context,
                            ref,
                            initialValue: template,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // 提示词
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SettingsSectionCard(
                      title: '记忆总结提示词',
                      description: '配置聊天页创建检查点时可选择的总结提示词，用于适配不同场景下的记忆沉淀方式。',
                      action: FilledButton.icon(
                        onPressed: () => _showMemoryPromptDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增记忆提示词'),
                      ),
                      child: MemoryPromptsList(
                        memoryPrompts: memoryPrompts,
                        onEditRequested: (memoryPrompt) {
                          _showMemoryPromptDialog(
                            context,
                            ref,
                            initialValue: memoryPrompt,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsSectionCard(
                      title: '模板提示词',
                      description:
                          '配置可在聊天页临时应用的变量模板。使用 {{变量名}} 声明注入位，{{正文}} 对应主输入框。',
                      action: FilledButton.icon(
                        onPressed: () =>
                            _showTemplatePromptDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增模板提示词'),
                      ),
                      child: TemplatePromptsList(
                        templatePrompts: templatePrompts,
                        onEditRequested: (templatePrompt) {
                          _showTemplatePromptDialog(
                            context,
                            ref,
                            initialValue: templatePrompt,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsSectionCard(
                      title: '固定顺序提示词',
                      description: '配置可逐步发送的用户提示词序列，适合做模型对比测试，不会自动整组连发。',
                      action: FilledButton.icon(
                        onPressed: () =>
                            _showFixedPromptSequenceDialog(context, ref),
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
                // 网络
                const NetworkSettingsTab(),
                // 输出处理
                const OutputProcessingTab(),
                // 其它
                const OtherSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _currentTabLabel {
    switch (_tabController.index) {
      case _tabProviders:
        return _tabLabelProviders;
      case _tabPresets:
        return _tabLabelPresets;
      case _tabPrompts:
        return _tabLabelPrompts;
      case _tabOther:
        return _tabLabelOther;
      case _tabNetwork:
        return _tabLabelNetwork;
      case _tabOutputProcessing:
        return _tabLabelOutputProcessing;
      default:
        return '';
    }
  }

  // ── 导出/导入 ──────────────────────────────────────────────────

  Future<void> _exportCurrentTab() async {
    final exportData = ref
        .read(settingsTransferWorkflowProvider)
        .buildExportData(_currentTransferTab);
    if (exportData == null) {
      showSettingsSnackbar(context, '$_currentTabLabel 没有可导出的数据');
      return;
    }

    await Clipboard.setData(ClipboardData(text: exportData.toJsonString()));
    if (mounted) {
      showSettingsSnackbar(context, '已复制$_currentTabLabel到剪贴板');
    }
  }

  Future<void> _importToCurrentTab() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final preparation = ref
        .read(settingsTransferWorkflowProvider)
        .prepareImport(
          tab: _currentTransferTab,
          clipboardText: clipboardData?.text,
        );
    switch (preparation.kind) {
      case SettingsImportPreparationKind.invalidClipboard:
        if (mounted) showSettingsSnackbar(context, '剪贴板中没有可识别的配置数据');
        return;
      case SettingsImportPreparationKind.unsupportedVersion:
        if (mounted) showSettingsSnackbar(context, '剪贴板配置版本不受支持，请更新应用后重试');
        return;
      case SettingsImportPreparationKind.tabMismatch:
        if (mounted) {
          showSettingsSnackbar(context, '剪贴板数据与$_currentTabLabel不匹配，请切换到对应标签');
        }
        return;
      case SettingsImportPreparationKind.noNewItems:
        if (mounted) showSettingsSnackbar(context, '剪贴板中的配置在本地均已存在，无可导入项');
        return;
      case SettingsImportPreparationKind.ready:
        final data = preparation.data;
        if (data == null || !mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => ImportConfirmDialog(exportData: data),
        );
        if (confirmed == true && mounted) {
          showSettingsSnackbar(context, '$_currentTabLabel已成功导入');
        }
    }
  }

  SettingsTransferTab get _currentTransferTab =>
      SettingsTransferTab.values[_tabController.index];

  // ── 复制预设 ──────────────────────────────────────────────────

  Future<void> _duplicatePresetPrompt(
    BuildContext context,
    WidgetRef ref,
    PresetPrompt source,
  ) async {
    final existingTemplates = ref.read(presetPromptsProvider);
    final existingNames = existingTemplates
        .map((template) => template.name.trim())
        .toSet();
    final duplicatedName = _buildDuplicatedPresetPromptName(
      sourceName: source.name,
      existingNames: existingNames,
    );
    final duplicatedTemplate = source.copyWith(
      id: generateEntityId(),
      name: duplicatedName,
      updatedAt: DateTime.now(),
      messages: source.messages
          .map((message) => message.copyWith(id: generateEntityId()))
          .toList(growable: false),
    );
    await ref.read(presetPromptsProvider.notifier).upsert(duplicatedTemplate);
    if (context.mounted) {
      showSettingsSnackbar(context, '预设 Prompt 已复制');
    }
  }

  String _buildDuplicatedPresetPromptName({
    required String sourceName,
    required Set<String> existingNames,
  }) {
    final normalizedSource = sourceName.trim();
    final sourceCoreName = _extractPresetPromptCopyCoreName(normalizedSource);
    final firstCandidate = '$sourceCoreName（副本）';
    if (!existingNames.contains(firstCandidate)) {
      return firstCandidate;
    }

    var suffix = 2;
    while (true) {
      final candidate = '$sourceCoreName（副本 $suffix）';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
      suffix += 1;
    }
  }

  String _extractPresetPromptCopyCoreName(String name) {
    final match = _presetPromptCopySuffixPattern.firstMatch(name);
    final baseName = match?.group(1)?.trim();
    if (baseName == null || baseName.isEmpty) {
      return name;
    }
    return baseName;
  }

  // ── Dialog 方法 ───────────────────────────────────────────────

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
                  // 保存表单所选协议：编辑时表单初始值为原协议，新建默认
                  // Chat Completions；协议变更立即作用于其下全部模型。
                  apiProtocol: formData.apiProtocol,
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
          provider: provider,
          initialValue: initialValue,
          fetchModels: ref.read(modelCatalogWorkflowProvider).fetch,
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
          onBatchAdd: (items) async {
            final models = items
                .map(
                  (item) => LlmProviderModelConfig(
                    id: generateEntityId(),
                    displayName: item.displayName,
                    modelName: item.modelName,
                    supportsReasoning: false,
                  ),
                )
                .toList();

            final addedCount = await ref
                .read(llmProviderConfigsProvider.notifier)
                .upsertModels(providerId: provider.id, models: models);

            if (context.mounted) {
              showSettingsSnackbar(context, '已添加 $addedCount 个模型');
            }
          },
        );
      },
    );
  }

  Future<void> _showPresetPromptDialog(
    BuildContext context,
    WidgetRef ref, {
    PresetPrompt? initialValue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return PresetPromptFormDialog(
          initialValue: initialValue,
          onSubmit: (formData) async {
            await _saveSettingsItem(
              context,
              isEditing: initialValue != null,
              createdMessage: '预设 Prompt 已保存',
              updatedMessage: '预设 Prompt 已更新',
              onSave: () {
                final template = PresetPrompt(
                  id: initialValue?.id ?? generateEntityId(),
                  name: formData.name,
                  messages: formData.messages,
                  updatedAt: DateTime.now(),
                );

                return ref
                    .read(presetPromptsProvider.notifier)
                    .upsert(template);
              },
            );
          },
        );
      },
    );
  }

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
      showSettingsSnackbar(
        context,
        isEditing ? updatedMessage : createdMessage,
      );
    }
  }
}
