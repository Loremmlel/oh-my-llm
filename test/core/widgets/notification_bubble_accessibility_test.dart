import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_data.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_stack.dart';

import '../../helpers/responsive_viewport_cases.dart';

NotificationBubbleData _data({
  String message = '同步完成',
  NotificationBubbleType type = NotificationBubbleType.info,
  NotificationBubbleAction? action,
}) {
  return NotificationBubbleData(message: message, type: type, action: action);
}

Widget _wrapContent(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

/// 构建 Provider + Stack 的测试环境；返回 container 供驱动状态。
Future<ProviderContainer> _pumpStack(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) =>
            Stack(children: [child!, const NotificationBubbleStack()]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  return container;
}

void main() {
  group('NotificationBubbleContent 语义', () {
    testWidgets('四种 type 参数化：每种只有一个完整 live region', (tester) async {
      for (final type in NotificationBubbleType.values) {
        await tester.pumpWidget(
          _wrapContent(
            NotificationBubbleContent(
              data: _data(type: type),
              onDismiss: () {},
            ),
          ),
        );
        final status = find.semantics.byLabel('${type.semanticLabel}：同步完成');
        expect(status, findsOneWidget, reason: '$type 应恰好一个 status 节点');
        expect(status, isSemantics(isLiveRegion: true));
        expect(
          find.text(type.semanticLabel),
          findsNothing,
          reason: '类型名称只存在于语义 label，不产生可见文本',
        );
      }
    });

    testWidgets('无 action：status 与「关闭通知」两个节点，图标/message 不重复', (tester) async {
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(data: _data(), onDismiss: () {}),
        ),
      );

      expect(find.semantics.byLabel('信息通知：同步完成'), findsOneWidget);
      expect(
        find.semantics.byPredicate((n) => n.tooltip == '关闭通知'),
        findsOneWidget,
      );
      // message 文本不生成独立语义 label
      expect(find.semantics.byLabel('同步完成'), findsNothing);
    });

    testWidgets('有 action：status/action/close 各一个且均有 tap', (tester) async {
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(
            data: _data(
              action: NotificationBubbleAction(label: '撤销', onPressed: () {}),
            ),
            onDismiss: () {},
          ),
        ),
      );

      expect(find.semantics.byLabel('信息通知：同步完成'), findsOneWidget);
      final action = find.semantics.byLabel('撤销');
      expect(action, findsOneWidget);
      expect(action, isSemantics(isButton: true, hasTapAction: true));
      expect(
        find.semantics.byPredicate((n) => n.tooltip == '关闭通知'),
        findsOneWidget,
      );
    });

    testWidgets('对 action 执行 semantics tap：action 先执行，再 dismiss', (
      tester,
    ) async {
      var actionCalls = 0;
      var dismissCalls = 0;
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(
            data: _data(
              action: NotificationBubbleAction(
                label: '撤销',
                onPressed: () => actionCalls++,
              ),
            ),
            onDismiss: () => dismissCalls++,
          ),
        ),
      );

      tester.semantics.tap(find.semantics.byLabel('撤销'));
      await tester.pump();
      expect(actionCalls, 1);
      expect(dismissCalls, 1);
    });

    testWidgets('对「关闭通知」执行 semantics tap：只 dismiss，不执行 action', (tester) async {
      var actionCalls = 0;
      var dismissCalls = 0;
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(
            data: _data(
              action: NotificationBubbleAction(
                label: '撤销',
                onPressed: () => actionCalls++,
              ),
            ),
            onDismiss: () => dismissCalls++,
          ),
        ),
      );

      tester.semantics.tap(
        find.semantics.byPredicate((n) => n.tooltip == '关闭通知'),
      );
      await tester.pump();
      expect(actionCalls, 0);
      expect(dismissCalls, 1);
    });

    testWidgets('standalone content 连续 Tab+Enter：有 action 时 action 后 close', (
      tester,
    ) async {
      var actionCalls = 0;
      var dismissCalls = 0;
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(
            data: _data(
              action: NotificationBubbleAction(
                label: '撤销',
                onPressed: () => actionCalls++,
              ),
            ),
            onDismiss: () => dismissCalls++,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(actionCalls, 1);
      expect(dismissCalls, 1);
    });

    testWidgets('standalone content 无 action：Tab 直接进入 close', (tester) async {
      var dismissCalls = 0;
      await tester.pumpWidget(
        _wrapContent(
          NotificationBubbleContent(
            data: _data(),
            onDismiss: () => dismissCalls++,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(dismissCalls, 1);
    });

    testWidgets('viewport smoke：两种视口下 status/action/close 一致', (tester) async {
      for (final vp in [phonePortrait, wideDesktop]) {
        tester.view.physicalSize = vp.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _wrapContent(
            NotificationBubbleContent(
              data: _data(
                action: NotificationBubbleAction(label: '撤销', onPressed: () {}),
              ),
              onDismiss: () {},
            ),
          ),
        );

        expect(find.semantics.byLabel('信息通知：同步完成'), findsOneWidget);
        expect(find.semantics.byLabel('撤销'), findsOneWidget);
        expect(
          find.semantics.byPredicate((n) => n.tooltip == '关闭通知'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('NotificationBubbleStack 行为', () {
    testWidgets('出场动画期间退出副本立即退出语义与交互', (tester) async {
      final container = await _pumpStack(tester);
      container
          .read(notificationBubblesProvider.notifier)
          .show(message: '同步完成');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // 入场完成

      expect(find.semantics.byLabel('信息通知：同步完成'), findsOneWidget);

      container
          .read(notificationBubblesProvider.notifier)
          .dismiss(container.read(notificationBubblesProvider).single.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50)); // 出场进行中，< 200ms

      // 视觉淡出可能仍在播放，但语义与可交互节点已退出
      expect(find.semantics.byLabel('信息通知：同步完成'), findsNothing);
      expect(
        find.semantics.byPredicate((n) => n.tooltip == '关闭通知'),
        findsNothing,
      );
    });

    testWidgets('通知插入不抢底层焦点', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) =>
                Stack(children: [child!, const NotificationBubbleStack()]),
            home: const Scaffold(body: TextField()),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final before = FocusManager.instance.primaryFocus;
      expect(before, isNotNull);

      container
          .read(notificationBubblesProvider.notifier)
          .show(message: '同步完成');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(FocusManager.instance.primaryFocus, same(before));

      // 清理：dismiss 取消 provider 的自动消失 Timer，否则测试结束时的
      // pending timer 断言会失败（provider timer 不在 widget dispose 链上）。
      container
          .read(notificationBubblesProvider.notifier)
          .dismiss(container.read(notificationBubblesProvider).single.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('最多三条回归：连续 show 4 条保留 3 条，各恰好一个 status', (tester) async {
      final container = await _pumpStack(tester);
      final notifier = container.read(notificationBubblesProvider.notifier);
      for (var i = 1; i <= 4; i++) {
        notifier.show(message: '通知 $i');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(notificationBubblesProvider), hasLength(3));
      expect(find.semantics.byLabel('信息通知：通知 2'), findsOneWidget);
      expect(find.semantics.byLabel('信息通知：通知 3'), findsOneWidget);
      expect(find.semantics.byLabel('信息通知：通知 4'), findsOneWidget);
      expect(find.semantics.byLabel('信息通知：通知 1'), findsNothing);

      // 清空 provider 并让退出动画结束，避免残留 timer/动画
      for (final d in container.read(notificationBubblesProvider)) {
        notifier.dismiss(d.id);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
