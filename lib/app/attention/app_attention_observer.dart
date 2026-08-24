import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/app/router/app_router.dart';

import 'app_attention_state.dart';
import 'app_window.dart';

/// AppWindow 绑定点。
///
/// 平台 composition 完成前固定绑定 no-op 安全默认值（Android/其余平台的
/// 最终绑定同样是 no-op，Windows 改绑 `WindowsAppWindow`），保证每个中间
/// 提交都可编译可启动，不抛「未绑定」异常。
final appWindowProvider = Provider<AppWindow>((ref) {
  final window = NoopAppWindow();
  ref.onDispose(() => unawaited(window.dispose()));
  return window;
});

/// 统一订阅生命周期、路由与窗口焦点的注意力观察者。
///
/// 只负责把三类来源收敛为 [AppAttentionState] 快照并回调，不判定通知抑制；
/// 消费方（终态通知深模块）只读快照，不自行监听 Flutter/window API。
///
/// 焦点竞态防护：订阅 focus stream 后再调用异步 [AppWindow.isFocused]，
/// 每个 stream 事件递增 revision；初始查询只在 revision 未变化且未 dispose
/// 时写回，防止迟到的旧查询覆盖较新的 blur/focus 事件。
final class AppAttentionObserver with WidgetsBindingObserver {
  AppAttentionObserver({
    required AppWindow window,
    required RouteInformationProvider routeInformationProvider,
    required void Function(AppAttentionState state) onStateChanged,
  }) : _window = window,
       _routeInformationProvider = routeInformationProvider,
       _onStateChanged = onStateChanged;

  final AppWindow _window;
  final RouteInformationProvider _routeInformationProvider;
  final void Function(AppAttentionState state) _onStateChanged;

  AppLifecycleState _lifecycleState = AppLifecycleState.detached;
  bool _windowFocused = false;
  Uri _location = Uri();
  int _focusRevision = 0;
  bool _started = false;
  bool _disposed = false;
  StreamSubscription<bool>? _focusSubscription;

  /// 当前快照（读取不触发回调）。
  AppAttentionState get current => AppAttentionState(
    lifecycleState: _lifecycleState,
    windowFocused: _windowFocused,
    location: _location,
  );

  /// 订阅三类来源并触发初始焦点查询；幂等。
  ///
  /// 首个 route 快照在订阅时同步收敛 location，但不回调（调用方在 start 后
  /// 直接读 [current]）；lifecycle 与焦点保持初值，等首个真实事件到达。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _location = _routeInformationProvider.value.uri;
    _routeInformationProvider.addListener(_handleRouteChanged);
    WidgetsBinding.instance.addObserver(this);
    _focusSubscription = _window.focusChanges.listen(
      _handleFocusChanged,
      onError: (Object _, StackTrace _) {
        // 焦点流出错不影响生命周期/路由收敛，保持最后一次已知焦点。
      },
    );
    unawaited(_queryInitialFocus());
  }

  /// 释放全部订阅与 observer 注册；幂等。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _routeInformationProvider.removeListener(_handleRouteChanged);
    unawaited(_focusSubscription?.cancel());
    _focusSubscription = null;
  }

  // ── 事件处理 ──────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || _lifecycleState == state) return;
    _lifecycleState = state;
    _emit();
  }

  void _handleRouteChanged() {
    if (_disposed) return;
    final uri = _routeInformationProvider.value.uri;
    if (uri == _location) return;
    _location = uri;
    _emit();
  }

  void _handleFocusChanged(bool focused) {
    if (_disposed) return;
    _focusRevision += 1;
    if (_windowFocused == focused) return;
    _windowFocused = focused;
    _emit();
  }

  /// 初始焦点查询：只在 revision 未变化（无较新 focus 事件）且未 dispose 时
  /// 写回；查询失败保持初值 false（偏「可能多发」的安全方向）。
  Future<void> _queryInitialFocus() async {
    bool focused;
    try {
      focused = await _window.isFocused();
    } catch (_) {
      return;
    }
    if (_disposed || _focusRevision != 0 || _windowFocused == focused) return;
    _windowFocused = focused;
    _emit();
  }

  void _emit() {
    _onStateChanged(current);
  }
}

/// 注意力状态控制器：装配 observer 并把快照收敛进 provider state。
final class AppAttentionStateController extends Notifier<AppAttentionState> {
  @override
  AppAttentionState build() {
    final window = ref.watch(appWindowProvider);
    final router = ref.watch(appRouterProvider);
    final observer = AppAttentionObserver(
      window: window,
      routeInformationProvider: router.routeInformationProvider,
      onStateChanged: _handleStateChanged,
    );
    observer.start();
    ref.onDispose(observer.dispose);
    return observer.current;
  }

  void _handleStateChanged(AppAttentionState next) {
    if (state == next) return;
    state = next;
  }
}

/// 应用注意力快照 provider：终态通知深模块在 report 时读取。
final appAttentionStateProvider =
    NotifierProvider<AppAttentionStateController, AppAttentionState>(
      AppAttentionStateController.new,
    );
