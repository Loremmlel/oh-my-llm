import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/windows_navigation_input_adapter.dart';

/// 记录调用次数并返回预设结果的返回请求 fake。
final class RecordingBackRequest {
  RecordingBackRequest({this.result = true});

  final bool result;
  int callCount = 0;

  Future<bool> call() async {
    callCount += 1;
    return result;
  }
}

/// 挂在 adapter 外层、记录继续向上冒泡的键盘逻辑键。
///
/// adapter 返回 handled 的事件止步于 adapter，不会到达这里，
/// 因此 [receivedKeys] 可观察「adapter 放行还是消费了某次按键」。
final class AncestorKeyEventRecorder extends StatelessWidget {
  const AncestorKeyEventRecorder({
    required this.receivedKeys,
    required this.child,
    super.key,
  });

  final List<LogicalKeyboardKey> receivedKeys;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        receivedKeys.add(event.logicalKey);
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// 构造「可聚焦子树 -> adapter -> 事件记录祖先」的最小测试树。
///
/// 内置 [Focus.autofocus] 保证键盘事件从子树冒泡经过 adapter；
/// `ColoredBox` 提供可命中的绘制面，保证 pointer 事件能到达 adapter 的
/// Listener（空 SizedBox 不参与 hit test）。
/// 传入 [child] 时由调用方负责让子树持有焦点与可命中区域。
Widget buildAdapterTree({
  required WindowsBackRequest onBackRequested,
  required List<LogicalKeyboardKey> ancestorKeys,
  Widget? child,
}) {
  return AncestorKeyEventRecorder(
    receivedKeys: ancestorKeys,
    child: WindowsNavigationInputAdapter(
      onBackRequested: onBackRequested,
      child:
          child ??
          Focus(
            autofocus: true,
            child: const ColoredBox(
              color: Color(0xFF212121),
              child: SizedBox.expand(),
            ),
          ),
    ),
  );
}

/// 按键模拟统一走 Windows 键盘映射。
///
/// browserBack 等浏览器键只在桌面平台的 physical key map 中存在，
/// 测试默认的 android 映射无法构造这些按键事件。
Future<bool> sendWindowsKeyDown(WidgetTester tester, LogicalKeyboardKey key) {
  return tester.sendKeyDownEvent(key, platform: 'windows');
}

Future<bool> sendWindowsKeyUp(WidgetTester tester, LogicalKeyboardKey key) {
  return tester.sendKeyUpEvent(key, platform: 'windows');
}

Future<bool> sendWindowsKeyRepeat(WidgetTester tester, LogicalKeyboardKey key) {
  return tester.sendKeyRepeatEvent(key, platform: 'windows');
}

/// 挂载默认测试树（无自定义子树），返回回调记录与祖先事件记录。
Future<(RecordingBackRequest, List<LogicalKeyboardKey>)> pumpAdapterTree(
  WidgetTester tester, {
  bool backResult = true,
}) async {
  final back = RecordingBackRequest(result: backResult);
  final ancestorKeys = <LogicalKeyboardKey>[];
  await tester.pumpWidget(
    buildAdapterTree(onBackRequested: back.call, ancestorKeys: ancestorKeys),
  );
  return (back, ancestorKeys);
}

void main() {
  group('鼠标后退侧键', () {
    testWidgets('按下后退侧键时恰好请求一次返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await tester.tapAt(
        tester.getCenter(find.byType(WindowsNavigationInputAdapter)),
        buttons: kBackMouseButton,
      );
      await tester.pump();

      expect(back.callCount, 1);
    });

    testWidgets('普通主键点击不请求返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await tester.tapAt(
        tester.getCenter(find.byType(WindowsNavigationInputAdapter)),
      );
      await tester.pump();

      expect(back.callCount, 0);
    });

    testWidgets('次键点击不请求返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await tester.tapAt(
        tester.getCenter(find.byType(WindowsNavigationInputAdapter)),
        buttons: kSecondaryButton,
      );
      await tester.pump();

      expect(back.callCount, 0);
    });
  });

  group('键盘 browserBack', () {
    testWidgets('首次按下 browserBack 请求一次返回并消费事件', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      final handled = await sendWindowsKeyDown(
        tester,
        LogicalKeyboardKey.browserBack,
      );

      expect(back.callCount, 1);
      expect(handled, isTrue);
      expect(ancestorKeys, isNot(contains(LogicalKeyboardKey.browserBack)));
    });

    testWidgets('长按 repeat 与松开不重复请求返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.browserBack);
      await sendWindowsKeyRepeat(tester, LogicalKeyboardKey.browserBack);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.browserBack);

      expect(back.callCount, 1);
    });

    testWidgets('browserForward 不请求返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.browserForward);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.browserForward);

      expect(back.callCount, 0);
    });

    testWidgets('Escape 不请求返回且不被吞掉', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.escape);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.escape);

      expect(back.callCount, 0);
      expect(ancestorKeys, contains(LogicalKeyboardKey.escape));
    });

    testWidgets('方向键 Left 与 Alt+Left 不请求返回', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyDown(tester, LogicalKeyboardKey.altLeft);
      await sendWindowsKeyDown(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.altLeft);

      expect(back.callCount, 0);
      expect(ancestorKeys, contains(LogicalKeyboardKey.arrowLeft));
    });
  });

  group('TextField 聚焦', () {
    Future<void> pumpTextFieldTree(
      WidgetTester tester, {
      required RecordingBackRequest back,
      required List<LogicalKeyboardKey> ancestorKeys,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildAdapterTree(
              onBackRequested: back.call,
              ancestorKeys: ancestorKeys,
              child: const TextField(),
            ),
          ),
        ),
      );
      // 主键点击聚焦并输入文本，让子树持有真实焦点与光标选区。
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '已输入文本');
      await tester.pump();
    }

    testWidgets('TextField 聚焦时 browserBack 仍冒泡到根 adapter', (tester) async {
      final back = RecordingBackRequest();
      final ancestorKeys = <LogicalKeyboardKey>[];
      await pumpTextFieldTree(tester, back: back, ancestorKeys: ancestorKeys);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.browserBack);

      expect(back.callCount, 1);
    });

    testWidgets('TextField 聚焦时 Alt+Left 不请求返回', (tester) async {
      final back = RecordingBackRequest();
      final ancestorKeys = <LogicalKeyboardKey>[];
      await pumpTextFieldTree(tester, back: back, ancestorKeys: ancestorKeys);

      await sendWindowsKeyDown(tester, LogicalKeyboardKey.altLeft);
      await sendWindowsKeyDown(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.arrowLeft);
      await sendWindowsKeyUp(tester, LogicalKeyboardKey.altLeft);

      expect(back.callCount, 0);
    });
  });

  group('根 no-op 与生命周期', () {
    testWidgets('返回请求返回 false 时无异常且不二次请求', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(
        tester,
        backResult: false,
      );

      await tester.tapAt(
        tester.getCenter(find.byType(WindowsNavigationInputAdapter)),
        buttons: kBackMouseButton,
      );
      await tester.pump();
      await sendWindowsKeyDown(tester, LogicalKeyboardKey.browserBack);
      await tester.pump();

      expect(back.callCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adapter 卸载后不再响应返回输入', (tester) async {
      final (back, ancestorKeys) = await pumpAdapterTree(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.tapAt(const Offset(100, 100), buttons: kBackMouseButton);
      await sendWindowsKeyDown(tester, LogicalKeyboardKey.browserBack);

      expect(back.callCount, 0);
    });
  });
}
