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
  final bool Function(BoxConstraints constraints) shouldScrollContent;

  @override
  Widget build(BuildContext context) {
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
          onPressed: isSaving ? null : onSubmit,
          child: Text(isSaving ? savingLabel : submitLabel),
        ),
      ],
    );
  }
}
