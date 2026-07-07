import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/message_anchor_rail.dart';

import '../../../helpers/test_harness.dart';
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

/// 定位锚点条中承载宽度变化的容器（源码显式暴露的稳定标识）。
final Finder railContainerFinder = find.byKey(const ValueKey('message-anchor-rail'));

/// 断言锚点条渲染出预期数量的可点击条目（InkWell）。
Matcher findsNAnchorItems(int count) => findsNWidgets(count);

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

  // ── 容器级展开: 基础渲染契约 ──────────────────────────────

  group('MessageAnchorRail compact mode', () {
    testWidgets('渲染 5 条用户消息时显示 5 个锚点条目', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      expect(find.byType(MessageAnchorRail), findsOneWidget);
      expect(find.byType(InkWell), findsNAnchorItems(5));
    });

    testWidgets('空消息列表不渲染任何锚点条目', (tester) async {
      await pumpAnchorRail(tester, userMessages: []);

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('单条消息只渲染一个锚点条目', (tester) async {
      await pumpAnchorRail(
        tester,
        userMessages: [_userMessage(id: 'msg-1')],
      );

      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('点击锚点条目回调 onSelectMessage', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1'),
        _userMessage(id: 'msg-2'),
        _userMessage(id: 'msg-3'),
      ];

      String? selectedId;
      await pumpAnchorRail(
        tester,
        userMessages: messages,
        onSelectMessage: (id) => selectedId = id,
      );

      // 第二个锚点条目对应 msg-2
      await tester.tap(find.byType(InkWell).at(1));
      await tester.pump();

      expect(selectedId, 'msg-2');
    });
  });

  // ── 容器级展开: 悬停交互 ──────────────────────────────────

  group('MessageAnchorRail container hover', () {
    testWidgets('鼠标进入时展开锚点条宽度', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      final widthBefore = tester.getSize(railContainerFinder).width;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(railContainerFinder));
      await tester.pumpAndSettle();

      final widthAfter = tester.getSize(railContainerFinder).width;
      expect(widthAfter, greaterThan(widthBefore));

      await gesture.removePointer();
    });

    testWidgets('鼠标离开时折叠回原宽度', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      final widthBefore = tester.getSize(railContainerFinder).width;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(railContainerFinder));
      await tester.pumpAndSettle();
      final widthExpanded = tester.getSize(railContainerFinder).width;
      expect(widthExpanded, greaterThan(widthBefore));

      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();

      final widthCollapsed = tester.getSize(railContainerFinder).width;
      expect(widthCollapsed, lessThan(widthExpanded));

      await gesture.removePointer();
    });

    testWidgets('展开时显示所有消息的预览文本', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '第一条消息，测试预览'),
        _userMessage(id: 'msg-2', content: '第二条消息，更多文字'),
        _userMessage(id: 'msg-3', content: '第三条消息，继续测试'),
        _userMessage(id: 'msg-4', content: '第四条消息，最后一条'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(railContainerFinder));
      await tester.pumpAndSettle();

      expect(find.text('第一条消息'), findsOneWidget);
      expect(find.text('第二条消息'), findsOneWidget);
      expect(find.text('第三条消息'), findsOneWidget);
      expect(find.text('第四条消息'), findsOneWidget);

      await gesture.removePointer();
    });
  });

  // ── 容器级展开: 长按交互与守卫 ────────────────────────────

  group('MessageAnchorRail long press and guards', () {
    testWidgets('长按展开锚点条宽度', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      final widthBefore = tester.getSize(railContainerFinder).width;

      await tester.longPress(railContainerFinder);
      await tester.pumpAndSettle();

      final widthAfter = tester.getSize(railContainerFinder).width;
      expect(widthAfter, greaterThan(widthBefore));
    });

    testWidgets('展开状态下点击仍触发 onSelectMessage', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      String? selectedId;
      await pumpAnchorRail(
        tester,
        userMessages: messages,
        onSelectMessage: (id) => selectedId = id,
      );

      await tester.tap(find.byType(InkWell).at(1));
      await tester.pump();
      expect(selectedId, 'msg-2');
    });

    testWidgets('消息数 ≤3 时鼠标悬停不展开', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '消息一，测试'),
        _userMessage(id: 'msg-2', content: '消息二，测试'),
        _userMessage(id: 'msg-3', content: '消息三，测试'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      final widthBefore = tester.getSize(railContainerFinder).width;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(railContainerFinder));
      await tester.pumpAndSettle();

      final widthAfter = tester.getSize(railContainerFinder).width;
      expect(widthAfter, equals(widthBefore));

      await gesture.removePointer();
    });

    testWidgets('2 条消息仍渲染锚点条', (tester) async {
      final messages = [_userMessage(id: 'msg-1'), _userMessage(id: 'msg-2')];
      await pumpAnchorRail(tester, userMessages: messages);

      expect(find.byType(MessageAnchorRail), findsOneWidget);
      expect(find.byType(InkWell), findsNAnchorItems(2));
    });

    testWidgets('父级重建时折叠展开状态', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
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

      final widthBefore = tester.getSize(railContainerFinder).width;

      await tester.longPress(railContainerFinder);
      await tester.pumpAndSettle();
      final widthExpanded = tester.getSize(railContainerFinder).width;
      expect(widthExpanded, greaterThan(widthBefore));

      // 父级 setState 触发 didUpdateWidget → 折叠
      wrapperKey.currentState!.triggerRebuild();
      await tester.pumpAndSettle();

      final widthAfterRebuild = tester.getSize(railContainerFinder).width;
      expect(widthAfterRebuild, lessThan(widthExpanded));
    });
  });
}

/// 用于测试滚动折叠的 StatefulWidget 包装器。
///
/// 通过 [triggerRebuild] 模拟父级重建，触发 [MessageAnchorRail.didUpdateWidget]。
class _ScrollWrapper extends StatefulWidget {
  const _ScrollWrapper({
    required this.messages,
    super.key,
  });

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
