import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenResponsiveTests() {
  testWidgets('320px 窄视口下工具栏与分页栏不产生布局溢出', (tester) async {
    await setUpHistoryScreenWithBulkConversations(
      tester,
      count: 25,
      viewportSize: const Size(320, 800),
    );

    // 搜索框收缩到可用父宽、分页栏进入紧凑模式，任何阶段都不允许溢出异常。
    expect(find.text('搜索历史对话'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('1440px 宽视口下内容合理限宽不无限拉伸', (tester) async {
    await setUpHistoryScreen(tester);

    expect(find.text('搜索历史对话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
