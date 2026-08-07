import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';

import '../../helpers/responsive_viewport_cases.dart';

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

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // 初次挂载只 pump；真实导航/抽屉动画之后再 settle。
  await tester.pump();
}

void main() {
  for (final viewport in requiredShellViewports) {
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
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('${target.label}页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in requiredShellViewports.where(
    (v) => v.shellMode == ShellNavigationMode.bottomBar,
  )) {
    testWidgets('${viewport.name}: 抽屉可打开且内容可达', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      await tester.tap(find.byTooltip('打开侧边内容'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('侧边内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
