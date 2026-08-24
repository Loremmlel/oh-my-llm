import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';

/// 测试固定通知 session（32 位小写十六进制）。
const _session = '000102030405060708090a0b0c0d0e0f';

/// ongoing projector 接受的全部阶段；idle 与终态一律显式拒绝。
const _ongoingPhases = [
  ChatGenerationPhase.preparing,
  ChatGenerationPhase.streaming,
  ChatGenerationPhase.retryWaiting,
  ChatGenerationPhase.stopping,
  ChatGenerationPhase.finalizing,
];

/// 构造指定阶段的 generation 快照。
ChatGenerationSnapshot _snapshot(
  ChatGenerationPhase phase, {
  int generationId = 1,
  String conversationId = 'conv-1',
  int attempt = 1,
}) {
  return ChatGenerationSnapshot(
    generationId: generationId,
    conversationId: conversationId,
    attempt: attempt,
    phase: phase,
  );
}

void main() {
  group('阶段映射', () {
    final cases =
        <
          ({
            String label,
            ChatGenerationPhase phase,
            String title,
            String text,
            ChatGenerationNotificationActionKind actionKind,
            String? actionLabel,
            String publicTitle,
            String publicText,
          })
        >[
          (
            label: '准备请求',
            phase: ChatGenerationPhase.preparing,
            title: '正在准备请求',
            text: '正在建立生成任务',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止生成',
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '流式生成',
            phase: ChatGenerationPhase.streaming,
            title: '正在生成 · 第 1 次尝试',
            text: '正文 0 字 · 推理 0 字',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止生成',
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '等待重试',
            phase: ChatGenerationPhase.retryWaiting,
            title: '请求中断',
            text: '正在等待第 1 次重试',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止重试',
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '正在停止',
            phase: ChatGenerationPhase.stopping,
            title: '正在停止',
            text: '正在停止并保存已有内容',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '正在保存',
            phase: ChatGenerationPhase.finalizing,
            title: '已接收完成',
            text: '正在保存结果 · 正文 0 字 · 推理 0 字',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
        ];

    for (final c in cases) {
      test('${c.label}阶段投影为固定文案与动作', () {
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(c.phase),
          streamingReply: null,
          notificationSessionId: _session,
        );

        expect(projection.payload.title, c.title, reason: c.label);
        expect(projection.payload.text, c.text, reason: c.label);
        expect(projection.payload.actionKind, c.actionKind, reason: c.label);
        expect(projection.payload.actionLabel, c.actionLabel, reason: c.label);
        expect(projection.payload.publicTitle, c.publicTitle, reason: c.label);
        expect(projection.payload.publicText, c.publicText, reason: c.label);
      });
    }

    test('准备请求阶段 token 使用 generationId、payload 携带会话 ID', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(
          ChatGenerationPhase.preparing,
          generationId: 7,
          conversationId: 'conv-42',
        ),
        streamingReply: null,
        notificationSessionId: _session,
      );
      expect(projection.payload.token, 7);
      expect(projection.payload.conversationId, 'conv-42');
    });

    test('流式标题使用当前 attempt', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.streaming, attempt: 3),
        streamingReply: null,
        notificationSessionId: _session,
      );
      expect(projection.payload.title, '正在生成 · 第 3 次尝试');
    });

    test('重试等待文案使用 max(1, attempt - 1)，避免显示第 0 次', () {
      for (final (attempt, expected) in [
        (1, '正在等待第 1 次重试'),
        (2, '正在等待第 1 次重试'),
        (5, '正在等待第 4 次重试'),
      ]) {
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(
            ChatGenerationPhase.retryWaiting,
            attempt: attempt,
          ),
          streamingReply: null,
          notificationSessionId: _session,
        );
        expect(projection.payload.text, expected, reason: 'attempt: $attempt');
      }
    });

    test('payload 携带按共享 codec 预编码的保护超时激活 payload', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(
          ChatGenerationPhase.preparing,
          generationId: 7,
          conversationId: 'conv-42',
        ),
        streamingReply: null,
        notificationSessionId: _session,
      );
      // eventKey 固定为 v1:<session>:<token>:foregroundProtectionTimedOut，
      // 只含 v/eventKey/conversationId 三键，供 Kotlin 在前台保护超时 fallback
      // 的 PendingIntent 中原样返回。
      expect(
        projection.payload.timeoutActivationPayload,
        '{"v":1,"eventKey":"v1:$_session:7:foregroundProtectionTimedOut",'
        '"conversationId":"conv-42"}',
      );
    });

    test('不同 session 的保护超时激活 payload 使用各自 event key', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: null,
        notificationSessionId: 'ffffffffffffffffffffffffffffffff',
      );
      expect(
        projection.payload.timeoutActivationPayload!,
        contains(
          'v1:ffffffffffffffffffffffffffffffff:1:'
          'foregroundProtectionTimedOut',
        ),
      );
    });

    test('传入 cachedTimeoutActivationPayload 时原样复用，不再重新编码', () async {
      const projector = ChatGenerationNotificationProjector();
      const session = '000102030405060708090a0b0c0d0e0f';
      const cached =
          '{"v":1,"eventKey":"v1:$session:1:foregroundProtectionTimedOut",'
          '"conversationId":"conv-1"}';
      final snapshot = ChatGenerationSnapshot(
        generationId: 1,
        conversationId: 'conv-1',
        attempt: 1,
        phase: ChatGenerationPhase.streaming,
      );
      final projection = projector.project(
        snapshot: snapshot,
        streamingReply: null,
        notificationSessionId: session,
        cachedTimeoutActivationPayload: cached,
      );
      expect(projection.payload.timeoutActivationPayload, cached);
      expect(projection.payload.token, 1);
    });
  });

  group('阶段收窄', () {
    test('idle 与全部终态阶段投影被显式拒绝，防止误启动或误清理前台服务', () {
      for (final phase in ChatGenerationPhase.values) {
        if (_ongoingPhases.contains(phase)) continue;
        expect(
          () => const ChatGenerationNotificationProjector().project(
            snapshot: _snapshot(phase),
            streamingReply: null,
            notificationSessionId: _session,
          ),
          throwsArgumentError,
          reason: '${phase.name} 不应被 ongoing projector 接受',
        );
      }
    });
  });

  group('字数统计', () {
    test('正文与推理复用聊天字数规则统计中英文并忽略 emoji', () {
      const reply = ChatStreamingReply(
        conversationId: 'conv-1',
        assistantMessageId: 'assistant-1',
        content: '你好 hello world 👨‍👩‍👧‍👦',
        reasoningContent: '🤔好 test!',
      );
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: reply,
        notificationSessionId: _session,
      );

      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 4, reasoning: 2),
      );
      expect(projection.payload.text, '正文 4 字 · 推理 2 字');
    });

    test('finalizing 沿用最后一次流式回复的字数', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        streamingReply: const ChatStreamingReply(
          conversationId: 'conv-1',
          assistantMessageId: 'assistant-1',
          content: '一二三',
          reasoningContent: '四',
        ),
        notificationSessionId: _session,
      );
      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 3, reasoning: 1),
      );
      expect(projection.payload.text, '正在保存结果 · 正文 3 字 · 推理 1 字');
    });

    test('finalizing 无流式回复时使用提供的 fallbackCounts', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        streamingReply: null,
        notificationSessionId: _session,
        fallbackCounts: const ChatGenerationCharacterCounts(
          content: 7,
          reasoning: 9,
        ),
      );
      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 7, reasoning: 9),
      );
      expect(projection.payload.text, '正在保存结果 · 正文 7 字 · 推理 9 字');
    });
  });

  group('长度上限', () {
    test('全部 ongoing 阶段标题与正文均不超过 48/120 字符簇上限', () {
      for (final phase in _ongoingPhases) {
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(phase, attempt: 9223372036854775807),
          streamingReply: null,
          notificationSessionId: _session,
          fallbackCounts: const ChatGenerationCharacterCounts(
            content: 9223372036854775807,
            reasoning: 9223372036854775807,
          ),
        );
        expect(
          projection.payload.title.characters.length,
          lessThanOrEqualTo(notificationTitleMaxCharacters),
          reason: '${phase.name} 标题超限',
        );
        expect(
          projection.payload.text.characters.length,
          lessThanOrEqualTo(notificationTextMaxCharacters),
          reason: '${phase.name} 正文超限',
        );
      }
    });

    test('最长可达标题（attempt 为 int 上限）保持原样且不超 48 上限', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(
          ChatGenerationPhase.streaming,
          attempt: 9223372036854775807,
        ),
        streamingReply: null,
        notificationSessionId: _session,
      );
      expect(projection.payload.title, '正在生成 · 第 9223372036854775807 次尝试');
      expect(projection.payload.title.characters.length, 32);
    });

    test('最长可达正文（fallbackCounts 为 int 上限）保持原样且不超 120 上限', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        streamingReply: null,
        notificationSessionId: _session,
        fallbackCounts: const ChatGenerationCharacterCounts(
          content: 9223372036854775807,
          reasoning: 9223372036854775807,
        ),
      );
      expect(
        projection.payload.text,
        '正在保存结果 · 正文 9223372036854775807 字 · 推理 9223372036854775807 字',
      );
      expect(projection.payload.text.characters.length, 60);
    });
  });
}
