import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_message.dart';

void main() {
  group('SyncProtocolCodec', () {
    test('v2 encrypted envelope round-trip 且无二次 JSON payload', () {
      const message = EncryptedSyncRequest(
        requestId: 'request-1',
        sessionId: 'session-1',
        sessionToken: 'dG9rZW4=',
        issuedAtMs: 100,
        nonce: 'MTIzNDU2Nzg5MDEy',
        ciphertext: 'Y2lwaGVydGV4dA==',
      );

      final encoded = SyncProtocolCodec.encode(message);
      final decoded = SyncProtocolCodec.decode(encoded);

      expect(decoded, isA<SyncProtocolDecodeSuccess>());
      expect((decoded as SyncProtocolDecodeSuccess).message, message);
      expect(jsonDecode(encoded), isA<Map<String, dynamic>>());
      expect(encoded, isNot(contains('"data":"{')));
    });

    test('缺失版本、非法 base64、未知分类和重复分类均被严格拒绝', () {
      final variants = [
        {
          'kind': 'pairingChallengeRequest',
          'requestId': 'r',
          'clientIdentity': 'c',
        },
        {
          'protocolVersion': 2,
          'kind': 'encryptedSyncRequest',
          'requestId': 'r',
          'sessionId': 's',
          'sessionToken': 'not base64',
          'issuedAtMs': 1,
          'nonce': 'MTIzNDU2Nzg5MDEy',
          'ciphertext': 'YQ==',
        },
      ];
      for (final variant in variants) {
        expect(
          SyncProtocolCodec.decodeObject(variant).runtimeType,
          SyncProtocolDecodeFailure,
        );
      }

      expect(
        SyncProtocolCodec.tryDecodePayload(
          jsonEncode({
            'kind': 'settingsSyncRequest',
            'categories': ['providers', 'providers'],
          }),
        ),
        isNull,
      );
      expect(
        SyncProtocolCodec.tryDecodePayload(
          jsonEncode({
            'kind': 'settingsSyncRequest',
            'categories': ['unknown'],
          }),
        ),
        isNull,
      );
    });

    test('v1 返回 public unsupportedProtocol，而不是迁移', () {
      final decoded = SyncProtocolCodec.decode(
        jsonEncode({
          'protocolVersion': 1,
          'kind': 'anything',
          'requestId': 'r',
        }),
      );
      expect(decoded, isA<SyncProtocolDecodeFailure>());
      expect(
        (decoded as SyncProtocolDecodeFailure).failure.code,
        SyncProtocolErrorCode.unsupportedProtocol,
      );
    });
  });
}
