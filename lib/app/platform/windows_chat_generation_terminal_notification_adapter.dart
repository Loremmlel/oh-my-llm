import 'dart:async';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification_payload_codec.dart';

import 'windows_notification_host_client.dart';

/// Windows 终态通知展示被宿主拒绝时的固定异常。
///
/// 只表达「本次展示未成功、由终态通知深模块决定重试」，不携带平台异常原文
/// 或 payload；深模块 fail-open 捕获后记录固定诊断，绝不影响 generation。
final class WindowsTerminalNotificationShowException implements Exception {
  const WindowsTerminalNotificationShowException();

  @override
  String toString() => 'WindowsTerminalNotificationShowException';
}

/// Windows 终态通知窄 adapter。
///
/// 只接收 [ChatGenerationSafeNotification]、只交回激活；所有平台交互委托共享
/// [WindowsNotificationHostClient]，本类不创建、不安装 MethodChannel handler。
/// live 与 pending payload 都经共享严格 codec 解码后才向上交付，raw payload
/// 不离开本类；不解释 generation outcome，也不感知聊天 presentation。
///
/// dispose 只取消自身订阅并关闭自己的激活流，绝不 dispose 共享 client——
/// 共享 owner 的释放由平台 composition 的 `disposeShared` 统一完成。
final class WindowsChatGenerationTerminalNotificationAdapter
    implements ChatGenerationTerminalNotificationAdapter {
  WindowsChatGenerationTerminalNotificationAdapter({required this.client});

  final WindowsNotificationHostClient client;

  final ChatGenerationNotificationPayloadCodec _payloadCodec =
      const ChatGenerationNotificationPayloadCodec();

  final _activations =
      StreamController<ChatGenerationNotificationActivation>.broadcast();

  StreamSubscription<String>? _liveSubscription;
  bool _initialized = false;
  bool _hostAvailable = false;
  bool _disposed = false;

  @override
  Stream<ChatGenerationNotificationActivation> get activations =>
      _activations.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    // 订阅必须先于第一个 await：初始化期间到达的 warm 回调不能丢。
    _liveSubscription = client.activationPayloads.listen(
      _handleLivePayload,
      onError: (Object _, StackTrace _) {
        // 生产 client 不产生流错误；防御性吞掉以保证后续回调仍可交付。
      },
    );
    try {
      _hostAvailable = await client.getAvailable();
    } catch (_) {
      // 非 client 契约的意外失败按不可用处理，保持整体 no-op。
      _hostAvailable = false;
    }
  }

  @override
  Future<void> show(ChatGenerationSafeNotification notification) async {
    if (_disposed) return;
    // 宿主不可用时保持 no-op：不发无意义通道请求，同时以固定异常暴露给
    // 深模块记录分类并保留重试机会，而不是静默完成导致收据被去重丢弃。
    if (!_hostAvailable) {
      throw const WindowsTerminalNotificationShowException();
    }
    bool shown;
    try {
      shown = await client.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        payload: notification.payload,
      );
    } catch (_) {
      throw const WindowsTerminalNotificationShowException();
    }
    if (!shown) throw const WindowsTerminalNotificationShowException();
  }

  @override
  Future<ChatGenerationNotificationActivation?> takePendingActivation() async {
    if (_disposed || !_hostAvailable) return null;
    List<String> payloads;
    try {
      payloads = await client.takePendingActivationPayloads();
    } catch (_) {
      return null;
    }
    ChatGenerationNotificationActivation? first;
    for (final payload in payloads) {
      final activation = _payloadCodec.decode(payload);
      if (activation == null) continue;
      // 首个合法项作为冷启动返回值；其余合法项按 FIFO 发到激活流，
      // 由默认深模块按 event key 去重。
      if (first == null) {
        first = activation;
        continue;
      }
      _activations.add(activation);
    }
    return first;
  }

  /// live 回调与 pending 共用同一严格 decoder：malformed 一律静默忽略。
  void _handleLivePayload(String payload) {
    if (_disposed) return;
    final activation = _payloadCodec.decode(payload);
    if (activation == null) return;
    _activations.add(activation);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final subscription = _liveSubscription;
    _liveSubscription = null;
    await subscription?.cancel();
    await _activations.close();
    // 共享 client 只由平台 composition 的 disposeShared 释放，这里绝不调用。
  }
}
