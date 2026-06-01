import 'package:flutter/material.dart';

import '../../../../../core/widgets/app_confirm_dialog.dart';

/// 终止模型回复前的确认弹窗，避免误触。
class StopStreamingConfirmDialog extends StatelessWidget {
  const StopStreamingConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmDialog(
      title: '终止本次回答？',
      message: '会保留当前已经生成的内容，并立即停止后续回复。',
      confirmLabel: '终止回答',
      cancelLabel: '继续生成',
    );
  }
}
