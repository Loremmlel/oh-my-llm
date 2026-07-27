import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_message.dart';

void main() {
  test('退休的 v1 动态信封不再提供生产构造器', () {
    const message = PairingChallengeRequest(
      requestId: 'request',
      clientIdentity: 'client',
    );

    final result = SyncProtocolCodec.decode(SyncProtocolCodec.encode(message));

    expect(result, isA<SyncProtocolDecodeSuccess>());
  });
}
