import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹窗共用的取消与提交键，不改变内容布局和业务校验。
///
/// Esc 默认尝试返回，保留 PopScope 的忙碌保护；自定义关闭流程通过
/// [onCancel] 接入。Ctrl+Enter 提交，普通 Enter 留给输入法和当前控件。
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({
    required this.child,
    this.onCancel,
    this.onSubmit,
    super.key,
  });

  final Widget child;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => FocusScope(
    autofocus: true,
    onKeyEvent: (node, event) {
      final keyboard = HardwareKeyboard.instance;
      final cancel = const SingleActivator(LogicalKeyboardKey.escape)
          .accepts(event, keyboard);
      final submit =
          const SingleActivator(
            LogicalKeyboardKey.enter,
            control: true,
          ).accepts(event, keyboard) ||
          const SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            control: true,
          ).accepts(event, keyboard);
      if (!cancel && !submit) return KeyEventResult.ignored;
      // 长按不能在退场中继续关闭父弹窗或重复提交。
      if (event is KeyRepeatEvent) return KeyEventResult.handled;

      final editable = FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      final composing = editable?.widget.controller.value.composing;
      if (composing != null && composing.isValid && !composing.isCollapsed) {
        // 放回平台输入法，同时阻止外层默认 Esc 关闭弹窗。
        return KeyEventResult.skipRemainingHandlers;
      }
      if (cancel) {
        if (onCancel case final cancelAction?) {
          cancelAction();
        } else {
          Navigator.of(context).maybePop();
        }
      } else {
        onSubmit?.call();
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}
