import 'package:equatable/equatable.dart';

import '../../settings/domain/models/auto_retry_settings.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_message.dart';

/// 一次 generation 的生命周期阶段。
///
/// 终态（succeeded/emptyReply/failed/cancelled/persistenceFailed）一旦进入，
/// 在下一次 command 开始时统一转入新的 [preparing]，由 coordinator 单一所有权维护，
/// 不再由散落的 clear* 布尔标志定义状态机。
///
/// 兼容投影（Task 6 将据此把 `_isBusy` / `ChatSessionsState` 旧字段改为
/// 从 phase 单向派生，禁止业务代码直接 copyWith 旧 bool 字段）：
///
/// | phase             | isStreaming | isAutoRetryWaiting | isBusy |
/// |-------------------|-------------|--------------------|--------|
/// | idle              | false       | false              | false  |
/// | preparing         | false       | false              | true   |
/// | streaming         | true        | false              | true   |
/// | stopping          | false       | false              | true   |
/// | retryWaiting      | false       | true               | true   |
/// | finalizing        | false       | false              | true   |
/// | succeeded         | false       | false              | false  |
/// | emptyReply        | false       | false              | false  |
/// | failed            | false       | false              | false  |
/// | cancelled         | false       | false              | false  |
/// | persistenceFailed | false       | false              | false  |
///
/// `stopping` 对外 `isStreaming=false`（停止按钮立即复位，防止需点两次），
/// 但 `isBusy=true` 以防新 generation 打断中断快照与持久化。
/// presentation 无需感知本枚举，仅消费上述兼容字段。
enum ChatGenerationPhase {
  idle,
  preparing,
  streaming,
  stopping,
  retryWaiting,
  finalizing,
  succeeded,
  emptyReply,
  failed,
  cancelled,
  persistenceFailed;

  /// 是否处于占用态（阻止新 generation / 会话切换 / 冲突 CRUD）。
  ///
  /// 终态 phase（succeeded/emptyReply/failed/cancelled/persistenceFailed）
  /// 在 cleanup 转回 idle 前的瞬间为 false——此时 durable save 已完成，
  /// 不会与新 generation 竞争。`finalizing` 为 attempt 终态后、durable save
  /// 完成前的窗口：对外 isStreaming/isAutoRetryWaiting 已可归 false，但
  /// generation 尚未结束，必须保持 busy 以阻止新 generation 覆盖桥接字段。
  bool get isBusy =>
      this == preparing ||
      this == streaming ||
      this == stopping ||
      this == retryWaiting ||
      this == finalizing;

  /// 是否为终态（succeeded/emptyReply/failed/cancelled/persistenceFailed）。
  ///
  /// 与 [isBusy] 互补：终态不再占用，durable save 已完成，可接受新 generation。
  /// invariant 断言据此校验：terminal phase 必有 outcome，non-terminal 不得有。
  bool get isTerminal =>
      this == succeeded ||
      this == emptyReply ||
      this == failed ||
      this == cancelled ||
      this == persistenceFailed;
}

/// generation 被取消的原因。
enum ChatCancelReason {
  /// 用户主动 stop。
  userStop,

  /// 新 generation 启动，旧 generation 被取代。
  superseded,

  /// controller dispose。
  disposed,
}

/// 一次 generation 的不可变快照，可安全放入 [ChatSessionsState]。
///
/// 不得包含 [StreamSubscription] / [Completer] / session token 等异步句柄--
/// 那些属于 coordinator 内部 handle 的私有字段。终态结果 [outcome] 不参与值相等：
/// 其类型与 [phase] 一一对应，phase 已能区分终态，避免把不可比较的原始异常拖进
/// Equatable 的 props。
class ChatGenerationSnapshot extends Equatable {
  const ChatGenerationSnapshot({
    required this.generationId,
    required this.conversationId,
    required this.attempt,
    required this.phase,
    this.assistantMessageId,
    this.cancelReason,
    this.outcome,
  });

  /// 单调递增的 generation 计数，区分不同次发送。
  final int generationId;

  /// 当前 generation 所属会话。
  final String conversationId;

  /// assistant 占位消息节点 ID；[preparing] 阶段尚未创建占位时为 null。
  final String? assistantMessageId;

  /// 当前 attempt 序号，从 1 开始。
  final int attempt;

  /// 当前阶段。
  final ChatGenerationPhase phase;

  /// 取消原因，仅 [ChatGenerationPhase.cancelled] 时非 null。
  final ChatCancelReason? cancelReason;

  /// 终态结果，进入终态后非 null。
  final ChatGenerationOutcome? outcome;

  ChatGenerationSnapshot copyWith({
    int? generationId,
    String? conversationId,
    String? assistantMessageId,
    int? attempt,
    ChatGenerationPhase? phase,
    ChatCancelReason? cancelReason,
    ChatGenerationOutcome? outcome,
  }) {
    return ChatGenerationSnapshot(
      generationId: generationId ?? this.generationId,
      conversationId: conversationId ?? this.conversationId,
      assistantMessageId: assistantMessageId ?? this.assistantMessageId,
      attempt: attempt ?? this.attempt,
      phase: phase ?? this.phase,
      cancelReason: cancelReason ?? this.cancelReason,
      outcome: outcome ?? this.outcome,
    );
  }

  @override
  List<Object?> get props => [
    generationId,
    conversationId,
    assistantMessageId,
    attempt,
    phase,
    cancelReason,
    // outcome 故意不参与值相等，见类文档。
  ];
}

