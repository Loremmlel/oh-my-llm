import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/attention/app_attention_observer.dart';
import 'package:oh_my_llm/app/attention/app_attention_state.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/notifications/terminal_notification_suppression.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';

/// completed 去重集合上限：超限只逐出最旧 completed key。
const _completedEventKeyLimit = 512;

/// in-flight 拦截集合上限：满时忽略新输入并记录固定诊断。
const _inFlightEventKeyLimit = 32;

/// 平台终态通知 adapter 绑定点。
///
/// 未被平台 composition override 时固定绑定 no-op 安全默认值，不抛「未
/// 绑定」异常；Android/Windows 真实 adapter 由 composition override。
final chatGenerationTerminalNotificationAdapterProvider =
    Provider<ChatGenerationTerminalNotificationAdapter>((ref) {
      final adapter = NoopChatGenerationTerminalNotificationAdapter();
      ref.onDispose(() => unawaited(adapter.dispose()));
      return adapter;
    });

/// 生成终态通知默认深模块。
///
/// 单一职责收敛点：收据 -> 固定安全文案/稳定 ID/payload 映射、注意力抑制、
/// report 去重（in-flight/completed）、activation 去重与恢复后导航。所有
/// 平台与注入回调错误 fail-open：不向 generation 抛出、不改写生成结果、
/// 诊断只记固定分类（不插值 payload、会话 ID 或异常文本）。
final class DefaultChatGenerationTerminalNotifications
    implements ChatGenerationTerminalNotifications {
  DefaultChatGenerationTerminalNotifications({
    required ChatGenerationTerminalNotificationAdapter adapter,
    required AppAttentionState Function() readAttention,
    required String Function() readActiveConversationId,
    required bool Function(String conversationId) conversationExists,
    required Future<void> Function() restoreHost,
    required void Function(String? conversationId) openChat,
    required void Function(String category) logDiagnostic,
  }) : _adapter = adapter,
       _readAttention = readAttention,
       _readActiveConversationId = readActiveConversationId,
       _conversationExists = conversationExists,
       _restoreHost = restoreHost,
       _openChat = openChat,
       _logDiagnostic = logDiagnostic;

  final ChatGenerationTerminalNotificationAdapter _adapter;
  final AppAttentionState Function() _readAttention;
  final String Function() _readActiveConversationId;
  final bool Function(String conversationId) _conversationExists;
  final Future<void> Function() _restoreHost;
  final void Function(String? conversationId) _openChat;
  final void Function(String category) _logDiagnostic;

  final _payloadCodec = const ChatGenerationNotificationPayloadCodec();

  // ── 生命周期与初始化 ──────────────────────────────────────

  Future<void>? _startFuture;
  bool _initializationUnavailable = false;
  bool _disposed = false;
  StreamSubscription<ChatGenerationNotificationActivation>?
  _activationSubscription;

  // ── 去重集合（completed 上限 512 / in-flight 上限 32）─────
  //
  // Dart 字面量 Set 即 insertion-ordered LinkedHashSet，completed 集合的
  // 最旧逐出依赖该插入顺序。

  /// 正在展示的 report key（并发重复拦截）。
  final Set<String> _reportingEventKeys = <String>{};

  /// 已完成的 report key（含被抑制的收据；超限逐出最旧）。
  final Set<String> _reportedEventKeys = <String>{};

  /// 正在导航的 activation key（hot/pending 并发拦截）。
  final Set<String> _activationsInFlight = <String>{};

  /// 已完成导航的 activation key（超限逐出最旧）。
  final Set<String> _activatedEventKeys = <String>{};

  /// 尚未执行的导航等待；dispose 时统一完成，避免激活流程悬挂。
  final Set<Completer<bool>> _pendingNavigations = <Completer<bool>>{};

  /// 幂等启动：订阅激活流 -> adapter 初始化 -> 消费冷启动 pending 激活。
  ///
  /// 完整初始化链保存为同一个 [_startFuture]；初始化失败以「不可用」完成
  /// （future 正常结束），保持对象可 dispose，不向 generation 抛出。
  Future<void> start() {
    final existing = _startFuture;
    if (existing != null) return existing;
    if (_disposed) {
      // 装配误用防御：dispose 后再 start 直接以已完成 future 收束，不订阅
      // 任何流、不触碰 adapter（经端口接口正常不可达）。
      return Future<void>.value();
    }
    final future = _start();
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    // 订阅必须先于第一个 await，避免初始化期间丢 warm callback。
    try {
      _activationSubscription = _adapter.activations.listen(
        _handleActivation,
        onError: (Object _, StackTrace _) {
          _logDiagnostic('terminal_activation_stream_error');
        },
      );
    } catch (_) {
      _logDiagnostic('terminal_activation_stream_error');
      _initializationUnavailable = true;
      return;
    }
    try {
      await _adapter.initialize();
    } catch (_) {
      _logDiagnostic('terminal_adapter_initialize_failed');
      _initializationUnavailable = true;
      return;
    }
    if (_disposed) return;
    ChatGenerationNotificationActivation? pending;
    try {
      pending = await _adapter.takePendingActivation();
    } catch (_) {
      _logDiagnostic('terminal_pending_activation_failed');
      return;
    }
    if (_disposed || pending == null) return;
    _handleActivation(pending);
  }

  // ── report（收据投递） ────────────────────────────────────

  @override
  Future<void> report(
    ChatGenerationTerminalReceipt receipt, {
    bool? suppressedAtTerminal,
  }) async {
    if (_disposed) return;
    // 调用时尚未显式 start：内部幂等启动，并与显式 start 共享同一个 future。
    final startFuture = _startFuture ?? start();
    await startFuture;
    if (_disposed) return;
    if (_initializationUnavailable) {
      // 初始化不可用：固定诊断后返回，绝不在插件 ready 前调用 show。
      _logDiagnostic('terminal_adapter_initialize_failed');
      return;
    }
    final eventKey = receipt.eventKey;
    if (_reportedEventKeys.contains(eventKey)) return; // 已完成重放（含抑制）。
    if (_reportingEventKeys.contains(eventKey)) return; // 并发重复拦截。
    if (_reportingEventKeys.length >= _inFlightEventKeyLimit) {
      _logDiagnostic('notification_in_flight_limit');
      return;
    }
    _reportingEventKeys.add(eventKey);
    try {
      await _deliverReceipt(
        eventKey,
        receipt,
        suppressedAtTerminal: suppressedAtTerminal,
      );
    } catch (_) {
      // 注入回调契约外抛错的兜底：fail-open，不向调用者抛出。
      _logDiagnostic('terminal_report_failed');
    } finally {
      _reportingEventKeys.remove(eventKey);
    }
  }

  Future<void> _deliverReceipt(
    String eventKey,
    ChatGenerationTerminalReceipt receipt, {
    bool? suppressedAtTerminal,
  }) async {
    // 冻结值优先：终态时刻的决策由 coordinator 冻结，执行时刻的评估只作
    // 未冻结的直接 report 调用时的回退。
    final suppressed =
        suppressedAtTerminal ?? _isSuppressed(receipt.conversationId);
    if (suppressed) {
      // 抑制也算完成：避免后续失焦时重放旧事件；抑制本身记固定诊断。
      _logDiagnostic('terminal_report_suppressed');
      _completeReport(eventKey);
      return;
    }
    final notification = _buildSafeNotification(receipt);
    if (notification == null) {
      _logDiagnostic('terminal_payload_invalid');
      return; // 不完成去重：允许未来重复 terminal snapshot 重试。
    }
    try {
      await _adapter.show(notification);
    } catch (_) {
      _logDiagnostic('terminal_notification_show_failed');
      return; // 展示失败不完成去重：允许后续重复报告重试。
    }
    if (_disposed) return;
    _completeReport(eventKey);
  }

  /// 注意力抑制：委托共享判定，避免与 app composition 冻结路径分叉。
  bool _isSuppressed(String conversationId) {
    return isTerminalNotificationSuppressed(
      attention: _readAttention(),
      // 惰性读取：仅 attentive 且 /chat 时才求值，保持既有读取契约。
      readActiveConversationId: _readActiveConversationId,
      conversationId: conversationId,
    );
  }

  /// 收据 -> 安全文案 + 稳定 ID + payload；收据 invariant 保证编码成功，
  /// 防御性失败（null）由调用方记录固定诊断后放行重试。
  ChatGenerationSafeNotification? _buildSafeNotification(
    ChatGenerationTerminalReceipt receipt,
  ) {
    final eventKey = receipt.eventKey;
    final payload = _payloadCodec.encode(
      eventKey: eventKey,
      conversationId: receipt.conversationId,
    );
    if (payload == null) return null;
    return ChatGenerationSafeNotification(
      id: chatGenerationNotificationIdFromEventKey(eventKey),
      title: _titleFor(receipt),
      body: _bodyFor(receipt),
      publicTitle: _publicTitleFor(receipt),
      publicBody: _publicBodyFor(receipt),
      payload: payload,
    );
  }

  // ── activation（点击激活与导航） ──────────────────────────

  void _handleActivation(ChatGenerationNotificationActivation activation) {
    if (_disposed) return;
    final eventKey = activation.eventKey;
    if (_activatedEventKeys.contains(eventKey)) return; // 已导航完成的重放。
    if (_activationsInFlight.contains(eventKey)) return; // hot/pending 并发。
    if (_activationsInFlight.length >= _inFlightEventKeyLimit) {
      _logDiagnostic('notification_in_flight_limit');
      return;
    }
    _activationsInFlight.add(eventKey);
    unawaited(_activate(activation));
  }

  Future<void> _activate(
    ChatGenerationNotificationActivation activation,
  ) async {
    final eventKey = activation.eventKey;
    try {
      try {
        await _restoreHost();
      } catch (_) {
        // 窗口恢复失败：只记固定诊断并放行重试，不导航、不标记完成。
        _logDiagnostic('window_restore_or_focus_failed');
        return;
      }
      if (_disposed) return;
      final navigated = await _navigateAtNextFrame(activation.conversationId);
      if (_disposed) return;
      if (navigated) {
        _completeActivation(eventKey);
      } else {
        _logDiagnostic('notification_navigation_failed');
      }
    } finally {
      _activationsInFlight.remove(eventKey);
    }
  }

  /// 注册 post-frame 回调并立即请求导航帧（空闲 scheduler 也要主动调度），
  /// 用 [Completer] 等待回调；返回导航是否成功。
  Future<bool> _navigateAtNextFrame(String conversationId) {
    final completer = Completer<bool>();
    _pendingNavigations.add(completer);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingNavigations.remove(completer);
      if (_disposed || completer.isCompleted) {
        // dispose 已完成等待（或回调迟到）：不再执行 openChat。
        if (!completer.isCompleted) completer.complete(false);
        return;
      }
      try {
        // 会话存在性必须在实际导航帧读取，不得捕获启动期快照。
        final exists = _conversationExists(conversationId);
        _openChat(exists ? conversationId : null);
        completer.complete(true);
      } catch (_) {
        completer.complete(false);
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    return completer.future;
  }

  // ── dispose ───────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 完成尚未执行的导航等待；回调稍后真正执行时因 disposed 跳过 openChat。
    for (final completer in List.of(_pendingNavigations)) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingNavigations.clear();
    final subscription = _activationSubscription;
    _activationSubscription = null;
    // 尽力而为地取消激活订阅但不等待其完成：取消返回的 future 依赖流内部
    // 异步清理链被事件循环继续排空，在没有后续帧驱动的调用点等待它会让
    // dispose 永久悬挂；订阅取消本身不持有待回收资源，真正的释放边界是
    // 下方的 adapter.dispose。
    unawaited(subscription?.cancel());
    try {
      await _adapter.dispose();
    } catch (_) {
      _logDiagnostic('terminal_adapter_dispose_failed');
    }
  }

  // ── 有界集合写入 ──────────────────────────────────────────

  void _completeReport(String eventKey) {
    _reportedEventKeys.add(eventKey);
    while (_reportedEventKeys.length > _completedEventKeyLimit) {
      _reportedEventKeys.remove(_reportedEventKeys.first);
    }
  }

  void _completeActivation(String eventKey) {
    _activatedEventKeys.add(eventKey);
    while (_activatedEventKeys.length > _completedEventKeyLimit) {
      _activatedEventKeys.remove(_activatedEventKeys.first);
    }
  }

  // ── 固定安全文案 ─────────────────────────────

  String _titleFor(ChatGenerationTerminalReceipt receipt) {
    return switch (receipt.terminalKind) {
      ChatGenerationTerminalKind.succeeded => '生成完成',
      ChatGenerationTerminalKind.emptyReply => '生成未完成',
      ChatGenerationTerminalKind.failed => '生成失败',
      ChatGenerationTerminalKind.persistenceFailed => '结果保存失败',
      ChatGenerationTerminalKind.foregroundProtectionTimedOut => '后台保护已结束',
    };
  }

  String _bodyFor(ChatGenerationTerminalReceipt receipt) {
    return switch (receipt.terminalKind) {
      ChatGenerationTerminalKind.succeeded =>
        '正文 ${receipt.contentCount} 字 · 推理 ${receipt.reasoningCount} 字',
      ChatGenerationTerminalKind.emptyReply => '模型返回了空回复',
      ChatGenerationTerminalKind.persistenceFailed => '回复结果未能保存，请打开应用查看',
      ChatGenerationTerminalKind.foregroundProtectionTimedOut => '请打开应用查看生成状态',
      ChatGenerationTerminalKind.failed => switch (receipt.failureKind) {
        ChatGenerationTerminalFailureKind.network => '网络不可达',
        ChatGenerationTerminalFailureKind.timeout => '请求超时',
        ChatGenerationTerminalFailureKind.authentication => '认证失败',
        ChatGenerationTerminalFailureKind.authorization => '请求被拒绝',
        ChatGenerationTerminalFailureKind.rateLimited => '请求过于频繁',
        ChatGenerationTerminalFailureKind.server => '服务暂时不可用',
        ChatGenerationTerminalFailureKind.invalidOutput => '输出处理失败',
        // 收据 invariant 保证 failed 不携带其余分类；防御性退化为 unknown 文案。
        _ => '请打开应用查看详情',
      },
    };
  }

  String _publicTitleFor(ChatGenerationTerminalReceipt receipt) {
    return switch (receipt.terminalKind) {
      ChatGenerationTerminalKind.succeeded => '生成完成',
      ChatGenerationTerminalKind.persistenceFailed => '结果保存失败',
      ChatGenerationTerminalKind.foregroundProtectionTimedOut => '后台保护已结束',
      ChatGenerationTerminalKind.emptyReply ||
      ChatGenerationTerminalKind.failed => '生成未完成',
    };
  }

  /// public 版本不含会话 ID、计数或失败细节；除保护超时外统一窄文案。
  String _publicBodyFor(ChatGenerationTerminalReceipt receipt) {
    return switch (receipt.terminalKind) {
      ChatGenerationTerminalKind.foregroundProtectionTimedOut => '请打开应用查看生成状态',
      _ => '请打开应用查看',
    };
  }
}

