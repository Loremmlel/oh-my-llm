import 'dart:async';

import 'package:flutter/services.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// Android 生成通知共享 MethodChannel 名。
///
/// 前台服务、终态通知与系统设置三类职责共享一条通道；本名与 Kotlin
/// `ChatGenerationNotificationProtocol` 在同一原子提交内切换，不得为兼容旧
/// 通道新增双写或双 handler。
const androidChatGenerationPlatformChannelName =
    'yuzu.shiki.oh_my_llm/chat_generation_notifications';

/// 单次平台命令等待原生 ACK 的固定上界。
///
/// 原生侧未响应（Kotlin 无 handler、engine detach、死锁等）时，通道调用以
/// [TimeoutException] 收束并按各域固定分类 fail-open。
const chatGenerationPlatformCommandTimeout = Duration(seconds: 2);

/// 终态通知未被原生确认展示的固定异常。
///
/// 只表达「展示失败、由上层决定是否重试」，不携带平台异常原文或 payload；
/// 终态通知深模块捕获后记录固定诊断，绝不影响 generation。
final class AndroidTerminalNotificationShowException implements Exception {
  const AndroidTerminalNotificationShowException();

  @override
  String toString() => 'AndroidTerminalNotificationShowException';
}

/// Android 生成通知唯一 MethodChannel owner。
///
/// Flutter MethodChannel 只允许一个 Dart handler，而前台服务、终态通知与系统
/// 设置三类职责共享一条通道，因此只有本类创建通道并安装回调处理器；三个窄
/// adapter 都委托本类，不得创建第二个 handler。职责：
///
/// - Dart → Kotlin 命令统一带超时与固定失败分类（fail-open）；
/// - Kotlin → Dart 回调分发到三条互不重叠的窄流：
///   - `stopRequested` / `openConversationRequested` → [foregroundActions]
///     （既有 ongoing 点击契约）；
///   - `foregroundServiceTimedOut` → [timeoutActions]：只在流已有 listener 时
///     ACK true，否则 ACK false 让 Kotlin 直接走原生 HIGH fallback——不能用
///     「stream 存在」伪装事件已被 Dart 接收；
///   - `notificationActivated` → [terminalActivations]：无 listener 时暂存本地
///     pending 槽，由 [takePendingActivation] 取走一次，点击不丢失。
final class AndroidChatGenerationPlatformBridge {
  AndroidChatGenerationPlatformBridge({
    MethodChannel? channel,
    Duration commandTimeout = chatGenerationPlatformCommandTimeout,
  }) : _channel =
           channel ??
           const MethodChannel(androidChatGenerationPlatformChannelName),
       _commandTimeout = commandTimeout {
    _channel.setMethodCallHandler(_handleNativeMethod);
  }

  final MethodChannel _channel;
  final Duration _commandTimeout;
  final ChatGenerationNotificationPayloadCodec _payloadCodec =
      const ChatGenerationNotificationPayloadCodec();

  final _foregroundActions =
      StreamController<ChatGenerationForegroundAction>.broadcast();
  final _timeoutActions =
      StreamController<ChatGenerationForegroundTimedOut>.broadcast();
  final _terminalActivations =
      StreamController<ChatGenerationNotificationActivation>.broadcast();

  /// 无 listener 时到达的 warm 终态激活暂存槽；取走一次即清空。
  ///
  /// 冷启动 pending 由 Kotlin slot 经 wire 提供本槽之外的另一来源，两者都在
  /// [takePendingActivation] 收敛，重复投递由上游 eventKey 去重兜底。
  ChatGenerationNotificationActivation? _pendingActivation;

  bool _disposed = false;

  // ── 前台动作窄流（ongoing 契约） ───────────────────────────────────────

  /// 用户点击 ongoing 通知的停止按钮或通知本体；不含前台保护超时。
  Stream<ChatGenerationForegroundAction> get foregroundActions =>
      _foregroundActions.stream;

  /// 前台服务保护超时事件；ACK 语义依赖本流的 listener 存在性。
  Stream<ChatGenerationForegroundTimedOut> get timeoutActions =>
      _timeoutActions.stream;

  // ── 终态激活窄流 ──────────────────────────────────────────────────────

