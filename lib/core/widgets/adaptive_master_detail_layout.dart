import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

/// 自适应主从布局：宽屏双栏，窄屏回退为调用方提供的紧凑布局。
///
/// 布局读取父组件分配到的约束宽度：`width < breakpoint` 走紧凑分支，
/// `width >= breakpoint`（等号属宽侧）走 master/detail 双栏。
class AdaptiveMasterDetailLayout extends StatelessWidget {
  const AdaptiveMasterDetailLayout({
    required this.master,
    required this.detail,
    this.compactChild,
    this.breakpoint = AppBreakpoints.contentMasterDetail,
    this.masterWidth = 280,
    this.gap = 16,
    this.minHeight = 360,
    super.key,
  });

  final Widget master;
  final Widget detail;
  final Widget? compactChild;

  /// 主从双栏切换阈值；等号属宽侧（`width >= breakpoint` 进入双栏）。
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
