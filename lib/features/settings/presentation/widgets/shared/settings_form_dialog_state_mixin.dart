import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';

import 'settings_form_dialog_scaffold.dart';

/// 设置页表单对话框与独立编辑页面共享的提交状态、校验、脏检查与控制器生命周期管理。
mixin SettingsFormDialogStateMixin<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool isSaving = false;
  bool leaveAllowed = false;
  String? saveError;

  final List<TextEditingController> _managedControllers = [];
  String _initialSnapshot = '';
  bool _confirmingLeave = false;

  @protected
  TextEditingController initController([String initialText = '']) {
    final ctrl = TextEditingController(text: initialText);
    _managedControllers.add(ctrl);
    return ctrl;
  }

  @protected
  LongTextEditingController initLongTextController([String initialText = '']) {
    final controller = LongTextEditingController(text: initialText);
    _managedControllers.add(controller);
    return controller;
  }

  @protected
  void disposeAllControllers() {
    for (final ctrl in _managedControllers) {
      ctrl.dispose();
    }
    _managedControllers.clear();
  }

  @protected
  void captureInitialSnapshot(String snapshot) {
    _initialSnapshot = snapshot;
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

  /// 在表单对话框或编辑页内显示一条通知。默认为 info 类型，调用方可覆盖。
  @protected
  void showFormSnackBar(String message) {
    context.showBubble(message);
  }

  /// 构建独立编辑页面的统一脚手架、离开确认、错误提示与响应式视口约束。
  @protected
  Widget buildEditorPage({
    required String title,
    required String targetName,
    required String Function() snapshotBuilder,
    required Future<void> Function() onSubmit,
    required Widget Function(
      BuildContext context,
      BoxConstraints constraints,
      bool shouldScroll,
    )
    builder,
    String? helpText,
    double width = 1080,
    bool submitEnabled = true,
    double minExpandedHeight = 420,
    bool Function(BoxConstraints constraints)? shouldScrollContent,
  }) {
    final resolveScroll =
        shouldScrollContent ??
        (constraints) =>
            constraints.maxWidth < AppBreakpoints.formMasterDetail &&
            constraints.maxHeight < minExpandedHeight;
    return SettingsFormDialogScaffold(
      fullPage: true,
      canPopPage: leaveAllowed,
      onRequestLeave: () => requestPageLeave(
        currentSnapshot: snapshotBuilder(),
        targetName: targetName,
      ),
      errorText: saveError,
      title: title,
      helpText: helpText,
      formKey: formKey,
      isSaving: isSaving,
      submitEnabled: submitEnabled,
      onSubmit: onSubmit,
      width: width,
      shouldScrollContent: resolveScroll,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            builder(context, constraints, resolveScroll(constraints)),
      ),
    );
  }

  /// 独立编辑页面的返回保护：有未保存更改时弹窗确认，确认或无更改后安全退栈。
  @protected
  Future<void> requestPageLeave({
    required String currentSnapshot,
    required String targetName,
  }) async {
    if (isSaving || _confirmingLeave) return;
    _confirmingLeave = true;
    final leave =
        currentSnapshot == _initialSnapshot ||
        await showDialog<bool>(
              context: context,
              builder: (_) => AppConfirmDialog(
                title: '放弃未保存的修改？',
                message: '返回后，本次对$targetName的修改将丢失。',
                confirmLabel: '放弃修改',
                isDestructive: true,
              ),
            ) ==
            true;
    _confirmingLeave = false;
    if (!mounted || !leave) return;
    setState(() => leaveAllowed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  /// 独立编辑页面的提交流程：允许退栈并退回上一级，异常时保留输入并在页面内提示错误。
  @protected
  Future<void> submitPageAndClose(Future<void> Function() onSubmit) async {
    if (isSaving) return;
    setState(() => saveError = null);
    try {
      await submitAndClose(() async {
        await onSubmit();
        if (mounted) {
          setState(() => leaveAllowed = true);
          await WidgetsBinding.instance.endOfFrame;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => saveError = '保存失败：$error');
      }
    }
  }

  @protected
  Future<void> submitAndClose(Future<void> Function() onSubmit) async {
    if (isSaving) return;
    setState(() {
      isSaving = true;
    });
    try {
      await onSubmit();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }
}
