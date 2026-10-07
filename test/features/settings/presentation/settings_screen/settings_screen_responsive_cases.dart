import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('窄屏恢复保存的标签，切换全部设置分组无溢出', (tester) async {
    // 1500 高度视口下各 tab 内容区的关键 heading 均在首屏直接可见，
    // 无需滚动；若内容超高产生 overflow，takeException 会直接失败。
    await setUpSettingsScreen(
      tester,
      size: const Size(390, 1500),
      initialTabIndex: 2,
      useDefaultsSeed: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('记忆总结提示词'), findsOneWidget);
    expect(find.text('模板提示词'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);

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
}
