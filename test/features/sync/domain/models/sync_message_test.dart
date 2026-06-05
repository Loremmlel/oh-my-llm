import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/domain/models/sync_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

void main() {
  group('SyncMessage', () {
    test('toJson 包含 type/version/requestId/payload 四个字段', () {
      const message = SyncMessage(
        type: 'settings_sync_request',
        requestId: 'r-1',
        payload: {'k': 'v'},
      );

      final json = message.toJson();

      expect(json['type'], 'settings_sync_request');
      expect(json['version'], 1);
      expect(json['requestId'], 'r-1');
      expect(json['payload'], {'k': 'v'});
    });

    test('tryFromJson 在缺少 type / requestId / payload 任一字段时返回 null',
        () {
      // 缺 type
      expect(
        SyncMessage.tryFromJson({'requestId': 'r', 'payload': <String, dynamic>{}}),
        isNull,
      );
      // 缺 requestId
      expect(
        SyncMessage.tryFromJson({
          'type': 't',
          'payload': <String, dynamic>{},
        }),
        isNull,
      );
      // 缺 payload
      expect(
        SyncMessage.tryFromJson({'type': 't', 'requestId': 'r'}),
        isNull,
      );
      // 字段类型不符
      expect(
        SyncMessage.tryFromJson({
          'type': 123,
          'requestId': 'r',
          'payload': <String, dynamic>{},
        }),
        isNull,
      );
    });

    test('tryFromJson 在 version 缺失时默认 1', () {
      final message = SyncMessage.tryFromJson({
        'type': 't',
        'requestId': 'r',
        'payload': <String, dynamic>{},
      });

      expect(message, isNotNull);
      expect(message!.version, 1);
    });

    test('request 自动生成非空 requestId', () {
      final message = SyncMessage.request(
        type: SyncMessageType.settingsSyncRequest,
        payload: const {'categories': <String>[]},
      );

      expect(message.type, SyncMessageType.settingsSyncRequest);
      expect(message.requestId, isNotEmpty);
      expect(message.version, 1);
    });

    test('response 使用传入的 requestId', () {
      final message = SyncMessage.response(
        type: SyncMessageType.settingsSyncResponse,
        requestId: 'orig-id',
        payload: const {'data': '...'},
      );

      expect(message.type, SyncMessageType.settingsSyncResponse);
      expect(message.requestId, 'orig-id');
    });

    test('error 包含 code 和 message，type 为 error', () {
      final message = SyncMessage.error(
        requestId: 'r-1',
        code: SyncErrorCode.unknownType,
        message: '不支持的消息类型',
      );

      expect(message.type, SyncMessageType.error);
      expect(message.payload['code'], SyncErrorCode.unknownType);
      expect(message.payload['message'], '不支持的消息类型');
    });
  });

  group('SyncMessageCodec', () {
    test('encode 再 tryDecode 可还原消息', () {
      const original = SyncMessage(
        type: 'settings_sync_request',
        requestId: 'r-1',
        payload: {'categories': ['providers', 'prompts']},
      );

      final encoded = SyncMessageCodec.encode(original);
      final decoded = SyncMessageCodec.tryDecode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.type, original.type);
      expect(decoded.requestId, original.requestId);
      expect(decoded.payload, original.payload);
      expect(decoded.version, original.version);
    });

    test('tryDecode 在非法 JSON / 非 Map / 缺字段时返回 null', () {
      // 非法 JSON
      expect(SyncMessageCodec.tryDecode('not a json'), isNull);
      // 合法 JSON 但非 Map
      expect(SyncMessageCodec.tryDecode('"hello"'), isNull);
      expect(SyncMessageCodec.tryDecode('[1,2,3]'), isNull);
      // Map 但缺字段
      expect(SyncMessageCodec.tryDecode('{"type":"t"}'), isNull);
      expect(
        SyncMessageCodec.tryDecode('{"type":"t","requestId":"r"}'),
        isNull,
      );
    });
  });
}
