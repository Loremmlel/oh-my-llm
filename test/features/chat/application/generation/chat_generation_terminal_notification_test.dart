import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';

/// 固定测试进程会话 ID（32 位小写十六进制，与计划预核对向量一致）。
const _session = '000102030405060708090a0b0c0d0e0f';

/// 构造指定阶段的 generation 快照；终态调用方自行传入匹配的 outcome。
ChatGenerationSnapshot _snapshot(
  ChatGenerationPhase phase, {
  int generationId = 1,
  String conversationId = 'conv-1',
  int attempt = 1,
  ChatGenerationOutcome? outcome,
}) {
  return ChatGenerationSnapshot(
    generationId: generationId,
    conversationId: conversationId,
    attempt: attempt,
    phase: phase,
    outcome: outcome,
  );
}

/// 组装合法收据；默认值只在成功终态下配对合法，供参数校验用例复用。
ChatGenerationTerminalReceipt _receipt({
  String notificationSessionId = _session,
  int generationId = 7,
  String conversationId = 'conv-1',
  ChatGenerationTerminalKind terminalKind =
      ChatGenerationTerminalKind.succeeded,
  int contentCount = 1,
  int reasoningCount = 0,
  ChatGenerationTerminalFailureKind failureKind =
      ChatGenerationTerminalFailureKind.none,
}) {
  return ChatGenerationTerminalReceipt(
    notificationSessionId: notificationSessionId,
    generationId: generationId,
    conversationId: conversationId,
    terminalKind: terminalKind,
    contentCount: contentCount,
    reasoningCount: reasoningCount,
    failureKind: failureKind,
  );
}

