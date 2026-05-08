import 'package:flutter/material.dart';

/// 设置页表单对话框共享的提交状态与基础校验能力。
mixin SettingsFormDialogStateMixin<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool isSaving = false;

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
