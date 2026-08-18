import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

import '../../domain/chat_error_messages.dart';
import '../../domain/chat_word_counter.dart';
import '../ports/chat_generation_client.dart';
import '../ports/chat_generation_foreground_service.dart';
import '../sessions/chat_sessions_state.dart';
import 'chat_generation_lifecycle.dart';

/// 通知标题最大字符簇数；超限时保留 47 个字符并追加单个「…」。
const notificationTitleMaxCharacters = 48;

/// 通知正文最大字符簇数；超限时保留 119 个字符并追加单个「…」。
const notificationTextMaxCharacters = 120;

/// 终态投影后通知应如何收口。
enum ChatGenerationNotificationTerminalBehavior {
  /// 保持前台服务（ongoing 阶段）。
  ongoing,

  /// 移除通知并停止前台服务（成功/取消）。
  remove,

  /// 转普通可划掉的安全错误通知（失败/空回复/持久化失败）。
  retainError,
}

/// 正文与推理各自的聊天字数计数。
///
/// 类型名保留 CharacterCounts 以避免扩大本次修复范围；实际统计规则与
/// [countChatWords] 一致，而通知文案截断仍单独按 Unicode 字符簇处理。
final class ChatGenerationCharacterCounts extends Equatable {
  const ChatGenerationCharacterCounts({
    required this.content,
    required this.reasoning,
  });

  /// 空计数。
  static const zero = ChatGenerationCharacterCounts(content: 0, reasoning: 0);

  /// 回复正文的聊天字数。
  final int content;

  /// 推理内容的聊天字数。
  final int reasoning;

  @override
  List<Object?> get props => [content, reasoning];
}

/// 一次通知投影：脱敏载荷 + 终态行为 + 字数统计。
final class ChatGenerationNotificationProjection extends Equatable {
  const ChatGenerationNotificationProjection({
    required this.payload,
    required this.terminalBehavior,
    required this.counts,
  });

  /// 已本地化、截断、脱敏的载荷。
  final ChatGenerationForegroundPayload payload;

  /// 该阶段对应的终态收口行为。
  final ChatGenerationNotificationTerminalBehavior terminalBehavior;

  /// 本次投影使用的字数（正文/推理分开）。
  final ChatGenerationCharacterCounts counts;

  @override
  List<Object?> get props => [payload, terminalBehavior, counts];
}

/// 纯函数通知投影器：把既有 generation 快照转为脱敏通知 view model。
///
/// 不读取 Provider、不启动 Timer、不调用平台端口。所有输出文案均来自
/// 固定 allowlist 或安全计数，不携带会话标题、模型名、prompt、正文/推理
/// 片段、endpoint、host、URL、凭据或异常原文。
final class ChatGenerationNotificationProjector {
  const ChatGenerationNotificationProjector();

  /// 投影一次通知。
  ///
  /// [streamingReply] 非空时复用聊天字数规则统计正文/推理；为空时使用
  /// [fallbackCounts]（finalizing 阶段由 coordinator 传入最后一次已知字数）。
  /// [ChatGenerationPhase.idle] 不会在活跃 run 中出现，此处显式拒绝，
  /// 防止一次意外的空闲投影启动前台服务。
  ChatGenerationNotificationProjection project({
    required ChatGenerationSnapshot snapshot,
    required ChatStreamingReply? streamingReply,
    ChatGenerationCharacterCounts fallbackCounts =
        ChatGenerationCharacterCounts.zero,
  }) {
    final counts = streamingReply != null
        ? ChatGenerationCharacterCounts(
            content: countChatWords(streamingReply.content),
            reasoning: countChatWords(streamingReply.reasoningContent),
          )
        : fallbackCounts;

    final copy = _copyFor(snapshot, counts);

    return ChatGenerationNotificationProjection(
      payload: ChatGenerationForegroundPayload(
        token: snapshot.generationId,
        conversationId: snapshot.conversationId,
        title: _truncate(copy.title, notificationTitleMaxCharacters),
        text: _truncate(copy.text, notificationTextMaxCharacters),
        publicTitle: _truncate(
          copy.publicTitle,
          notificationTitleMaxCharacters,
        ),
        publicText: _truncate(copy.publicText, notificationTextMaxCharacters),
        actionKind: copy.actionKind,
        actionLabel: copy.actionLabel,
      ),
      terminalBehavior: copy.terminalBehavior,
      counts: counts,
    );
  }
}

/// 一次投影的中间文案（含 private/public 两套副本）。
typedef _NotificationCopy = ({
  String title,
  String text,
  String publicTitle,
  String publicText,
  ChatGenerationNotificationActionKind actionKind,
  String? actionLabel,
  ChatGenerationNotificationTerminalBehavior terminalBehavior,
});

/// ongoing 阶段的锁屏固定文案。
const _ongoingPublicCopy = (title: '正在生成', text: '请打开应用查看进度');

/// retain-error 阶段的锁屏固定文案。
const _errorPublicCopy = (title: '生成失败', text: '请打开应用查看');

