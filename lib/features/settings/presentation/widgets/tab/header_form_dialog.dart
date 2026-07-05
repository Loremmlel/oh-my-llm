import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/custom_headers_controller.dart';
import '../settings_form_dialog_scaffold.dart';
import '../settings_form_dialog_state_mixin.dart';

/// 自定义请求头的新增/编辑对话框。
class HeaderFormDialog extends ConsumerStatefulWidget {
  const HeaderFormDialog({
    super.key,
    this.index,
    this.initialKey = '',
    this.initialValue = '',
  });

  final int? index;
  final String initialKey;
  final String initialValue;

  @override
  ConsumerState<HeaderFormDialog> createState() => _HeaderFormDialogState();
}

class _HeaderFormDialogState extends ConsumerState<HeaderFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _keyController = initController(widget.initialKey);
    _valueController = initController(widget.initialValue);
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  bool get _isEditing => widget.index != null;

  Future<void> _handleSubmit() async {
    if (!validateForm()) return;
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();
    final controller = ref.read(customHeadersProvider.notifier);
    if (_isEditing) {
      await controller.updateHeader(widget.index!, key, value);
      showFormSnackBar('请求头已更新');
    } else {
      await controller.addHeader(key, value);
      showFormSnackBar('请求头已添加');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsFormDialogScaffold(
      title: _isEditing ? '编辑请求头' : '新增请求头',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: () => submitAndClose(_handleSubmit),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: '请求头键',
              hintText: '如 User-Agent、X-Custom',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            validator: validateRequired,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _valueController,
            decoration: const InputDecoration(
              labelText: '请求头值',
              hintText: '自定义的值',
              border: OutlineInputBorder(),
            ),
            validator: validateRequired,
          ),
        ],
      ),
    );
  }
}
