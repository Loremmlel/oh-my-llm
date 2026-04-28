import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

/// 宽屏（桌面）尺寸：NavigationRail 可见。
const _wideSize = Size(1440, 900);

/// 紧凑（手机）尺寸：NavigationBar 可见。
const _compactSize = Size(600, 900);

/// 把 [AppShellScaffold] 包裹在 GoRouter 中，以便导航断言可正常工作。
Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDestination destination,
  required Size size,
  Widget? endDrawer,
  List<Widget> actions = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: destination.path,
    routes: [
      for (final dest in AppDestination.values)
        GoRoute(
          path: dest.path,
          builder: (context, state) => AppShellScaffold(
            currentDestination: dest,
            title: dest.label,
            body: Text('${dest.label}页面'),
            endDrawer: endDrawer,
            actions: actions,
          ),
        ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ── AppDestination ─────────────────────────────────────────────────────────

  group('AppDestination', () {
    test('包含四个入口：chat / history / favorites / settings', () {
      expect(AppDestination.values.length, 4);
      expect(
        AppDestination.values.map((d) => d.name),
        containsAll(['chat', 'history', 'favorites', 'settings']),
      );
    });

    test('各入口路径正确', () {
      expect(AppDestination.chat.path, '/chat');
      expect(AppDestination.history.path, '/history');
      expect(AppDestination.favorites.path, '/favorites');
      expect(AppDestination.settings.path, '/settings');
    });
  });

  // ── AppShellScaffold 布局自适应 ────────────────────────────────────────────

  group('AppShellScaffold 宽屏布局', () {
    testWidgets('宽屏时显示 NavigationRail，不显示 NavigationBar', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _wideSize,
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('宽屏时 NavigationRail 包含所有目标标签', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _wideSize,
      );

      for (final dest in AppDestination.values) {
        expect(find.text(dest.label), findsWidgets);
      }
    });

    testWidgets('宽屏时不显示抽屉按钮', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _wideSize,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      expect(find.byTooltip('打开侧边内容'), findsNothing);
    });

    testWidgets('宽屏时点击 NavigationRail 切换到历史对话页', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _wideSize,
      );

      // 历史对话标签在 NavigationRail 中
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(AppDestination.history.label),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('历史对话页面'), findsOneWidget);
    });
  });

  group('AppShellScaffold 紧凑布局', () {
    testWidgets('紧凑时显示 NavigationBar，不显示 NavigationRail', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _compactSize,
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('紧凑时有 endDrawer 则显示抽屉按钮', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _compactSize,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      expect(find.byTooltip('打开侧边内容'), findsOneWidget);
    });

    testWidgets('紧凑时没有 endDrawer 则不显示抽屉按钮', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _compactSize,
      );

      expect(find.byTooltip('打开侧边内容'), findsNothing);
    });

    testWidgets('紧凑时点击 NavigationBar 切换到收藏页', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _compactSize,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(AppDestination.favorites.label),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收藏页面'), findsOneWidget);
    });

    testWidgets('重复点击当前入口不跳转', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: _compactSize,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(AppDestination.chat.label),
        ),
      );
      await tester.pumpAndSettle();

      // 仍在聊天页
      expect(find.text('对话页面'), findsOneWidget);
    });
  });

  // ── AppBreakpoints ─────────────────────────────────────────────────────────

  group('AppBreakpoints', () {
    test('compact 断点为 720', () {
      expect(AppBreakpoints.compact, 720);
    });

    testWidgets('精确在断点宽度时为宽屏布局', (tester) async {
      // 720px 是 compact 阈值，< 720 才是紧凑布局
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: const Size(720, 900),
      );
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('断点以下一像素为紧凑布局', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: const Size(719, 900),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
