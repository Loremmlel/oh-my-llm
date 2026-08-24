import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';

import '../../domain/chat_word_counter.dart';
import '../ports/chat_generation_foreground_service.dart';
import '../sessions/chat_sessions_state.dart';
import 'chat_generation_lifecycle.dart';
import 'chat_generation_terminal_notification.dart';

/// 通知标题最大字符簇数；超限时保留 47 个字符并追加单个「…」。
const notificationTitleMaxCharacters = 48;

/// 通知正文最大字符簇数；超限时保留 119 个字符并追加单个「…」。
const notificationTextMaxCharacters = 120;

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

/// 一次通知投影：脱敏载荷 + 字数统计。
///
/// 只描述 ongoing 前台服务通知；终态展示由终态收据 projector 与终态通知
/// 端口负责，不再经过本投影。
final class ChatGenerationNotificationProjection extends Equatable {
  const ChatGenerationNotificationProjection({
    required this.payload,
    required this.counts,
  });

  /// 已本地化、截断、脱敏的载荷。
  final ChatGenerationForegroundPayload payload;

  /// 本次投影使用的字数（正文/推理分开）。
  final ChatGenerationCharacterCounts counts;

  @override
  List<Object?> get props => [payload, counts];
}

/// 纯函数通知投影器：把既有 generation 快照转为脱敏 ongoing 通知 view model。
///
/// 不读取 Provider、不启动 Timer、不调用平台端口。所有输出文案均来自
/// 固定 allowlist 或安全计数，不携带会话标题、模型名、prompt、正文/推理
/// 片段、endpoint、host、URL、凭据或异常原文。
final class ChatGenerationNotificationProjector {
  const ChatGenerationNotificationProjector();

  /// 投影一次 ongoing 通知。
  ///
  /// 只接受 preparing/streaming/retryWaiting/stopping/finalizing；对 idle 和
  /// 所有 terminal phase 抛 [ArgumentError]，由 coordinator 保证不会以这些
  /// 阶段调用（意外传入一律显式失败，防止误启动或误清理前台服务）。
  ///
  /// [streamingReply] 非空时复用聊天字数规则统计正文/推理；为空时使用
  /// [fallbackCounts]（finalizing 阶段由 coordinator 传入最后一次已知字数）。
  /// [notificationSessionId] 用于预编码前台保护超时的激活 payload，写入每次
  /// start/update 载荷，供原生侧在失去 Dart 通道时原样复用。
  /// [cachedTimeoutActivationPayload] 为同一 token 首次投影的编码结果：传入时
  /// 原样复用，避免每个快照都重复执行一次 codec 编码。
  ChatGenerationNotificationProjection project({
    required ChatGenerationSnapshot snapshot,
    required ChatStreamingReply? streamingReply,
    required String notificationSessionId,
    ChatGenerationCharacterCounts fallbackCounts =
        ChatGenerationCharacterCounts.zero,
    String? cachedTimeoutActivationPayload,
  }) {
    if (!_isOngoingPhase(snapshot.phase)) {
      throw ArgumentError.value(
        snapshot.phase,
        'phase',
        'ongoing projector 只接受 preparing/streaming/retryWaiting/stopping/finalizing',
      );
    }
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
        timeoutActivationPayload:
            cachedTimeoutActivationPayload ??
            const ChatGenerationNotificationPayloadCodec().encode(
              eventKey:
                  'v1:$notificationSessionId:${snapshot.generationId}:'
                  '${ChatGenerationTerminalKind.foregroundProtectionTimedOut.name}',
              conversationId: snapshot.conversationId,
            ),
      ),
      counts: counts,
    );
  }
}

/// 是否为 ongoing projector 接受的阶段；idle 与全部终态显式拒绝。
bool _isOngoingPhase(ChatGenerationPhase phase) {
  return switch (phase) {
    ChatGenerationPhase.preparing ||
    ChatGenerationPhase.streaming ||
    ChatGenerationPhase.retryWaiting ||
    ChatGenerationPhase.stopping ||
    ChatGenerationPhase.finalizing => true,
    ChatGenerationPhase.idle ||
    ChatGenerationPhase.succeeded ||
    ChatGenerationPhase.emptyReply ||
    ChatGenerationPhase.failed ||
    ChatGenerationPhase.cancelled ||
    ChatGenerationPhase.persistenceFailed => false,
  };
}

/// 一次投影的中间文案（含 private/public 两套副本）。
typedef _NotificationCopy = ({
  String title,
  String text,
  String publicTitle,
  String publicText,
  ChatGenerationNotificationActionKind actionKind,
  String? actionLabel,
});

/// ongoing 阶段的锁屏固定文案。
const _ongoingPublicCopy = (title: '正在生成', text: '请打开应用查看进度');

/// 按阶段组装固定文案与动作（只覆盖 ongoing 五个阶段）。
_NotificationCopy _copyFor(
  ChatGenerationSnapshot snapshot,
  ChatGenerationCharacterCounts counts,
) {
  return switch (snapshot.phase) {
    ChatGenerationPhase.preparing => (
      title: '正在准备请求',
      text: '正在建立生成任务',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止生成',
    ),
    ChatGenerationPhase.streaming => (
      title: '正在生成 · 第 ${snapshot.attempt} 次尝试',
      text: '正文 ${counts.content} 字 · 推理 ${counts.reasoning} 字',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止生成',
    ),
    ChatGenerationPhase.retryWaiting => (
      title: '请求中断',
      // retryWaiting 已先递增 attempt，这里用 max(1, attempt - 1) 显示第 N 次重试。
      text: '正在等待第 ${math.max(1, snapshot.attempt - 1)} 次重试',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止重试',
    ),
    ChatGenerationPhase.stopping => (
      title: '正在停止',
      text: '正在停止并保存已有内容',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
    ),
    ChatGenerationPhase.finalizing => (
      title: '已接收完成',
      text: '正在保存结果 · 正文 ${counts.content} 字 · 推理 ${counts.reasoning} 字',
      publicTitle: _ongoingPublicCopy.title,
      publicText: _ongoingPublicCopy.text,
      actionKind: ChatGenerationNotificationActionKind.none,
      actionLabel: null,
    ),
    // idle 与终态阶段已在 project() 入口显式拒绝，不会到达这里。
    ChatGenerationPhase.idle ||
    ChatGenerationPhase.succeeded ||
    ChatGenerationPhase.emptyReply ||
    ChatGenerationPhase.failed ||
    ChatGenerationPhase.cancelled ||
    ChatGenerationPhase.persistenceFailed => throw ArgumentError.value(
      snapshot.phase,
    ),
  };
}

/// 按 Unicode 字符簇截断；超限时保留 [maxCharacters] - 1 个字符并追加单个「…」。
String _truncate(String value, int maxCharacters) {
  final graphemes = value.characters;
  if (graphemes.length <= maxCharacters) return value;
  return '${graphemes.take(maxCharacters - 1)}…';
}
