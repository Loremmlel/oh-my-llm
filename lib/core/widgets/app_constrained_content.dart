import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 内容限宽容器：把业务内容限制在可读宽度内，并支持横向 padding 与对齐。
class AppConstrainedContent extends StatelessWidget {
  const AppConstrainedContent({
    required this.child,
    this.maxWidth = AppContentWidths.readable,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
