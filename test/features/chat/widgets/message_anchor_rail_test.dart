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

  group('MessageAnchorRail compact mode', () {
    testWidgets('renders 5 user messages with anchor rail', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      // 验证根容器存在
      expect(
        find.byKey(const ValueKey('message-anchor-rail')),
        findsOneWidget,
      );

      // 验证 5 个指示器条全部存在
      for (int i = 1; i <= 5; i++) {
        expect(
          find.byKey(ValueKey('message-anchor-item-$i')),
          findsOneWidget,
        );
      }
    });

    testWidgets('renders nothing when userMessages is empty', (tester) async {
      await pumpAnchorRail(tester, userMessages: []);

      // 没有消息时指示器条不应存在
      expect(
        find.byKey(const ValueKey('message-anchor-item-1')),
        findsNothing,
      );
    });

    testWidgets(
      'highlights active message differently from inactive ones',
      (tester) async {
        final messages = [
          _userMessage(id: 'msg-1'),
          _userMessage(id: 'msg-2'),
          _userMessage(id: 'msg-3'),
        ];
        await pumpAnchorRail(
          tester,
          userMessages: messages,
          activeMessageId: 'msg-2',
        );

        // 获取主题色
        final theme = Theme.of(
          tester.element(find.byType(MessageAnchorRail)),
        );

        // 活动消息（msg-2，index 2，key = message-anchor-item-2）
        final activeContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('message-anchor-item-2')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final activeDecoration =
            activeContainer.decoration as BoxDecoration;
        expect(activeDecoration.color, theme.colorScheme.primary);

        // 非活动消息（msg-1，index 1，key = message-anchor-item-1）
        final inactiveContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('message-anchor-item-1')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final inactiveDecoration =
            inactiveContainer.decoration as BoxDecoration;
        expect(inactiveDecoration.color, theme.colorScheme.outline);
      },
    );

    testWidgets('renders single message correctly', (tester) async {
      await pumpAnchorRail(
        tester,
        userMessages: [_userMessage(id: 'msg-1')],
      );

      expect(
        find.byKey(const ValueKey('message-anchor-item-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('message-anchor-item-2')),
        findsNothing,
      );
    });

    testWidgets('calls onSelectMessage when tapped', (tester) async {
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

      // 点击第二条消息（message-anchor-item-2），对应 msg-2
      await tester.tap(
        find.byKey(const ValueKey('message-anchor-item-2')),
      );
      await tester.pump();

      expect(selectedId, 'msg-2');
    });
  });

  // ── Task 6: 悬停交互与预览气泡 ──────────────────────────────

  group('MessageAnchorRail hover interaction', () {
    testWidgets('shows preview bubble on mouse hover', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '你好世界，测试消息'),
        _userMessage(id: 'msg-2'),
        _userMessage(id: 'msg-3'),
        _userMessage(id: 'msg-4'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      final bubbleKey = const ValueKey('preview-bubble-msg-1');

      // 初始状态：气泡透明度为 0
      final initialOpacity = tester.widget<AnimatedOpacity>(find.byKey(bubbleKey));
      expect(initialOpacity.opacity, 0.0);

      // 模拟鼠标悬停在指示器上
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('message-anchor-item-1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 气泡透明度变为 1，可见
      final expandedOpacity = tester.widget<AnimatedOpacity>(find.byKey(bubbleKey));
      expect(expandedOpacity.opacity, 1.0);

      await gesture.removePointer();
    });

    testWidgets('hides preview bubble on mouse exit', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '你好世界，测试消息'),
        _userMessage(id: 'msg-2'),
        _userMessage(id: 'msg-3'),
        _userMessage(id: 'msg-4'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      final bubbleKey = const ValueKey('preview-bubble-msg-1');

      // 先展开
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('message-anchor-item-1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 确认已展开
      expect(tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity, 1.0);

      // 鼠标移开
      await gesture.moveTo(const Offset(0, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 气泡透明度变回 0
      final collapsedOpacity = tester.widget<AnimatedOpacity>(find.byKey(bubbleKey));
      expect(collapsedOpacity.opacity, 0.0);

      await gesture.removePointer();
    });

    testWidgets('preview bubble displays correct text', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '你好世界，这是预览文本'),
        _userMessage(id: 'msg-2'),
        _userMessage(id: 'msg-3'),
        _userMessage(id: 'msg-4'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      // 模拟悬停展开
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('message-anchor-item-1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 预览文本应在第一个标点符号处截断
      expect(find.text('你好世界'), findsOneWidget);

      await gesture.removePointer();
    });

    testWidgets('preview bubble respects max width', (tester) async {
      final messages = [
        _userMessage(
          id: 'msg-1',
          content: '这是一段很长的消息内容用于测试预览气泡的宽度限制功能',
        ),
        _userMessage(id: 'msg-2'),
        _userMessage(id: 'msg-3'),
        _userMessage(id: 'msg-4'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      // 模拟悬停展开
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('message-anchor-item-1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 气泡渲染宽度不超过 200dp
      final bubbleKey = const ValueKey('preview-bubble-msg-1');
      final containerFinder = find.descendant(
        of: find.byKey(bubbleKey),
        matching: find.byType(Container),
      );
      final bubbleSize = tester.getSize(containerFinder);
      expect(bubbleSize.width, lessThanOrEqualTo(200));

      await gesture.removePointer();
    });
  });

  // ── Task 7: 长按交互与守卫 ──────────────────────────────────

  group('MessageAnchorRail long press and guards', () {
    testWidgets('expands preview bubble on long press', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      final bubbleKey = const ValueKey('preview-bubble-msg-1');

      // 初始状态：展开状态为收起
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        0.0,
      );

      // 长按第一个指示器
      await tester.longPress(
        find.byKey(const ValueKey('message-anchor-item-1')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // 验证气泡透明度变为 1（已展开）
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        1.0,
      );
    });

    testWidgets(
      'tap still triggers onSelectMessage with GestureDetector present',
      (tester) async {
        final messages = [
          _userMessage(id: 'msg-1'),
          _userMessage(id: 'msg-2'),
          _userMessage(id: 'msg-3'),
          _userMessage(id: 'msg-4'),
          _userMessage(id: 'msg-5'),
        ];

        String? selectedId;
        await pumpAnchorRail(
          tester,
          userMessages: messages,
          onSelectMessage: (id) => selectedId = id,
        );

        // 点击第二条消息——应仍然触发 onSelectMessage
        await tester.tap(
          find.byKey(const ValueKey('message-anchor-item-2')),
        );
        await tester.pump();

        expect(selectedId, 'msg-2');
      },
    );

    testWidgets('does not expand when 3 or fewer messages', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1', content: '消息一，测试'),
        _userMessage(id: 'msg-2', content: '消息二，测试'),
        _userMessage(id: 'msg-3', content: '消息三，测试'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      final bubbleKey = const ValueKey('preview-bubble-msg-1');

      // 初始状态：透明度为 0
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        0.0,
      );

      // 长按——≤3 条消息时不应展开
      await tester.longPress(
        find.byKey(const ValueKey('message-anchor-item-1')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // 透明度仍为 0
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        0.0,
      );
    });

    testWidgets('still renders anchor rail with 2 messages', (tester) async {
      final messages = [
        _userMessage(id: 'msg-1'),
        _userMessage(id: 'msg-2'),
      ];
      await pumpAnchorRail(tester, userMessages: messages);

      // 锚点条仍然可见
      expect(
        find.byKey(const ValueKey('message-anchor-rail')),
        findsOneWidget,
      );

      // 2 个指示器条存在
      expect(
        find.byKey(const ValueKey('message-anchor-item-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('message-anchor-item-2')),
        findsOneWidget,
      );
      // 第 3 个不存在
      expect(
        find.byKey(const ValueKey('message-anchor-item-3')),
        findsNothing,
      );
    });

    testWidgets('collapses on scroll trigger', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}'),
      );

      // 使用 StatefulWidget 包装器来触发 setState → didUpdateWidget
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
            home: _ScrollWrapper(
              key: wrapperKey,
              messages: messages,
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleKey = const ValueKey('preview-bubble-msg-1');

      // 长按展开
      await tester.longPress(
        find.byKey(const ValueKey('message-anchor-item-1')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // 确认气泡已展开
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        1.0,
      );

      // 触发父级重建（模拟滚动），didUpdateWidget 应折叠气泡
      wrapperKey.currentState!.triggerRebuild();
      await tester.pump();

      // 气泡应折叠
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(bubbleKey)).opacity,
        0.0,
      );
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
