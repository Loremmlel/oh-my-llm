import 'package:flutter/material.dart';

/// 自适应主从布局：宽屏双栏，窄屏回退为调用方提供的紧凑布局。
class AdaptiveMasterDetailLayout extends StatelessWidget {
  const AdaptiveMasterDetailLayout({
    required this.master,
    required this.detail,
    this.compactChild,
    this.breakpoint = 840,
    this.masterWidth = 280,
    this.gap = 16,
    this.minHeight = 360,
    super.key,
  });

  final Widget master;
  final Widget detail;
  final Widget? compactChild;
  final double breakpoint;
  final double masterWidth;
  final double gap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return compactChild ??
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  master,
                  SizedBox(height: gap),
                  detail,
                ],
              );
        }

        return SizedBox(
          height: minHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: masterWidth, child: master),
              SizedBox(width: gap),
              Expanded(child: detail),
            ],
          ),
        );
      },
    );
  }
}
