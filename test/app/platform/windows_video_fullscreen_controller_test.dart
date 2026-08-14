import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/windows_video_fullscreen_controller.dart';

/// 用于测试的 Fake 窗口全屏网关：记录 setFullScreen 调用、控制单个在途命令、
/// 提供外部全屏事件发射。
final class FakeWindowsVideoWindowGateway implements WindowsVideoWindowGateway {
  FakeWindowsVideoWindowGateway({
    required bool initialFullscreen,
    bool failIsFullScreen = false,
  }) : _fullscreen = initialFullscreen,
       _failIsFullScreen = failIsFullScreen;

  bool _fullscreen;
  final bool _failIsFullScreen;
  final setCalls = <bool>[];
  final _listeners = <ValueChanged<bool>>{};
  Completer<void>? _blockedCompleter;
  Object? _nextSetError;

  @override
  Future<bool> isFullScreen() async {
    if (_failIsFullScreen) {
      throw StateError('模拟初始化查询失败');
    }
    return _fullscreen;
  }

  @override
  Future<void> setFullScreen(bool value) {
    setCalls.add(value);
    final nextError = _nextSetError;
    if (nextError != null) {
      _nextSetError = null;
      throw nextError;
    }
    final blocked = _blockedCompleter;
    if (blocked != null) {
      return blocked.future;
    }
    _fullscreen = value;
    return Future.value();
  }

  @override
  void addFullscreenListener(ValueChanged<bool> listener) {
    _listeners.add(listener);
  }

  @override
  void removeFullscreenListener(ValueChanged<bool> listener) {
    _listeners.remove(listener);
  }

  @override
  void dispose() {
    _listeners.clear();
  }

  /// 拦截下一次 setFullScreen，直到 [completeBlockedSet] 或 [failBlockedSet]。
  void blockNextSet() {
    _blockedCompleter = Completer<void>();
  }

  /// 以 [actual] 作为完成后的窗口实际状态，完成在途命令。
  void completeBlockedSet({required bool actual}) {
    _fullscreen = actual;
    _blockedCompleter!.complete();
    _blockedCompleter = null;
  }

  /// 让在途命令失败，模拟平台调用异常。
  void failBlockedSet([Object? error]) {
    _blockedCompleter!.completeError(error ?? StateError('模拟平台切换失败'));
    _blockedCompleter = null;
  }

  /// 让下一次 setFullScreen 直接抛出。
  void failNextSet([Object? error]) {
    _nextSetError = error ?? StateError('模拟平台切换失败');
  }

  /// 发射一次外部全屏窗口事件并同步更新内部窗口状态。
  void emitFullscreen(bool value) {
    _fullscreen = value;
    for (final listener in List<ValueChanged<bool>>.of(_listeners)) {
      listener(value);
    }
  }
}

