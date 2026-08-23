import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';

import '../../domain/chat_error_messages.dart';
import '../../domain/chat_word_counter.dart';
import '../ports/chat_generation_client.dart';
import 'chat_generation_lifecycle.dart';
import 'chat_generation_notification.dart';

/// 生成终态的种类。
enum ChatGenerationTerminalKind {
  succeeded,
  emptyReply,
  failed,
  persistenceFailed,
  foregroundProtectionTimedOut,
}

/// 生成终态的失败分类；只表达固定安全分类，不携带异常原文或堆栈。
enum ChatGenerationTerminalFailureKind {
  none,
  emptyReply,
  network,
  timeout,
  authentication,
  authorization,
  rateLimited,
  server,
  invalidOutput,
  persistence,
  foregroundProtection,
  unknown,
}

/// 进程级通知会话 ID 必须为 32 位小写十六进制（只用于事件命名，不进入文案）。
final _notificationSessionIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// 生成终态的安全收据。
///
/// 只携带整数计数与固定安全分类，禁止携带正文、原始错误、会话标题或平台
/// 字段；供终态通知模块投递与去重，不参与任何通知文案拼接。
final class ChatGenerationTerminalReceipt extends Equatable {
  ChatGenerationTerminalReceipt({
    required this.notificationSessionId,
    required this.generationId,
    required this.conversationId,
    required this.terminalKind,
    required this.contentCount,
    required this.reasoningCount,
    required this.failureKind,
  }) : assert(
         _notificationSessionIdPattern.hasMatch(notificationSessionId),
         'notificationSessionId 必须为 32 位小写十六进制',
       ),
       assert(
         generationId >= 1 && generationId <= 9223372036854775807,
         'generationId 必须落在 1..Long 上限',
       ),
       assert(_isValidConversationId(conversationId), 'conversationId 不合法'),
       assert(contentCount >= 0, 'contentCount 不能为负'),
       assert(reasoningCount >= 0, 'reasoningCount 不能为负'),
       assert(_isValidKindPairing(terminalKind, failureKind), '终态种类与失败分类不匹配');

  /// 进程级事件命名 ID（32 位小写十六进制），不进入通知文案或日志。
  final String notificationSessionId;

  /// 单调递增的 generation 计数；传给 Kotlin Long 不溢出。
  final int generationId;

  /// 当前 generation 所属会话。
  final String conversationId;

  /// 终态种类。
  final ChatGenerationTerminalKind terminalKind;

  /// 正文聊天字数（成功终态由完整 outcome 重算，其余沿用最后安全计数）。
  final int contentCount;

  /// 推理聊天字数。
  final int reasoningCount;

  /// 终态失败分类。
  final ChatGenerationTerminalFailureKind failureKind;

  /// 固定格式事件键，供通知 ID 与去重使用；不携带任何正文或计数。
  String get eventKey =>
      'v1:$notificationSessionId:$generationId:${terminalKind.name}';

  @override
  List<Object?> get props => [
    notificationSessionId,
    generationId,
    conversationId,
    terminalKind,
    contentCount,
    reasoningCount,
    failureKind,
  ];
}

/// conversationId trim 后为 1..256 字符且不含控制字符。
bool _isValidConversationId(String value) {
  if (_hasControlCharacter(value)) return false;
  final trimmed = value.trim();
  return trimmed.isNotEmpty && trimmed.length <= 256;
}

/// 是否包含 C0 控制字符或 DEL。
bool _hasControlCharacter(String value) {
  for (var i = 0; i < value.length; i += 1) {
    final code = value.codeUnitAt(i);
    if (code < 0x20 || code == 0x7f) return true;
  }
  return false;
}

/// 终态种类与失败分类的配对约束。
bool _isValidKindPairing(
  ChatGenerationTerminalKind terminal,
  ChatGenerationTerminalFailureKind failure,
) {
  return switch (terminal) {
    ChatGenerationTerminalKind.succeeded =>
      failure == ChatGenerationTerminalFailureKind.none,
    ChatGenerationTerminalKind.emptyReply =>
      failure == ChatGenerationTerminalFailureKind.emptyReply,
    ChatGenerationTerminalKind.persistenceFailed =>
      failure == ChatGenerationTerminalFailureKind.persistence,
    ChatGenerationTerminalKind.foregroundProtectionTimedOut =>
      failure == ChatGenerationTerminalFailureKind.foregroundProtection,
    ChatGenerationTerminalKind.failed => switch (failure) {
      ChatGenerationTerminalFailureKind.network ||
      ChatGenerationTerminalFailureKind.timeout ||
      ChatGenerationTerminalFailureKind.authentication ||
      ChatGenerationTerminalFailureKind.authorization ||
      ChatGenerationTerminalFailureKind.rateLimited ||
      ChatGenerationTerminalFailureKind.server ||
      ChatGenerationTerminalFailureKind.invalidOutput ||
      ChatGenerationTerminalFailureKind.unknown => true,
      _ => false,
    },
  };
}

