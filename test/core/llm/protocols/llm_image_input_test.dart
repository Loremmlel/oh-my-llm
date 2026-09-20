import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_input_encoder.dart';

void main() {
  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 按官方格式编码有序图文与纯图片消息', () {
      final image = LlmImagePart(
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final request = _request(protocol, [
        const LlmTextMessage(role: LlmRole.system, text: '系统'),
        LlmUserMessage(content: [image, const LlmTextPart('说明'), image]),
        const LlmTextMessage(role: LlmRole.assistant, text: '答复'),
        LlmUserMessage(content: [image]),
      ]);
      final wire = encodeLlmInput(request, Uri.parse('https://example.com'));
      final messages =
          wire[protocol == LlmApiProtocol.responses ? 'input' : 'messages']
              as List;
      final user = messages.where((dynamic m) => m['role'] == 'user').toList();
      final block = switch (protocol) {
        LlmApiProtocol.chatCompletions => {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,AQID'},
        },
        LlmApiProtocol.responses => {
          'type': 'input_image',
          'image_url': 'data:image/png;base64,AQID',
        },
        LlmApiProtocol.anthropic => {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AQID',
          },
        },
      };
      expect(user.first['content'], [
        block,
        {
          'type': protocol == LlmApiProtocol.responses ? 'input_text' : 'text',
          'text': '说明',
        },
        block,
      ]);
      expect(user.last['content'], [block]);
      expect(request.hasImages, isTrue);
    });
  }

  test('图片字节防御复制且拒绝不支持的格式和空数据', () {
    final bytes = Uint8List.fromList([1]);
    final image = LlmImagePart(mimeType: 'image/png', bytes: bytes);
    bytes[0] = 2;
    expect(image.bytes.single, 1);
    expect(() => image.bytes[0] = 3, throwsUnsupportedError);
    for (final input in [
      (mime: 'image/svg+xml', bytes: bytes),
      (mime: 'image/png', bytes: Uint8List(0)),
    ]) {
      expect(
        () => LlmImagePart(mimeType: input.mime, bytes: input.bytes),
        throwsA(isA<LlmException>()),
      );
    }
  });

  test('完整上下文超过图片字节预算时显式拒绝', () {
    final image = LlmImagePart(
      mimeType: 'image/png',
      bytes: Uint8List(LlmImagePart.maxBytes),
    );
    expect(
      () => encodeLlmInput(
        _request(LlmApiProtocol.responses, [
          LlmUserMessage(content: List.filled(6, image)),
        ]),
        Uri.parse('https://example.com'),
      ),
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '失败类型',
          LlmFailureKind.invalidRequest,
        ),
      ),
    );
  });
}

LlmRequest _request(LlmApiProtocol protocol, List<LlmInputItem> input) =>
    LlmRequest(
      target: LlmRequestTarget(
        protocol: protocol,
        endpoint: 'https://example.com',
        apiKey: 'test',
        model: 'vision',
      ),
      input: input,
    );
