import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/media_grid_density_actions.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import '../../../../helpers/test_harness.dart';

/// 创建内存 SharedPreferences，可按需种子初始值。
Future<SharedPreferences> _prefs({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

/// 把单个 actions 挂到 AppBar 上，返回所在 ProviderScope 的容器供断言 provider。
Future<ProviderContainer> _pumpActions(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required Widget actions,
}) async {
  await pumpTestApp(
    tester,
    preferences: preferences,
    child: Scaffold(
      appBar: AppBar(actions: [actions]),
      body: const SizedBox.shrink(),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

void main() {
  testWidgets('expanded 显示三个密度按钮，当前密度按钮带 selected 语义', (tester) async {
    final preferences = await _prefs();
    await _pumpActions(
      tester,
      preferences: preferences,
      actions: const MediaGridDensityActions.expanded(),
    );

    expect(find.byTooltip('紧凑密度'), findsOneWidget);
    expect(find.byTooltip('标准密度'), findsOneWidget);
    expect(find.byTooltip('舒适密度'), findsOneWidget);
    // 默认密度为标准：标准按钮的语义节点带 selected，其余未选中。
    expect(
      tester.getSemantics(find.byTooltip('标准密度')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(find.byTooltip('紧凑密度')).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(
      tester.getSemantics(find.byTooltip('舒适密度')).flagsCollection.isSelected,
      Tristate.isFalse,
    );
  });

  testWidgets('点击舒适密度更新 provider 并持久化', (tester) async {
    final preferences = await _prefs();
    final container = await _pumpActions(
      tester,
      preferences: preferences,
      actions: const MediaGridDensityActions.expanded(),
    );

    await tester.tap(find.byTooltip('舒适密度'));
    await tester.pump();

    expect(
      container.read(mediaGridDensityProvider),
      AppLayoutDensity.comfortable,
    );
    expect(preferences.getString(mediaGridDensityStorageKey), 'comfortable');
  });

  testWidgets('menu 显示密度菜单，选择标准更新 provider 并持久化', (tester) async {
    // 初始舒适，选择「标准」后应回退并持久化 standard。
    final preferences = await _prefs(
      seed: {mediaGridDensityStorageKey: 'comfortable'},
    );
    final container = await _pumpActions(
      tester,
      preferences: preferences,
      actions: const MediaGridDensityActions.menu(),
    );

    // 窄布局形态只暴露「显示密度」菜单，不渲染三个展开 tooltip。
    expect(find.byTooltip('显示密度'), findsOneWidget);
    expect(find.byTooltip('紧凑密度'), findsNothing);

    await tester.tap(find.byTooltip('显示密度'));
    await settleOverlayTransition(tester);

    // 三个密度项按 values 顺序：紧凑/标准/舒适；文本标签被 IgnorePointer
    // 包裹，点整个菜单项（InkWell 区域）才能稳定命中。
    expect(
      find.byType(CheckedPopupMenuItem<AppLayoutDensity>),
      findsNWidgets(3),
    );
    expect(find.text('标准'), findsOneWidget);

    await tester.tap(find.byType(CheckedPopupMenuItem<AppLayoutDensity>).at(1));
    await settleOverlayTransition(tester);

    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.standard);
    expect(preferences.getString(mediaGridDensityStorageKey), 'standard');
  });

  testWidgets('Tab 聚焦展开按钮后 Enter 触发密度切换（键盘等价操作）', (tester) async {
    final preferences = await _prefs();
    final container = await _pumpActions(
      tester,
      preferences: preferences,
      actions: const MediaGridDensityActions.expanded(),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // 第一个可聚焦节点是「紧凑密度」按钮，且只聚焦一个节点。
    expect(
      find.semantics.byFlag(SemanticsFlag.isFocused),
      isSemantics(isButton: true),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // Enter 激活聚焦按钮：紧凑密度生效并持久化。
    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.compact);
    expect(preferences.getString(mediaGridDensityStorageKey), 'compact');
  });
}
