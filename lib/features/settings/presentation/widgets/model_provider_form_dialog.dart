import 'package:flutter/material.dart';

import '../../domain/models/llm_provider_config.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

/// 服务商表单提交数据。
class ModelProviderFormData {
  const ModelProviderFormData({
    required this.name,
    required this.apiUrl,
    required this.apiKey,
  });

  final String name;
  final String apiUrl;
  final String apiKey;
}

/// 新增或编辑服务商的对话框。
class ModelProviderFormDialog extends StatefulWidget {
  const ModelProviderFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(ModelProviderFormData formData) onSubmit;
  final LlmProviderConfig? initialValue;

  @override
  State<ModelProviderFormDialog> createState() =>
      _ModelProviderFormDialogState();
}

class _ModelProviderFormDialogState extends State<ModelProviderFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _apiUrlController = TextEditingController(
      text: widget.initialValue?.apiUrl ?? '',
    );
    _apiKeyController = TextEditingController(
      text: widget.initialValue?.apiKey ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑服务商' : '新增服务商',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const ValueKey('model-provider-name-field'),
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '服务商名称',
              hintText: '例如：DeepSeek 官方',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('model-provider-api-url-field'),
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
            key: const ValueKey('model-provider-api-key-field'),
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
            validator: validateRequired,
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
        ModelProviderFormData(
          name: _nameController.text.trim(),
          apiUrl: _apiUrlController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
        ),
      );
    });
  }

  String? _validateUrl(String? value) {
    final requiredError = validateRequired(value);
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
