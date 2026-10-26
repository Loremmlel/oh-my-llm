import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/features/settings/application/worldbooks/world_books_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/worldbooks/world_book.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/worldbooks/world_book_editor.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

void main() {
  testWidgets('世界书从独立页签创建、排序停用并持久保存，删除明确确认', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.tab.last_index': 6});
    final preferences = await SharedPreferences.getInstance();
    final router = createAppRouter(
      initialLocation: '/settings',
      videoPlayerBindingsFactory: () => throw StateError('本测试不打开视频'),
    );
    addTearDown(router.dispose);
    await pumpTestApp(tester, preferences: preferences, router: router);
    await tester.tap(find.text('新增世界书'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextField, '世界书名称'), '群岛');
    await tester.tap(find.text('新增条目'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(AppTextField, '标题'), '世界');
    await tester.enterText(
      find.widgetWithText(AppTextField, '正文'),
      '城市之间由帆船联系。',
    );
    await tester.tap(find.text('新增条目'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(AppTextField, '标题'), '人物');
    await tester.enterText(find.widgetWithText(AppTextField, '正文'), '人物设定');
    await tester.tap(find.text('启用条目'));
    await tester.tap(find.byTooltip('上移'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('2 个条目 · 1 个启用'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('新增世界书')),
    );
    final book = container.read(worldBooksProvider).single;
    expect(book.entries.map((entry) => entry.title), ['人物', '世界']);
    expect(book.entries.first.enabled, isFalse);
    await tester.tap(find.byTooltip('编辑 群岛'));
    await tester.pumpAndSettle();
    expect(find.text('人物设定'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('世界书操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除 群岛'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已有聊天记录保留'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(container.read(worldBooksProvider), isEmpty);
    expect(find.textContaining('还没有世界书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏编辑失败保留正文，取消返回保护未保存修改', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('编辑'),
            ),
          ),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, _) => WorldBookEditor(
            initialValue: TestFixtures.worldBook(
              entries: const [
                WorldBookEntry(id: 'entry', title: '规则', content: '原文'),
              ],
            ),
            onSubmit: (_) async => throw StateError('保存失败测试'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpTestApp(
      tester,
      router: router,
      preferences: await SharedPreferences.getInstance(),
      viewportSize: const Size(390, 760),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextField, '正文'), '修改正文');
    final editableFinder = find.descendant(
      of: find.widgetWithText(AppTextField, '正文'),
      matching: find.byType(EditableText),
    );
    final originalState = tester.state<EditableTextState>(editableFinder);
    final originalSize = tester.getSize(editableFinder);
    const selectedValue = TextEditingValue(
      text: '修改正文',
      selection: TextSelection(baseOffset: 1, extentOffset: 3),
    );
    tester.testTextInput.updateEditingValue(selectedValue);
    for (final bottom in [360.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.state<EditableTextState>(editableFinder),
        same(originalState),
      );
      expect(originalState.widget.focusNode.hasFocus, isTrue);
      expect(originalState.widget.controller.value, selectedValue);
      expect(tester.getSize(editableFinder), originalSize);
      await tester.ensureVisible(editableFinder);
      expect(editableFinder.hitTestable(), findsOneWidget);
    }
    tester.view.resetViewInsets();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('保存失败测试'), findsOneWidget);
    expect(find.text('修改正文'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(find.text('修改正文'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
