import 'package:flutter/material.dart';

import '../../domain/models/llm_model_config.dart';

/// 模型配置表单提交数据。
class ModelConfigFormData {
  const ModelConfigFormData({
    required this.displayName,
    required this.apiUrl,
    required this.apiKey,
    required this.modelName,
    required this.supportsReasoning,
  });

  final String displayName;
  final String apiUrl;
  final String apiKey;
  final String modelName;
  final bool supportsReasoning;
}

/// 新增或编辑模型配置的对话框。
class ModelConfigFormDialog extends StatefulWidget {
  const ModelConfigFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(ModelConfigFormData formData) onSubmit;
  final LlmModelConfig? initialValue;

  @override
  State<ModelConfigFormDialog> createState() => _ModelConfigFormDialogState();
}

/// 模型配置表单的输入状态。
class _ModelConfigFormDialogState extends State<ModelConfigFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _displayNameController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelNameController;

  late bool _supportsReasoning;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialValue?.displayName ?? '',
    );
    _apiUrlController = TextEditingController(
      text: widget.initialValue?.apiUrl ?? '',
    );
    _apiKeyController = TextEditingController(
      text: widget.initialValue?.apiKey ?? '',
    );
    _modelNameController = TextEditingController(
      text: widget.initialValue?.modelName ?? '',
    );
    _supportsReasoning = widget.initialValue?.supportsReasoning ?? false;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  @override
  /// 构建模型配置表单和保存按钮。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return AlertDialog(
      title: Text(isEditing ? '编辑模型配置' : '新增模型配置'),
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
                    hintText: '例如：Claude Sonnet 4.5',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://api.example.com/v1/chat/completions',
                  ),
                  keyboardType: TextInputType.url,
                  validator: _validateUrl,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(labelText: 'API Key'),
                  obscureText: true,
                  validator: _validateRequired,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modelNameController,
                  decoration: const InputDecoration(
                    labelText: 'API 模型名称',
                    hintText: '例如：gpt-4.1',
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

  /// 提交表单并在成功后关闭对话框。
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
        apiUrl: _apiUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        modelName: _modelNameController.text.trim(),
        supportsReasoning: _supportsReasoning,
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 校验必填字段是否为空。
  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }

    return null;
  }

  /// 校验输入是否为合法 URL。
  String? _validateUrl(String? value) {
    final requiredError = _validateRequired(value);
    if (requiredError != null) {
      return requiredError;
    }

    final uri = Uri.tryParse(value!.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '请输入有效的 URL';
    }

    return null;
  }
}
