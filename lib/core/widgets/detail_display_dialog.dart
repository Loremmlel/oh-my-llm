import 'package:flutter/material.dart';

/// 纯展示弹窗的统一壳层。
///
/// 适用于只读详情、信息展示等不需要用户操作的弹窗。提供固定宽度和最大高度约束，
/// 内容超出时自动滚动，确保弹窗尺寸一致不随内容变化。
///
/// [maxContentHeight] 未指定时自动取视口高度的 65%，保证弹窗不超出屏幕。
///
/// 与 [SettingsFormDialogScaffold]（表单弹窗）对应，本组件专用于纯展示场景。
class DetailDisplayDialog extends StatelessWidget {
  const DetailDisplayDialog({
    required this.title,
    required this.child,
    this.closeLabel = '关闭',
    this.width = 640,
    this.maxContentHeight,
    super.key,
  });

  /// 弹窗标题，通常为 [Text] widget。
  final Widget title;

  /// 弹窗内容，会被包裹在可滚动区域中。支持任意 widget 子树。
  final Widget child;

  /// 关闭按钮文案。
  final String closeLabel;

  /// 弹窗内容区宽度。
  final double width;

  /// 内容区最大高度，为 null 时自动取视口高度的 65%。
  final double? maxContentHeight;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveMaxHeight = maxContentHeight ?? (screenHeight * 0.65);

    return AlertDialog(
      title: title,
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
          child: SingleChildScrollView(child: child),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(closeLabel),
        ),
      ],
    );
  }
}
