import 'package:flutter/material.dart';

/// 设置页表单对话框共享的提交状态、校验与控制器生命周期管理。
mixin SettingsFormDialogStateMixin<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool isSaving = false;
  final List<TextEditingController> _managedControllers = [];

  @protected
  TextEditingController initController([String initialText = '']) {
    final ctrl = TextEditingController(text: initialText);
    _managedControllers.add(ctrl);
    return ctrl;
  }

  @protected
  void disposeAllControllers() {
    for (final ctrl in _managedControllers) {
      ctrl.dispose();
    }
    _managedControllers.clear();
  }

  @protected
  bool validateForm() => formKey.currentState?.validate() ?? false;

  @protected
  String? validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }
    return null;
  }

  @protected
  void showFormSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @protected
  Future<void> submitAndClose(Future<void> Function() onSubmit) async {
    setState(() {
      isSaving = true;
    });
    await onSubmit();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
