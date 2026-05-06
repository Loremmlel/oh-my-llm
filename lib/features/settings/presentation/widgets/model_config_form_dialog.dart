import 'package:flutter/material.dart';

import '../../domain/models/llm_provider_config.dart';

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

class _ModelConfigFormDialogState extends State<ModelConfigFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _displayNameController;
  late final TextEditingController _modelNameController;

  late bool _supportsReasoning;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialValue?.displayName ?? '',
    );
    _modelNameController = TextEditingController(
      text: widget.initialValue?.modelName ?? '',
    );
    _supportsReasoning = widget.initialValue?.supportsReasoning ?? false;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return AlertDialog(
      title: Text(isEditing ? '编辑模型' : '新增模型'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    hintText: '例如：DeepSeek V4 Flash',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modelNameController,
                  decoration: const InputDecoration(
                    labelText: 'API 模型名称',
                    hintText: '例如：deepseek-v4-flash',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
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
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSubmit,
          child: Text(_isSaving ? '保存中...' : '保存'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await widget.onSubmit(
      ModelConfigFormData(
        displayName: _displayNameController.text.trim(),
        modelName: _modelNameController.text.trim(),
        supportsReasoning: _supportsReasoning,
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }

    return null;
  }
}
