import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 前台服务命令失败的固定分类。
///
/// 只表达「命令为什么没被接受」，不携带异常原文、payload 或堆栈；
/// 分类供 coordinator 做脱敏诊断与 fail-open 决策，不得转成聊天失败。
enum ChatForegroundFailureCode {
  /// 当前平台不支持前台服务（非 Android）。
  unsupportedPlatform,

  /// 原生通道不可用（engine detach、通道未注册等）。
  channelUnavailable,

  /// 单次命令等待原生 ACK 超时。
  channelTimeout,

  /// 系统拒绝前台服务启动（后台启动限制等）。
  startNotAllowed,

  /// 安全校验失败（malformed 载荷被原生拒绝等）。
  security,

  /// 原生 Service 不可用或已停止。
  serviceUnavailable,

  /// 命令携带的 token 已被新 generation 取代。
  staleToken,

  /// 载荷结构不符合协议（缺字段、错类型）。
  malformedPayload,

  /// 其他原生侧失败。
  nativeFailure,
}

/// 单次前台服务命令的结果。
final class ChatForegroundCommandResult extends Equatable {
  /// 命令被原生侧接受并实际应用（start 的 ACK 在 startForeground 之后）。
  const ChatForegroundCommandResult.accepted()
    : accepted = true,
      failureCode = null;

  /// 命令未被接受，附固定失败分类。
  const ChatForegroundCommandResult.unavailable(this.failureCode)
    : accepted = false;

  /// 命令是否被接受。
  final bool accepted;

  /// 未接受时的固定失败分类；[accepted] 为 true 时为 null。
  final ChatForegroundFailureCode? failureCode;

  @override
  List<Object?> get props => [accepted, failureCode];
}

/// 通知权限查询/请求结果。
enum ChatNotificationPermissionStatus {
  /// 平台低于 Android 13，无需通知运行时权限。
  notRequired,

  /// 已授权。
  granted,

  /// 用户拒绝。
  denied,

  /// 之前已询问过且被拒绝，不再重复弹窗。
  skippedAlreadyRequested,

  /// 平台通道不可用或 Activity 状态不允许发起请求。
  unavailable,
}

/// 通知动作的种类。
enum ChatGenerationNotificationActionKind {
  /// 无动作。
  none,

  /// 停止生成。
  stop,

  /// 打开会话。
  openConversation,
}

/// 投递给原生前台服务的脱敏通知载荷。
///
/// 所有文本字段均已由 projector 本地化、截断并脱敏；原生侧只显示这些字段，
/// 不解析任何 domain JSON。[timeoutActivationPayload] 是唯一例外：它由共享
/// Dart codec 预编码，原生侧只保存并在前台保护超时 fallback 中原样返回，
/// 同样不解析内容。
final class ChatGenerationForegroundPayload extends Equatable {
  const ChatGenerationForegroundPayload({
    required this.token,
    required this.conversationId,
    required this.title,
    required this.text,
    required this.publicTitle,
    required this.publicText,
    required this.actionKind,
    this.actionLabel,
    this.timeoutActivationPayload,
  });

  /// 当前进程内的 generation token（即 generationId），用于乱序保护。
  final int token;

  /// 通知点击导航目标的会话 ID。
  final String conversationId;

  /// 解锁后显示的通知标题（private）。
  final String title;

  /// 解锁后显示的通知正文（private）。
  final String text;

  /// 锁屏 public 版本的通知标题。
  final String publicTitle;

  /// 锁屏 public 版本的通知正文。
  final String publicText;

  /// 动作种类。
  final ChatGenerationNotificationActionKind actionKind;

  /// 动作按钮文案；[actionKind] 为 none 时为 null。
  final String? actionLabel;

  /// Dart 预编码的 foregroundProtectionTimedOut 激活 payload（严格 v1 JSON，
  /// 只含 v/eventKey/conversationId 三键且不超过 1024 UTF-8 bytes）。
  ///
  /// 由共享 codec 按 `v1:<notificationSessionId>:<token>:foregroundProtectionTimedOut`
  /// 预编码；Kotlin 只保存并在前台保护超时 fallback 的 PendingIntent 中原样
  /// 返回，不解析 event key、不复刻 JSON/session 规则。null 时原生侧按协议
  /// 不符拒绝（fail-open）。
  final String? timeoutActivationPayload;

  @override
  List<Object?> get props => [
    token,
    conversationId,
    title,
    text,
    publicTitle,
    publicText,
    actionKind,
    actionLabel,
    timeoutActivationPayload,
  ];
}

/// 来自原生通知/Service 的动作基类（sealed，穷举见各子类）。
sealed class ChatGenerationForegroundAction {
  const ChatGenerationForegroundAction();
}

/// 用户点击了「停止生成」；携带 token 供 Dart 侧校验。
final class ChatGenerationStopRequested extends ChatGenerationForegroundAction {
  const ChatGenerationStopRequested({
    required this.token,
    required this.conversationId,
  });

  final int token;
  final String conversationId;
}

/// 用户点击了 ongoing 通知，请求打开指定会话。
///
/// 只承载既有 Android ongoing 前台通知的点击直达会话契约；新终态通知的
/// 点击激活走终态通知深模块，不经本动作。
final class ChatGenerationOpenConversationRequested
    extends ChatGenerationForegroundAction {
  const ChatGenerationOpenConversationRequested(this.conversationId);

  final String conversationId;
}

/// 前台服务因平台超时（Android 15 dataSync 额度）或原生异常不再可用；
/// 报告后当前 token 不得在后台重新启动 Service。
final class ChatGenerationForegroundTimedOut
    extends ChatGenerationForegroundAction {
  const ChatGenerationForegroundTimedOut({
    required this.token,
    required this.conversationId,
  });

  final int token;
  final String conversationId;
}

/// 应用层拥有的窄平台端口：Android 由 MethodChannel adapter 实现，
/// 非 Android 绑定 no-op。
///
/// 端口方法返回可观察的成功/失败结果，但调用方不得把失败转换成聊天失败。
/// 端口不拥有 MethodChannel；[dispose] 只释放实现自身的动作转发资源，
/// 不清理 generation state，原生回调 handler 与通道的清理由共享 bridge 的
/// dispose 路径统一完成（composition 持有 bridge 生命周期）。
abstract interface class ChatGenerationForegroundServicePort {
  /// 查询并按需请求 Android 通知权限。
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission();

  /// 开始一次带唯一 [ChatGenerationForegroundPayload.token] 的前台生成。
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  );

  /// 更新当前 token 的通知投影。
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  );

  /// 所有终态与取消时移除前台通知并停止服务。
  ///
  /// 终态展示不再走前台通道：失败/空回复等普通错误通知职责已移交终态通知
  /// 端口，本端口只保留 ongoing 前台服务的清理职责。
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  });

  /// 来自通知的 stopRequested / openConversationRequested / timeout 动作。
  Stream<ChatGenerationForegroundAction> get actions;

  /// 取走一次冷启动缓存的待打开会话 ID（没有或已取走时为 null）。
  Future<String?> takePendingOpenConversation();

  /// 释放 Dart 侧通道资源；幂等。
  void dispose();
}

/// 生产端口必须由 app composition 绑定（Android adapter / no-op）。
final chatGenerationForegroundServiceProvider =
    Provider<ChatGenerationForegroundServicePort>(
      (ref) => throw UnsupportedError('聊天生成前台服务必须由 app composition 绑定'),
    );
