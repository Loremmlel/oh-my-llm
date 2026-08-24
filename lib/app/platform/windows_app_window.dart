import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:oh_my_llm/app/attention/app_window.dart';

/// 窗口恢复/聚焦失败的固定诊断分类。
///
/// 与终态通知深模块共用同一命名：恢复步骤失败只上报该分类，不携带窗口
/// 句柄、异常原文或堆栈。
const windowsWindowRestoreFailedDiagnostic = 'window_restore_or_focus_failed';

/// 窗口诊断回调：接收固定分类，由实现决定如何记录。
typedef WindowsWindowDiagnosticReporter = void Function(String category);

/// 默认诊断输出：只打印固定分类，不带任何敏感细节。
void _defaultDiagnosticReporter(String category) {
  debugPrint('[WindowsAppWindow] $category');
}

/// window_manager 的窄 seam：[WindowsAppWindow] 只依赖本接口。
///
/// 插件类型只允许出现在 app/platform 与 bootstrap 初始化路径；测试提供 Fake
/// 记录调用并控制可见/最小化/聚焦状态，绝不触碰真实 window_manager。
abstract interface class WindowsWindowManagerClient {
  Future<bool> isVisible();

  Future<bool> isMinimized();

  Future<bool> isFocused();

  Future<void> show();

  Future<void> restore();

  Future<void> focus();

  void addFocusListener(void Function(bool focused) listener);

  void removeFocusListener(void Function(bool focused) listener);
}

/// 生产实现：包装全局 windowManager 单例并把原生焦点事件转发给监听者。
final class WindowManagerWindowsWindowClient
    with WindowListener
    implements WindowsWindowManagerClient {
  final _focusListeners = <void Function(bool focused)>{};

  void _emit(bool focused) {
    for (final listener in List.of(_focusListeners)) {
      listener(focused);
    }
  }

  @override
  void onWindowFocus() => _emit(true);

  @override
  void onWindowBlur() => _emit(false);

  @override
  void addFocusListener(void Function(bool focused) listener) {
    if (_focusListeners.isEmpty) {
      windowManager.addListener(this);
    }
    _focusListeners.add(listener);
  }

  @override
  void removeFocusListener(void Function(bool focused) listener) {
    _focusListeners.remove(listener);
    if (_focusListeners.isEmpty) {
      windowManager.removeListener(this);
    }
  }

  @override
  Future<bool> isVisible() => windowManager.isVisible();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<bool> isFocused() => windowManager.isFocused();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> restore() => windowManager.restore();

  @override
  Future<void> focus() => windowManager.focus();
}

/// Windows 桌面窗口端口实现：包装 [WindowsWindowManagerClient] 完成焦点监听
/// 与恢复聚焦。
///
/// restoreAndFocus 固定「不可见则 show → 最小化则 restore → 最后 focus」；
/// 三步各自独立 catch，任何一步失败都继续后续步骤且不向调用方抛出——通知
/// 点击后的会话导航不因窗口 API 失败而丢失目标（后台调用 SetForegroundWindow
/// 被前台锁拒绝时只会退化为任务栏闪烁，激活本身仍需继续）。任一步失败只在
/// 最后上报一次固定诊断分类，不携带异常原文。
final class WindowsAppWindow implements AppWindow {
  WindowsAppWindow({
    required WindowsWindowManagerClient client,
    WindowsWindowDiagnosticReporter diagnosticReporter =
        _defaultDiagnosticReporter,
  }) : _client = client,
       _diagnosticReporter = diagnosticReporter;

  final WindowsWindowManagerClient _client;
  final WindowsWindowDiagnosticReporter _diagnosticReporter;

  final _focusChanges = StreamController<bool>.broadcast();
  bool _forwardingFocus = false;
  bool _disposed = false;

  void _emitFocus(bool focused) {
    if (_disposed) return;
    _focusChanges.add(focused);
  }

  @override
  Stream<bool> get focusChanges {
    // 首次访问才向 seam 注册转发，避免无人消费时触碰全局插件监听。
    if (!_forwardingFocus && !_disposed) {
      _forwardingFocus = true;
      _client.addFocusListener(_emitFocus);
    }
    return _focusChanges.stream;
  }

  @override
  Future<bool> isFocused() => _client.isFocused();

  @override
  Future<void> restoreAndFocus() async {
    if (_disposed) return;
    var failed = false;
    try {
      if (!await _client.isVisible()) {
        await _client.show();
      }
    } catch (_) {
      failed = true;
    }
    try {
      if (await _client.isMinimized()) {
        await _client.restore();
      }
    } catch (_) {
      failed = true;
    }
    try {
      await _client.focus();
    } catch (_) {
      failed = true;
    }
    if (failed) {
      _diagnosticReporter(windowsWindowRestoreFailedDiagnostic);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_forwardingFocus) {
      _forwardingFocus = false;
      _client.removeFocusListener(_emitFocus);
    }
    await _focusChanges.close();
  }
}
