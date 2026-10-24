import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/widgets/app_adaptive_actions.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../application/preferences/settings_tab_preferences.dart';
import '../application/prompts/fixed_prompt_sequences_controller.dart';
import '../application/prompts/memory_prompts_controller.dart';
import '../application/prompts/preset_prompts_controller.dart';
import '../application/prompts/template_prompts_controller.dart';
import '../application/providers/llm_model_configs_controller.dart';
import '../application/providers/model_catalog_workflow.dart';
import '../application/transfer/settings_transfer_coordinator.dart';
import '../application/transfer/settings_transfer_coordinator_provider.dart';
import '../application/transfer/settings_transfer_types.dart';
import '../domain/models/preferences/settings_tab.dart';
import '../domain/models/prompts/fixed_prompt_sequence.dart';
import '../domain/models/prompts/memory_prompt.dart';
import '../domain/models/prompts/preset_prompt.dart';
import '../domain/models/prompts/template_prompt.dart';
import '../domain/models/providers/llm_provider_config.dart';
import 'widgets/prompts/forms/silly_tavern_import_dialog.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/shared/settings_workspace.dart';
import 'widgets/tabs/network_settings_tab.dart';
import 'widgets/tabs/other_settings_tab.dart';
import 'widgets/tabs/output_processing_tab.dart';
import 'widgets/transfer/import_confirm_dialog.dart';
import 'widgets/worldbooks/world_books_tab.dart';

SettingsTransferGroup _transferGroupForTab(SettingsTab tab) {
  switch (tab) {
    case SettingsTab.providers:
      return SettingsTransferGroup.providers;
    case SettingsTab.presets:
      return SettingsTransferGroup.presets;
    case SettingsTab.prompts:
      return SettingsTransferGroup.prompts;
    case SettingsTab.network:
      return SettingsTransferGroup.network;
    case SettingsTab.outputProcessing:
      return SettingsTransferGroup.outputProcessing;
    case SettingsTab.other:
      return SettingsTransferGroup.other;
    case SettingsTab.worldBooks:
      return SettingsTransferGroup.worldBooks;
  }
}