/// 把 generation 快照投影为终态收据；非终态/取消返回 null。
///
/// 纯函数：不读 Provider、不启动 Timer、不触达平台。成功终态不信任节流后的
/// [counts]，直接从完整 outcome 重算；其余终态沿用传入的最后安全计数。
ChatGenerationTerminalReceipt? projectChatGenerationTerminalReceipt({
  required String notificationSessionId,
  required ChatGenerationSnapshot snapshot,
  required ChatGenerationCharacterCounts counts,
}) {
  return switch (snapshot.phase) {
    ChatGenerationPhase.succeeded => _receiptForSuccess(
      notificationSessionId: notificationSessionId,
      snapshot: snapshot,
    ),
    ChatGenerationPhase.emptyReply => _receipt(
      notificationSessionId: notificationSessionId,
      snapshot: snapshot,
      counts: counts,
      terminalKind: ChatGenerationTerminalKind.emptyReply,
      failureKind: ChatGenerationTerminalFailureKind.emptyReply,
    ),
    ChatGenerationPhase.failed => _receiptForFailure(
      notificationSessionId: notificationSessionId,
      snapshot: snapshot,
      counts: counts,
    ),
    ChatGenerationPhase.persistenceFailed => _receipt(
      notificationSessionId: notificationSessionId,
      snapshot: snapshot,
      counts: counts,
      terminalKind: ChatGenerationTerminalKind.persistenceFailed,
      failureKind: ChatGenerationTerminalFailureKind.persistence,
    ),
    // 取消与全部非终态阶段不生成收据。
    ChatGenerationPhase.cancelled ||
    ChatGenerationPhase.idle ||
    ChatGenerationPhase.preparing ||
    ChatGenerationPhase.streaming ||
    ChatGenerationPhase.stopping ||
    ChatGenerationPhase.retryWaiting ||
    ChatGenerationPhase.finalizing => null,
  };
}

/// 成功终态：从完整 outcome 重算计数，不信任节流 fallback。
///
/// 终态 phase 必有 outcome（snapshot invariant）；缺失或类型不符时防御性
/// 返回 null，避免把错误计数写进收据。
ChatGenerationTerminalReceipt? _receiptForSuccess({
  required String notificationSessionId,
  required ChatGenerationSnapshot snapshot,
}) {
  final outcome = snapshot.outcome;
  if (outcome is! ChatGenerationSuccess) return null;
  return _receipt(
    notificationSessionId: notificationSessionId,
    snapshot: snapshot,
    counts: ChatGenerationCharacterCounts(
      content: countChatWords(outcome.content),
      reasoning: countChatWords(outcome.reasoningContent),
    ),
    terminalKind: ChatGenerationTerminalKind.succeeded,
    failureKind: ChatGenerationTerminalFailureKind.none,
  );
}

/// 失败终态：按既有安全类型信息分类；outcome 缺失时退化为 unknown。
ChatGenerationTerminalReceipt _receiptForFailure({
  required String notificationSessionId,
  required ChatGenerationSnapshot snapshot,
  required ChatGenerationCharacterCounts counts,
}) {
  final outcome = snapshot.outcome;
  return _receipt(
    notificationSessionId: notificationSessionId,
    snapshot: snapshot,
    counts: counts,
    terminalKind: ChatGenerationTerminalKind.failed,
    failureKind: outcome is ChatGenerationFailure
        ? _failureKindFor(outcome.error)
        : ChatGenerationTerminalFailureKind.unknown,
  );
}

/// 按快照字段组装收据。
ChatGenerationTerminalReceipt _receipt({
  required String notificationSessionId,
  required ChatGenerationSnapshot snapshot,
  required ChatGenerationCharacterCounts counts,
  required ChatGenerationTerminalKind terminalKind,
  required ChatGenerationTerminalFailureKind failureKind,
}) {
  return ChatGenerationTerminalReceipt(
    notificationSessionId: notificationSessionId,
    generationId: snapshot.generationId,
    conversationId: snapshot.conversationId,
    terminalKind: terminalKind,
    contentCount: counts.content,
    reasoningCount: counts.reasoning,
    failureKind: failureKind,
  );
}

/// 把失败阶段的原始异常映射为安全分类。
///
/// 只读取既有安全类型信息：output rule 哨兵、Timeout/Socket 类型（含包装
/// cause）与 ChatGenerationException.statusCode；绝不检查文本 substring，
/// 也不调用 error.toString()。
ChatGenerationTerminalFailureKind _failureKindFor(Object error) {
  if (error == ChatErrorMessages.outputRuleEmptied) {
    return ChatGenerationTerminalFailureKind.invalidOutput;
  }
  if (error is TimeoutException ||
      (error is ChatGenerationException && error.cause is TimeoutException)) {
    return ChatGenerationTerminalFailureKind.timeout;
  }
  if (error is SocketException ||
      (error is ChatGenerationException && error.cause is SocketException)) {
    return ChatGenerationTerminalFailureKind.network;
  }
  if (error is ChatGenerationException) {
    return switch (error.statusCode) {
      401 => ChatGenerationTerminalFailureKind.authentication,
      403 => ChatGenerationTerminalFailureKind.authorization,
      429 => ChatGenerationTerminalFailureKind.rateLimited,
      final code? when code >= 500 && code <= 599 =>
        ChatGenerationTerminalFailureKind.server,
      _ => ChatGenerationTerminalFailureKind.unknown,
    };
  }
  return ChatGenerationTerminalFailureKind.unknown;
}