void main() {
  test('快速切换依据 desired 串行执行而不读取陈旧 actual', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    gateway.blockNextSet();
    final first = controller.toggle();
    final second = controller.toggle();
    expect(gateway.setCalls, [true]);

    gateway.completeBlockedSet(actual: true);
    await first;
    await second;
    expect(gateway.setCalls, [true, false]);
    expect(controller.desiredFullscreen, isFalse);
  });

  test('窗口模式 exitIfFullscreen 返回未消费成功且不改变窗口', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    final result = await controller.exitIfFullscreen();
    expect(result.consumed, isFalse);
    expect(result.succeeded, isTrue);
    expect(gateway.setCalls, isEmpty);
    expect(controller.actualFullscreen, isFalse);
    expect(controller.desiredFullscreen, isFalse);
  });

  test('全屏时 exitIfFullscreen 退出全屏', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();
    await controller.toggle();

    final result = await controller.exitIfFullscreen();
    expect(result.consumed, isTrue);
    expect(result.succeeded, isTrue);
    expect(controller.actualFullscreen, isFalse);
    expect(gateway.setCalls, [true, false]);
  });

  test('无在途命令时外部窗口事件同时校准 actual 与 desired', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    gateway.emitFullscreen(true);
    expect(controller.actualFullscreen, isTrue);
    expect(controller.desiredFullscreen, isTrue);
    expect(gateway.setCalls, isEmpty);
  });

  test('在途命令的窗口事件只校准 actual 而不改写期望', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    gateway.blockNextSet();
    final first = controller.toggle(); // desired=true，setFullScreen(true) 在途
    final second = controller.toggle(); // desired=false，追加到队列
    expect(controller.desiredFullscreen, isFalse);

    gateway.emitFullscreen(true); // 在途命令产生的窗口事件
    expect(controller.actualFullscreen, isTrue);
    expect(controller.desiredFullscreen, isFalse); // 不被事件改写

    gateway.completeBlockedSet(actual: true);
    await first;
    await second;
    expect(gateway.setCalls, [true, false]); // 继续收敛到最新期望
  });

  test('初始化记录初始窗口模式并在关闭时恢复', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();
    expect(controller.actualFullscreen, isFalse);
    expect(controller.desiredFullscreen, isFalse);

    await controller.toggle();
    expect(controller.actualFullscreen, isTrue);

    final restored = await controller.restoreAndDispose();
    expect(restored, isTrue);
    expect(controller.desiredFullscreen, isFalse);
    expect(gateway.setCalls, [true, false]);
  });

  test('初始全屏会话允许退出并在关闭时恢复全屏', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: true);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();
    expect(controller.actualFullscreen, isTrue);
    expect(controller.desiredFullscreen, isTrue);

    final exit = await controller.exitIfFullscreen();
    expect(exit.consumed, isTrue);
    expect(exit.succeeded, isTrue);
    expect(controller.actualFullscreen, isFalse);
    expect(gateway.setCalls, [false]);

    final restored = await controller.restoreAndDispose();
    expect(restored, isTrue);
    expect(controller.desiredFullscreen, isTrue);
    expect(gateway.setCalls, [false, true]);
  });

  test('最新请求失败时 desired 回退到已确认 actual 且不无限重试', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    gateway.blockNextSet();
    final first = controller.toggle();
    expect(controller.desiredFullscreen, isTrue);
    expect(gateway.setCalls, [true]);

    gateway.failBlockedSet();
    final result = await first;
    expect(result.consumed, isTrue);
    expect(result.succeeded, isFalse);
    expect(controller.desiredFullscreen, isFalse); // 回退到已确认 actual
    expect(controller.actualFullscreen, isFalse);
    expect(gateway.setCalls, [true]); // 不无限重试
  });

  test('旧命令失败不覆盖更新后的 desired', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();

    gateway.blockNextSet();
    final first = controller.toggle(); // gen1：期望进入全屏，调用在途
    expect(controller.desiredFullscreen, isTrue);

    final second = controller.toggle(); // gen2：更新期望为窗口模式

    gateway.failBlockedSet(); // 旧命令失败，已不是最新请求
    await first;
    await second;

    expect(controller.desiredFullscreen, isFalse); // 保留最新期望
    expect(controller.actualFullscreen, isFalse);
    expect(gateway.setCalls, [true]);
  });

  test('初始化查询异常不向页面抛出且后续命令返回失败', () async {
    final gateway = FakeWindowsVideoWindowGateway(
      initialFullscreen: false,
      failIsFullScreen: true,
    );
    final recorded = <String>[];
    final controller = WindowsVideoFullscreenController(
      gateway: gateway,
      errorReporter: (operation, error, stack) => recorded.add(operation),
    );

    await controller.initializeSession(); // 不向页面抛出

    final toggleResult = await controller.toggle();
    expect(toggleResult.consumed, isTrue);
    expect(toggleResult.succeeded, isFalse);

    final exitResult = await controller.exitIfFullscreen();
    expect(exitResult.consumed, isTrue);
    expect(exitResult.succeeded, isFalse);

    final restored = await controller.restoreAndDispose();
    expect(restored, isFalse);

    expect(recorded, ['初始化']);
  });

  test('restoreAndDispose 幂等且释放后不再响应窗口事件', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final controller = WindowsVideoFullscreenController(gateway: gateway);
    await controller.initializeSession();
    await controller.toggle();
    expect(controller.actualFullscreen, isTrue);

    final first = await controller.restoreAndDispose();
    expect(first, isTrue);
    final second = await controller.restoreAndDispose(); // 幂等
    expect(second, isTrue);
    expect(gateway.setCalls, [true, false]); // 只恢复一次

    gateway.emitFullscreen(true); // listener 已移除
    expect(controller.actualFullscreen, isFalse);
  });

  test('切换失败返回失败结果且 reporter 收到固定 operation 与错误类型', () async {
    final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
    final recorded = <({String operation, Object error})>[];
    final controller = WindowsVideoFullscreenController(
      gateway: gateway,
      errorReporter: (operation, error, stack) {
        recorded.add((operation: operation, error: error));
      },
    );
    await controller.initializeSession();

    gateway.failNextSet();
    final result = await controller.toggle();
    expect(result.consumed, isTrue);
    expect(result.succeeded, isFalse); // 用户反馈不含异常文本，只是布尔结果

    expect(recorded, hasLength(1));
    expect(recorded.single.operation, '切换');
    expect(recorded.single.error, isA<StateError>());
  });

  test('默认错误 reporter 只输出固定文案与异常类型', () {
    final lines = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      lines.add(message ?? '');
    };
    try {
      reportVideoWindowError(
        '切换',
        StateError('媒体 URI 与敏感 Header 绝不出现在日志'),
        StackTrace.current,
      );
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(lines, hasLength(1));
    expect(lines.single, contains('[WindowsVideoFullscreen]'));
    expect(lines.single, contains('StateError'));
    expect(lines.single, isNot(contains('媒体 URI')));
  });
}
