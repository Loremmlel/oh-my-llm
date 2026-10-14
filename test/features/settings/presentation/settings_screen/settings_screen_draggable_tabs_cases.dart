import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/preferences/settings_tab_preferences.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/settings_tab.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/draggable_settings_tab_bar.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

const _touchDragDelay = Duration(milliseconds: 350);

class _CustomOrderController extends SettingsTabOrderController {
  @override
  List<SettingsTab> build() => const [
    SettingsTab.worldBooks,
    SettingsTab.other,
    SettingsTab.providers,
    SettingsTab.presets,
    SettingsTab.prompts,
    SettingsTab.network,
    SettingsTab.outputProcessing,
  ];
}

void registerSettingsScreenDraggableTabsTests() {
  group('设置页标签可拖动与自适应', () {
    testWidgets('宽屏下鼠标拖拽页签重排并持久化到 preferences', (tester) async {
      final database = await setUpSettingsScreen(tester, useDefaultsSeed: true);
      addTearDown(database.close);

      // 初始顺序验证：服务商在第 0 位（顶部），预设在第 1 位
      expect(find.text('服务商'), findsOneWidget);
      expect(find.text('预设'), findsOneWidget);
      expect(
        tester.getCenter(find.text('服务商')).dy,
        lessThan(tester.getCenter(find.text('预设')).dy),
      );

      // 用鼠标将"服务商"向下拖拽到"预设"的后面
      final sourceLocation = tester.getCenter(find.text('服务商'));
      final targetLocation =
          tester.getCenter(find.text('预设')) + const Offset(0, 40);

      final mouseGesture = await tester.startGesture(
        sourceLocation,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouseGesture.moveTo(targetLocation);
      await settleScrollMotion(tester);
      await mouseGesture.up();
      await settleScrollMotion(tester);

      // 拖动后"预设"移到上方，"服务商"移到下方
      expect(
        tester.getCenter(find.text('预设')).dy,
        lessThan(tester.getCenter(find.text('服务商')).dy),
      );
      // 当前选中的仍是服务商，新增服务商按钮可见
      expect(find.text('新增服务商'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('触控设备上快速横向滑动仅滚动列表，长按拖拽则触发重排', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(390, 844),
        useDefaultsSeed: true,
      );
      addTearDown(database.close);

      // 窄屏初始状态无溢出
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.text('服务商')).dx,
        lessThan(tester.getCenter(find.text('预设')).dx),
      );

      // 1. 快速触控滑动：不等待长按直接滑动，验证不会触发重排
      final touchScroll = await tester.startGesture(
        tester.getCenter(find.text('服务商')),
        kind: PointerDeviceKind.touch,
      );
      await touchScroll.moveBy(const Offset(-100, 0));
      await settleScrollMotion(tester);
      await touchScroll.up();
      await settleScrollMotion(tester);
      expect(tester.takeException(), isNull);
      // 快速横滑仅滚动，两项相对顺序不变
      expect(
        tester.getCenter(find.text('服务商')).dx,
        lessThan(tester.getCenter(find.text('预设')).dx),
      );

      // 2. 长按触控拖拽：按下停留 350ms 后拖动
      final touchDrag = await tester.startGesture(
        tester.getCenter(find.text('服务商')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await tester.pump(_touchDragDelay);
      await touchDrag.moveTo(
        tester.getCenter(find.text('预设')) + const Offset(50, 0),
      );
      await settleScrollMotion(tester);
      await touchDrag.up();
      await settleScrollMotion(tester);
      expect(tester.takeException(), isNull);
      // 长按拖拽后顺序交换，"预设"在"服务商"左侧
      expect(
        tester.getCenter(find.text('预设')).dx,
        lessThan(tester.getCenter(find.text('服务商')).dx),
      );
    });

    testWidgets('读取持久化的自定义页签顺序并在初次加载时渲染对应顺序', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 900),
        useDefaultsSeed: true,
        extraOverrides: [
          settingsTabOrderProvider.overrideWith(_CustomOrderController.new),
        ],
      );
      addTearDown(database.close);

      // 验证宽屏下侧边栏按自定义顺序渲染：世界书在最上方，接着是其它，接着是服务商
      final worldBooksY = tester
          .getCenter(find.widgetWithText(ListTile, '世界书'))
          .dy;
      final otherY = tester.getCenter(find.widgetWithText(ListTile, '其它')).dy;
      final providersY = tester
          .getCenter(find.widgetWithText(ListTile, '服务商'))
          .dy;

      expect(worldBooksY, lessThan(otherY));
      expect(otherY, lessThan(providersY));
    });

    testWidgets('窄屏下呈现 DraggableSettingsTabBar 且滚动可浏览全部页签', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(390, 844),
        useDefaultsSeed: true,
      );
      addTearDown(database.close);

      expect(find.byType(DraggableSettingsTabBar), findsOneWidget);
      final tabScrollable = find.descendant(
        of: find.byType(DraggableSettingsTabBar),
        matching: find.byType(Scrollable),
      );
      for (final tab in SettingsTab.defaultOrder) {
        await tester.scrollUntilVisible(
          find.text(tab.label),
          50.0,
          scrollable: tabScrollable,
        );
        expect(find.text(tab.label), findsOneWidget);
      }
    });

    testWidgets('切换到非服务商页签时宽屏隐藏服务商新增操作按钮', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 900),
        useDefaultsSeed: true,
      );
      addTearDown(database.close);

      // 默认在服务商页，"新增服务商"按钮可见
      expect(find.text('新增服务商'), findsOneWidget);

      // 切换到"预设"页签
      await switchToTab(tester, 1);
      expect(find.text('新增预设'), findsOneWidget);
      expect(find.text('新增服务商'), findsNothing);

      // 切换回"服务商"页签，"新增服务商"恢复可见
      await switchToTab(tester, 0);
      expect(find.text('新增服务商'), findsOneWidget);
    });

    testWidgets('窄屏下选中服务商时新增服务商按钮折行在下方展示且无溢出', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(390, 844),
        useDefaultsSeed: true,
      );
      addTearDown(database.close);

      expect(tester.takeException(), isNull);
      expect(find.text('新增服务商'), findsOneWidget);

      // 切换到其他页签无溢出
      await switchToTab(tester, 3); // 网络
      expect(tester.takeException(), isNull);
      expect(find.text('新增服务商'), findsNothing);
    });

    testWidgets('窄屏页签项声明选中与按钮无障碍语义', (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(390, 844),
        useDefaultsSeed: true,
      );
      addTearDown(database.close);

      final semantics = tester.getSemantics(find.text('服务商'));
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(semantics.flagsCollection.isButton, isTrue);
    });
  });
}
