import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';

/// 展示给平台层的安全通知值对象。
///
/// 文案由默认深模块按固定安全文案表生成；`public*` 字段只供 Android 锁屏
/// public 副本使用，Windows adapter 明确忽略。不携带正文、推理、会话标题
/// 或原始错误；adapter 不接收收据，也不理解 generation outcome。
final class ChatGenerationSafeNotification extends Equatable {
  const ChatGenerationSafeNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.publicTitle,
    required this.publicBody,
    required this.payload,
  });

  /// 由 eventKey 稳定计算的通知 ID（FNV-1a，10000..2147483646）。
  final int id;

  /// private 通知标题。
  final String title;

  /// private 通知正文。
  final String body;

  /// Android 锁屏 public 副本标题。
  final String publicTitle;

  /// Android 锁屏 public 副本正文。
  final String publicBody;

  /// 严格 v1 JSON payload（只含 v/eventKey/conversationId 三键）。
  final String payload;

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    publicTitle,
    publicBody,
    payload,
  ];
}

/// 终态通知点击激活（payload 解码后的安全形态）。
final class ChatGenerationNotificationActivation extends Equatable {
  const ChatGenerationNotificationActivation({
    required this.eventKey,
    required this.conversationId,
  });

  /// 触发激活的通知事件键（用于 hot/pending 去重）。
  final String eventKey;

  /// 导航目标会话 ID。
  final String conversationId;

  @override
  List<Object?> get props => [eventKey, conversationId];
}

/// 平台终态通知 adapter 内部接口。
///
/// Android/Windows adapter 与 no-op 实现都只接收安全通知、只交回激活；
/// 展示/初始化失败由默认深模块 fail-open 捕获，adapter 不抛给调用者。
abstract interface class ChatGenerationTerminalNotificationAdapter {
  /// warm 激活流（通知点击时应用已在运行）。
  Stream<ChatGenerationNotificationActivation> get activations;

  /// 初始化平台通知能力；幂等性由实现保证。
  Future<void> initialize();

  /// 展示一条终态通知。
  Future<void> show(ChatGenerationSafeNotification notification);

  /// 取走一次冷启动 pending 激活（没有或已取走时为 null）。
  Future<ChatGenerationNotificationActivation?> takePendingActivation();

  /// 释放平台资源；幂等。
  Future<void> dispose();
}

/// 终态通知 payload 的严格 v1 codec。
///
/// JSON 只允许 `v` / `eventKey` / `conversationId` 三个键，UTF-8 编码后总长
/// 不超过 1024 bytes；decode 对未知版本、额外/缺失字段、错类型、超长或语法
/// 不合法的输入一律返回 null（由调用方记录固定诊断后忽略），绝不抛出。
final class ChatGenerationNotificationPayloadCodec {
  const ChatGenerationNotificationPayloadCodec();

  /// payload v1 的 UTF-8 总长度上限。
  static const maxPayloadBytes = 1024;

  /// 编码为三键 JSON；任一字段不合法或超长时返回 null。
  String? encode({required String eventKey, required String conversationId}) {
    if (!_isValidEventKey(eventKey)) return null;
    if (!_isValidConversationId(conversationId)) return null;
    final payload = jsonEncode({
      'v': 1,
      'eventKey': eventKey,
      'conversationId': conversationId,
    });
    if (utf8.encode(payload).length > maxPayloadBytes) return null;
    return payload;
  }

  /// 严格解码为激活；malformed 输入返回 null（不记录、不抛出）。
  ChatGenerationNotificationActivation? decode(String payload) {
    if (payload.isEmpty) return null;
    if (utf8.encode(payload).length > maxPayloadBytes) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded.length != 3) return null;
    if (decoded['v'] is! int || decoded['v'] != 1) return null;
    final eventKey = decoded['eventKey'];
    final conversationId = decoded['conversationId'];
    if (eventKey is! String || !_isValidEventKey(eventKey)) return null;
    if (conversationId is! String) return null;
    if (!_isValidConversationId(conversationId)) return null;
    return ChatGenerationNotificationActivation(
      eventKey: eventKey,
      conversationId: conversationId,
    );
  }

  /// eventKey 必须不超过 128 字符并完全匹配
  /// `v1:<32 位小写 hex>:<正 int64>:<已知终态种类>`。
  static bool _isValidEventKey(String eventKey) {
    if (eventKey.isEmpty || eventKey.length > 128) return false;
    final match = _eventKeyPattern.firstMatch(eventKey);
    if (match == null) return false;
    // 正 int64 上界由 int.tryParse 保证（溢出返回 null）。
    final generationId = int.tryParse(match.group(1)!);
    return generationId != null && generationId >= 1;
  }

  /// conversationId trim 后为 1..256 字符且不含控制字符。
  static bool _isValidConversationId(String conversationId) {
    for (var i = 0; i < conversationId.length; i += 1) {
      final code = conversationId.codeUnitAt(i);
      if (code < 0x20 || code == 0x7f) return false;
    }
    final trimmed = conversationId.trim();
    return trimmed.isNotEmpty && trimmed.length <= 256;
  }
}

/// eventKey 结构正则：终态种类枚举取值按声明顺序拼入，保证与收据的
/// `terminalKind.name` 一致；捕获 generation 数字段以校验 int64 上界。
final RegExp _eventKeyPattern = RegExp(
  '^v1:[0-9a-f]{32}:([1-9][0-9]*):'
  '(${ChatGenerationTerminalKind.values.map((kind) => kind.name).join('|')})\$',
);

/// 由 eventKey 的 UTF-8 bytes 计算 FNV-1a 32-bit 稳定通知 ID。
///
/// 公式（计划 5.2）：hash 初值 0x811C9DC5，逐字节
/// `hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF`，取正后映射到
/// `10000 + (positive % 2147473647)`。结果固定落在 10000..2147483646，
/// 不与 ongoing 通知 ID 4101 冲突；不使用 Dart `String.hashCode`
/// （跨进程/跨运行不稳定）。测试向量由一次性脚本独立生成后锁入测试。
int chatGenerationNotificationIdFromEventKey(String eventKey) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(eventKey)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  final positive = hash & 0x7FFFFFFF;
  return 10000 + (positive % 2147473647);
}
