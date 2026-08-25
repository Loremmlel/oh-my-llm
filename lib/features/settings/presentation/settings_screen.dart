import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../application/prompts/fixed_prompt_sequences_controller.dart';
import '../application/providers/llm_model_configs_controller.dart';
import '../application/prompts/memory_prompts_controller.dart';
import '../application/providers/model_catalog_workflow.dart';
import '../application/prompts/preset_prompts_controller.dart';
import '../application/preferences/settings_tab_preferences.dart';
import '../application/transfer/settings_transfer_catalog_provider.dart';
import '../application/transfer/settings_transfer_coordinator.dart';
import '../application/transfer/settings_transfer_types.dart';
import '../application/prompts/template_prompts_controller.dart';
import '../domain/models/prompts/fixed_prompt_sequence.dart';
import '../domain/models/providers/llm_provider_config.dart';
import '../domain/models/prompts/memory_prompt.dart';
import '../domain/models/prompts/preset_prompt.dart';
import '../domain/models/prompts/template_prompt.dart';
import 'widgets/transfer/import_confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/tabs/network_settings_tab.dart';
import 'widgets/tabs/other_settings_tab.dart';
import 'widgets/tabs/output_processing_tab.dart';

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

const _transferGroupsByTab = <SettingsTransferGroup>[
  SettingsTransferGroup.providers,
  SettingsTransferGroup.presets,
  SettingsTransferGroup.prompts,
  SettingsTransferGroup.network,
  SettingsTransferGroup.outputProcessing,
  SettingsTransferGroup.other,
];

/// 设置页入口，使用标签页组织服务商、预设、提示词和其它设置。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
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
          tooltip: '从剪贴板导入设置',
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
                      description: '配置可在聊天页选择的预设 Prompt，支持 system、前置、最新输入前与后置上下文，并记住最近一次使用的选择。',
                      action: FilledButton.icon(
                        onPressed: () => _showPresetPromptDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增预设'),
                      ),
                      child: PresetPromptsList(
                        templates: presetPrompts,
                        onCopyToClipboardRequested: (template) {
                          return _copyPresetPromptToClipboard(
                            context,
                            ref,
                            template,
                          );
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
    final preparation = ref
        .read(settingsTransferCoordinatorProvider)
        .exportGroups({_currentTransferGroup});
    if (preparation is SettingsExportNoContent) {
      showSettingsSnackbar(context, '$_currentTabLabel 没有可导出的数据');
      return;
    }

    final exportBatch = preparation as SettingsExportBatch;
    var confirmedSensitive = false;
    if (exportBatch.containsSensitive) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认复制敏感设置'),
          content: const Text('服务商 API Key 和自定义 Header 值将进入系统剪贴板，可能被其他应用读取。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认复制'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      confirmedSensitive = true;
    }

    final exposed = exportBatch.exposeJson(
      confirmedSensitive: confirmedSensitive,
    );
    if (exposed is! SettingsExportJsonExposed) return;
    await Clipboard.setData(ClipboardData(text: exposed.text));
    if (mounted) {
      showSettingsSnackbar(context, '已复制$_currentTabLabel到剪贴板');
    }
  }

  Future<void> _importToCurrentTab() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final preparation = ref
        .read(settingsTransferCoordinatorProvider)
        .prepareJson(clipboardData?.text);
    if (preparation is SettingsImportMalformed) {
      if (mounted) showSettingsSnackbar(context, '导入内容无效');
      return;
    }
    if (preparation is SettingsImportUnsupportedVersion) {
      if (mounted) showSettingsSnackbar(context, '不支持的设置传输版本');
      return;
    }
    if (preparation is SettingsImportUnknownSection) {
      if (mounted) {
        showSettingsSnackbar(context, '未知设置项：${preparation.sectionKey}');
      }
      return;
    }
    if (preparation is SettingsImportNoChanges) {
      if (mounted) showSettingsSnackbar(context, '没有可导入的变化');
      return;
    }
    if (preparation is SettingsImportSectionOutsideAllowedGroups ||
        preparation is SettingsImportInvalidParticipantPayload) {
      if (mounted) showSettingsSnackbar(context, '导入内容无效');
      return;
    }
    if (preparation is SettingsImportReady) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) =>
            ImportConfirmDialog(batch: preparation.batch),
      );
      if (confirmed == true && mounted) {
        showSettingsSnackbar(context, '设置已成功导入');
      }
    }
  }

  SettingsTransferGroup get _currentTransferGroup =>
      _transferGroupsByTab[_tabController.index];

  // ── 复制预设 ──────────────────────────────────────────────────

  /// 把单条预设序列化成导出 JSON 写入剪贴板，供贴到另一台设备的导入框。
  Future<void> _copyPresetPromptToClipboard(
    BuildContext context,
    WidgetRef ref,
    PresetPrompt source,
  ) async {
    final participant = ref
        .read(settingsTransferCatalogProvider)
        .participant<List<PresetPrompt>>(
          const SettingsTransferKey('presetPrompts'),
        );
    final preparation = ref
        .read(settingsTransferCoordinatorProvider)
        .exportValue(participant, [source]);
    if (preparation is! SettingsExportBatch) return;
    final exposed = preparation.exposeJson(confirmedSensitive: false);
    if (exposed is! SettingsExportJsonExposed) return;
    await Clipboard.setData(ClipboardData(text: exposed.text));
    if (context.mounted) {
      showSettingsSnackbar(context, '已复制预设 Prompt 到剪贴板');
    }
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
