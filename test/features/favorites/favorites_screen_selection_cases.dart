import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 打开系统未分类收藏夹的分页列表页。
Future<AppDatabase> _openSystemCollection(
  WidgetTester tester, {
  required int itemCount,
  void Function(AppDatabase database)? extraSeed,
}) {
  return setUpFavoritesScreen(
    tester,
    seed: (db) {
      seedFavoriteItems(
        db,
        collectionId: '__uncategorized_favorites__',
        count: itemCount,
      );
      extraSeed?.call(db);
    },
    initialLocation:
        '/favorites/collections/__uncategorized_favorites__?pageSize=10',
  );
}

/// 按住修饰键点击指定文本的条目行。
Future<void> _tapWithModifier(
  WidgetTester tester,
  String rowText, {
  required LogicalKeyboardKey modifier,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.tap(find.text(rowText));
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// 通过第一行的溢出菜单执行菜单项。
Future<void> _openRowMenu(WidgetTester tester, String actionLabel) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await settleOverlayTransition(tester);
  await tester.tap(find.text(actionLabel));
  await settleOverlayTransition(tester);
}

void registerFavoritesScreenSelectionTests() {
  testWidgets('Ctrl 加点击切换单项选择并在工具栏计数', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );

    expect(find.text('已选择 1 项'), findsOneWidget);

    // 再次 Ctrl+点击同一行取消选择，退出选择模式。
    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );

    expect(find.text('已选择 1 项'), findsNothing);
  });

  testWidgets('Shift 区间选择选中闭区间全部条目', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    // 先 Ctrl+点击建立锚点，再 Shift+点击区间终点。
    await _tapWithModifier(
      tester,
      '问题004',
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await _tapWithModifier(
      tester,
      '问题002',
      modifier: LogicalKeyboardKey.shiftLeft,
    );

    expect(find.text('已选择 3 项'), findsOneWidget);
  });

  testWidgets('Ctrl+A 只选择当前页且翻页后清空选择', (tester) async {
    await _openSystemCollection(tester, itemCount: 15);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('已选择 10 项'), findsOneWidget);

    // 翻页改变数据窗口：选择与锚点必须清空。
    await tester.tap(find.byTooltip('下一页'));
    await settleRouteTransition(tester);

    expect(find.text('已选择 10 项'), findsNothing);
    expect(find.text('已选择 1 项'), findsNothing);
  });

  testWidgets('Esc 键退出选择模式且保留选中数据', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('已选择 1 项'), findsNothing);
    // 条目仍在列表中，退出选择不删除数据。
    expect(find.text('问题005'), findsOneWidget);
  });

  // 与上一用例构成差异契约：generic Back（Android 系统返回 / Windows 侧键
  // 经 dispatcher 进入的同一条链）走 App Shell 本地返回目标，同样先清
  // 选择态且留在收藏夹内容页，而不是把 Back 当成退出页面。
  testWidgets('系统返回先清除收藏选择态且留在收藏夹页', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(find.text('已选择 1 项'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('已选择 1 项'), findsNothing);
    expect(find.text('问题005'), findsOneWidget);
    expect(find.textContaining('共 5 条 · 1/1 页'), findsOneWidget);
  });

  testWidgets('Delete 键对选中项发起删除确认且取消不生效', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settleOverlayTransition(tester);

    expect(find.textContaining('将删除 1 个收藏'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    expect(find.text('问题005'), findsOneWidget);
  });

  testWidgets('长按进入选择模式且选择态点击切换勾选', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await tester.longPress(find.text('问题005'));
    await tester.pump();

    expect(find.text('已选择 1 项'), findsOneWidget);

    // 选择态下普通点击切换另一行勾选，而不是打开详情。
    await tester.tap(find.text('问题003'));
    await tester.pump();

    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.text('收藏详情'), findsNothing);
  });

  testWidgets('工具栏移动把选中项移入目标收藏夹', (tester) async {
    await _openSystemCollection(
      tester,
      itemCount: 5,
      extraSeed: (db) => seedCollection(db, id: 'col-target', name: '归档夹'),
    );

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );

    // 工具栏的"移动"打开对话框（此时树上只有一个移动按钮）。
    await tester.tap(find.widgetWithText(FilledButton, '移动'));
    await settleOverlayTransition(tester);

    // 对话框内的确认按钮与工具栏同名，限定在 AlertDialog 内点击。
    await tester.tap(find.text('归档夹'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '移动'),
      ),
    );
    await settleRouteTransition(tester);

    // 移动后 revision 刷新当前页，被移走的条目从本夹消失。
    expect(find.text('问题005'), findsNothing);
  });

  testWidgets('工具栏批量删除需确认且确认后条目消失', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _tapWithModifier(
      tester,
      '问题005',
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await _tapWithModifier(
      tester,
      '问题004',
      modifier: LogicalKeyboardKey.controlLeft,
    );

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settleOverlayTransition(tester);

    expect(find.textContaining('将删除 2 个收藏'), findsOneWidget);

    // 确认对话框的"删除"与工具栏同名，限定在 AlertDialog 内点击。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await settleRouteTransition(tester);

    expect(find.text('已选择 2 项'), findsNothing);
    expect(find.text('问题005'), findsNothing);
    expect(find.text('问题004'), findsNothing);
    expect(find.textContaining('共 3 条 · 1/1 页'), findsOneWidget);
  });

  testWidgets('行内溢出菜单提供选择、移动与删除入口', (tester) async {
    await _openSystemCollection(tester, itemCount: 5);

    await _openRowMenu(tester, '选择');
    await tester.pump();

    // "选择"把该行加入选择并进入选择模式。
    expect(find.text('已选择 1 项'), findsOneWidget);
  });
}
