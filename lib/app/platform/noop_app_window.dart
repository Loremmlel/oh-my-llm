import 'package:oh_my_llm/app/attention/app_window.dart';

/// 非 Windows 平台（Android/其余平台）的 no-op 窗口。
///
/// Android 无桌面窗口失焦概念：恒视为 focused（注意力只额外依赖 Flutter
/// lifecycle），restore/dispose 为 no-op，不发起任何平台调用。Windows 由
/// 平台 composition 绑定 `WindowsAppWindow`，不使用本类。
final class NoopAppWindow implements AppWindow {
  @override
  Stream<bool> get focusChanges => const Stream.empty();

  @override
  Future<bool> isFocused() async => true;

  @override
  Future<void> restoreAndFocus() async {}

  @override
  Future<void> dispose() async {}
}
