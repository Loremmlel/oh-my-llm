import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/windows_app_window.dart';

/// window_manager seam 的受控 Fake：记录调用序列并允许按操作名注入失败。
final class _FakeWindowsWindowManagerClient
    implements WindowsWindowManagerClient {
  bool visible = true;
  bool minimized = false;
  bool focused = true;
  final throwOn = <String>{};
  final ops = <String>[];
  final focusListeners = <void Function(bool focused)>{};

  void _record(String operation) {
    ops.add(operation);
    if (throwOn.contains(operation)) {
      throw StateError('$operation 失败');
    }
  }

  void emitFocus(bool focused) {
    for (final listener in List.of(focusListeners)) {
      listener(focused);
    }
  }

  @override
  Future<bool> isVisible() async {
    _record('isVisible');
    return visible;
  }

  @override
  Future<bool> isMinimized() async {
    _record('isMinimized');
    return minimized;
  }

  @override
  Future<bool> isFocused() async {
    _record('isFocused');
    return focused;
  }

  @override
  Future<void> show() async => _record('show');

  @override
  Future<void> restore() async => _record('restore');

  @override
  Future<void> focus() async => _record('focus');

  @override
  void addFocusListener(void Function(bool focused) listener) =>
      focusListeners.add(listener);

  @override
  void removeFocusListener(void Function(bool focused) listener) =>
      focusListeners.remove(listener);
}

void main() {
  test('窗口不可见时先 show 再 focus', () async {
    final client = _FakeWindowsWindowManagerClient()..visible = false;
    final diagnostics = <String>{};
    final window = WindowsAppWindow(
      client: client,
      diagnosticReporter: diagnostics.add,
    );
    addTearDown(window.dispose);

    await window.restoreAndFocus();

    expect(client.ops, containsAllInOrder(['isVisible', 'show', 'focus']));
    expect(client.ops, isNot(contains('restore')));
    // 全部步骤成功，不上报失败诊断。
    expect(diagnostics, isEmpty);
  });

  test('窗口最小化时先 restore 再 focus', () async {
    final client = _FakeWindowsWindowManagerClient()
      ..visible = true
      ..minimized = true;
    final diagnostics = <String>{};
    final window = WindowsAppWindow(
      client: client,
      diagnosticReporter: diagnostics.add,
    );
    addTearDown(window.dispose);

    await window.restoreAndFocus();

    expect(
      client.ops,
      containsAllInOrder(['isVisible', 'isMinimized', 'restore', 'focus']),
    );
    expect(client.ops, isNot(contains('show')));
    expect(diagnostics, isEmpty);
  });

  test('窗口恢复部分失败仍尝试 focus', () async {
    // 任一前置步骤抛错都不得阻断后续步骤：focus 恒被尝试，且不向调用方抛出。
    for (final entry in {
      'isVisible': (visible: false, minimized: false),
      'show': (visible: false, minimized: false),
      'restore': (visible: true, minimized: true),
      'focus': (visible: true, minimized: false),
    }.entries) {
      final client = _FakeWindowsWindowManagerClient()
        ..visible = entry.value.visible
        ..minimized = entry.value.minimized
        ..throwOn.add(entry.key);
      final diagnostics = <String>{};
      final window = WindowsAppWindow(
        client: client,
        diagnosticReporter: diagnostics.add,
      );
      addTearDown(window.dispose);

      await window.restoreAndFocus();

      expect(
        client.ops,
        contains('focus'),
        reason: '${entry.key} 失败后仍必须尝试 focus',
      );
      expect(diagnostics, {
        windowsWindowRestoreFailedDiagnostic,
      }, reason: '${entry.key} 失败后上报固定诊断分类');
    }
  });

  test('焦点变化经 seam 转发且 dispose 后移除监听', () async {
    final client = _FakeWindowsWindowManagerClient();
    final window = WindowsAppWindow(client: client, diagnosticReporter: (_) {});
    addTearDown(window.dispose);

    // 先建立焦点流期望再触发事件；emitsDone 保证除这两个事件外无其他转发。
    final expectation = expectLater(
      window.focusChanges,
      emitsInOrder([true, false, emitsDone]),
    );
    expect(client.focusListeners, hasLength(1));

    client.emitFocus(true);
    client.emitFocus(false);

    expect(await window.isFocused(), isTrue);

    // dispose 移除 seam 监听并关闭焦点流，缓冲事件先于 done 投递。
    await window.dispose();
    expect(client.focusListeners, isEmpty);
    await expectation;
  });
}
