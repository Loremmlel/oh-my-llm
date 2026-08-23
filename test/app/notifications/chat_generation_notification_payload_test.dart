import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';

/// 固定测试进程会话 ID（与计划 5.2 预核对向量一致）。
const _session = '000102030405060708090a0b0c0d0e0f';

/// 第二个固定 session：用于跨进程 event key/ID 隔离向量。
const _otherSession = 'ffffffffffffffffffffffffffffffff';

void main() {
  group('chatGenerationNotificationIdFromEventKey', () {
    test('固定 event key 生成固定通知 ID', () {
      // 预核对向量：由一次性脚本 logs/generate_fnv_vectors.dart 独立生成后
      // 锁入本测试；session/generation/kind 均为固定输入。
      expect(
        chatGenerationNotificationIdFromEventKey('v1:$_session:7:succeeded'),
        1672833428,
      );
      expect(
        chatGenerationNotificationIdFromEventKey(
          'v1:$_session:7:foregroundProtectionTimedOut',
        ),
        937742124,
      );
      // ID 界约束：始终落在 10000..2147483646，不与 ongoing 通知 ID 4101 冲突。
      const kinds = [
        'succeeded',
        'emptyReply',
        'failed',
        'persistenceFailed',
        'foregroundProtectionTimedOut',
      ];
      const generations = [1, 7, 9223372036854775807];
      for (final kind in kinds) {
        for (final generation in generations) {
          final id = chatGenerationNotificationIdFromEventKey(
            'v1:$_session:$generation:$kind',
          );
          expect(id, greaterThanOrEqualTo(10000));
          expect(id, lessThanOrEqualTo(2147483646));
        }
      }
    });

    test('不同进程 session 的相同终态不会复用通知 ID 向量', () {
      final keyA = 'v1:$_session:7:succeeded';
      final keyB = 'v1:$_otherSession:7:succeeded';
      // session 隔离的本质是 event key 不同；若 FNV 碰撞则只保留 event key
      // 断言并更换固定 session 向量（计划 5.2）。
      expect(keyA, isNot(keyB));
      final idA = chatGenerationNotificationIdFromEventKey(keyA);
      final idB = chatGenerationNotificationIdFromEventKey(keyB);
      expect(idA, isNot(idB));
      // 同一 generation 的保护超时与真正终态（不同 kind）也得到不同 ID。
      final timeoutId = chatGenerationNotificationIdFromEventKey(
        'v1:$_session:7:foregroundProtectionTimedOut',
      );
      expect(idA, isNot(timeoutId));
    });
  });

  group('ChatGenerationNotificationPayloadCodec', () {
    const codec = ChatGenerationNotificationPayloadCodec();
    const eventKey = 'v1:$_session:7:succeeded';

    test('payload 只包含三个允许字段', () {
      final payload = codec.encode(
        eventKey: eventKey,
        conversationId: 'conv-1',
      )!;
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'v', 'eventKey', 'conversationId'});
      expect(decoded['v'], 1);
      expect(decoded['eventKey'], eventKey);
      expect(decoded['conversationId'], 'conv-1');
      // UTF-8 编码总长不超过 1024 bytes。
      expect(utf8.encode(payload).length, lessThanOrEqualTo(1024));
      // encode/decode round-trip 交回同一激活。
      final activation = codec.decode(payload);
      expect(activation, isNotNull);
      expect(activation!.eventKey, eventKey);
      expect(activation.conversationId, 'conv-1');
    });

    test('超长 控制字符 额外字段 未知版本和 malformed payload 被忽略', () {
      // 超长：conversationId 超过 256 字符（payload 同时超过 1024 bytes）。
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': eventKey,
            'conversationId': 'a' * 257,
          }),
        ),
        isNull,
      );
      // 控制字符：NUL 与 DEL。
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': eventKey,
            'conversationId': 'a${String.fromCharCode(0)}b',
          }),
        ),
        isNull,
      );
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': eventKey,
            'conversationId': 'a${String.fromCharCode(0x7f)}b',
          }),
        ),
        isNull,
      );
      // 额外字段。
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': eventKey,
            'conversationId': 'conv-1',
            'title': 'x',
          }),
        ),
        isNull,
      );
      // 缺失字段。
      expect(codec.decode(jsonEncode({'v': 1, 'eventKey': eventKey})), isNull);
      // 未知版本与错类型版本。
      expect(
        codec.decode(
          jsonEncode({
            'v': 2,
            'eventKey': eventKey,
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      expect(
        codec.decode(
          jsonEncode({
            'v': '1',
            'eventKey': eventKey,
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      // malformed JSON / 顶层非对象 / 空串。
      expect(codec.decode('not json'), isNull);
      expect(codec.decode('{"v":1,'), isNull);
      expect(codec.decode('[1,2]'), isNull);
      expect(codec.decode('null'), isNull);
      expect(codec.decode(''), isNull);
      // eventKey 语法不合法：未知种类 / 大写 hex session / 零 generation /
      // 超出 int64 上界。
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': 'v1:$_session:7:unknownKind',
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': 'v1:${'A' * 32}:7:succeeded',
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': 'v1:$_session:0:succeeded',
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      expect(
        codec.decode(
          jsonEncode({
            'v': 1,
            'eventKey': 'v1:$_session:9223372036854775808:succeeded',
            'conversationId': 'conv-1',
          }),
        ),
        isNull,
      );
      // conversationId trim 后为空。
      expect(
        codec.decode(
          jsonEncode({'v': 1, 'eventKey': eventKey, 'conversationId': '   '}),
        ),
        isNull,
      );
    });

    test('encode 拒绝非法 event key 与会话 ID', () {
      expect(
        codec.encode(eventKey: 'not-an-event-key', conversationId: 'conv-1'),
        isNull,
      );
      expect(
        codec.encode(
          eventKey: 'v1:$_session:0:succeeded',
          conversationId: 'conv-1',
        ),
        isNull,
      );
      expect(
        codec.encode(
          eventKey: eventKey,
          conversationId: 'a${String.fromCharCode(0)}b',
        ),
        isNull,
      );
      expect(
        codec.encode(eventKey: eventKey, conversationId: 'x' * 257),
        isNull,
      );
      expect(codec.encode(eventKey: eventKey, conversationId: '   '), isNull);
    });
  });
}