  /// 终态通知点击激活；不承载 ongoing 通知点击。
  Stream<ChatGenerationNotificationActivation> get terminalActivations =>
      _terminalActivations.stream;

  // ── 前台服务命令 ──────────────────────────────────────────────────────

  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() =>
      _invokeCommand(
        'ensureNotificationPermission',
        null,
        _decodePermissionStatus,
        (_) => ChatNotificationPermissionStatus.unavailable,
      );

  Future<ChatForegroundCommandResult> startForeground(
    ChatGenerationForegroundPayload payload,
  ) => _invokeCommand(
    'startForegroundGeneration',
    _encodeForegroundPayload(payload),
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  Future<ChatForegroundCommandResult> updateForeground(
    ChatGenerationForegroundPayload payload,
  ) => _invokeCommand(
    'updateForegroundGeneration',
    _encodeForegroundPayload(payload),
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  Future<ChatForegroundCommandResult> removeForeground({
    required int token,
    required String conversationId,
  }) => _invokeCommand(
    'removeForegroundGeneration',
    {'token': token, 'conversationId': conversationId},
    _decodeCommandResult,
    ChatForegroundCommandResult.unavailable,
  );

  Future<String?> takePendingOpenConversation() => _invokeCommand(
    'takePendingOpenConversation',
    null,
    _decodePendingConversationId,
    (_) => null,
  );

  // ── 终态通知命令 ──────────────────────────────────────────────────────

  /// 展示一条终态通知；原生确认展示后正常返回。
  ///
  /// 原生拒绝（false）、malformed 应答或任何通道失败都抛出固定的
  /// [AndroidTerminalNotificationShowException]，由终态通知深模块 fail-open
  /// 捕获并保留重试机会，不向调用方泄漏异常原文。
  Future<void> showTerminalNotification(
    ChatGenerationSafeNotification notification,
  ) async {
    final shown = await _invokeCommand<bool>(
      'showTerminalNotification',
      {
        'id': notification.id,
        'title': notification.title,
        'body': notification.body,
        'publicTitle': notification.publicTitle,
        'publicBody': notification.publicBody,
        'payload': notification.payload,
      },
      _decodeStrictBool,
      (_) => false,
    );
    if (!shown) throw const AndroidTerminalNotificationShowException();
  }

  /// 取走一次终态冷启动 pending 激活；没有或已取走时为 null。
  ///
  /// 优先消费本地暂存槽（listener 缺位时到达的 warm 激活），槽空才走 wire：
  /// `takePendingNotificationActivation` 返回 nullable activation map
  /// （`{payload: <严格 v1 JSON 字符串>}`），Kotlin 一次性 slot 保证只回一次；
  /// 外层 map 宽松读取、payload 内容经共享 codec 严格解码，malformed 一律
  /// fail-open 为 null。
  Future<ChatGenerationNotificationActivation?> takePendingActivation() async {
    final local = _pendingActivation;
    if (local != null) {
      _pendingActivation = null;
      return local;
    }
    return _invokeCommand(
      'takePendingNotificationActivation',
      null,
      _decodePendingActivation,
      (_) => null,
    );
  }

  // ── 系统设置命令 ──────────────────────────────────────────────────────

  /// 查询系统通知状态；应答为固定字符串 `enabled` / `disabled` /
  /// `unavailable`，未知值或通道失败退化为 [SystemNotificationStatus.unavailable]。
  Future<SystemNotificationStatus> getNotificationSettingsStatus() =>
      _invokeCommand(
        'getNotificationSettingsStatus',
        null,
        _decodeSettingsStatus,
        (_) => SystemNotificationStatus.unavailable,
      );

  /// 打开系统通知设置页；无法打开或通道失败时为 false，不抛错。
  Future<bool> openNotificationSettings() => _invokeCommand<bool>(
    'openNotificationSettings',
    null,
    _decodeStrictBool,
    (_) => false,
  );

  // ── 生命周期 ──────────────────────────────────────────────────────────

  /// 移除回调处理器并关闭全部窄流；幂等。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _pendingActivation = null;
    _foregroundActions.close();
    _timeoutActions.close();
    _terminalActivations.close();
  }

  // ── 命令边界 ──────────────────────────────────────────────────────────

  /// 统一的通道调用边界：捕获缺插件/平台异常/超时/其他异常并映射为固定失败
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

  /// 把脱敏 ongoing 载荷编码为协议 map；actionLabel 与 timeoutActivationPayload
  /// 恒为键（无值时为 null），让原生侧不会把缺键误判为缺字段。
  Map<String, Object?> _encodeForegroundPayload(
    ChatGenerationForegroundPayload payload,
  ) {
    return {
      'token': payload.token,
      'conversationId': payload.conversationId,
      'title': payload.title,
      'text': payload.text,
      'publicTitle': payload.publicTitle,
      'publicText': payload.publicText,
      'actionKind': payload.actionKind.name,
      'actionLabel': payload.actionLabel,
      'timeoutActivationPayload': payload.timeoutActivationPayload,
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

  /// 只接受真正的 bool；null / 数字等其他类型按失败处理。
  bool _decodeStrictBool(Object? value) => value is bool && value;

  SystemNotificationStatus _decodeSettingsStatus(Object? value) {
    switch (value) {
      case 'enabled':
        return SystemNotificationStatus.enabled;
      case 'disabled':
        return SystemNotificationStatus.disabled;
      case 'unavailable':
        return SystemNotificationStatus.unavailable;
      default:
        return SystemNotificationStatus.unavailable;
    }
  }

  ChatGenerationNotificationActivation? _decodePendingActivation(
    Object? value,
  ) {
    if (value is! Map) return null;
    final payload = value['payload'];
    if (payload is! String) return null;
    return _payloadCodec.decode(payload);
  }

  // ── 原生回调入口 ──────────────────────────────────────────────────────

  /// 只有类型完整且目标窄流可接收的回调才返回 true；malformed / 未知方法 /
  /// 已 dispose 返回 false，原生侧收到拒绝后自行兜底。
  Future<bool> _handleNativeMethod(MethodCall call) async {
    if (_disposed) return false;
    final arguments = call.arguments;
    switch (call.method) {
      case 'stopRequested':
        final stopArguments = _mapArguments(arguments);
        final stopToken = stopArguments == null
            ? null
            : _positiveToken(stopArguments);
        final stopConversationId = stopArguments == null
            ? null
            : _nonBlankConversationId(stopArguments);
        if (stopToken == null || stopConversationId == null) return false;
        _foregroundActions.add(
          ChatGenerationStopRequested(
            token: stopToken,
            conversationId: stopConversationId,
          ),
        );
        return true;
      case 'openConversationRequested':
        final openArguments = _mapArguments(arguments);
        final openConversationId = openArguments == null
            ? null
            : _nonBlankConversationId(openArguments);
        if (openConversationId == null) return false;
        _foregroundActions.add(
          ChatGenerationOpenConversationRequested(openConversationId),
        );
        return true;
      case 'foregroundServiceTimedOut':
        final timeoutArguments = _mapArguments(arguments);
        final timeoutToken = timeoutArguments == null
            ? null
            : _positiveToken(timeoutArguments);
        final timeoutConversationId = timeoutArguments == null
            ? null
            : _nonBlankConversationId(timeoutArguments);
        if (timeoutToken == null || timeoutConversationId == null) {
          return false;
        }
        // ACK 必须如实反映「Dart 有人消费」：无 listener 时交给 Kotlin 原生
        // HIGH fallback，而不是把事件丢进无人订阅的流后谎报受理。
        if (!_timeoutActions.hasListener) return false;
        _timeoutActions.add(
          ChatGenerationForegroundTimedOut(
            token: timeoutToken,
            conversationId: timeoutConversationId,
          ),
        );
        return true;
      case 'notificationActivated':
        // 回调参数是原始 payload JSON 字符串本身；经共享严格 codec 解码，
        // malformed 一律拒绝。
        if (arguments is! String || arguments.isEmpty) return false;
        final activation = _payloadCodec.decode(arguments);
        if (activation == null) return false;
        if (_terminalActivations.hasListener) {
          _terminalActivations.add(activation);
        } else {
          // 无 listener 不丢点击：暂存本地，等 takePendingActivation 取走。
          _pendingActivation = activation;
        }
        return true;
      default:
        return false;
    }
  }

  /// 回调参数必须是 map；其他形态一律拒绝。
  Map<Object?, Object?>? _mapArguments(Object? arguments) =>
      arguments is Map ? arguments : null;

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
