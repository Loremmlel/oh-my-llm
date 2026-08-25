import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

/// 测试化的窗口全屏网关：把 [VideoFullscreenController] 与 window_manager 插件解耦。
///
/// 生产实现包装 windowManager 并注册/反注册自身为 [WindowListener]；测试提供
/// Fake 记录调用并控制单个在途命令。插件类型只允许出现在 app/platform 与
/// bootstrap 初始化路径，media presentation 不 import 本接口。
abstract interface class WindowsVideoWindowGateway {
  /// 查询窗口当前是否处于原生全屏。
  Future<bool> isFullScreen();

  /// 请求窗口进入（true）或退出（false）原生全屏。
  Future<void> setFullScreen(bool value);

  /// 注册全屏状态变化监听器。
  void addFullscreenListener(ValueChanged<bool> listener);

  /// 反注册全屏状态变化监听器。
  void removeFullscreenListener(ValueChanged<bool> listener);

  /// 幂等释放网关持有的插件资源。
  void dispose();
}

/// 窗口错误 reporter：接收固定 operation 与错误类型，由实现决定如何记录。
///
/// 生产默认实现只输出安全文案，不得把异常文本、媒体 URI、Header 或 stack trace
/// 写入日志；测试实现可以记录结构化参数。
typedef VideoWindowErrorReporter = void Function(
  String operation,
  Object error,
  StackTrace stackTrace,
);

/// 默认错误 reporter：只输出固定操作与异常类型，不泄漏敏感细节。
void reportVideoWindowError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('[WindowsVideoFullscreen] $operation 失败 (${error.runtimeType})');
}

/// 生产窗口网关：包装 window_manager，把原生窗口事件转发为 presentation-neutral
/// 的布尔回调。
final class WindowManagerVideoWindowGateway
    with WindowListener
    implements WindowsVideoWindowGateway {
  final _listeners = <ValueChanged<bool>>{};

  @override
  void addFullscreenListener(ValueChanged<bool> listener) {
    if (_listeners.isEmpty) {
      windowManager.addListener(this);
    }
    _listeners.add(listener);
  }

  @override
  void removeFullscreenListener(ValueChanged<bool> listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      windowManager.removeListener(this);
    }
  }

  @override
  void dispose() {
    if (_listeners.isNotEmpty) {
      windowManager.removeListener(this);
      _listeners.clear();
    }
  }

  @override
  void onWindowEnterFullScreen() => _emit(true);

  @override
  void onWindowLeaveFullScreen() => _emit(false);

  void _emit(bool value) {
    for (final listener in List<ValueChanged<bool>>.of(_listeners)) {
      listener(value);
    }
  }

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
}

