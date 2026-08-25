import 'dart:async';

import 'package:flutter/services.dart';

import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 单次前台服务命令等待原生 ACK 的固定上界。
///
/// 原生侧未响应（Kotlin Channel 无 handler、engine detach、死锁等）时，
/// 通道调用以 [TimeoutException] 收束并映射为 [ChatForegroundFailureCode.channelTimeout]。
const chatGenerationForegroundChannelTimeout = Duration(seconds: 2);

/// Android 生成前台服务的 MethodChannel 适配器。
///
/// 实现 [ChatGenerationForegroundServicePort]：把脱敏通知载荷按 Section 1.3
/// 协议编码为 Dart → Kotlin 方法调用，并把 Kotlin → Dart 的 stop/open/timeout
/// 回调解码为 typed action 进入 actions 流。任何通道失败（缺插件、平台异常、
/// 超时、协议不符）都映射为固定失败分类，绝不向 generation controller 抛出。
final class AndroidChatGenerationForegroundService
    implements ChatGenerationForegroundServicePort {
  AndroidChatGenerationForegroundService({
    MethodChannel? channel,
    this._commandTimeout = chatGenerationForegroundChannelTimeout,
  }) : _channel =
           channel ??
           const MethodChannel(
             'yuzu.shiki.oh_my_llm/chat_generation_foreground_service',
           ) {
    _channel.setMethodCallHandler(_handleNativeMethod);
  }

  final MethodChannel _channel;
  final Duration _commandTimeout;
  final _actions = StreamController<ChatGenerationForegroundAction>.broadcast();
  var _disposed = false;

  @override
  Stream<ChatGenerationForegroundAction> get actions => _actions.stream;

  @override
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() =>
      _invokeCommand(
        'ensureNotificationPermission',
        null,
        _decodePermissionStatus,
        (_) => ChatNotificationPermissionStatus.unavailable,
      );

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) => _invokeCommand(
    'startForegroundGeneration',
    _encodePayload(payload),
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) => _invokeCommand(
    'updateForegroundGeneration',
    _encodePayload(payload),
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) => _invokeCommand(
    'removeForegroundGeneration',
    {'token': token, 'conversationId': conversationId},
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  @override
  Future<ChatForegroundCommandResult> fail(
    ChatGenerationForegroundPayload payload,
  ) => _invokeCommand(
    'failForegroundGeneration',
    _encodePayload(payload),
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  @override
  Future<String?> takePendingOpenConversation() => _invokeCommand(
    'takePendingOpenConversation',
    null,
    _decodePendingConversationId,
    (_) => null,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // 只释放 Dart 侧 handler / stream；原生 engine detach 清理由
    // `ChatGenerationForegroundChannel.dispose()` 通知 Service 完成。
    _channel.setMethodCallHandler(null);
    _actions.close();
  }

  /// 统一的通道调用边界：捕获缺插件/平台异常/超时/其他异常并返回固定失败
  /// 分类。不记录异常原文，异常不能逃逸到调用方。
  Future<T> _invokeCommand<T>(
    String method,
    Object? arguments,
    T Function(Object? value) decode,
    T Function(ChatForegroundFailureCode code) onFailure,
  ) async {
    try {
      final value = await _channel
          .invokeMethod<Object?>(method, arguments)
          .timeout(_commandTimeout);
      return decode(value);
    } on MissingPluginException {
      return onFailure(ChatForegroundFailureCode.channelUnavailable);
    } on PlatformException {
      return onFailure(ChatForegroundFailureCode.nativeFailure);
    } on TimeoutException {
      return onFailure(ChatForegroundFailureCode.channelTimeout);
    } on Exception {
      return onFailure(ChatForegroundFailureCode.nativeFailure);
    }
  }

  /// 把脱敏载荷编码为协议 map；actionLabel 恒为键（无动作时为 null），
  /// 让原生侧不会把缺键误判为缺字段。
  Map<String, Object?> _encodePayload(ChatGenerationForegroundPayload payload) {
    return {
      'token': payload.token,
      'conversationId': payload.conversationId,
      'title': payload.title,
      'text': payload.text,
      'publicTitle': payload.publicTitle,
      'publicText': payload.publicText,
      'actionKind': payload.actionKind.name,
      'actionLabel': payload.actionLabel,
    };
  }

  /// 命令结果只解码自 Map；缺字段、错类型、未知 failureCode 一律按协议不符
  /// 处理，不做整表强转。
  ChatForegroundCommandResult _decodeCommandResult(Object? value) {
    if (value is! Map) {
      return const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.malformedPayload,
      );
    }
    if (value['accepted'] == true) {
      return const ChatForegroundCommandResult.accepted();
    }
    final failureName = value['failureCode'];
    if (failureName is String) {
      for (final code in ChatForegroundFailureCode.values) {
        if (code.name == failureName) {
          return ChatForegroundCommandResult.unavailable(code);
        }
      }
    }
    return const ChatForegroundCommandResult.unavailable(
      ChatForegroundFailureCode.malformedPayload,
    );
  }

  ChatNotificationPermissionStatus _decodePermissionStatus(Object? value) {
    if (value is! Map) {
      return ChatNotificationPermissionStatus.unavailable;
    }
    final status = value['status'];
    if (status is String) {
      for (final candidate in ChatNotificationPermissionStatus.values) {
        if (candidate.name == status) return candidate;
      }
    }
    return ChatNotificationPermissionStatus.unavailable;
  }

  String? _decodePendingConversationId(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  /// 原生回调入口：只有类型完整的 action 才加入 actions 流并返回 true；
  /// malformed / 未知方法 / 已 dispose 返回 false，原生侧收到拒绝后自行兜底。
  Future<bool> _handleNativeMethod(MethodCall call) async {
    if (_disposed) return false;
    final action = _decodeNativeAction(call);
    if (action == null) return false;
    _actions.add(action);
    return true;
  }

  /// 解码 Kotlin → Dart 回调。方法名与参数键遵循 Section 1.3；
  /// 缺字段、错类型、非正 token、空白 conversation ID、未知方法一律返回 null。
  ChatGenerationForegroundAction? _decodeNativeAction(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) return null;
    switch (call.method) {
      case 'stopRequested':
        final token = _positiveToken(arguments);
        final conversationId = _nonBlankConversationId(arguments);
        if (token == null || conversationId == null) return null;
        return ChatGenerationStopRequested(
          token: token,
          conversationId: conversationId,
        );
      case 'openConversationRequested':
        final conversationId = _nonBlankConversationId(arguments);
        if (conversationId == null) return null;
        return ChatGenerationOpenConversationRequested(conversationId);
      case 'foregroundServiceTimedOut':
        final token = _positiveToken(arguments);
        final conversationId = _nonBlankConversationId(arguments);
        if (token == null || conversationId == null) return null;
        return ChatGenerationForegroundTimedOut(
          token: token,
          conversationId: conversationId,
        );
      default:
        return null;
    }
  }

  /// 只接受正整数 token；缺字段、double、0、负数一律拒绝。
  int? _positiveToken(Map<Object?, Object?> arguments) {
    final token = arguments['token'];
    if (token is! int || token <= 0) return null;
    return token;
  }

  /// 只接受非空白 conversation ID；缺字段、空白一律拒绝。
  String? _nonBlankConversationId(Map<Object?, Object?> arguments) {
    final conversationId = arguments['conversationId'];
    if (conversationId is! String || conversationId.trim().isEmpty) {
      return null;
    }
    return conversationId;
  }
}
