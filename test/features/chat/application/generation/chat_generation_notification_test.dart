import 'dart:async';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';

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

/// 终态阶段配套的典型 outcome（与 phase 一一对应，遵循 snapshot invariant）。
ChatGenerationOutcome _outcomeFor(ChatGenerationPhase phase) {
  return switch (phase) {
    ChatGenerationPhase.succeeded => const ChatGenerationSuccess(
      generationId: 1,
      attempt: 1,
      content: '好',
      reasoningContent: '',
    ),
    ChatGenerationPhase.cancelled => const ChatGenerationCancelled(
      generationId: 1,
      attempt: 1,
      reason: ChatCancelReason.userStop,
    ),
    ChatGenerationPhase.emptyReply => const ChatGenerationEmptyReply(
      generationId: 1,
      attempt: 1,
    ),
    ChatGenerationPhase.failed => ChatGenerationFailure(
      generationId: 1,
      attempt: 1,
      error: _SecretTalkingError(),
    ),
    ChatGenerationPhase.persistenceFailed => ChatGenerationPersistenceFailure(
      generationId: 1,
      attempt: 1,
      error: StateError('写盘失败'),
    ),
    _ => throw ArgumentError('非终态阶段无需 outcome：$phase'),
  };
}

/// toString 包含密钥、URL、prompt 与堆栈行样文本的恶意异常，
/// 用于验证通知摘要绝不透出原始异常文本。
final class _SecretTalkingError implements Exception {
  @override
  String toString() =>
      'Authorization: Bearer sk-secret-123 '
      'https://private.example/v1 帮我写一封辞职信 '
      'at _secret_stack.dart:42';
}

/// 把密钥、URL、prompt 与堆栈样片段塞进异常的所有信息通道，
/// 用于验证摘要器只看状态码、其他字段一律不得进入通知。
ChatGenerationException _secretFilledException({required int statusCode}) {
  return ChatGenerationException(
    '请求失败：Authorization: Bearer sk-secret-123 帮我写一封辞职信 at _secret_stack.dart:42',
    statusCode: statusCode,
    uri: Uri.parse('https://private.example/v1/chat/completions'),
    apiErrorCode: 'sk-secret-123',
    responseBody: '{"error":{"message":"帮我写一封辞职信"}} at _secret_stack.dart:42',
    cause: StateError('private.example'),
  );
}

