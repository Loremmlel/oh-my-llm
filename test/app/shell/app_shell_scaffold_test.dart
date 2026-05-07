import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';

const _wideSize = Size(1440, 900);
const _compactSize = Size(600, 900);

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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide layout can navigate with rail destinations', (
    tester,
  ) async {
    await _pumpShell(tester, destination: AppDestination.chat, size: _wideSize);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(AppDestination.history.label),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史对话页面'), findsOneWidget);
  });

  testWidgets('compact layout can navigate with bottom destinations', (
    tester,
  ) async {
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

  testWidgets('compact layout exposes drawer action when endDrawer exists', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      destination: AppDestination.chat,
      size: _compactSize,
      endDrawer: const Drawer(child: Text('侧边内容')),
    );

    expect(find.byTooltip('打开侧边内容'), findsOneWidget);
  });
}
