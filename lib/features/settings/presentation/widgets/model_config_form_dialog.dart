import 'package:flutter/material.dart';

import '../../domain/models/llm_provider_config.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

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

/// 新增或编辑服务商下模型的对话框。
class ModelConfigFormDialog extends StatefulWidget {
  const ModelConfigFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(ModelConfigFormData formData) onSubmit;
  final LlmProviderModelConfig? initialValue;

  @override
  State<ModelConfigFormDialog> createState() => _ModelConfigFormDialogState();
}

class _ModelConfigFormDialogState extends State<ModelConfigFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _displayNameController;
  late final TextEditingController _modelNameController;

  late bool _supportsReasoning;

  @override
  void initState() {
    super.initState();
    _displayNameController = initController(widget.initialValue?.displayName ?? '');
    _modelNameController = initController(widget.initialValue?.modelName ?? '');
    _supportsReasoning = widget.initialValue?.supportsReasoning ?? false;
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑模型' : '新增模型',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
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
  }
}
