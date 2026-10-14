import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_dialog_actions.dart';

/// 设置页表单对话框的统一壳层。
class SettingsFormDialogScaffold extends StatelessWidget {
  const SettingsFormDialogScaffold({
    required this.title,
    required this.formKey,
    required this.child,
    required this.isSaving,
    required this.onSubmit,
    this.helpText,
    this.fullPage = false,
    this.width = 720,
    this.submitLabel = '保存',
    this.savingLabel = '保存中...',
    this.submitEnabled = true,
    this.shouldScrollContent = _alwaysScrollContent,
    super.key,
  });

  static bool _alwaysScrollContent(BoxConstraints _) => true;

  final String title;
  final bool fullPage;
  final String? helpText;
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
    return AppDialogActions(
      onSubmit: (isSaving || !submitEnabled) ? null : onSubmit,
      child: PopScope<void>(
        canPop: !isSaving,
        child: fullPage
            ? Scaffold(
                appBar: AppBar(
                  title: helpText == null
                      ? Text(title)
                      : AppHelpTitle(title: title, message: helpText!),
                  actions: [
                    TextButton(
                      onPressed: isSaving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('取消'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: FilledButton(
                        onPressed: (isSaving || !submitEnabled)
                            ? null
                            : onSubmit,
                        child: Text(isSaving ? savingLabel : submitLabel),
                      ),
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(builder: _buildForm),
                  ),
                ),
              )
            : _buildAlertDialog(context),
      ),
    );
  }

  Widget _buildAlertDialog(BuildContext context) {
    return AlertDialog(
      title: helpText == null
          ? Text(title)
          : AppHelpTitle(title: title, message: helpText!),
      content: SizedBox(
        width: width,
        child: LayoutBuilder(builder: _buildForm),
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

  Widget _buildForm(BuildContext context, BoxConstraints constraints) {
    // 键盘改变可用高度时只切换约束，避免增删滚动容器卸载输入框、关闭输入法。
    return Form(
      key: formKey,
      child: SingleChildScrollView(
        key: const ValueKey('settings-form-dialog-outer-scroll-view'),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: shouldScrollContent(constraints)
                ? double.infinity
                : constraints.maxHeight,
          ),
          child: child,
        ),
      ),
    );
  }
}
