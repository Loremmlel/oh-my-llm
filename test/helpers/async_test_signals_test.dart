import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'async_test_signals.dart';

class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;
}

final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
);

/// 可切换的 Notifier：build 按 [fail] 开关抛错，用于在同一 provider 上先后
/// 制造「成功命中」与「重建抛错」两种状态，而不需要第二个 provider。
class ToggleNotifier extends Notifier<int> {
  bool fail = false;

  @override
  int build() {
    if (fail) throw StateError('boom');
    return 0;
  }

  /// 打开抛错开关并使自身失效：后续重建（或同步 flush）会抛错。
  void setFail() {
    fail = true;
    ref.invalidateSelf();
  }
}

final toggleProvider = NotifierProvider<ToggleNotifier, int>(
  ToggleNotifier.new,
);

void main() {
  group('waitForProviderState', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('注册前已满足时立即命中', () async {
      final state = await waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) => s == 0,
        description: '初始计数 0',
      );
      expect(state, 0);
    });

    test('注册后状态变化时命中', () async {
      final future = waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) => s >= 1,
        description: '计数自增到 1',
      );
      container.read(counterProvider.notifier).state = 1;
      expect(await future, 1);
    });

    test('Provider 错误转发给调用方', () async {
      final failing = Provider<int>((ref) => throw StateError('boom'));
      await expectLater(
        waitForProviderState<int>(
          container: container,
          provider: failing,
          matches: (_) => false,
          description: '永不匹配',
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
      );
    });

    test('超时错误携带等待描述', () async {
      await expectLater(
        waitForProviderState<int>(
          container: container,
          provider: counterProvider,
          matches: (_) => false,
          description: '等待永不发生的状态',
          timeout: Duration.zero,
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            contains('等待永不发生的状态'),
          ),
        ),
      );
    });

    test('完成后不再监听', () async {
      var matchCalls = 0;
      await waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) {
          matchCalls++;
          return s == 0;
        },
        description: '初始状态',
      );
      container.read(counterProvider.notifier).state = 1;
      container.read(counterProvider.notifier).state = 2;
      await Future<void>.value();
      expect(matchCalls, 1);
    });

    test('命中后同 provider 抛错：onError 已完成守卫短路', () async {
      // fireImmediately 在 listen 时同步命中并 complete，whenComplete(close)
      // 还排在微任务队列，此刻订阅仍打开。随后同一 provider 在同一同步块内
      // 抛错：onError 的 isCompleted 守卫短路二次 completeError——若无守卫，
      // 对已完成的 completer 调 completeError 会抛「Future already completed」
      // 并被 Riverpod 上报为未处理错误炸掉测试。
      final future = waitForProviderState<int>(
        container: container,
        provider: toggleProvider,
        matches: (s) => s == 0,
        description: '初始计数 0',
      );
      container.read(toggleProvider.notifier).setFail();
      // 二次 listen 触发 flush：被 invalidate 的 provider 同步重建抛错，
      // 错误同步投递给仍打开的监听器（走 onError 守卫），不依赖异步调度。
      container.listen<int>(toggleProvider, (_, _) {}).close();
      // 命中结果不受影响。invalidateSelf 排队的零延时 Timer 由 tearDown 的
      // container.dispose() 取消（scheduler.dispose 取消 pending task）。
      expect(await future, 0);
    });
  });
}
