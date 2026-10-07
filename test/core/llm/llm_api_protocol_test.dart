import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

void main() {
  group('LlmApiProtocol', () {
    test('三种协议按固定持久化值编码与解码', () {
      for (final (stored, protocol) in [
        ('chatCompletions', LlmApiProtocol.chatCompletions),
        ('responses', LlmApiProtocol.responses),
        ('anthropic', LlmApiProtocol.anthropic),
      ]) {
        expect(protocol.storageValue, stored);
        expect(LlmApiProtocol.fromStorageValue(stored), protocol);
      }
    });

    test('fromStorageValue 未知值抛 FormatException', () {
      expect(
        () => LlmApiProtocol.fromStorageValue('future-protocol'),
        throwsFormatException,
      );
    });
  });
}