/// Windows 原生全屏会话：实现 presentation 的 [VideoFullscreenController] 窄端口。
///
/// 状态分为已确认的实际全屏与输入已请求的期望全屏。命令先同步更新 desired，
/// 再进入单一串行队列；每次最多一个 `setFullScreen` 平台调用在途，后续命令
/// 依据 desired 而不是尚未更新的 actual 计算。插件失败被转换为安全结果，不把
/// 平台异常泄漏到 Widget。
final class WindowsVideoFullscreenController
    implements VideoFullscreenController {
  WindowsVideoFullscreenController({
    required this._gateway,
    this._errorReporter = reportVideoWindowError,
  });

  final WindowsVideoWindowGateway _gateway;
  final VideoWindowErrorReporter _errorReporter;

  bool _initialFullscreen = false;
  bool _actualFullscreen = false;
  bool _desiredFullscreen = false;
  bool _commandInFlight = false;
  bool _disposed = false;
  bool _initializationComplete = false;
  bool _initializationFailed = false;
  bool _restoreSucceeded = false;
  Future<void>? _initialization;
  Future<bool> _tail = Future<bool>.value(true);
  int _generation = 0;
  int _queuedCommands = 0;

  @override
  bool get actualFullscreen => _actualFullscreen;

  @override
  bool get desiredFullscreen => _desiredFullscreen;

  /// 幂等开始会话：只创建一次 [Future]，记录初始全屏状态并注册窗口事件监听。
  ///
  /// 捕获 gateway 异常并记录初始化失败，绝不向页面的 `unawaited` 调用抛出。
  @override
  Future<void> initializeSession() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final initial = await _gateway.isFullScreen();
      _initialFullscreen = initial;
      _actualFullscreen = initial;
      _desiredFullscreen = initial;
      _gateway.addFullscreenListener(_onFullscreenChanged);
    } catch (error, stackTrace) {
      _initializationFailed = true;
      _reportError('初始化', error, stackTrace);
    } finally {
      _initializationComplete = true;
    }
  }

  @override
  Future<VideoFullscreenCommandResult> toggle() async {
    if (!_initializationComplete) {
      await initializeSession();
    }
    if (_initializationFailed || _disposed) {
      return const VideoFullscreenCommandResult(
        consumed: true,
        succeeded: false,
      );
    }
    final generation = ++_generation;
    _desiredFullscreen = !_desiredFullscreen;
    _enqueue(generation, '切换');
    final ok = await _tail;
    return VideoFullscreenCommandResult(consumed: true, succeeded: ok);
  }

  @override
  Future<VideoFullscreenCommandResult> exitIfFullscreen() async {
    if (!_initializationComplete) {
      await initializeSession();
    }
    if (_initializationFailed || _disposed) {
      return const VideoFullscreenCommandResult(
        consumed: true,
        succeeded: false,
      );
    }
    if (!_actualFullscreen && !_desiredFullscreen) {
      return const VideoFullscreenCommandResult(
        consumed: false,
        succeeded: true,
      );
    }
    final generation = ++_generation;
    _desiredFullscreen = false;
    _enqueue(generation, '退出');
    final ok = await _tail;
    return VideoFullscreenCommandResult(consumed: true, succeeded: ok);
  }

  @override
  Future<bool> restoreAndDispose() async {
    if (_disposed) return _restoreSucceeded;
    if (!_initializationComplete) {
      await initializeSession();
    }
    if (_initializationFailed) {
      _disposed = true;
      return false;
    }
    _disposed = true;
    try {
      _gateway.removeFullscreenListener(_onFullscreenChanged);
    } catch (error, stackTrace) {
      _reportError('恢复', error, stackTrace);
    }
    final generation = ++_generation;
    _desiredFullscreen = _initialFullscreen;
    _enqueue(generation, '恢复');
    await _tail;
    _restoreSucceeded = _actualFullscreen == _initialFullscreen;
    return _restoreSucceeded;
  }

  /// 队列空闲时同步启动首个收敛，保证命令路径在初始化完成后无需等待微任务；
  /// 否则追加到串行队列，保证同时最多一个 `setFullScreen` 在途。
  void _enqueue(int generation, String operation) {
    if (_queuedCommands == 0) {
      _commandInFlight = true;
      _queuedCommands = 1;
      _tail = _reconcile(
        generation,
        operation,
      ).whenComplete(_onCommandComplete);
    } else {
      _queuedCommands++;
      _tail = _tail
          .then((_) => _reconcile(generation, operation))
          .whenComplete(_onCommandComplete);
    }
  }

  void _onCommandComplete() {
    _queuedCommands--;
    if (_queuedCommands == 0) _commandInFlight = false;
  }

  /// 只在实际状态不等于当前期望时调用一次 gateway；成功后以网关查询校准 actual。
  ///
  /// 失败时若本命令仍是最新请求，把 desired 回退到已确认 actual，避免队列无限
  /// 重试；已有更新请求则保留更新后的 desired 继续串行收敛。
  Future<bool> _reconcile(int generation, String operation) async {
    if (_actualFullscreen == _desiredFullscreen) return true;
    try {
      await _gateway.setFullScreen(_desiredFullscreen);
      _actualFullscreen = await _gateway.isFullScreen();
      return true;
    } catch (error, stackTrace) {
      _reportError(operation, error, stackTrace);
      if (generation == _generation) {
        _desiredFullscreen = _actualFullscreen;
      }
      return false;
    }
  }

  /// 外部窗口事件：有命令在途时只校准 actual；无命令在途时接受用户/系统改变，
  /// 同时更新 actual 与 desired。关闭页面仍以 initial 为准。
  void _onFullscreenChanged(bool value) {
    _actualFullscreen = value;
    if (!_commandInFlight) _desiredFullscreen = value;
  }

  void _reportError(String operation, Object error, StackTrace stackTrace) {
    _errorReporter(operation, error, stackTrace);
  }
}
