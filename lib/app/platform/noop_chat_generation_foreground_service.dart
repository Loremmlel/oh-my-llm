import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 非 Android 平台的生成前台服务 no-op。
///
/// Windows / Linux / macOS / iOS / Fuchsia 统一绑定到本类：所有命令返回
/// [ChatForegroundFailureCode.unsupportedPlatform]，权限返回 notRequired，
/// 待打开会话恒为 null，actions 永不 emit，也不发起任何 MethodChannel 调用。
/// 必须是 app/platform 里的真实类，feature application 不做条件 import。
final class NoopChatGenerationForegroundService
    implements ChatGenerationForegroundServicePort {
  @override
  Future<ChatNotificationPermissionStatus>
  ensureNotificationPermission() async =>
      ChatNotificationPermissionStatus.notRequired;

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) async => const ChatForegroundCommandResult.unavailable(
    ChatForegroundFailureCode.unsupportedPlatform,
  );

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) async => const ChatForegroundCommandResult.unavailable(
    ChatForegroundFailureCode.unsupportedPlatform,
  );

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) async => const ChatForegroundCommandResult.unavailable(
    ChatForegroundFailureCode.unsupportedPlatform,
  );

  @override
  Future<ChatForegroundCommandResult> fail(
    ChatGenerationForegroundPayload payload,
  ) async => const ChatForegroundCommandResult.unavailable(
    ChatForegroundFailureCode.unsupportedPlatform,
  );

  @override
  Stream<ChatGenerationForegroundAction> get actions => const Stream.empty();

  @override
  Future<String?> takePendingOpenConversation() async => null;

  @override
  void dispose() {}
}