void main() {
  group('阶段映射', () {
    final cases =
        <
          ({
            String label,
            ChatGenerationPhase phase,
            ChatGenerationOutcome? outcome,
            String title,
            String text,
            ChatGenerationNotificationActionKind actionKind,
            String? actionLabel,
            ChatGenerationNotificationTerminalBehavior terminal,
            String publicTitle,
            String publicText,
          })
        >[
          (
            label: '准备请求',
            phase: ChatGenerationPhase.preparing,
            outcome: null,
            title: '正在准备请求',
            text: '正在建立生成任务',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止生成',
            terminal: ChatGenerationNotificationTerminalBehavior.ongoing,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '流式生成',
            phase: ChatGenerationPhase.streaming,
            outcome: null,
            title: '正在生成 · 第 1 次尝试',
            text: '正文 0 字 · 推理 0 字',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止生成',
            terminal: ChatGenerationNotificationTerminalBehavior.ongoing,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '等待重试',
            phase: ChatGenerationPhase.retryWaiting,
            outcome: null,
            title: '请求中断',
            text: '正在等待第 1 次重试',
            actionKind: ChatGenerationNotificationActionKind.stop,
            actionLabel: '停止重试',
            terminal: ChatGenerationNotificationTerminalBehavior.ongoing,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '正在停止',
            phase: ChatGenerationPhase.stopping,
            outcome: null,
            title: '正在停止',
            text: '正在停止并保存已有内容',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            terminal: ChatGenerationNotificationTerminalBehavior.ongoing,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '正在保存',
            phase: ChatGenerationPhase.finalizing,
            outcome: null,
            title: '已接收完成',
            text: '正在保存结果 · 正文 0 字 · 推理 0 字',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            terminal: ChatGenerationNotificationTerminalBehavior.ongoing,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '成功完成',
            phase: ChatGenerationPhase.succeeded,
            outcome: _outcomeFor(ChatGenerationPhase.succeeded),
            title: '已完成',
            text: '已完成',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            terminal: ChatGenerationNotificationTerminalBehavior.remove,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '用户取消',
            phase: ChatGenerationPhase.cancelled,
            outcome: _outcomeFor(ChatGenerationPhase.cancelled),
            title: '已停止',
            text: '已停止',
            actionKind: ChatGenerationNotificationActionKind.none,
            actionLabel: null,
            terminal: ChatGenerationNotificationTerminalBehavior.remove,
            publicTitle: '正在生成',
            publicText: '请打开应用查看进度',
          ),
          (
            label: '空回复',
            phase: ChatGenerationPhase.emptyReply,
            outcome: _outcomeFor(ChatGenerationPhase.emptyReply),
            title: '生成失败',
            text: '模型返回了空回复',
            actionKind: ChatGenerationNotificationActionKind.openConversation,
            actionLabel: '查看详情',
            terminal: ChatGenerationNotificationTerminalBehavior.retainError,
            publicTitle: '生成失败',
            publicText: '请打开应用查看',
          ),
          (
            label: '生成失败',
            phase: ChatGenerationPhase.failed,
            outcome: _outcomeFor(ChatGenerationPhase.failed),
            title: '生成失败',
            text: '生成失败，请打开应用查看详情',
            actionKind: ChatGenerationNotificationActionKind.openConversation,
            actionLabel: '查看详情',
            terminal: ChatGenerationNotificationTerminalBehavior.retainError,
            publicTitle: '生成失败',
            publicText: '请打开应用查看',
          ),
          (
            label: '保存失败',
            phase: ChatGenerationPhase.persistenceFailed,
            outcome: _outcomeFor(ChatGenerationPhase.persistenceFailed),
            title: '结果保存失败',
            text: '回复结果未能保存，请打开应用查看',
            actionKind: ChatGenerationNotificationActionKind.openConversation,
            actionLabel: '查看详情',
            terminal: ChatGenerationNotificationTerminalBehavior.retainError,
            publicTitle: '生成失败',
            publicText: '请打开应用查看',
          ),
        ];

    for (final c in cases) {
      test('${c.label}阶段投影为固定文案、动作与终态行为', () {
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(c.phase, outcome: c.outcome),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(projection.payload.title, c.title, reason: c.label);
        expect(projection.payload.text, c.text, reason: c.label);
        expect(projection.payload.actionKind, c.actionKind, reason: c.label);
        expect(projection.payload.actionLabel, c.actionLabel, reason: c.label);
        expect(projection.terminalBehavior, c.terminal, reason: c.label);
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
        counts: ChatGenerationCharacterCounts.zero,
      );
      expect(projection.payload.token, 7);
      expect(projection.payload.conversationId, 'conv-42');
    });

    test('流式标题使用当前 attempt', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.streaming, attempt: 3),
        counts: ChatGenerationCharacterCounts.zero,
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
          counts: ChatGenerationCharacterCounts.zero,
        );
        expect(projection.payload.text, expected, reason: 'attempt: $attempt');
      }
    });
  });

  group('预计算字数', () {
    test('流式阶段使用调用方提供的正文与推理字数', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        counts: const ChatGenerationCharacterCounts(content: 4, reasoning: 2),
      );

      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 4, reasoning: 2),
      );
      expect(projection.payload.text, '正文 4 字 · 推理 2 字');
    });

    test('finalizing 使用调用方保留的最后字数', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        counts: const ChatGenerationCharacterCounts(content: 3, reasoning: 1),
      );
      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 3, reasoning: 1),
      );
      expect(projection.payload.text, '正在保存结果 · 正文 3 字 · 推理 1 字');
    });

    test('finalizing 原样使用预计算字数', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        counts: const ChatGenerationCharacterCounts(content: 7, reasoning: 9),
      );
      expect(
        projection.counts,
        const ChatGenerationCharacterCounts(content: 7, reasoning: 9),
      );
      expect(projection.payload.text, '正在保存结果 · 正文 7 字 · 推理 9 字');
    });
  });

  group('错误摘要与隐私', () {
    const secretFragments = [
      'sk-secret-123',
      'private.example',
      '帮我写一封',
      'Authorization',
      '_secret_stack.dart',
    ];

    final cases =
        <
          ({
            ChatGenerationPhase phase,
            ChatGenerationOutcome outcome,
            String expectedText,
          })
        >[
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 401),
            ),
            expectedText: '认证失败',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 403),
            ),
            expectedText: '请求被拒绝',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 429),
            ),
            expectedText: '请求过于频繁',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 500),
            ),
            expectedText: '服务暂时不可用',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 599),
            ),
            expectedText: '服务暂时不可用',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _secretFilledException(statusCode: 400),
            ),
            expectedText: '生成失败，请打开应用查看详情',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: TimeoutException('SSE 空闲'),
            ),
            expectedText: '请求超时',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: SocketException('connection refused'),
            ),
            expectedText: '网络不可达',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: ChatGenerationException(
                '被包装的超时',
                cause: TimeoutException('x'),
              ),
            ),
            expectedText: '请求超时',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: ChatGenerationException(
                '被包装的网络错误',
                cause: SocketException('x'),
              ),
            ),
            expectedText: '网络不可达',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: ChatErrorMessages.outputRuleEmptied,
            ),
            expectedText: '输出处理失败',
          ),
          (
            phase: ChatGenerationPhase.failed,
            outcome: ChatGenerationFailure(
              generationId: 1,
              attempt: 1,
              error: _SecretTalkingError(),
            ),
            expectedText: '生成失败，请打开应用查看详情',
          ),
          (
            phase: ChatGenerationPhase.emptyReply,
            outcome: const ChatGenerationEmptyReply(
              generationId: 1,
              attempt: 1,
            ),
            expectedText: '模型返回了空回复',
          ),
          (
            phase: ChatGenerationPhase.persistenceFailed,
            outcome: ChatGenerationPersistenceFailure(
              generationId: 1,
              attempt: 1,
              error: StateError('写盘失败'),
            ),
            expectedText: '回复结果未能保存，请打开应用查看',
          ),
        ];

    test('终态错误只投影 allowlist 摘要，密钥片段不得进入任何通知字段', () {
      for (final c in cases) {
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(c.phase, outcome: c.outcome),
          counts: ChatGenerationCharacterCounts.zero,
        );

        expect(
          projection.payload.text,
          c.expectedText,
          reason: '${c.outcome.runtimeType} 摘要不符',
        );
        for (final fragment in secretFragments) {
          expect(
            projection.payload.title,
            isNot(contains(fragment)),
            reason: '标题泄漏 ${c.outcome.runtimeType} 的 $fragment',
          );
          expect(
            projection.payload.text,
            isNot(contains(fragment)),
            reason: '正文泄漏 ${c.outcome.runtimeType} 的 $fragment',
          );
          expect(
            projection.payload.publicTitle,
            isNot(contains(fragment)),
            reason: 'public 标题泄漏 ${c.outcome.runtimeType} 的 $fragment',
          );
          expect(
            projection.payload.publicText,
            isNot(contains(fragment)),
            reason: 'public 正文泄漏 ${c.outcome.runtimeType} 的 $fragment',
          );
        }
      }
    });
  });

  group('长度上限', () {
    test('全部阶段标题与正文均不超过 48/120 字符簇上限', () {
      for (final phase in ChatGenerationPhase.values) {
        if (phase == ChatGenerationPhase.idle) {
          // project() 拒绝 idle，见「idle 拦截」用例。
          continue;
        }
        final projection = const ChatGenerationNotificationProjector().project(
          snapshot: _snapshot(
            phase,
            attempt: 9223372036854775807,
            outcome: phase.isTerminal ? _outcomeFor(phase) : null,
          ),
          counts: const ChatGenerationCharacterCounts(
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
        counts: ChatGenerationCharacterCounts.zero,
      );
      expect(projection.payload.title, '正在生成 · 第 9223372036854775807 次尝试');
      expect(projection.payload.title.characters.length, 32);
    });

    test('最长可达正文（预计算字数为 int 上限）保持原样且不超 120 上限', () {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        counts: const ChatGenerationCharacterCounts(
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

  test('idle 阶段投影被拒绝，防止误启动前台服务', () {
    expect(
      () => const ChatGenerationNotificationProjector().project(
        snapshot: _snapshot(ChatGenerationPhase.idle),
        counts: ChatGenerationCharacterCounts.zero,
      ),
      throwsArgumentError,
    );
  });
}
