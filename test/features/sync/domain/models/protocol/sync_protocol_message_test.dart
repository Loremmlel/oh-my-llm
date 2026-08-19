import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

SettingsTransferDocument _document({Map<String, Object?>? sections}) {
  return SettingsTransferDocument(sections: sections ?? const {});
}

void main() {
  group('SyncProtocolCodec', () {
    test('typed 消息 round-trip 还原同一消息且加密信封不二次 JSON 包裹 payload', () {
      const pairingRequest = PairingChallengeRequest(
        requestId: 'request',
        clientIdentity: 'client',
      );
      const encryptedRequest = EncryptedSyncRequest(
        requestId: 'request-1',
        sessionId: 'session-1',
        sessionToken: 'dG9rZW4=',
        issuedAtMs: 100,
        nonce: 'MTIzNDU2Nzg5MDEy',
        ciphertext: 'Y2lwaGVydGV4dA==',
      );
      const cases = <(String, SyncProtocolMessage)>[
        ('pairingChallengeRequest', pairingRequest),
        ('encryptedSyncRequest', encryptedRequest),
      ];
      for (final (name, message) in cases) {
        final decoded = SyncProtocolCodec.decode(
          SyncProtocolCodec.encode(message),
        );
        expect(decoded, isA<SyncProtocolDecodeSuccess>(), reason: name);
        expect(
          (decoded as SyncProtocolDecodeSuccess).message,
          message,
          reason: name,
        );
      }

      final encoded = SyncProtocolCodec.encode(encryptedRequest);
      expect(jsonDecode(encoded), isA<Map<String, dynamic>>());
      expect(encoded, isNot(contains('"data":"{')));
    });

    test('缺失版本、非法 base64、v3 和未来版本均被拒绝', () {
      final variants = [
        {
          'kind': 'pairingChallengeRequest',
          'requestId': 'r',
          'clientIdentity': 'c',
        },
        {
          'protocolVersion': 3,
          'kind': 'encryptedSyncRequest',
          'requestId': 'r',
          'sessionId': 's',
          'sessionToken': 'not base64',
          'issuedAtMs': 1,
          'nonce': 'MTIzNDU2Nzg5MDEy',
          'ciphertext': 'YQ==',
        },
        {
          'protocolVersion': 5,
          'kind': 'pairingChallengeRequest',
          'requestId': 'r',
          'clientIdentity': 'c',
        },
      ];
      for (final variant in variants) {
        expect(
          SyncProtocolCodec.decodeObject(variant).runtimeType,
          SyncProtocolDecodeFailure,
        );
      }
    });

    test('v4 设置请求编码稳定 group ID 和敏感确认位', () {
      final payload = SettingsSyncRequestPayload({
        const SettingsSyncGroupId('prompts'),
        const SettingsSyncGroupId('providers'),
      }, confirmedSensitive: true);

      final encoded = jsonDecode(SyncProtocolCodec.encodePayload(payload));
      expect(encoded, {
        'kind': 'settingsSyncRequest',
        'groups': ['prompts', 'providers'],
        'confirmedSensitive': true,
      });
      expect(
        SyncProtocolCodec.tryDecodePayload(
          SyncProtocolCodec.encodePayload(payload),
        ),
        payload,
      );
    });

    test('未知但语法有效的 group ID 留给服务端 catalog 校验', () {
      final decoded = SyncProtocolCodec.tryDecodePayload(
        jsonEncode({
          'kind': 'settingsSyncRequest',
          'groups': ['futureGroup'],
          'confirmedSensitive': false,
        }),
      );

      expect(decoded, isA<SettingsSyncRequestPayload>());
      expect((decoded as SettingsSyncRequestPayload).groups, {
        const SettingsSyncGroupId('futureGroup'),
      });
    });

    test('空 group、重复 group 和非法 group ID 被严格拒绝', () {
      for (final groups in [
        <String>[],
        ['providers', 'providers'],
        [''],
        ['-invalid'],
      ]) {
        expect(
          SyncProtocolCodec.tryDecodePayload(
            jsonEncode({
              'kind': 'settingsSyncRequest',
              'groups': groups,
              'confirmedSensitive': false,
            }),
          ),
          isNull,
          reason: groups.toString(),
        );
      }
    });

    test('v4 响应携带结构化 v9 document，不包含 snapshot.data 或二次 JSON', () {
      final payload = SettingsSyncResponsePayload(
        _document(sections: {'providerValue': 'incoming'}),
      );

      final encoded = jsonDecode(SyncProtocolCodec.encodePayload(payload));
      expect(encoded, {
        'kind': 'settingsSyncResponse',
        'document': {
          'identifier': SettingsTransferDocument.identifier,
          'formatVersion': SettingsTransferDocument.formatVersion,
          'sections': {'providerValue': 'incoming'},
        },
      });
      expect(encoded, isNot(contains('snapshot')));
      expect(encoded, isNot(contains('data')));
      expect(
        SyncProtocolCodec.tryDecodePayload(
          SyncProtocolCodec.encodePayload(payload),
        ),
        payload,
      );
    });

    test('响应 document 缺字段、错误版本或非法 section 时被拒绝', () {
      final documents = [
        {
          'identifier': SettingsTransferDocument.identifier,
          'formatVersion': SettingsTransferDocument.formatVersion,
        },
        {
          'identifier': SettingsTransferDocument.identifier,
          'formatVersion': SettingsTransferDocument.formatVersion - 1,
          'sections': <String, Object?>{},
        },
        {
          'identifier': SettingsTransferDocument.identifier,
          'formatVersion': SettingsTransferDocument.formatVersion,
          'sections': {'-invalid': true},
        },
      ];
      for (final document in documents) {
        expect(
          SyncProtocolCodec.tryDecodePayload(
            jsonEncode({'kind': 'settingsSyncResponse', 'document': document}),
          ),
          isNull,
        );
      }
      expect(
        SyncProtocolCodec.tryDecodePayload(
          jsonEncode({
            'kind': 'settingsSyncResponse',
            'snapshot': {
              'formatVersion': SettingsTransferDocument.formatVersion,
              'data': <String, Object?>{},
            },
          }),
        ),
        isNull,
      );
    });

    test('旧版顶层消息返回 public unsupportedProtocol，而不是迁移', () {
      final decoded = SyncProtocolCodec.decode(
        jsonEncode({
          'protocolVersion': 3,
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
