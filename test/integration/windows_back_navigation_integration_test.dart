import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/platform/windows_navigation_input_adapter.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../helpers/async/widget_test_animation.dart';
import '../helpers/fixtures.dart';
import '../helpers/responsive_viewport_cases.dart';

/// 集成测试：Windows 返回输入（鼠标后退侧键 / browserBack）必须经
/// BackButtonDispatcher 进入既有返回链，不得绕过 Dialog、PopScope、
/// App Shell 本地目标或 GoRouter 子路由的优先级。
///
/// 分两层观察：
/// - 根部组合：真实 [OhMyLlmApp] 全栈，验证 Windows 挂载、Android 不挂载；
/// - 返回链：最小 GoRouter + AppShellScaffold，adapter 直接构造并绑定
///   真实 `router.backButtonDispatcher`，逐分支验证与系统返回一致的结果。

String _shellBodyText(AppDestination dest) =>
    dest == AppDestination.chat ? '聊天页面' : '${dest.label}页面';

/// 各顶层目的地页面：可命中的正文面 + 区分文本，保证 pointer 事件
/// 稳定到达根部 adapter 的 Listener。
Widget _shellBody(AppDestination dest) {
  return ColoredBox(
    color: const Color(0xFF101418),
    child: Center(child: Text(_shellBodyText(dest))),
  );
}