void main() {
  group('projectChatGenerationTerminalReceipt', () {
    test('成功终态生成安全计数收据', () {
      final receipt = projectChatGenerationTerminalReceipt(
        notificationSessionId: _session,
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 7,
          conversationId: 'conv-2',
          outcome: const ChatGenerationSuccess(
            generationId: 7,
            attempt: 1,
            content: '你好 hello',
            reasoningContent: '思考 test',
          ),
        ),
        counts: ChatGenerationCharacterCounts.zero,
      );

      expect(receipt, isNotNull);
      expect(receipt!.notificationSessionId, _session);
      expect(receipt.generationId, 7);
      expect(receipt.conversationId, 'conv-2');
      expect(receipt.terminalKind, ChatGenerationTerminalKind.succeeded);
      expect(receipt.failureKind, ChatGenerationTerminalFailureKind.none);
      // 你好=2 + hello=1 => 3；思考=2 + test=1 => 3。
      expect(receipt.contentCount, 3);
      expect(receipt.reasoningCount, 3);
    });

    test('成功终态从完整 outcome 计数而不使用节流 fallback', () {
      final receipt = projectChatGenerationTerminalReceipt(
        notificationSessionId: _session,
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: const ChatGenerationSuccess(
            generationId: 1,
            attempt: 1,
            content: '你好世界',
            reasoningContent: 'abc',
          ),
        ),
        // 节流 fallback 与完整 outcome 明显不同，收据必须按 outcome 重算。
        counts: const ChatGenerationCharacterCounts(
          content: 999,
          reasoning: 888,
        ),
      );

      expect(receipt!.contentCount, 4);
      expect(receipt.reasoningCount, 1);
    });

    test('空回复使用独立终态与安全分类', () {
      final receipt = projectChatGenerationTerminalReceipt(
        notificationSessionId: _session,
        snapshot: _snapshot(
          ChatGenerationPhase.emptyReply,
          outcome: const ChatGenerationEmptyReply(generationId: 1, attempt: 1),
        ),
        counts: const ChatGenerationCharacterCounts(content: 3, reasoning: 2),
      );

      expect(receipt!.terminalKind, ChatGenerationTerminalKind.emptyReply);
      expect(receipt.failureKind, ChatGenerationTerminalFailureKind.emptyReply);
      // 空回复不展示计数，沿用传入的最后安全计数。
      expect(receipt.contentCount, 3);
      expect(receipt.reasoningCount, 2);
    });

    test('最终失败按异常类型映射安全分类', () {
      final cases =
          <(Object error, ChatGenerationTerminalFailureKind expected)>[
            (
              ChatErrorMessages.outputRuleEmptied,
              ChatGenerationTerminalFailureKind.invalidOutput,
            ),
            (
              TimeoutException('SSE 空闲'),
              ChatGenerationTerminalFailureKind.timeout,
            ),
            (
              SocketException('connection refused'),
              ChatGenerationTerminalFailureKind.network,
            ),
            (
              ChatGenerationException('包装超时', cause: TimeoutException('x')),
              ChatGenerationTerminalFailureKind.timeout,
            ),
            (
              ChatGenerationException('包装网络', cause: SocketException('x')),
              ChatGenerationTerminalFailureKind.network,
            ),
            (StateError('其他'), ChatGenerationTerminalFailureKind.unknown),
          ];

      for (final (error, expected) in cases) {
        final receipt = projectChatGenerationTerminalReceipt(
          notificationSessionId: _session,
          snapshot: _snapshot(
            ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: error,
            ),
          ),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(receipt!.terminalKind, ChatGenerationTerminalKind.failed);
        expect(receipt.failureKind, expected, reason: '$error 分类不符');
      }
    });

    test('HTTP 401 403 429 和 5xx 只读取 ChatGenerationException.statusCode', () {
      final cases =
          <(int statusCode, ChatGenerationTerminalFailureKind expected)>[
            (401, ChatGenerationTerminalFailureKind.authentication),
            (403, ChatGenerationTerminalFailureKind.authorization),
            (429, ChatGenerationTerminalFailureKind.rateLimited),
            (500, ChatGenerationTerminalFailureKind.server),
            (599, ChatGenerationTerminalFailureKind.server),
          ];

      for (final (statusCode, expected) in cases) {
        final receipt = projectChatGenerationTerminalReceipt(
          notificationSessionId: _session,
          snapshot: _snapshot(
            ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              // 文本与响应体塞满误导信息，分类必须只看 statusCode。
              error: ChatGenerationException(
                '请求失败 200 OK',
                statusCode: statusCode,
                responseBody: '{"error":{"code":"rate_limit_exceeded"}}',
              ),
            ),
          ),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(receipt!.failureKind, expected, reason: 'HTTP $statusCode 分类不符');
      }
    });

    test('缺少 statusCode 且类型不可识别时统一退化为 unknown', () {
      final cases = <Object>[
        ChatGenerationException('SSE 解析错误'),
        ChatGenerationException('协议错误', cause: StateError('x')),
        StateError('未知异常'),
        FormatException('bad json'),
        // 有 statusCode 但不在已识别集合（400）同样退化为 unknown。
        ChatGenerationException('请求被拒', statusCode: 400),
      ];

      for (final error in cases) {
        final receipt = projectChatGenerationTerminalReceipt(
          notificationSessionId: _session,
          snapshot: _snapshot(
            ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: error,
            ),
          ),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(
          receipt!.failureKind,
          ChatGenerationTerminalFailureKind.unknown,
          reason: '$error 应退化为 unknown',
        );
      }
    });

    test('持久化失败不归类为普通生成失败', () {
      final receipt = projectChatGenerationTerminalReceipt(
        notificationSessionId: _session,
        snapshot: _snapshot(
          ChatGenerationPhase.persistenceFailed,
          outcome: ChatGenerationPersistenceFailure(
            generationId: 1,
            attempt: 1,
            error: StateError('写盘失败'),
          ),
        ),
        counts: const ChatGenerationCharacterCounts(content: 5, reasoning: 6),
      );

      expect(
        receipt!.terminalKind,
        ChatGenerationTerminalKind.persistenceFailed,
      );
      expect(
        receipt.failureKind,
        ChatGenerationTerminalFailureKind.persistence,
      );
      expect(receipt.contentCount, 5);
      expect(receipt.reasoningCount, 6);
    });

    test('取消和非终态不生成收据', () {
      for (final phase in ChatGenerationPhase.values) {
        if (phase == ChatGenerationPhase.succeeded ||
            phase == ChatGenerationPhase.emptyReply ||
            phase == ChatGenerationPhase.failed ||
            phase == ChatGenerationPhase.persistenceFailed) {
          continue;
        }
        final receipt = projectChatGenerationTerminalReceipt(
          notificationSessionId: _session,
          snapshot: _snapshot(
            phase,
            outcome: phase == ChatGenerationPhase.cancelled
                ? const ChatGenerationCancelled(
                    generationId: 1,
                    attempt: 1,
                    reason: ChatCancelReason.userStop,
                  )
                : null,
          ),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(receipt, isNull, reason: '${phase.name} 不应生成收据');
      }
    });
  });

  group('ChatGenerationTerminalReceipt', () {
    test('收据拒绝非法 session generation ID 会话 ID 与负计数', () {
      expect(_receipt, returnsNormally);

      // notificationSessionId 必须为 32 位小写十六进制。
      for (final bad in [
        '',
        'abc',
        '000102030405060708090a0b0c0d0e0', // 31 位
        '000102030405060708090a0b0c0d0e0f0', // 33 位
        '00010203-0405-0607-0809-0a0b0c0d0e0f', // 含连字符
        '000102030405060708090A0B0C0D0E0F', // 大写非 [0-9a-f]
      ]) {
        expect(
          () => _receipt(notificationSessionId: bad),
          throwsAssertionError,
          reason: 'session「$bad」应被拒绝',
        );
      }

      // generationId 必须为正且不超 Kotlin Long 上限。
      for (final bad in [0, -1]) {
        expect(
          () => _receipt(generationId: bad),
          throwsAssertionError,
          reason: 'generationId $bad 应被拒绝',
        );
      }
      expect(
        () => _receipt(generationId: 9223372036854775807),
        returnsNormally,
      );

      // conversationId trim 后 1..256 字符且不含控制字符。
      for (final bad in [
        '',
        '   ',
        'a\nb',
        'a${String.fromCharCode(0)}b',
        'a' * 257,
      ]) {
        expect(
          () => _receipt(conversationId: bad),
          throwsAssertionError,
          reason: 'conversationId「$bad」应被拒绝',
        );
      }

      // 负计数。
      for (final bad in [-1, -9223372036854775808]) {
        expect(() => _receipt(contentCount: bad), throwsAssertionError);
        expect(() => _receipt(reasoningCount: bad), throwsAssertionError);
      }
    });

    test('收据拒绝终态与失败分类的非法配对', () {
      // 成功终态必须配 none。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.succeeded,
          failureKind: ChatGenerationTerminalFailureKind.network,
        ),
        throwsAssertionError,
      );
      // 空回复必须配 emptyReply。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.emptyReply,
          failureKind: ChatGenerationTerminalFailureKind.none,
        ),
        throwsAssertionError,
      );
      // 持久化失败必须配 persistence。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.persistenceFailed,
          failureKind: ChatGenerationTerminalFailureKind.unknown,
        ),
        throwsAssertionError,
      );
      // 保护超时必须配 foregroundProtection。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.foregroundProtectionTimedOut,
          failureKind: ChatGenerationTerminalFailureKind.none,
        ),
        throwsAssertionError,
      );
      // failed 只能配合法失败分类，不能配 none。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.failed,
          failureKind: ChatGenerationTerminalFailureKind.none,
        ),
        throwsAssertionError,
      );
      // 合法配对可正常构造。
      expect(
        () => _receipt(
          terminalKind: ChatGenerationTerminalKind.foregroundProtectionTimedOut,
          failureKind: ChatGenerationTerminalFailureKind.foregroundProtection,
        ),
        returnsNormally,
      );
    });

    test('不同 session 的相同 generation 生成不同 event key', () {
      final a = _receipt(notificationSessionId: _session);
      final b = _receipt(
        notificationSessionId: 'ffffffffffffffffffffffffffffffff',
      );
      expect(a.eventKey, isNot(b.eventKey));
    });

    test('event key 格式固定且不携带正文', () {
      final receipt = _receipt(
        notificationSessionId: _session,
        generationId: 7,
        conversationId: 'secret-conversation',
        contentCount: 88,
        reasoningCount: 99,
      );

      expect(
        receipt.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
      expect(
        receipt.eventKey,
        matches(
          RegExp(
            r'^v1:[0-9a-f]{32}:[1-9][0-9]*:'
            r'(succeeded|emptyReply|failed|persistenceFailed|'
            r'foregroundProtectionTimedOut)$',
          ),
        ),
      );
      // 会话 ID 与计数都不应进入事件键；计数用两位数字避免与固定
      // session 的十六进制位（如 '5'、'3'）误碰撞。
      expect(receipt.eventKey, isNot(contains('secret-conversation')));
      expect(receipt.eventKey, isNot(contains('88')));
      expect(receipt.eventKey, isNot(contains('99')));
    });
  });
}
