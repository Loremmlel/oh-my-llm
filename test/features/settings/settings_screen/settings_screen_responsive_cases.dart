import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

/// 每个 tab 的关键 heading（内容区可滚动到达的文案）。
const _tabHeadingByIndex = <int, String>{
  0: '服务商设置',
  1: '预设 Prompt',
  2: '记忆总结提示词',
  3: '请求头定义',
  4: '输出正则处理',
  5: '自动重试',
};

/// 提示词 tab 除首个 section 外的补充 heading。
const _promptsTabAdditionalHeadings = ['模板提示词', '固定顺序提示词'];

void registerSettingsScreenResponsiveTests() {
  testWidgets('390px: 六 tab 关键 heading 可达', (tester) async {
    // 1500 高度视口下各 tab 内容区的关键 heading 均在首屏直接可见，
    // 无需滚动；若内容超高产生 overflow，takeException 会直接失败。
    await setUpSettingsScreen(
      tester,
      size: const Size(390, 1500),
      useDefaultsSeed: true,
    );
    expect(tester.takeException(), isNull);

    for (var i = 0; i < tabLabels.length; i++) {
      await switchToTab(tester, i);
      final heading = _tabHeadingByIndex[i]!;
      expect(find.text(heading), findsWidgets);
      if (i == 2) {
        for (final additional in _promptsTabAdditionalHeadings) {
          expect(find.text(additional), findsWidgets);
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('390px: 新增服务商表单内容可达', (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(390, 1500),
      useDefaultsSeed: true,
    );

    await tester.tap(find.text('新增服务商'));
    await settleOverlayTransition(tester);

    expect(find.text('服务商名称'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 填入名称后取消关闭对话框，证明表单可交互且可达可退出；
    // 业务校验树由既有模型表单测试覆盖，此处不重复。
    await tester.enterText(providerNameField(), '测试服务商');
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('600px: 新增预设 Prompt compact 表单内容可达', (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(600, 1500),
      useDefaultsSeed: true,
    );
    await switchToTab(tester, 1);

    await tester.tap(find.text('新增预设'));
    await settleOverlayTransition(tester);

    expect(find.text('预设 Prompt 名称'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1024px: 服务商页 smoke', (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(1024, 900),
      useDefaultsSeed: true,
    );

    expect(find.text('服务商设置'), findsOneWidget);
    expect(find.text('新增服务商'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
