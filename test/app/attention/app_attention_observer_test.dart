import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/attention/app_attention_observer.dart';
import 'package:oh_my_llm/app/attention/app_attention_state.dart';
import 'package:oh_my_llm/app/attention/app_window.dart';
import 'package:oh_my_llm/app/router/app_router.dart';

/// 可控 fake 窗口：isFocused 由测试延迟完成，focusChanges 为手动流。
final class FakeAppWindow implements AppWindow {
  final focusController = StreamController<bool>();
  final Completer<bool> isFocusedResult = Completer<bool>();
  int restoreAndFocusCallCount = 0;

  @override
  Stream<bool> get focusChanges => focusController.stream;

  @override
  Future<bool> isFocused() => isFocusedResult.future;

  @override
  Future<void> restoreAndFocus() async {
    restoreAndFocusCallCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

/// 最小路由信息 provider：update 同步换值并通知监听者。
final class FakeRouteInformationProvider extends RouteInformationProvider
    with ChangeNotifier {
  FakeRouteInformationProvider(Uri initial)
    : _value = RouteInformation(uri: initial);

  RouteInformation _value;

  @override
  RouteInformation get value => _value;

  void update(Uri location) {
    _value = RouteInformation(uri: location);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppAttentionObserver buildObserver(
    List<AppAttentionState> states, {
    FakeAppWindow? window,
    String initialPath = '/chat',
  }) {
    return AppAttentionObserver(
      window: window ?? FakeAppWindow(),
      routeInformationProvider: FakeRouteInformationProvider(
        Uri(path: initialPath),
      ),
      onStateChanged: states.add,
    );
  }

  group('AppAttentionObserver', () {
    test('首个真实快照前保持 detached 且未聚焦', () async {
      final states = <AppAttentionState>[];
      // isFocused 永不完成：模拟初始焦点查询尚未返回。
      final observer = buildObserver(states);

      observer.start();
      await pumpEventQueue();

      expect(observer.current.lifecycleState, AppLifecycleState.detached);
      expect(observer.current.windowFocused, isFalse);
      // detached + 未聚焦 => hostIsAttentive 为 false，通知决策选择展示。
      expect(observer.current.hostIsAttentive, isFalse);
      // 首个 route 快照在 start 时同步收敛 location。
      expect(observer.current.location.path, '/chat');
      observer.dispose();
    });

    test('迟到的初始焦点查询不覆盖较新的 focus event', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final observer = buildObserver(states, window: window);

      observer.start();
      // 较新的 blur 事件先到达（focus revision 递增）。
      window.focusController.add(false);
      await pumpEventQueue();
      expect(observer.current.windowFocused, isFalse);

      // 迟到的初始查询此刻才返回 true：不得覆盖较新的 blur 事件。
      window.isFocusedResult.complete(true);
      await pumpEventQueue();
      expect(observer.current.windowFocused, isFalse);
      observer.dispose();
    });

    test('无事件介入时初始焦点查询写回', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final observer = buildObserver(states, window: window);

      observer.start();
      await pumpEventQueue();
      expect(observer.current.windowFocused, isFalse);

      window.isFocusedResult.complete(true);
      await pumpEventQueue();
      expect(observer.current.windowFocused, isTrue);
      // lifecycle 仍为 detached：焦点写回不改变 hostIsAttentive。
      expect(observer.current.hostIsAttentive, isFalse);
      observer.dispose();
    });

    test('focus 事件按最新值更新快照', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final observer = buildObserver(states, window: window);

      observer.start();
      window.isFocusedResult.complete(false);
      await pumpEventQueue();

      window.focusController.add(true);
      await pumpEventQueue();
      expect(observer.current.windowFocused, isTrue);

      window.focusController.add(false);
      await pumpEventQueue();
      expect(observer.current.windowFocused, isFalse);
      observer.dispose();
    });

    test('路由变化更新快照', () async {
      final states = <AppAttentionState>[];
      final provider = FakeRouteInformationProvider(Uri(path: '/chat'));
      final observer = AppAttentionObserver(
        window: FakeAppWindow(),
        routeInformationProvider: provider,
        onStateChanged: states.add,
      );

      observer.start();
      provider.update(Uri.parse('/history'));
      await pumpEventQueue();
      expect(observer.current.location.path, '/history');

      provider.update(Uri.parse('/chat?conversationId=conv-1'));
      await pumpEventQueue();
      expect(observer.current.location.path, '/chat');
      expect(
        observer.current.location.queryParameters['conversationId'],
        'conv-1',
      );
      observer.dispose();
    });

    test('生命周期变化更新快照', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final observer = buildObserver(states, window: window);

      observer.start();
      window.isFocusedResult.complete(true);
      await pumpEventQueue();
      expect(observer.current.hostIsAttentive, isFalse);

      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      expect(observer.current.lifecycleState, AppLifecycleState.resumed);
      expect(observer.current.hostIsAttentive, isTrue);

      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await pumpEventQueue();
      expect(observer.current.hostIsAttentive, isFalse);
      observer.dispose();
    });

    test('dispose 后不再响应事件且重复 dispose 安全', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final provider = FakeRouteInformationProvider(Uri(path: '/chat'));
      final observer = AppAttentionObserver(
        window: window,
        routeInformationProvider: provider,
        onStateChanged: states.add,
      );

      observer.start();
      observer.dispose();
      observer.dispose(); // 幂等。

      provider.update(Uri.parse('/history'));
      window.focusController.add(true);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      // dispose 后任何来源都不再更新快照。
      expect(observer.current.location.path, '/chat');
      expect(observer.current.windowFocused, isFalse);
      expect(observer.current.lifecycleState, AppLifecycleState.detached);
    });

    test('重复 start 只订阅一次', () async {
      final states = <AppAttentionState>[];
      final window = FakeAppWindow();
      final observer = buildObserver(states, window: window);

      observer.start();
      observer.start();
      window.focusController.add(true);
      await pumpEventQueue();
      // 同一事件只产生一次状态回调。
      expect(states.where((state) => state.windowFocused).length, 1);
      observer.dispose();
    });
  });

  group('appAttentionStateProvider', () {
    test('provider 装配 observer 并随焦点与路由更新', () async {
      final router = GoRouter(
        initialLocation: '/chat',
        routes: [
          GoRoute(
            path: '/chat',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      );
      final window = FakeAppWindow();
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appWindowProvider.overrideWithValue(window),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(router.dispose);

      final initial = container.read(appAttentionStateProvider);
      expect(initial.location.path, '/chat');
      expect(initial.hostIsAttentive, isFalse);

      window.isFocusedResult.complete(true);
      await pumpEventQueue();
      var current = container.read(appAttentionStateProvider);
      expect(current.windowFocused, isTrue);
      expect(current.hostIsAttentive, isFalse); // lifecycle 仍 detached。

      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      current = container.read(appAttentionStateProvider);
      expect(current.hostIsAttentive, isTrue);

      router.go('/history');
      await pumpEventQueue();
      current = container.read(appAttentionStateProvider);
      expect(current.location.path, '/history');
      expect(current.hostIsAttentive, isTrue); // attentive 但路由非 /chat。
    });
  });
}