/// 不可变重试策略，command 开始时从 settings 快照读取一次。
///
/// coordinator 在 retry loop 中不再 ref.read，也不依赖会话在等待期间的可变配置--
/// 等待窗口期内用户改动设置不影响当前 generation，下一次发送才生效。
class ChatRetryPolicy extends Equatable {
  const ChatRetryPolicy({
    required this.enabled,
    required this.maxRetryCount,
    required this.retryMode,
    required this.maxJitterSeconds,
    required this.retryOnAbnormalFinishReason,
    required this.retryOnTimeout,
    required this.timeout,
  });

  /// 是否启用自动重试（来自 [ChatConversation.autoRetryEnabled]）。
  final bool enabled;

  /// 最大重试次数，0 表示不限。
  final int maxRetryCount;

  /// 重试间隔模式。
  final RetryMode retryMode;

  /// 抖动上限秒数（perMinuteWindow 下为窗口内抖动，fixedInterval 下为基础间隔）。
  final int maxJitterSeconds;

  /// 异常 finish_reason 是否触发重试。
  final bool retryOnAbnormalFinishReason;

  /// SSE 空闲超时是否触发重试。
  final bool retryOnTimeout;

  /// SSE 空闲超时时长。
  final Duration timeout;

  /// 从会话开关 + 全局设置构造一次性快照。
  factory ChatRetryPolicy.fromSnapshot({
    required bool conversationAutoRetryEnabled,
    required AutoRetrySettings settings,
  }) {
    return ChatRetryPolicy(
      enabled: conversationAutoRetryEnabled,
      maxRetryCount: settings.maxRetryCount,
      retryMode: settings.retryMode,
      maxJitterSeconds: settings.maxJitterSeconds,
      retryOnAbnormalFinishReason: settings.retryOnAbnormalFinishReason,
      retryOnTimeout: settings.retryOnTimeout,
      timeout: Duration(seconds: settings.timeoutSeconds),
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    maxRetryCount,
    retryMode,
    maxJitterSeconds,
    retryOnAbnormalFinishReason,
    retryOnTimeout,
    timeout,
  ];
}

/// 一次 generation 的不可变请求。
///
/// messages 已经过 5 步拼接（检查点记忆 -> before 模板 -> 对话过滤 ->
/// beforeLatestInput 模板 -> after 模板）与 [ExcludeByIdMessageFilter] 过滤，
/// coordinator 不重新构造 prompt，也不决定 checkpoint 顺序。
class ChatGenerationRequest extends Equatable {
  const ChatGenerationRequest({
    required this.conversationId,
    required this.assistantMessageId,
    required this.modelConfig,
    required this.messages,
    required this.retryPolicy,
    this.parentMessageId,
    this.reasoningEffort,
    this.streamIdleTimeout,
    this.retryDelay,
  });

  final String conversationId;

  /// controller 预创建的 assistant 占位节点 ID。
  final String assistantMessageId;

  /// 占位节点的父消息 ID，用于校验写入归属。
  final String? parentMessageId;

  final LlmModelConfig modelConfig;

  final ReasoningEffort? reasoningEffort;

  /// 已构建完成的请求消息序列。
  final List<ChatCompletionRequestMessage> messages;

  final ChatRetryPolicy retryPolicy;

  /// SSE 空闲超时；null 表示不启用。
  final Duration? streamIdleTimeout;

  /// 测试注入的重试等待时长；null 表示按 retryPolicy 计算。
  final Duration? retryDelay;

  @override
  List<Object?> get props => [
    conversationId,
    assistantMessageId,
    parentMessageId,
    modelConfig,
    reasoningEffort,
    messages,
    retryPolicy,
    streamIdleTimeout,
    retryDelay,
  ];
}

/// generation 终态结果。
///
/// 类型与 [ChatGenerationPhase] 终态一一对应：
/// [ChatGenerationSuccess]↔[succeeded]、[ChatGenerationEmptyReply]↔[emptyReply]、
/// [ChatGenerationFailure]↔[failed]、[ChatGenerationCancelled]↔[cancelled]、
/// [ChatGenerationPersistenceFailure]↔[persistenceFailed]。携带的原始异常供
/// controller 既有 formatter 使用，不在此处格式化文案。
sealed class ChatGenerationOutcome {
  const ChatGenerationOutcome({
    required this.generationId,
    required this.attempt,
  });

  final int generationId;
  final int attempt;
}

/// 成功完成：非空内容已处理。
class ChatGenerationSuccess extends ChatGenerationOutcome {
  const ChatGenerationSuccess({
    required super.generationId,
    required super.attempt,
    required this.content,
    required this.reasoningContent,
    this.finishReason,
  });

  final String content;
  final String reasoningContent;
  final String? finishReason;
}

/// 空回复：content 与 reasoningContent 均为空。
class ChatGenerationEmptyReply extends ChatGenerationOutcome {
  const ChatGenerationEmptyReply({
    required super.generationId,
    required super.attempt,
    this.finishReason,
  });

  final String? finishReason;
}

/// 失败：流错误、retry 上限、不可重试 finish reason 或 output rule 错误。
class ChatGenerationFailure extends ChatGenerationOutcome {
  const ChatGenerationFailure({
    required super.generationId,
    required super.attempt,
    required this.error,
    this.stackTrace,
  });

  final Object error;
  final StackTrace? stackTrace;
}

/// 取消：用户 stop、retry 等待取消、旧 generation 被取代。
class ChatGenerationCancelled extends ChatGenerationOutcome {
  const ChatGenerationCancelled({
    required super.generationId,
    required super.attempt,
    required this.reason,
    this.partialContent = '',
  });

  final ChatCancelReason reason;

  /// 取消前已收到的部分内容（可能为空字符串）。
  final String partialContent;
}

/// 持久化失败：关键 save/flush Future 失败。
class ChatGenerationPersistenceFailure extends ChatGenerationOutcome {
  const ChatGenerationPersistenceFailure({
    required super.generationId,
    required super.attempt,
    required this.error,
  });

  final Object error;
}
