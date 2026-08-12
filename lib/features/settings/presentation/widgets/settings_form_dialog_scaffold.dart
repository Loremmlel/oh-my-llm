import 'package:flutter/material.dart';

/// 设置页表单对话框的统一壳层。
class SettingsFormDialogScaffold extends StatelessWidget {
  const SettingsFormDialogScaffold({
    required this.title,
    required this.formKey,
    required this.child,
    required this.isSaving,
    required this.onSubmit,
    this.width = 720,
    this.submitLabel = '保存',
    this.savingLabel = '保存中...',
    this.submitEnabled = true,
    this.shouldScrollContent = _alwaysScrollContent,
    super.key,
  });

  static bool _alwaysScrollContent(BoxConstraints _) => true;

  final String title;
  final GlobalKey<FormState> formKey;
  final Widget child;
  final bool isSaving;
  final Future<void> Function() onSubmit;
  final double width;
  final String submitLabel;
  final String savingLabel;
  final bool submitEnabled;
  final bool Function(BoxConstraints constraints) shouldScrollContent;

  @override
  Widget build(BuildContext context) {
    // 保存期间阻止 system Back 与 barrier tap 关闭对话框（取消/保存按钮
    // 已禁用，避免提交中的表单被意外卸载）；保存完成后 isSaving 恢复 false，
    // 路由回到可正常关闭状态。
    return PopScope<void>(canPop: !isSaving, child: _buildAlertDialog(context));
  }

  Widget _buildAlertDialog(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!shouldScrollContent(constraints)) {
              return Form(key: formKey, child: child);
            }

            return Form(
              key: formKey,
              child: SingleChildScrollView(
                key: const ValueKey('settings-form-dialog-outer-scroll-view'),
                child: child,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (isSaving || !submitEnabled) ? null : onSubmit,
          child: Text(isSaving ? savingLabel : submitLabel),
        ),
      ],
    );
  }
}
