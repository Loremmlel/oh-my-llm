import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_form_dialog_scaffold.dart';
import '../../shared/settings_form_dialog_state_mixin.dart';

/// 服务商表单提交数据。
class ModelProviderFormData {
  const ModelProviderFormData({
    required this.name,
    required this.apiUrl,
    required this.apiKey,
    required this.apiProtocol,
  });

  final String name;
  final String apiUrl;
  final String apiKey;
  final LlmApiProtocol apiProtocol;
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
  late LlmApiProtocol _selectedProtocol;

  @override
  void initState() {
    super.initState();
    _nameController = initController(widget.initialValue?.name ?? '');
    _apiUrlController = initController(widget.initialValue?.apiUrl ?? '');
    _apiKeyController = initController(widget.initialValue?.apiKey ?? '');
    // 编辑时沿用原协议，新建默认 Chat Completions（与持久化默认值一致）。
    _selectedProtocol =
        widget.initialValue?.apiProtocol ?? LlmApiProtocol.chatCompletions;
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
      title: isEditing ? '编辑服务商' : '新增服务商',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const ValueKey('model-provider-name-field'), // test-key
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '服务商名称',
              hintText: '例如：DeepSeek 官方',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('model-provider-api-url-field'), // test-key
            controller: _apiUrlController,
            decoration: const InputDecoration(
              labelText: 'API URL',
              hintText: 'https://api.example.com/v1/chat/completions',
            ),
            keyboardType: TextInputType.url,
            validator: _validateUrl,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LlmApiProtocol>(
            key: const ValueKey('model-provider-protocol-field'), // test-key
            initialValue: _selectedProtocol,
            // 紧凑视口下选中项过长时省略显示，避免横向溢出。
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'API 模式'),
            items: [
              for (final protocol in LlmApiProtocol.values)
                DropdownMenuItem(
                  value: protocol,
                  child: Text(protocol.displayName),
                ),
            ],
            onChanged: (protocol) {
              if (protocol != null) {
                setState(() {
                  _selectedProtocol = protocol;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('model-provider-api-key-field'), // test-key
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
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
          apiProtocol: _selectedProtocol,
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
