import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../core/utils/id_generator.dart';
import '../application/auto_retry_settings_controller.dart';
import '../application/fixed_prompt_sequences_controller.dart';
import '../application/llm_model_configs_controller.dart';
import '../application/memory_prompts_controller.dart';
import '../application/preset_prompts_controller.dart';
import '../application/settings_import_deduplicator.dart';
import '../application/template_prompts_controller.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import '../domain/models/llm_provider_config.dart';
import '../domain/models/memory_prompt.dart';
import '../domain/models/preset_prompt.dart';
import '../domain/models/settings_export_data.dart';
import '../domain/models/template_prompt.dart';
import 'widgets/import_confirm_dialog.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/tab/other_settings_tab.dart';

const _settingsLastTabIndexKey = 'settings.tab.last_index';

const _tabProviders = 0;
const _tabPresets = 1;
const _tabPrompts = 2;
const _tabOther = 3;

const _tabLabelProviders = '服务商';
const _tabLabelPresets = '预设 Prompt';
const _tabLabelPrompts = '提示词';
const _tabLabelOther = '其它设置';

/// 设置页入口，使用标签页组织服务商、预设、提示词和其它设置。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  static const _importDeduplicator = SettingsImportDeduplicator();
  static final _presetPromptCopySuffixPattern = RegExp(
    r'^(.+?)（副本(?: \d+)?）$',
  );

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = ref
        .read(sharedPreferencesProvider)
        .getInt(_settingsLastTabIndexKey) ??
        0;
    _tabController = TabController(
      initialIndex: initialIndex.clamp(0, 3),
      length: 4,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
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
      ref
          .read(sharedPreferencesProvider)
          .setInt(_settingsLastTabIndexKey, _tabController.index);
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
                        onPressed: () =>
                            _showModelProviderDialog(context, ref),
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
                          '配置可在聊天页选择的预设 Prompt，支持 system、前置与后置上下文，并记住最近一次使用的选择。',
                      action: FilledButton.icon(
                        onPressed: () =>
                            _showPresetPromptDialog(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增预设'),
                      ),
                      child: PresetPromptsList(
                        templates: presetPrompts,
                        onDuplicateRequested: (template) {
                          return _duplicatePresetPrompt(
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
                      description:
                          '配置聊天页创建检查点时可选择的总结提示词，用于适配不同场景下的记忆沉淀方式。',
                      action: FilledButton.icon(
                        onPressed: () =>
                            _showMemoryPromptDialog(context, ref),
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
                      description:
                          '配置可逐步发送的用户提示词序列，适合做模型对比测试，不会自动整组连发。',
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
      default:
        return '';
    }
  }

  // ── 导出/导入 ──────────────────────────────────────────────────

  Future<void> _exportCurrentTab() async {
    final index = _tabController.index;
    final exportData = _buildTabExportData(index);
    if (exportData == null) {
      showSettingsSnackbar(context, '$_currentTabLabel 没有可导出的数据');
      return;
    }

    await Clipboard.setData(ClipboardData(text: exportData.toJsonString()));
    if (mounted) {
      showSettingsSnackbar(context, '已复制$_currentTabLabel到剪贴板');
    }
  }

  SettingsExportData? _buildTabExportData(int index) {
    switch (index) {
      case _tabProviders:
        final providers = ref.read(llmProviderConfigsProvider);
        if (providers.isEmpty) return null;
        return SettingsExportData(
          modelProviders: providers,
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
        );
      case _tabPresets:
        final templates = ref.read(presetPromptsProvider);
        if (templates.isEmpty) return null;
        return SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: templates,
          templatePrompts: const [],
          fixedPromptSequences: const [],
        );
      case _tabPrompts:
        final memoryPrompts = ref.read(memoryPromptsProvider);
        final templatePrompts = ref.read(templatePromptsProvider);
        final sequences = ref.read(fixedPromptSequencesProvider);
        if (memoryPrompts.isEmpty &&
            templatePrompts.isEmpty &&
            sequences.isEmpty) {
          return null;
        }
        return SettingsExportData(
          modelProviders: const [],
          memoryPrompts: memoryPrompts,
          presetPrompts: const [],
          templatePrompts: templatePrompts,
          fixedPromptSequences: sequences,
        );
      case _tabOther:
        final settings = ref.read(autoRetrySettingsProvider);
        return SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
          autoRetrySettings: settings,
        );
      default:
        return null;
    }
  }

  Future<void> _importToCurrentTab() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final exportData = SettingsExportData.tryParseJson(clipboardData?.text);

    if (exportData == null || !exportData.hasContent) {
      if (mounted) {
        showSettingsSnackbar(context, '剪贴板中没有可识别的配置数据');
      }
      return;
    }

    final index = _tabController.index;
    if (!_dataMatchesTab(exportData, index)) {
      if (mounted) {
        showSettingsSnackbar(context, '剪贴板数据与$_currentTabLabel不匹配，请切换到对应标签');
      }
      return;
    }

    // 去重（autoRetrySettings 不需要去重，deduplicator 会直接透传）。
    final dedupedData = _importDeduplicator.deduplicate(
      data: exportData,
      existingProviders: ref.read(llmProviderConfigsProvider),
      existingMemoryPrompts: ref.read(memoryPromptsProvider),
      existingPresetPrompts: ref.read(presetPromptsProvider),
      existingTemplatePrompts: ref.read(templatePromptsProvider),
      existingSequences: ref.read(fixedPromptSequencesProvider),
    );

    if (!dedupedData.hasContent) {
      if (mounted) {
        showSettingsSnackbar(context, '剪贴板中的配置在本地均已存在，无可导入项');
      }
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ImportConfirmDialog(exportData: dedupedData);
      },
    );

    if (confirmed == true && mounted) {
      showSettingsSnackbar(context, '$_currentTabLabel已成功导入');
    }
  }

  /// 检查导出数据是否匹配当前标签页。
  bool _dataMatchesTab(SettingsExportData data, int index) {
    switch (index) {
      case _tabProviders:
        return data.modelProviders.isNotEmpty;
      case _tabPresets:
        return data.presetPrompts.isNotEmpty;
      case _tabPrompts:
        return data.memoryPrompts.isNotEmpty ||
            data.templatePrompts.isNotEmpty ||
            data.fixedPromptSequences.isNotEmpty;
      case _tabOther:
        return data.autoRetrySettings != null;
      default:
        return false;
    }
  }

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
