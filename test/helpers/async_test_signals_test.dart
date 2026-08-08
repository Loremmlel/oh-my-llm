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
  });
}
