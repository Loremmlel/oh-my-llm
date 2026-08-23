import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Windows 返回请求回调：返回是否真正完成了返回。
///
/// 返回 `false` 表示已在返回链根部（如 Chat 根页面），无动作可做；
/// 输入侧仍把该输入视为已消费，不再寻找其他处理器。
typedef WindowsBackRequest = Future<bool> Function();

/// 把 Windows 鼠标后退侧键与 `browserBack` 键翻译成一次返回请求的根部输入适配器。
///
/// 只做输入翻译：不认识路由、页面或会话，返回语义完全由调用方注入的
/// [onBackRequested] 决定（生产为 GoRouter BackButtonDispatcher）。是否
/// 启用由 app composition 按 `defaultTargetPlatform` 判断，本文件不读平台。
final class WindowsNavigationInputAdapter extends StatelessWidget {
  const WindowsNavigationInputAdapter({
    required this.onBackRequested,
    required this.child,
    super.key,
  });

  final WindowsBackRequest onBackRequested;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // 只作为键盘事件冒泡链上的观察点，自身不参与焦点遍历。
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: Listener(onPointerDown: _handlePointerDown, child: child),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 只认首次按下：repeat 会随长按连续穿透多层页面，up 无导航语义。
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }
    unawaited(onBackRequested());
    return KeyEventResult.handled;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton == 0) {
      return;
    }
    unawaited(onBackRequested());
  }
}
