import 'dart:math';

import 'llm_event.dart';

/// 单次调用的取消句柄；监听器可移除，已完成调用不被句柄长期保留。
class LlmCallControl {
  final String requestId = List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static final _random = Random.secure();
  bool _cancelled = false;
  bool _claimed = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;

  void claim() {
    if (_claimed) throw StateError('取消句柄只能用于一次调用');
    _claimed = true;
    throwIfCancelled();
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const LlmException('调用已取消', kind: LlmFailureKind.cancelled);
    }
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}
