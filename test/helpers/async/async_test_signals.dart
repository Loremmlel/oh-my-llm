import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// 等待 [provider] 的状态满足 [matches] 后返回该状态。
///
/// 基于 [ProviderContainer.listen] 而非轮询；[fireImmediately] 保证注册监听前
/// 状态已满足时也能立即命中，避免漏事件。[description] 用于失败保护：超时
/// 抛出的错误必须能看出在等什么，而不是笼统的超时。
Future<StateT> waitForProviderState<StateT>({
  required ProviderContainer container,
  required ProviderListenable<StateT> provider,
  required bool Function(StateT state) matches,
  required String description,
  Duration timeout = const Duration(seconds: 5),
}) {
  final completer = Completer<StateT>();
  final subscription = container.listen<StateT>(
    provider,
    (previous, next) {
      if (!completer.isCompleted && matches(next)) {
        completer.complete(next);
      }
    },
    fireImmediately: true,
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  return completer.future
      .timeout(
        timeout,
        onTimeout: () => throw TimeoutException(description, timeout),
      )
      .whenComplete(subscription.close);
}