/// 默认终态通知深模块 Provider。
///
/// 依赖 [chatGenerationTerminalNotificationAdapterProvider]（平台 composition
/// 完成前为 no-op 安全默认值）。创建即幂等启动：应用根部只需 eager watch 本
/// provider，冷启动 pending 激活的消费不等首次 generation 报告。会话存在性
/// 经 `ref.read` 在导航帧读取，不在启动期捕获摘要列表快照。
final chatGenerationTerminalNotificationsProvider =
    Provider<ChatGenerationTerminalNotifications>((ref) {
      final module = DefaultChatGenerationTerminalNotifications(
        adapter: ref.watch(chatGenerationTerminalNotificationAdapterProvider),
        readAttention: () => ref.read(appAttentionStateProvider),
        readActiveConversationId: () => ref.read(activeConversationIdProvider),
        conversationExists: (conversationId) => ref
            .read(chatSessionsProvider)
            .conversationSummaries
            .any((summary) => summary.id == conversationId),
        restoreHost: () => ref.read(appWindowProvider).restoreAndFocus(),
        openChat: (conversationId) {
          final router = ref.read(appRouterProvider);
          if (conversationId == null) {
            // 会话已删除：回退聊天根页，不弹错误、不恢复数据。
            router.goNamed(AppDestination.chat.name);
            return;
          }
          router.goNamed(
            AppDestination.chat.name,
            queryParameters: {AppRouteParameter.conversationId: conversationId},
          );
        },
        logDiagnostic: (category) {
          debugPrint('[chat-generation-terminal] $category');
        },
      );
      // 与协调器 provider 的根部启动先例一致：创建即幂等 start，端口接口因此
      // 只需暴露业务能力（report），测试 fake 无需实现启动入口。
      unawaited(module.start());
      ref.onDispose(() => unawaited(module.dispose()));
      return module;
    });