/// 集成树路由：与 app_shell_scaffold_test 相同的 AppShellScaffold 形态，
/// 另补一个可 push 的收藏详情子路由验证「返回只退一层」。
GoRouter _integrationRouter({
  required String initialLocation,
  Widget? endDrawer,
  bool hasLocalBackTarget = false,
  VoidCallback? onLocalBack,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      for (final dest in AppDestination.values)
        if (dest == AppDestination.favorites)
          GoRoute(
            path: dest.path,
            builder: (context, state) => AppShellScaffold(
              currentDestination: dest,
              title: dest.label,
              body: _shellBody(dest),
              endDrawer: endDrawer,
              hasLocalBackTarget: hasLocalBackTarget,
              onLocalBack: onLocalBack,
            ),
            routes: [
              GoRoute(
                path: 'items/:id',
                builder: (context, state) => Scaffold(
                  body: ColoredBox(
                    color: const Color(0xFF101418),
                    child: Center(
                      // 详情页持有焦点，browserBack 才能沿 Focus 树冒泡到
                      // 根部 adapter；真实页面的正文均含可聚焦控件。
                      child: Focus(autofocus: true, child: const Text('详情页面')),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          GoRoute(
            path: dest.path,
            builder: (context, state) => AppShellScaffold(
              currentDestination: dest,
              title: dest.label,
              body: _shellBody(dest),
              endDrawer: endDrawer,
              hasLocalBackTarget: hasLocalBackTarget,
              onLocalBack: onLocalBack,
            ),
          ),
    ],
  );
}

/// 挂载集成树：MaterialApp.router 的 builder 内包 adapter，回调只经
/// 真实 BackButtonDispatcher，与生产根部 composition 的绑定方式一致。
Future<GoRouter> _pumpIntegrationTree(
  WidgetTester tester, {
  required Size size,
  String initialLocation = '/chat',
  Widget? endDrawer,
  bool hasLocalBackTarget = false,
  VoidCallback? onLocalBack,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = _integrationRouter(
    initialLocation: initialLocation,
    endDrawer: endDrawer,
    hasLocalBackTarget: hasLocalBackTarget,
    onLocalBack: onLocalBack,
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => WindowsNavigationInputAdapter(
        // defaultValue 传 false：Router 尚未注册回调时视为未消费。
        onBackRequested: () =>
            router.backButtonDispatcher.invokeCallback(Future.value(false)),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// 全栈挂载真实 [OhMyLlmApp]；provider 组合固定 Windows 宿主，不打开真实
/// Android MethodChannel。目标平台由用例的 TargetPlatformVariant 控制。
Future<void> _pumpFullApp(WidgetTester tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);

  final preferences = await TestFixtures.seedPreferences(
    database: database,
    models: [TestFixtures.gpt41()],
    prompts: [TestFixtures.codeAssistantPrompt()],
  );

  tester.view.physicalSize = const Size(1440, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        customHeadersMapProvider.overrideWith((ref) => const {}),
        ...appCompositionOverrides(hostPlatform: TargetPlatform.windows),
      ],
      child: const OhMyLlmApp(),
    ),
  );
  await tester.pump();
}

/// 以 Windows 键盘映射发送 browserBack 首次按下。
Future<void> _pressBrowserBack(WidgetTester tester) {
  return tester.sendKeyDownEvent(
    LogicalKeyboardKey.browserBack,
    platform: 'windows',
  );
}

void main() {
  group('根部组合（真实 OhMyLlmApp）', () {
    testWidgets(
      'Windows 宿主鼠标后退侧键把设置页退回对话',
      (tester) async {
        await _pumpFullApp(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('设置'),
          ),
        );
        await settleRouteTransition(tester);
        expect(find.text('服务商设置'), findsOneWidget);

        await tester.tapAt(
          tester.getCenter(find.byType(SettingsScreen)),
          buttons: kBackMouseButton,
        );
        await settleRouteTransition(tester);

        expect(find.text('服务商设置'), findsNothing);
        expect(find.text('历史会话面板'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Android 宿主鼠标后退侧键不触发返回',
      (tester) async {
        await _pumpFullApp(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('设置'),
          ),
        );
        await settleRouteTransition(tester);
        expect(find.text('服务商设置'), findsOneWidget);

        await tester.tapAt(
          tester.getCenter(find.byType(SettingsScreen)),
          buttons: kBackMouseButton,
        );
        await settleRouteTransition(tester);

        // Android 不挂载 Windows adapter：侧键输入不产生任何导航。
        expect(find.text('服务商设置'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('真实返回链（BackButtonDispatcher）', () {
    testWidgets('鼠标后退侧键只关闭普通 Dialog', (tester) async {
      final router = await _pumpIntegrationTree(
        tester,
        size: wideDesktop.size,
        initialLocation: AppDestination.settings.path,
      );

      // showDialog 的 Future 完成于对话框关闭，不能在此 await（会挂起）。
      final dialogClosed = showDialog<void>(
        context: tester.element(find.text('设置页面')),
        builder: (context) => const AlertDialog(title: Text('对话框标题')),
      );
      await settleOverlayTransition(tester);
      expect(find.text('对话框标题'), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.text('对话框标题')),
        buttons: kBackMouseButton,
      );
      await settleOverlayTransition(tester);
      await dialogClosed;

      expect(find.text('对话框标题'), findsNothing);
      expect(find.text('设置页面'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.settings.path,
      );
    });

    testWidgets('browserBack 被 busy PopScope 拦截时不退底层页面', (tester) async {
      final router = await _pumpIntegrationTree(
        tester,
        size: wideDesktop.size,
        initialLocation: AppDestination.settings.path,
      );

      // busy 对话框不会被关闭，其 Future 保持 pending，不得 await。
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('设置页面')),
          builder: (context) => PopScope(
            canPop: false,
            child: Focus(
              autofocus: true,
              child: const AlertDialog(title: Text('忙等对话框')),
            ),
          ),
        ),
      );
      await settleOverlayTransition(tester);
      expect(find.text('忙等对话框'), findsOneWidget);

      await _pressBrowserBack(tester);
      await settleOverlayTransition(tester);

      expect(find.text('忙等对话框'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.settings.path,
      );
    });

    testWidgets('鼠标后退侧键只关闭 Drawer', (tester) async {
      final router = await _pumpIntegrationTree(
        tester,
        size: phonePortrait.size,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      await tester.tap(find.byTooltip('打开侧边内容'));
      await settleOverlayTransition(tester);
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isEndDrawerOpen, isTrue);

      await tester.tapAt(
        tester.getCenter(find.text('侧边内容')),
        buttons: kBackMouseButton,
      );
      await settleOverlayTransition(tester);

      expect(scaffold.isEndDrawerOpen, isFalse);
      expect(find.text('聊天页面'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.chat.path,
      );
    });

    testWidgets('鼠标后退侧键只清理 App Shell 本地返回目标', (tester) async {
      var localBackCalls = 0;
      final router = await _pumpIntegrationTree(
        tester,
        size: wideDesktop.size,
        hasLocalBackTarget: true,
        onLocalBack: () => localBackCalls += 1,
      );

      await tester.tapAt(
        tester.getCenter(find.text('聊天页面')),
        buttons: kBackMouseButton,
      );
      await settleRouteTransition(tester);

      expect(localBackCalls, 1);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.chat.path,
      );
      expect(find.text('聊天页面'), findsOneWidget);
    });

    testWidgets('browserBack 对 pushed 子路由只退一层', (tester) async {
      final router = await _pumpIntegrationTree(
        tester,
        size: wideDesktop.size,
        initialLocation: AppDestination.favorites.path,
      );

      router.push('/favorites/items/1');
      await settleRouteTransition(tester);
      expect(find.text('详情页面'), findsOneWidget);

      await _pressBrowserBack(tester);
      await settleRouteTransition(tester);

      expect(find.text('详情页面'), findsNothing);
      expect(find.text('收藏页面'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.favorites.path,
      );
    });

    testWidgets('鼠标后退侧键把非对话顶层退回对话', (tester) async {
      final router = await _pumpIntegrationTree(
        tester,
        size: wideDesktop.size,
        initialLocation: AppDestination.settings.path,
      );

      await tester.tapAt(
        tester.getCenter(find.text('设置页面')),
        buttons: kBackMouseButton,
      );
      await settleRouteTransition(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.chat.path,
      );
      expect(find.text('聊天页面'), findsOneWidget);
    });

    testWidgets('对话根的鼠标后退侧键不改写路由、不退出', (tester) async {
      final router = await _pumpIntegrationTree(tester, size: wideDesktop.size);

      await tester.tapAt(
        tester.getCenter(find.text('聊天页面')),
        buttons: kBackMouseButton,
      );
      await settleRouteTransition(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        AppDestination.chat.path,
      );
      expect(find.text('聊天页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
