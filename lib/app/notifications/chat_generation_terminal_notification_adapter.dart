import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification_payload_codec.dart';

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
