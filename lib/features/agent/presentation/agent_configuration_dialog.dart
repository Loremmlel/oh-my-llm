import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../application/agent_context.dart';
import '../application/agent_harness.dart';
import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';
import 'agent_transcript.dart';

Future<void> showAgentConfiguration(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _ConfigurationDialog(),
);

class _ConfigurationDialog extends ConsumerStatefulWidget {
  const _ConfigurationDialog();
  @override
  ConsumerState<_ConfigurationDialog> createState() =>
      _ConfigurationDialogState();
}

class _ConfigurationDialogState extends ConsumerState<_ConfigurationDialog> {
  final _name = TextEditingController(), _preset = TextEditingController();
  final _instructions = {
    for (final role in AgentRole.values) role: TextEditingController(),
  };
  final _roleModels = <AgentRole, String?>{};
  final _presetRoles = <AgentRole>{};
  late AgentConfiguration _saved;
  AgentRole _role = AgentRole.coordinator;
  String? _modelId;
  bool _allowClose = false;

  @override
  void initState() {
    super.initState();
    _load(
      resolveAgentConfiguration(
        ref.read(agentWorkspaceProvider).workspace!.configuration,
      ),
    );
  }

  void _load(AgentConfiguration configuration) {
    _saved = configuration;
    _name.text = configuration.name;
    _preset.text = configuration.preset;
    _modelId = configuration.modelId;
    _presetRoles
      ..clear()
      ..addAll(configuration.presetRoles);
    for (final role in AgentRole.values) {
      _instructions[role]!.text = configuration.settings(role).instructions;
      _roleModels[role] = configuration.settings(role).modelId;
    }
  }

  AgentConfiguration get _value => AgentConfiguration(
    name: _name.text.trim(),
    revision: _saved.revision,
    modelId: _modelId,
    preset: _preset.text,
    presetRoles: _presetRoles,
    roles: {
      for (final role in AgentRole.values)
        role: AgentRoleSettings(
          modelId: role == AgentRole.coordinator ? null : _roleModels[role],
          instructions: _instructions[role]!.text,
        ),
    },
  );
  bool get _dirty => _value != _saved;

  Future<bool> _discard() async =>
      !_dirty ||
      await showDialog<bool>(
            context: context,
            builder: (_) => const AppConfirmDialog(
              title: '放弃未保存的配置？',
              message: '已保存的方案和现有会话不受影响。',
              confirmLabel: '放弃修改',
            ),
          ) ==
          true;

  Future<void> _close() async {
    if (!await _discard() || !mounted) return;
    setState(() => _allowClose = true);
    Navigator.pop(context);
  }

  AgentConfiguration? _save() {
    final saved = ref
        .read(agentWorkspaceProvider.notifier)
        .saveConfiguration(_value);
    if (saved != null) setState(() => _load(saved));
    return saved;
  }

