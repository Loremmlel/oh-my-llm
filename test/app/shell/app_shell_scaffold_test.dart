import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/widgets/app_adaptive_actions.dart';

import '../../helpers/responsive_viewport_cases.dart';
import '../../helpers/async/widget_test_animation.dart';

/// 各顶层目的地页面的可见正文：对话页用「聊天页面」与 label「对话」区分，
/// 其余沿用既有约定的「{label}页面」。
String _shellBodyText(AppDestination dest) =>
    dest == AppDestination.chat ? '聊天页面' : '${dest.label}页面';

/// 构造承载全部顶层目的地的 GoRouter，供顶层 Back 行为与导航用例复用。
GoRouter _shellRouter({
  required String initialLocation,
  Widget? endDrawer,
  List<Widget> actions = const [],
  AppAdaptiveActions? adaptiveActions,
  bool hasLocalBackTarget = false,
  VoidCallback? onLocalBack,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      for (final dest in AppDestination.values)
        GoRoute(
          path: dest.path,
          builder: (context, state) => AppShellScaffold(
            currentDestination: dest,
            title: dest.label,
            body: Text(_shellBodyText(dest)),
            endDrawer: endDrawer,
            actions: actions,
            adaptiveActions: adaptiveActions,
            hasLocalBackTarget: hasLocalBackTarget,
            onLocalBack: onLocalBack,
          ),
        ),
    ],
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDestination destination,
  required Size size,
  Widget? endDrawer,
  List<Widget> actions = const [],
  AppAdaptiveActions? adaptiveActions,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = _shellRouter(
    initialLocation: destination.path,
    endDrawer: endDrawer,
    actions: actions,
    adaptiveActions: adaptiveActions,
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // 初次挂载只 pump；真实导航/抽屉动画之后再 settle。
  await tester.pump();
}

void main() {
  const navigationViewports = [phonePortrait, wideDesktop];
  const drawerViewports = [phonePortrait];

  for (final viewport in navigationViewports) {
    testWidgets('${viewport.name}: 目的地导航可达', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
      );
      expect(tester.takeException(), isNull);

      const target = AppDestination.history;
      final navLabel = find.text(target.label);
      if (viewport.shellMode == ShellNavigationMode.bottomBar) {
        await tester.tap(
          find.descendant(of: find.byType(NavigationBar), matching: navLabel),
        );
      } else {
        await tester.tap(
          find.descendant(of: find.byType(NavigationRail), matching: navLabel),
        );
      }
      await settleRouteTransition(tester);

      expect(find.text('${target.label}页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in drawerViewports) {
    testWidgets('${viewport.name}: 抽屉可打开、内容可达，系统返回仅关闭抽屉', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      await tester.tap(find.byTooltip('打开侧边内容'));
      await settleOverlayTransition(tester);

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isEndDrawerOpen, isTrue);
      expect(find.text('侧边内容'), findsOneWidget);

      // 抽屉打开时会向路由注册 LocalHistoryEntry，系统返回只弹出它关闭
      // 抽屉，不会退出对话页。
      await tester.binding.handlePopRoute();
      await settleOverlayTransition(tester);

      expect(scaffold.isEndDrawerOpen, isFalse);
      expect(find.text('聊天页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${viewport.name}: 右边缘拖拽不打开抽屉', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isEndDrawerOpen, isFalse);

      // 右缘要保留给 Android 边缘返回手势，抽屉边缘拖拽不得抢占。
      await tester.dragFrom(
        Offset(viewport.size.width - 1, viewport.size.height / 2),
        const Offset(-240, 0),
      );
      await settleOverlayTransition(tester);

      expect(scaffold.isEndDrawerOpen, isFalse);
      expect(find.text('侧边内容'), findsNothing);
    });
  }

  testWidgets('系统返回将非对话顶层目的地退回对话', (tester) async {
    final router = _shellRouter(initialLocation: AppDestination.settings.path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('设置页面'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);

    expect(router.routeInformationProvider.value.uri.path, '/chat');
    expect(find.text('聊天页面'), findsOneWidget);
  });

  testWidgets('系统返回将历史顶层目的地退回对话', (tester) async {
    final router = _shellRouter(initialLocation: AppDestination.history.path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('${AppDestination.history.label}页面'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);

    expect(router.routeInformationProvider.value.uri.path, '/chat');
    expect(find.text('聊天页面'), findsOneWidget);
  });

  testWidgets('对话根无本地返回目标时系统返回不改写路由', (tester) async {
    final router = _shellRouter(initialLocation: AppDestination.chat.path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('聊天页面'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);

    // chat 根没有 local target 时交系统退出，AppShell 不得改写为其他路由。
    expect(router.routeInformationProvider.value.uri.path, '/chat');
    expect(find.text('聊天页面'), findsOneWidget);
  });

  testWidgets('有本地返回目标时系统返回只调用一次本地回调', (tester) async {
    var onLocalBackCalls = 0;
    final router = _shellRouter(
      initialLocation: AppDestination.chat.path,
      hasLocalBackTarget: true,
      onLocalBack: () {
        onLocalBackCalls += 1;
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('聊天页面'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);

    // 本地返回目标优先：只调用一次 onLocalBack，路由不被改写。
    expect(onLocalBackCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/chat');
    expect(find.text('聊天页面'), findsOneWidget);
  });

  testWidgets('壳层保留固定动作，并按 720 断点选择响应式动作', (tester) async {
    const adaptive = AppAdaptiveActions(
      compactActions: [Text('紧凑动作')],
      wideActions: [Text('宽侧动作')],
    );
    await _pumpShell(
      tester,
      destination: AppDestination.chat,
      size: shellBelowBoundary.size,
      actions: const [Text('固定动作')],
      adaptiveActions: adaptive,
    );
    expect(find.text('固定动作'), findsOneWidget);
    expect(find.text('紧凑动作'), findsOneWidget);
    expect(find.text('宽侧动作'), findsNothing);
  });

  testWidgets('壳层在 720 等号走宽侧，固定动作仍保留', (tester) async {
    const adaptive = AppAdaptiveActions(
      compactActions: [Text('紧凑动作')],
      wideActions: [Text('宽侧动作')],
    );
    await _pumpShell(
      tester,
      destination: AppDestination.chat,
      size: shellAtBoundary.size,
      actions: const [Text('固定动作')],
      adaptiveActions: adaptive,
    );
    expect(find.text('固定动作'), findsOneWidget);
    expect(find.text('宽侧动作'), findsOneWidget);
    expect(find.text('紧凑动作'), findsNothing);
  });
}