/// 按阶段组装固定文案与动作。
///
/// succeeded/cancelled 的 payload 只为保持类型完整（Kotlin 不显示 remove
/// payload 的 title/text），public 文案沿用 ongoing 固定文案，不宣称失败。
_NotificationCopy _copyFor(
  ChatGenerationSnapshot snapshot,
  ChatGenerationCharacterCounts counts,
) {
  return switch (snapshot.phase) {
    ChatGenerationPhase.idle => throw ArgumentError.value(snapshot.phase),
    ChatGenerationPhase.preparing => (
      title: '正在准备请求',
      text: '正在建立生成任务',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止生成',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.ongoing,
    ),
    ChatGenerationPhase.streaming => (
      title: '正在生成 · 第 ${snapshot.attempt} 次尝试',
      text: '正文 ${counts.content} 字 · 推理 ${counts.reasoning} 字',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止生成',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.ongoing,
    ),
    ChatGenerationPhase.retryWaiting => (
      title: '请求中断',
      // retryWaiting 已先递增 attempt，这里用 max(1, attempt - 1) 显示第 N 次重试。
      text: '正在等待第 ${math.max(1, snapshot.attempt - 1)} 次重试',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止重试',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.ongoing,
    ),
    ChatGenerationPhase.stopping => (
      title: '正在停止',
      text: '正在停止并保存已有内容',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.ongoing,
    ),
    ChatGenerationPhase.finalizing => (
      title: '已接收完成',
      text: '正在保存结果 · 正文 ${counts.content} 字 · 推理 ${counts.reasoning} 字',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.ongoing,
    ),
    ChatGenerationPhase.succeeded => (
      title: '已完成',
      text: '已完成',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.remove,
    ),
    ChatGenerationPhase.cancelled => (
      title: '已停止',
      text: '已停止',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.remove,
    ),
    ChatGenerationPhase.emptyReply => (
      title: '生成失败',
      text: _errorTextFor(snapshot),
      publicTitle: _errorPublicCopy.title,
      publicText: _errorPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.openConversation,
      actionLabel: '查看详情',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.retainError,
    ),
    ChatGenerationPhase.failed => (
      title: '生成失败',
      text: _errorTextFor(snapshot),
      publicTitle: _errorPublicCopy.title,
      publicText: _errorPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.openConversation,
      actionLabel: '查看详情',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.retainError,
    ),
    ChatGenerationPhase.persistenceFailed => (
      title: '结果保存失败',
      text: _errorTextFor(snapshot),
      publicTitle: _errorPublicCopy.title,
      publicText: _errorPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.openConversation,
      actionLabel: '查看详情',
      terminalBehavior: ChatGenerationNotificationTerminalBehavior.retainError,
    ),
  };
}

/// 终态错误阶段的正文：只允许 allowlist 安全摘要。
///
/// 终态 phase 必有 outcome（snapshot invariant）；缺失时防御性回退到
/// 未知错误文案，绝不拼接原始异常文本。
String _errorTextFor(ChatGenerationSnapshot snapshot) {
  final outcome = snapshot.outcome;
  if (outcome == null) return '生成失败，请打开应用查看详情';
  return summarizeChatGenerationNotificationError(outcome);
}

/// 生成终态错误的通知专用安全摘要。
///
/// 只能从类型和安全元数据分类，禁止通过 `error.toString()`、responseBody、
/// apiErrorCode、uri 或 message substring 构造通知文案。
String summarizeChatGenerationNotificationError(ChatGenerationOutcome outcome) {
  if (outcome is ChatGenerationEmptyReply) return '模型返回了空回复';
  if (outcome is ChatGenerationPersistenceFailure) {
    return '回复结果未能保存，请打开应用查看';
  }
  if (outcome is! ChatGenerationFailure) {
    return '生成失败，请打开应用查看详情';
  }

  final error = outcome.error;
  if (error == ChatErrorMessages.outputRuleEmptied) return '输出处理失败';
  if (error is TimeoutException ||
      (error is ChatGenerationException && error.cause is TimeoutException)) {
    return '请求超时';
  }
  if (error is SocketException ||
      (error is ChatGenerationException && error.cause is SocketException)) {
    return '网络不可达';
  }
  if (error is ChatGenerationException) {
    return switch (error.statusCode) {
      401 => '认证失败',
      403 => '请求被拒绝',
      429 => '请求过于频繁',
      final code? when code >= 500 && code <= 599 => '服务暂时不可用',
      _ => '生成失败，请打开应用查看详情',
    };
  }
  return '生成失败，请打开应用查看详情';
}

/// 按 Unicode 字符簇截断；超限时保留 [maxCharacters] - 1 个字符并追加单个「…」。
String _truncate(String value, int maxCharacters) {
  final graphemes = value.characters;
  if (graphemes.length <= maxCharacters) return value;
  return '${graphemes.take(maxCharacters - 1)}…';
}
