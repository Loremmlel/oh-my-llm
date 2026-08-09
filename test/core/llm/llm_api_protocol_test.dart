import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

void main() {
  group('LlmApiProtocol', () {
    test('三种协议存储值稳定且与枚举名一致', () {
      expect(LlmApiProtocol.chatCompletions.storageValue, 'chatCompletions');
      expect(LlmApiProtocol.responses.storageValue, 'responses');
      expect(LlmApiProtocol.anthropic.storageValue, 'anthropic');
    });

    test('展示名稳定', () {
      expect(LlmApiProtocol.chatCompletions.displayName, 'Chat Completions');
      expect(LlmApiProtocol.responses.displayName, 'Responses');
      expect(LlmApiProtocol.anthropic.displayName, 'Anthropic');
    });

    test('fromStorageValue 三种存储值都能解析', () {
      for (final protocol in LlmApiProtocol.values) {
        expect(
          LlmApiProtocol.fromStorageValue(protocol.storageValue),
          protocol,
        );
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
