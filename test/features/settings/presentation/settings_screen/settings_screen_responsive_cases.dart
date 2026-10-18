import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

import 'settings_screen_test_helpers.dart';
import '../../../../helpers/async/widget_test_animation.dart';

/// 每个 tab 的关键 heading（内容区可滚动到达的文案）。
const _tabHeadingByIndex = <int, String>{
  0: '新增服务商',
  1: '预设 Prompt',
  2: '记忆总结提示词',
  3: '请求头定义',
  4: '输出正则处理',
  5: '自动重试',
};

/// 提示词 tab 除首个 section 外的补充 heading。
const _promptsTabAdditionalHeadings = ['模板提示词', '固定顺序提示词'];

void registerSettingsScreenResponsiveTests() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('$width 宽设置分类可直达提示词分组并返回总览', (tester) async {
      await setUpSettingsScreen(
        tester,
        size: Size(width, 1500),
        useDefaultsSeed: true,
      );
      await switchToTab(tester, 2);
      if (width < 1000) {
        await tester.tap(find.byTooltip('提示词分类'));
        await settleOverlayTransition(tester);
        await tester.tap(find.text('模板提示词').last);
      } else {
        await tester.tap(find.widgetWithText(ListTile, '模板提示词'));
      }
      await settleOverlayTransition(tester);
      if (width >= 1000) {
        expect(
          tester
              .getSemantics(find.widgetWithText(ListTile, '模板提示词'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      }
      expect(find.widgetWithText(SettingsSectionCard, '模板提示词'), findsOneWidget);
      expect(find.widgetWithText(SettingsSectionCard, '记忆总结提示词'), findsNothing);
      expect(find.widgetWithText(SettingsSectionCard, '固定顺序提示词'), findsNothing);
      await tester.tap(find.text('提示词'));
      await settleOverlayTransition(tester);
      expect(
        find.widgetWithText(SettingsSectionCard, '记忆总结提示词'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SettingsSectionCard, '固定顺序提示词'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
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