  @override
  void dispose() {
    _name.dispose();
    _preset.dispose();
    for (final controller in _instructions.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final models = ref.watch(agentModelsProvider);
    final presets = ref.watch(agentPresetsProvider);
    final configurations = controller.configurations;
    final selectedModel = _role == AgentRole.coordinator
        ? _modelId
        : _roleModels[_role];
    final validModel = models.any((m) => m.id == selectedModel);
    return PopScope<void>(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: const Text('模型与规则'),
        content: SizedBox(
          width: AppContentWidths.readable,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '当前会话：${state.workspace!.sessionTitle} · ${state.workspace!.configuration.name} · 配置版本 ${state.workspace!.configuration.revision}',
                ),
                const SizedBox(height: AppSpacing.sm),
                if (configurations.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: ValueKey('history/${_saved.revision}'),
                    decoration: const InputDecoration(labelText: '载入已保存方案'),
                    isExpanded: true,
                    items: [
                      for (final c in configurations)
                        DropdownMenuItem(
                          value: c.revision,
                          child: Text(
                            '${c.name} · 版本 ${c.revision}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: state.busy
                        ? null
                        : (revision) async {
                            if (revision == null ||
                                !await _discard() ||
                                !mounted) {
                              return;
                            }
                            setState(
                              () => _load(
                                configurations.firstWhere(
                                  (c) => c.revision == revision,
                                ),
                              ),
                            );
                          },
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _name,
                  readOnly: state.busy,
                  decoration: const InputDecoration(
                    labelText: '方案名称',
                    helperText: '更改名称后保存，可另存一套方案。',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<AgentRole>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '配置职责'),
                  items: [
                    for (final r in AgentRole.values)
                      DropdownMenuItem(
                        value: r,
                        child: Text(agentRoleLabel(r)),
                      ),
                  ],
                  onChanged: (r) {
                    if (r != null) setState(() => _role = r);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: ValueKey('model/${_role.name}/$selectedModel'),
                  initialValue: validModel
                      ? selectedModel
                      : (_role == AgentRole.coordinator ? null : ''),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _role == AgentRole.coordinator
                        ? '主模型（需支持工具调用）'
                        : '此职责的模型',
                    helperText: selectedModel != null && !validModel
                        ? '已选模型不可用，请重新选择。'
                        : null,
                  ),
                  items: [
                    if (_role != AgentRole.coordinator)
                      const DropdownMenuItem(value: '', child: Text('继承主模型')),
                    for (final m in models)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: state.busy
                      ? null
                      : (id) => setState(() {
                          if (_role == AgentRole.coordinator) {
                            _modelId = id;
                          } else {
                            _roleModels[_role] = id == '' ? null : id;
                          }
                        }),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (models.isEmpty) const Text('请先在设置中添加支持工具调用的模型。'),
                TextField(
                  key: ValueKey(_role),
                  controller: _instructions[_role],
                  readOnly: state.busy,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '角色提示词',
                    helperText: '留空时采用此职责的默认提示词。',
                    alignLabelWithHint: true,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: state.busy
                        ? null
                        : () => setState(
                            () => _instructions[_role]!.text =
                                agentInstructions(_role),
                          ),
                    child: const Text('恢复此职责的默认提示词'),
                  ),
                ),
                const Divider(),
                if (presets.isNotEmpty)
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: '追加现有预设文本'),
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < presets.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            presets[i].name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: state.busy
                        ? null
                        : (index) {
                            if (index != null) {
                              setState(
                                () => _preset.text = [
                                  _preset.text,
                                  presets[index].content,
                                ].where((s) => s.isNotEmpty).join('\n\n'),
                              );
                            }
                          },
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _preset,
                  readOnly: state.busy,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '共享预设与文风',
                    helperText: '现有预设仅复制已启用文本；在本会话作为前置预设使用。',
                    helperMaxLines: 3,
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final role in AgentRole.values)
                      FilterChip(
                        label: Text(agentRoleLabel(role)),
                        selected: _presetRoles.contains(role),
                        onSelected: state.busy
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _presetRoles.add(role);
                                } else {
                                  _presetRoles.remove(role);
                                }
                              }),
                      ),
                  ],
                ),
                const Text('选中的职责会使用共享预设。工具权限由应用执行，修改提示词不会扩大权限。'),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  state.busy
                      ? '运行中可以查看配置，结束后可编辑。'
                      : '保存方案保留旧版本。已有历史时，应用配置会在本作品新建会话。',
                ),
                if (_saved.revision > 0) Text('已载入配置版本 ${_saved.revision}'),
                if (state.error.isNotEmpty)
                  Text(
                    state.error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('关闭')),
          OutlinedButton(
            onPressed: state.busy ? null : _save,
            child: const Text('保存方案'),
          ),
          FilledButton(
            onPressed: state.busy
                ? null
                : () {
                    final saved = _dirty || _saved.revision == 0
                        ? _save()
                        : _saved;
                    if (saved == null) return;
                    controller.applyConfiguration(saved);
                    if (ref.read(agentWorkspaceProvider).error.isEmpty) {
                      setState(() => _allowClose = true);
                      Navigator.pop(context);
                    }
                  },
            child: Text(state.workspace!.history.isEmpty ? '应用配置' : '应用并新建会话'),
          ),
        ],
      ),
    );
  }
}
