import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/message_anchor_rail.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../../../test_database.dart';

ChatMessage _userMessage({
  required String id,
  String content = 'message content',
}) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime.now(),
    parentId: 'root',
  );
}

/// 挂载 MessageAnchorRail 到标准测试环境。
///
/// [onSelectMessage] 缺省时自动提供空回调。
Future<AppDatabase> pumpAnchorRail(
  WidgetTester tester, {
  required List<ChatMessage> userMessages,
  String? activeMessageId,
  ValueChanged<String>? onSelectMessage,
  double maxHeight = 400,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return pumpTestApp(
    tester,
    child: Material(
      child: MessageAnchorRail(
        userMessages: userMessages,
        activeMessageId: activeMessageId,
        maxHeight: maxHeight,
        onSelectMessage: onSelectMessage ?? (_) {},
      ),
    ),
    preferences: prefs,
  );
}

/// 定位第 1 条锚点条目的语义节点（label 格式 `第 1 条用户消息：<preview>`）。
///
/// hover/longPress 直接施加在语义节点上即可命中 rail 的展开交互区域，
/// 不再依赖容器级 test-key。
Finder _firstAnchor(String preview) =>
    find.bySemanticsLabel('第 1 条用户消息：$preview');

/// 当前持有主焦点的语义节点。
SemanticsFinder _focusedNode() =>
    find.semantics.byFlag(SemanticsFlag.isFocused);

/// 带尾部 TextField sentinel 的锚点挂载：焦点离开 rail 后落在 sentinel，
/// 不会 wrap 回第一个锚点，保证「焦点完全离开后折叠」可验证。
Future<AppDatabase> _pumpRailWithSentinel(
  WidgetTester tester, {
  required List<ChatMessage> userMessages,
  String? activeMessageId,
  ValueChanged<String>? onSelectMessage,
  double maxHeight = 400,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // 锚点交互控件与 TextField 都需要 Material 祖先，MaterialApp 的 home 不会
  // 自动提供（pumpAnchorRail 里已有的 Material 包裹同理）。
  return pumpTestApp(
    tester,
    child: Material(
      child: Column(
        children: [
          const SizedBox(height: 200),
          MessageAnchorRail(
            userMessages: userMessages,
            activeMessageId: activeMessageId,
            maxHeight: maxHeight,
            onSelectMessage: onSelectMessage ?? (_) {},
          ),
          const TextField(),
        ],
      ),
    ),
    preferences: prefs,
  );
}

void main() {
  group('extractPreviewText', () {
    test('应在第一个逗号处截断', () {
      const input = '你好，请问今天天气怎么样？谢谢';
      expect(MessageAnchorRail.extractPreviewText(input), '你好');
    });

    test('空字符串应返回空字符串', () {
      const input = '';
      expect(MessageAnchorRail.extractPreviewText(input), '');
    });

    test('纯标点符号应返回空字符串', () {
      const input = '。！？';
      expect(MessageAnchorRail.extractPreviewText(input), '');
    });

    test('应剥离 Markdown ** 语法后再截断', () {
      const input = '**你好**世界，再见';
      expect(MessageAnchorRail.extractPreviewText(input), '你好世界');
    });

    test('无标点长文本应限制在 15 个字符内', () {
      const input = '这是一段超长文本没有标点符号一直写下去超过十五个字的内容';
      final result = MessageAnchorRail.extractPreviewText(input);
      expect(result.length, lessThanOrEqualTo(15));
      expect(result, '这是一段超长文本没有标点符号一');
    });
  });

  // ── 容器级展开: 悬停交互 ──────────────────────────────────

  group('MessageAnchorRail container hover', () {
    testWidgets('鼠标进入时展开预览，离开后折叠', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      expect(find.text('消息1'), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(_firstAnchor('消息1')));
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息1'), findsOneWidget);

      await gesture.moveTo(const Offset(0, 0));
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息1'), findsNothing);

      await gesture.removePointer();
    });
  });

  // ── 容器级展开: 长按交互与守卫 ────────────────────────────

  group('MessageAnchorRail long press and guards', () {
    testWidgets('长按展开并显示消息预览文本', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      expect(find.text('消息1'), findsNothing);

      await tester.longPress(_firstAnchor('消息1'));
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息1'), findsOneWidget);
    });

    testWidgets('消息数 ≤3 时鼠标悬停不展开', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '消息一，测试'),
        _userMessage(id: 'msg-2', content: '消息二，测试'),
        _userMessage(id: 'msg-3', content: '消息三，测试'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      // ≤3 条时悬停后预览文本仍不可见
      expect(find.text('消息一'), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(_firstAnchor('消息一')));
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息一'), findsNothing);

      await gesture.removePointer();
    });

    testWidgets('父级重建时折叠展开状态', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
      );
      final wrapperKey = GlobalKey<_ScrollWrapperState>();

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = await createTestDatabase(prefs);
      addTearDown(() => db.close());

      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            home: _ScrollWrapper(key: wrapperKey, messages: messages),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('消息1'), findsNothing);

      await tester.longPress(_firstAnchor('消息1'));
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息1'), findsOneWidget);

      wrapperKey.currentState!.triggerRebuild();
      await settleAnimatedWidgetTransition(tester);

      expect(find.text('消息1'), findsNothing);
    });
  });

  group('a11y 语义与焦点契约', () {
    List<ChatMessage> fiveMessages() => [
      for (var i = 1; i <= 5; i++)
        _userMessage(id: 'msg-$i', content: '第 $i 条消息内容'),
    ];

    testWidgets('compact 未展开时 label 含序号与 preview，value 为 N/5', (tester) async {
      await pumpAnchorRail(
        tester,
        userMessages: fiveMessages(),
        activeMessageId: 'msg-2',
      );

      final first = find.semantics.byLabel('第 1 条用户消息：第 1 条消息内容');
      expect(first, findsOneWidget);
      expect(first, isSemantics(value: '1 / 5', isButton: true));
      expect(find.semantics.byLabel('第 5 条用户消息：第 5 条消息内容'), findsOneWidget);
    });

    testWidgets('selected 只标记 active 项，且不是 live region', (tester) async {
      await pumpAnchorRail(
        tester,
        userMessages: fiveMessages(),
        activeMessageId: 'msg-2',
      );

      expect(
        find.semantics.byLabel('第 2 条用户消息：第 2 条消息内容'),
        isSemantics(
          hasSelectedState: true,
          isSelected: true,
          isLiveRegion: false,
        ),
      );
      expect(
        find.semantics.byLabel('第 1 条用户消息：第 1 条消息内容'),
        isSemantics(isSelected: false),
      );
    });

    testWidgets('preview 为空时 label 仅序号，不带空冒号', (tester) async {
      await pumpAnchorRail(
        tester,
        userMessages: [_userMessage(id: 'msg-1', content: '###')],
      );

      expect(find.semantics.byLabel('第 1 条用户消息'), findsOneWidget);
      expect(find.semantics.byLabel('第 1 条用户消息：'), findsNothing);
    });

    testWidgets('semantics tap 激活对应锚点', (tester) async {
      final selected = <String>[];
      await pumpAnchorRail(
        tester,
        userMessages: fiveMessages(),
        onSelectMessage: selected.add,
      );

      tester.semantics.tap(find.semantics.byLabel('第 2 条用户消息：第 2 条消息内容'));
      await tester.pump();
      expect(selected, ['msg-2']);
    });

    testWidgets('键盘进入 rail 展开，按顺序激活 msg-1、msg-2', (tester) async {
      final selected = <String>[];
      await _pumpRailWithSentinel(
        tester,
        userMessages: fiveMessages(),
        onSelectMessage: selected.add,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // 焦点进入 rail 后预览展开，视觉 preview 出现
      expect(find.text('第 1 条消息内容'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-1']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-1', 'msg-2']);
    });

    testWidgets('低 maxHeight 时连续 Tab 可到达末项并激活', (tester) async {
      final selected = <String>[];
      await _pumpRailWithSentinel(
        tester,
        userMessages: [
          for (var i = 1; i <= 10; i++)
            _userMessage(id: 'msg-$i', content: '第 $i 条消息内容'),
        ],
        maxHeight: 60,
        onSelectMessage: selected.add,
      );

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-10']);
    });

    testWidgets('父级重建更新 active ID 时 rail 保持展开且焦点不丢', (tester) async {
      final selected = <String>[];
      final messages = fiveMessages();
      await _pumpRailWithSentinel(
        tester,
        userMessages: messages,
        activeMessageId: 'msg-1',
        onSelectMessage: selected.add,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(); // 聚焦第 2 项

      await _pumpRailWithSentinel(
        tester,
        userMessages: messages,
        activeMessageId: 'msg-2',
        onSelectMessage: selected.add,
      );
      await tester.pump();

      expect(find.text('第 2 条消息内容'), findsOneWidget); // 仍展开
      // 焦点不丢：重建后持有主焦点的语义节点仍是第 2 项
      expect(_focusedNode(), isSemantics(label: '第 2 条用户消息：第 2 条消息内容'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-2']);
    });

    testWidgets('焦点离开 rail 后折叠，且不误触发定位', (tester) async {
      final selected = <String>[];
      await _pumpRailWithSentinel(
        tester,
        userMessages: fiveMessages(),
        onSelectMessage: selected.add,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('第 1 条消息内容'), findsOneWidget); // 展开

      // 5 个锚点各占一个 Tab 位：逐项走完后下一次 Tab 才落到尾部
      // TextField sentinel，焦点完全离开 rail 触发折叠。
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      expect(find.text('第 1 条消息内容'), findsNothing); // 折叠
      expect(selected, isEmpty);
    });
  });
}

/// 用于测试滚动折叠的 StatefulWidget 包装器。
///
/// 通过 [triggerRebuild] 模拟父级重建，触发 [MessageAnchorRail.didUpdateWidget]。
class _ScrollWrapper extends StatefulWidget {
  const _ScrollWrapper({required this.messages, super.key});

  final List<ChatMessage> messages;

  @override
  State<_ScrollWrapper> createState() => _ScrollWrapperState();
}

class _ScrollWrapperState extends State<_ScrollWrapper> {
  void triggerRebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: MessageAnchorRail(
        userMessages: widget.messages,
        activeMessageId: null,
        maxHeight: 400,
        onSelectMessage: (_) {},
      ),
    );
  }
}
