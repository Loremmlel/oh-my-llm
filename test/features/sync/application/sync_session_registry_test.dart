import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/sync_session_registry.dart';
import 'package:oh_my_llm/features/sync/domain/models/session/sync_session.dart';

final class _FakeClock implements SyncClock {
  _FakeClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

void main() {
  test('nonce 仅可消费一次，session idle 过期后失效', () {
    final clock = _FakeClock(DateTime(2026));
    final registry = SyncSessionRegistry(clock);
    registry.open(
      SyncSession(
        id: 'session',
        peerId: 'peer',
        token: const [1],
        key: const [2],
        createdAt: clock.now(),
        lastActivityAt: clock.now(),
      ),
    );

    expect(
      registry.consumeNonce(sessionId: 'session', nonce: const [9]),
      isTrue,
    );
    expect(
      registry.consumeNonce(sessionId: 'session', nonce: const [9]),
      isFalse,
    );
    clock.value = clock.value.add(const Duration(minutes: 11));
    expect(registry.lookup(sessionId: 'session', token: const [1]), isNull);
  });
}
