import 'package:flutter/material.dart';

import '../../../data/model_list_client.dart';
import '../../../domain/models/llm_provider_config.dart';
import '../settings_form_dialog_scaffold.dart';
import '../settings_form_dialog_state_mixin.dart';
import 'model_fetch_section.dart';

/// 服务商下模型表单的提交数据。
class ModelConfigFormData {
  const ModelConfigFormData({
    required this.displayName,
    required this.modelName,
    required this.supportsReasoning,
  });

  final String displayName;
  final String modelName;
  final bool supportsReasoning;
}

/// 批量添加模型的单项数据。
class ModelBatchFormData {
  const ModelBatchFormData({
    required this.displayName,
    required this.modelName,
  });

  final String displayName;
  final String modelName;
}

enum _FormMode { manual, fetch }

/// 新增或编辑服务商下模型的对话框。
class ModelConfigFormDialog extends StatefulWidget {
  const ModelConfigFormDialog({
    required this.provider,
    required this.onSubmit,
    required this.onBatchAdd,
    required this.fetchModels,
    this.initialValue,
    super.key,
  });

  final LlmProviderConfig provider;

  final Future<void> Function(ModelConfigFormData formData) onSubmit;

  final Future<void> Function(List<ModelBatchFormData> items) onBatchAdd;

  final Future<List<RemoteModelInfo>> Function({
    required String modelsUrl,
    required String apiKey,
  }) fetchModels;

  final LlmProviderModelConfig? initialValue;

  @override
  State<ModelConfigFormDialog> createState() => _ModelConfigFormDialogState();
}

class _ModelConfigFormDialogState extends State<ModelConfigFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _displayNameController;
  late final TextEditingController _modelNameController;
  late bool _supportsReasoning;
  _FormMode _mode = _FormMode.manual;

  final GlobalKey<ModelFetchSectionState> _fetchSectionKey =
      GlobalKey<ModelFetchSectionState>();

  @override
  void initState() {
    super.initState();
    _displayNameController =
        initController(widget.initialValue?.displayName ?? '');
    _modelNameController =
        initController(widget.initialValue?.modelName ?? '');
    _supportsReasoning = widget.initialValue?.supportsReasoning ?? false;
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  bool get _isEditing => widget.initialValue != null;

  bool get _isBatchSubmitReady {
    final section = _fetchSectionKey.currentState;
    if (section == null) return false;
    final entries = section.entries;
    final selected = entries.where((e) => e.selected).toList();
    if (selected.isEmpty) return false;
    return selected.every((e) => e.controller.text.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsFormDialogScaffold(
      title: _isEditing ? '编辑模型' : '新增模型',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 520,
      submitLabel: _mode == _FormMode.fetch ? '添加所选模型' : '保存',
      submitEnabled: _mode != _FormMode.fetch || _isBatchSubmitReady,
      shouldScrollContent: (_) => true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isEditing) _buildModeSwitch(),
          if (_isEditing) ...[
            ..._buildManualForm(),
          ] else ...[
            // 始终构建两个区块但用 Visibility 控制可见性，
            // 这样切换模式时 ModelFetchSection 的 State（含已拉取的模型列表）会被保留。
            Visibility(
              visible: _mode == _FormMode.manual,
              maintainState: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildManualForm(),
              ),
            ),
            Visibility(
              visible: _mode == _FormMode.fetch,
              maintainState: true,
              child: ModelFetchSection(
                key: _fetchSectionKey,
                provider: widget.provider,
                fetchModels: widget.fetchModels,
                onSelectionChanged: () => setState(() {}),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SegmentedButton<_FormMode>(
        key: const ValueKey('model-config-mode-switch'),
        segments: const [
          ButtonSegment(
            value: _FormMode.manual,
            label: Text('手动输入'),
            icon: Icon(Icons.edit_outlined),
          ),
          ButtonSegment(
            value: _FormMode.fetch,
            label: Text('从 API 拉取'),
            icon: Icon(Icons.download_rounded),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
          });
        },
      ),
    );
  }

  List<Widget> _buildManualForm() {
    return [
      TextFormField(
        key: const ValueKey('model-config-display-name-field'),
        controller: _displayNameController,
        decoration: const InputDecoration(
          labelText: '显示名称',
          hintText: '例如：DeepSeek V4 Flash',
        ),
        validator: validateRequired,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('model-config-api-name-field'),
        controller: _modelNameController,
        decoration: const InputDecoration(
          labelText: 'API 模型名称',
          hintText: '例如：deepseek-v4-flash',
        ),
        validator: validateRequired,
      ),
      const SizedBox(height: 12),
      SwitchListTile.adaptive(
        key: const ValueKey('model-config-supports-reasoning-field'),
        contentPadding: EdgeInsets.zero,
        value: _supportsReasoning,
        title: const Text('支持深度思考'),
        subtitle: const Text('聊天页会据此决定是否展示思考相关选项。'),
        onChanged: (value) {
          setState(() {
            _supportsReasoning = value;
          });
        },
      ),
    ];
  }

  Future<void> _handleSubmit() async {
    if (_mode == _FormMode.manual) {
      if (!validateForm()) {
        return;
      }
      await submitAndClose(() {
        return widget.onSubmit(
          ModelConfigFormData(
            displayName: _displayNameController.text.trim(),
            modelName: _modelNameController.text.trim(),
            supportsReasoning: _supportsReasoning,
          ),
        );
      });
      return;
    }

    // 拉取模式
    final section = _fetchSectionKey.currentState;
    if (section == null) return;

    final selectedEntries = section.entries.where((e) => e.selected).toList();
    if (selectedEntries.isEmpty) return;

    final items = selectedEntries
        .map((e) => ModelBatchFormData(
              displayName: e.controller.text.trim(),
              modelName: e.remoteModel.id,
            ))
        .toList();

    await submitAndClose(() {
      return widget.onBatchAdd(items);
    });
  }
}