/// 设置页入口，使用可拖拽标签页组织服务商、预设、提示词和其它设置。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  int? _promptCategory;

  @override
  void initState() {
    super.initState();
    final initialOrder = ref.read(settingsTabOrderProvider);
    _tabController = TabController(
      initialIndex: ref
          .read(settingsTabPreferencesProvider)
          .initialIndex(tabCount: initialOrder.length),
      length: initialOrder.length,
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

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    final currentOrder = ref.read(settingsTabOrderProvider);
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        newIndex < 0 ||
        newIndex >= currentOrder.length) {
      return;
    }

    final activeIndex = _tabController.index.clamp(0, currentOrder.length - 1);
    final activeTab = currentOrder[activeIndex];

    // 同步预计算重排后索引并更新控制器，避免 await 持久化导致 TabBarView 错帧闪烁
    final nextOrder = List<SettingsTab>.of(currentOrder);
    final item = nextOrder.removeAt(oldIndex);
    nextOrder.insert(newIndex, item);
    final nextActiveIndex = nextOrder.indexOf(activeTab);

    if (nextActiveIndex != -1 && nextActiveIndex != _tabController.index) {
      _tabController.index = nextActiveIndex;
    }

    await ref
        .read(settingsTabOrderProvider.notifier)
        .reorder(oldIndex, newIndex);

    await _saveTabIndex();
  }

  SettingsTab _currentTab(List<SettingsTab> tabsOrder) {
    if (tabsOrder.isEmpty) return SettingsTab.providers;
    final index = _tabController.index.clamp(0, tabsOrder.length - 1);
    return tabsOrder[index];
  }

  String _currentTabLabel(List<SettingsTab> tabsOrder) =>
      _currentTab(tabsOrder).exportLabel;

  SettingsTransferGroup _currentTransferGroup(List<SettingsTab> tabsOrder) =>
      _transferGroupForTab(_currentTab(tabsOrder));

  @override
  Widget build(BuildContext context) {
    final tabsOrder = ref.watch(settingsTabOrderProvider);
    final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
    final modelProviders = ref.watch(llmProviderConfigsProvider);
    final memoryPrompts = ref.watch(memoryPromptsProvider);
    final presetPrompts = ref.watch(presetPromptsProvider);
    final templatePrompts = ref.watch(templatePromptsProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置',
      adaptiveActions: AppAdaptiveActions(
        wideActions: [
          Tooltip(
            message: '从剪贴板导入设置',
            child: TextButton.icon(
              onPressed: () => _importToCurrentTab(tabsOrder),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导入'),
            ),
          ),
          Tooltip(
            message: '导出${_currentTabLabel(tabsOrder)}',
            child: TextButton.icon(
              onPressed: () => _exportCurrentTab(tabsOrder),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        compactActions: [
          IconButton(
            onPressed: () => _importToCurrentTab(tabsOrder),
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '从剪贴板导入设置',
          ),
          IconButton(
            onPressed: () => _exportCurrentTab(tabsOrder),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出${_currentTabLabel(tabsOrder)}',
          ),
        ],
      ),
      body: SettingsWorkspace(
        controller: _tabController,
        tabs: tabsOrder,
        selectedPromptCategory: _promptCategory,
        onReorder: _handleReorder,
        onPromptCategorySelected: (index) =>
            setState(() => _promptCategory = index < 0 ? null : index),
        onPromptOverview: () => setState(() => _promptCategory = null),
        providerAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppHelpButton(
              title: '服务商设置',
              message: '管理服务商与其下模型。聊天页会记住最近一次使用的模型。',
            ),
            FilledButton.icon(
              onPressed: () => _showModelProviderDialog(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增服务商'),
            ),
          ],
        ),
        children: tabsOrder
            .map(
              (tab) => _buildTabContent(
                context,
                tab,
                modelProviders: modelProviders,
                presetPrompts: presetPrompts,
                memoryPrompts: memoryPrompts,
                templatePrompts: templatePrompts,
                fixedPromptSequences: fixedPromptSequences,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    SettingsTab tab, {
    required List<LlmProviderConfig> modelProviders,
    required List<PresetPrompt> presetPrompts,
    required List<MemoryPrompt> memoryPrompts,
    required List<TemplatePrompt> templatePrompts,
    required List<FixedPromptSequence> fixedPromptSequences,
  }) {
    switch (tab) {
      case SettingsTab.providers:
        return KeyedSubtree(
          key: const ValueKey('settings_tab_content_providers'),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppContentWidths.wide,
                  ),
                  child: ModelConfigsList(
                    providers: modelProviders,
                    onBatchAddModelsRequested: (provider) =>
                        _showModelConfigDialog(
                          context,
                          ref,
                          provider: provider,
                          initialBatchMode: true,
                        ),
                    onEditProviderRequested: (provider) {
                      _showModelProviderDialog(
                        context,
                        ref,
                        initialValue: provider,
                      );
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
                ),
              ),
            ],
          ),
        );
      case SettingsTab.presets:
        return KeyedSubtree(
          key: const ValueKey('settings_tab_content_presets'),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: '预设 Prompt',
                titleStyle: Theme.of(context).textTheme.titleLarge,
                description: '配置可在聊天页选择的预设 Prompt，支持 system、前置、最新输入前与后置上下文，并记住最近一次使用的选择。',
                action: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showPresetPromptDialog(context, ref),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('新增预设'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const SillyTavernImportDialog(),
                      ),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导入 SillyTavern'),
                    ),
                  ],
                ),
                child: PresetPromptsList(
                  templates: presetPrompts,
                  onCopyToClipboardRequested: (template) {
                    return _copyPresetPromptToClipboard(context, ref, template);
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
        );
      case SettingsTab.prompts:
        return KeyedSubtree(
          key: const ValueKey('settings_tab_content_prompts'),
          child: ListView(
            key: PageStorageKey('settings-prompts-${_promptCategory ?? 'all'}'),
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppContentWidths.wide,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_promptCategory == null) ...[
                        Text(
                          '提示词总览',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '3 个分类 · ${memoryPrompts.length + templatePrompts.length + fixedPromptSequences.length} 项',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_promptCategory == null || _promptCategory == 0)
                        SettingsSectionCard(
                          title: '记忆总结提示词',
                          useSideHeader: _promptCategory == null,
                          titleStyle: _promptCategory == null
                              ? null
                              : Theme.of(context).textTheme.titleLarge,
                          status: Text(
                            '${memoryPrompts.length} 项 · 检查点总结',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          description: '配置聊天页创建检查点时可选择的总结提示词，用于适配不同场景下的记忆沉淀方式。',
                          action: FilledButton.icon(
                            onPressed: () =>
                                _showMemoryPromptDialog(context, ref),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('新增记忆提示词'),
                          ),
                          child: MemoryPromptsList(
                            onDelete: ref
                                .read(memoryPromptsProvider.notifier)
                                .deleteById,
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
                      if (_promptCategory == null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_promptCategory == null || _promptCategory == 1)
                        SettingsSectionCard(
                          title: '模板提示词',
                          useSideHeader: _promptCategory == null,
                          titleStyle: _promptCategory == null
                              ? null
                              : Theme.of(context).textTheme.titleLarge,
                          status: Text(
                            '${templatePrompts.length} 项 · 输入与变量',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          description: '配置可在聊天页临时应用的变量模板。使用 {{变量名}} 声明注入位，{{正文}} 对应主输入框。',
                          action: FilledButton.icon(
                            onPressed: () =>
                                _showTemplatePromptDialog(context, ref),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('新增模板提示词'),
                          ),
                          child: TemplatePromptsList(
                            onDelete: ref
                                .read(templatePromptsProvider.notifier)
                                .deleteById,
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
                      if (_promptCategory == null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_promptCategory == null || _promptCategory == 2)
                        SettingsSectionCard(
                          title: '固定顺序提示词',
                          useSideHeader: _promptCategory == null,
                          titleStyle: _promptCategory == null
                              ? null
                              : Theme.of(context).textTheme.titleLarge,
                          status: Text(
                            '${fixedPromptSequences.length} 项 · 分步发送',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          description: '配置可逐步发送的用户提示词序列，适合做模型对比测试，不会自动整组连发。',
                          action: FilledButton.icon(
                            onPressed: () =>
                                _showFixedPromptSequenceDialog(context, ref),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('新增序列'),
                          ),
                          child: FixedPromptSequencesList(
                            onDelete: ref
                                .read(fixedPromptSequencesProvider.notifier)
                                .deleteById,
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
                ),
              ),
            ],
          ),
        );
      case SettingsTab.network:
        return const KeyedSubtree(
          key: ValueKey('settings_tab_content_network'),
          child: NetworkSettingsTab(),
        );
      case SettingsTab.outputProcessing:
        return const KeyedSubtree(
          key: ValueKey('settings_tab_content_output_processing'),
          child: OutputProcessingTab(),
        );
      case SettingsTab.other:
        return const KeyedSubtree(
          key: ValueKey('settings_tab_content_other'),
          child: OtherSettingsTab(),
        );
      case SettingsTab.worldBooks:
        return const KeyedSubtree(
          key: ValueKey('settings_tab_content_world_books'),
          child: WorldBooksTab(),
        );
    }
  }

  // ── 导出/导入 ──────────────────────────────────────────────────

  Future<void> _exportCurrentTab(List<SettingsTab> tabsOrder) async {
    final group = _currentTransferGroup(tabsOrder);
    final label = _currentTabLabel(tabsOrder);
    final preparation = ref
        .read(settingsTransferCoordinatorProvider)
        .exportGroups({group});
    if (preparation is SettingsExportNoContent) {
      showSettingsSnackbar(context, '$label 没有可导出的数据');
      return;
    }

    final exportBatch = preparation as SettingsExportBatch;
    var confirmedSensitive = false;
    if (exportBatch.containsSensitive) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AppConfirmDialog(
          title: '确认复制敏感设置',
          message: '服务商 API Key 和自定义 Header 值将进入系统剪贴板，可能被其他应用读取。',
          confirmLabel: '确认复制',
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
      showSettingsSnackbar(context, '已复制$label到剪贴板');
    }
  }

  Future<void> _importToCurrentTab(List<SettingsTab> tabsOrder) async {
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
        preparation is SettingsImportInvalidSectionPayload) {
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

  // ── 复制预设 ──────────────────────────────────────────────────

  /// 把单条预设序列化成导出 JSON 写入剪贴板，供贴到另一台设备的导入框。
  Future<void> _copyPresetPromptToClipboard(
    BuildContext context,
    WidgetRef ref,
    PresetPrompt source,
  ) async {
    final preparation = ref
        .read(settingsTransferCoordinatorProvider)
        .exportPreset(source);
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
    bool initialBatchMode = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ModelConfigFormDialog(
          provider: provider,
          initialBatchMode: initialBatchMode,
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
                  supportsImageInput: formData.supportsImageInput,
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
                    supportsReasoning: item.supportsReasoning,
                    supportsImageInput: item.supportsImageInput,
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
    return context.push<void>(
      '/settings/presets/${initialValue == null ? 'new' : Uri.encodeComponent(initialValue.id)}',
    );
  }

  Future<void> _showMemoryPromptDialog(
    BuildContext context,
    WidgetRef ref, {
    MemoryPrompt? initialValue,
  }) {
    return context.push<void>(
      '/settings/memory-prompts/${initialValue == null ? 'new' : Uri.encodeComponent(initialValue.id)}',
    );
  }

  Future<void> _showTemplatePromptDialog(
    BuildContext context,
    WidgetRef ref, {
    TemplatePrompt? initialValue,
  }) {
    return context.push<void>(
      '/settings/template-prompts/${initialValue == null ? 'new' : Uri.encodeComponent(initialValue.id)}',
    );
  }

  Future<void> _showFixedPromptSequenceDialog(
    BuildContext context,
    WidgetRef ref, {
    FixedPromptSequence? initialValue,
  }) {
    return context.push<void>(
      '/settings/fixed-sequences/${initialValue == null ? 'new' : Uri.encodeComponent(initialValue.id)}',
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
