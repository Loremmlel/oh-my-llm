import 'dart:async';

import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

import 'android_chat_generation_platform_bridge.dart';

/// Android 生成前台服务的窄 adapter（ongoing 职责）。
///
/// 实现 [ChatGenerationForegroundServicePort]：把脱敏 ongoing 载荷（含 Dart
/// 预编码的 `timeoutActivationPayload`）经共享
/// [AndroidChatGenerationPlatformBridge] 发送为命令，并把 Kotlin 的 stop/open/
/// timeout 回调合并进 [actions] 窄流。通道所有权归共享 bridge：本类不创建、
/// 不安装、不移除 MethodChannel handler。
///
/// timeout 受理语义：只在 [actions] 存在监听者时才订阅桥接的 timeout 流，让
/// 「原生 timeout 回调是否被受理」端到端如实反映给 Kotlin 的 fallback 决策；
/// stop/open 沿用既有契约，不依赖监听者存在性。
///
/// dispose 只释放自身动作转发资源；注入的共享 bridge 由 composition 统一释放，
/// 仅当 bridge 为内部自建（独立使用场景）时才随 dispose 一并释放。
final class AndroidChatGenerationForegroundService
    implements ChatGenerationForegroundServicePort {
  AndroidChatGenerationForegroundService({
    AndroidChatGenerationPlatformBridge? bridge,
  }) : bridge = bridge ?? AndroidChatGenerationPlatformBridge(),
       _ownsBridge = bridge == null {
    _actions = StreamController<ChatGenerationForegroundAction>.broadcast(
      onListen: () => _connectBridgeStreams(),
      onCancel: () => _disconnectBridgeStreams(),
    );
  }

  /// 共享平台桥；注入方负责其生命周期（composition 只在 disposeShared 释放）。
  final AndroidChatGenerationPlatformBridge bridge;
  final bool _ownsBridge;

  late final StreamController<ChatGenerationForegroundAction> _actions;
  StreamSubscription<ChatGenerationForegroundAction>? _foregroundSubscription;
  StreamSubscription<ChatGenerationForegroundTimedOut>? _timeoutSubscription;
  bool _disposed = false;

  @override
  Stream<ChatGenerationForegroundAction> get actions => _actions.stream;

  @override
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() =>
      bridge.ensureNotificationPermission();

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) => bridge.startForeground(payload);

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) => bridge.updateForeground(payload);

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) => bridge.removeForeground(token: token, conversationId: conversationId);

  @override
  Future<String?> takePendingOpenConversation() =>
      bridge.takePendingOpenConversation();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disconnectBridgeStreams();
    // 自建 bridge 归属本实例：随 dispose 一并释放；注入的共享 bridge 绝不在
    // 这里释放，避免端口各自 dispose 重复释放 shared owner。
    if (_ownsBridge) bridge.dispose();
    _actions.close();
  }

  /// 首个 actions 监听者出现时接通桥接流；保证桥接 timeout 流的 listener
  /// 存在性与本端口消费方一一对应。
  void _connectBridgeStreams() {
    if (_disposed) return;
    _foregroundSubscription ??= bridge.foregroundActions.listen(
      _actions.add,
      onError: _actions.addError,
    );
    _timeoutSubscription ??= bridge.timeoutActions.listen(
      _actions.add,
      onError: _actions.addError,
    );
  }

  /// 最后一个监听者离开或 dispose 时断开桥接流；取消是尽力而为的异步操作，
  /// 不等待其完成。
  void _disconnectBridgeStreams() {
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_timeoutSubscription?.cancel());
    _foregroundSubscription = null;
    _timeoutSubscription = null;
  }
}
