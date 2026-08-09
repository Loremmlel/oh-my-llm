import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import 'chat_generation_lifecycle.dart';
import 'chat_sessions_state.dart';

/// 一次 generation 的发送命令（immutable）。
///
/// controller 在 [ChatSessionsController.sendMessage] / [editMessage] /
/// [retryLatestAssistant] 时构造，携带构建请求所需的全部上下文与重试策略
/// 快照（从 settings 一次性读取，等待窗口期内用户改动设置不影响当前 generation）。
/// [ChatGenerationRun] 据此驱动完整生命周期，不回读 Riverpod state。
class ChatGenerationCommand extends Equatable {
  const ChatGenerationCommand({
    required this.conversation,
    required this.modelConfig,
    required this.presetPrompt,
    required this.requestConversationMessages,
    required this.requestCheckpointChain,
    required this.parentMessageId,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.appliedCheckpointTitle,
    required this.retryPolicy,
    this.retryDelay,
  });

  /// 发起 generation 时的活动会话快照（含已追加的用户/编辑消息）。
  final ChatConversation conversation;

  final LlmModelConfig modelConfig;
  final PresetPrompt? presetPrompt;

  /// 经 checkpoint context 解析后的尾部消息序列。
  final List<ChatMessage> requestConversationMessages;

  /// 解析后的检查点链。
  final List<ChatCheckpoint> requestCheckpointChain;

  /// assistant 占位的父消息 ID。
  final String? parentMessageId;

  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  /// 显示在 assistant 消息上的检查点标题。
  final String appliedCheckpointTitle;

  /// 从会话开关 + 全局设置一次性读取的重试策略快照。
  final ChatRetryPolicy retryPolicy;

  /// 测试注入的重试等待时长；null 表示按 [retryPolicy] 计算。
  final Duration? retryDelay;

  @override
  List<Object?> get props => [
    conversation,
    modelConfig,
    presetPrompt,
    requestConversationMessages,
    requestCheckpointChain,
    parentMessageId,
    reasoningEnabled,
    reasoningEffort,
    appliedCheckpointTitle,
    retryPolicy,
    retryDelay,
  ];
}

/// generation 时序的唯一消费方。controller 实现此接口。
///
/// [prepare] / [completeAttempt] / [stop] 返回的 Future 由 [ChatGenerationRun]
/// await，terminal decision 与 persistence 不脱离 run 的串行控制流（不变量 3）。
/// [projectProgress] 为同步 UI 投影，保持 300ms 节流，不入串行 queue。
///
/// host 不持 phase / token / completion--那些由 run 单一拥有。host 方法每次 await
/// 前后由实现方自行验证未 dispose 且 run 仍为当前 run（不变量 9）。
abstract interface class ChatGenerationHost {
  /// 创建占位 assistant、追加到树、写 preparing state、durable pending checkpoint。
  ///
  /// 返回 durable 后的 request snapshot + run context；失败返回
  /// [ChatPrepareFailure]，run 据此进入 persistenceFailed 终态、不启动网络。
  Future<ChatPrepareResult> prepare(ChatGenerationCommand command);

  /// attempt 终态决策：复用 finishGenerationSuccess/Error + durable save。
  ///
  /// 返回 success / outputRuleFailed（已 durable）/ retry（intermediate 已
  /// durable）/ giveUp（retry 耗尽，已 durable）/ persistenceFailed。
  Future<ChatAttemptDecision> completeAttempt(ChatAttemptSnapshot attempt);

  /// 构造 stopped conversation + durable save，返回 cancelled / persistenceFailed。
  /// preparing / streaming / retryWaiting 三种 phase 统一经此落盘。
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial);

  /// chunk 与 phase 变化的 UI 投影，同步节流。run 把 [ChatGenerationSnapshot]
  /// 与 [ChatGenerationProgress.streamingReply] 交给 host 写入 state。
  void projectProgress(ChatGenerationProgress progress);
}

/// [host.prepare] 的返回。
sealed class ChatPrepareResult extends Equatable {
  const ChatPrepareResult();
}

/// prepare 成功：已 durable pending checkpoint，返回构建好的 request + run context。
class ChatPrepareSuccess extends ChatPrepareResult {
  const ChatPrepareSuccess({
    required this.request,
    required this.streamingConversation,
    required this.assistantMessage,
    required this.streamingReply,
  });

  final ChatGenerationLifecycleRequest request;

  /// 含占位 assistant 的会话快照（isStreaming=true）。
  final ChatConversation streamingConversation;
  final ChatMessage assistantMessage;
  final ChatStreamingReply streamingReply;

  @override
  List<Object?> get props => [
    request,
    streamingConversation,
    assistantMessage,
    streamingReply,
  ];
}

/// prepare 失败：pending checkpoint durable save 失败。run 据此进入 persistenceFailed。
class ChatPrepareFailure extends ChatPrepareResult {
  const ChatPrepareFailure(this.error);

  final Object error;

  @override
  List<Object?> get props => [error];
}

/// 传给 [host.completeAttempt] 的 attempt 终态快照。
class ChatAttemptSnapshot extends Equatable {
  const ChatAttemptSnapshot({
    required this.generationId,
    required this.attempt,
    required this.attemptOutcome,
    required this.streamingConversation,
    required this.assistantMessage,
    required this.streamingReply,
    required this.retryPolicy,
  });

  final int generationId;
  final int attempt;

  /// 本次 attempt 的终态结果（[ChatGenerationSuccess] /
  /// [ChatGenerationEmptyReply] / [ChatGenerationFailure]）。
  final ChatGenerationOutcome attemptOutcome;

  final ChatConversation streamingConversation;
  final ChatMessage assistantMessage;
  final ChatStreamingReply streamingReply;
  final ChatRetryPolicy retryPolicy;

  @override
  List<Object?> get props => [
    generationId,
    attempt,
    attemptOutcome,
    streamingConversation,
    assistantMessage,
    streamingReply,
    retryPolicy,
  ];
}

/// [host.completeAttempt] 的返回决策。
sealed class ChatAttemptDecision extends Equatable {
  const ChatAttemptDecision();
}

/// 成功终态：已 durable，conversation 为最终会话。run 进 succeeded。
class ChatAttemptSucceed extends ChatAttemptDecision {
  const ChatAttemptSucceed(this.conversation);

  final ChatConversation conversation;

  @override
  List<Object?> get props => [conversation];
}

/// 输出规则清空正文：已 durable，终态 failed。outcome 为 Failure（outputRule）。
class ChatAttemptOutputRuleFailed extends ChatAttemptDecision {
  const ChatAttemptOutputRuleFailed(this.conversation, this.outcome);

  final ChatConversation conversation;
  final ChatGenerationFailure outcome;

  @override
  List<Object?> get props => [conversation, outcome];
}

/// 重试信号：intermediate 已 durable，等待下一 attempt。run 调度 retry timer。
class ChatAttemptRetry extends ChatAttemptDecision {
  const ChatAttemptRetry();

  @override
  List<Object?> get props => const [];
}

/// retry 耗尽：已 durable intermediate，终态为 [terminalOutcome]。
/// host 负责异常 finish（Success）-> Failure 的转换。
class ChatAttemptGiveUp extends ChatAttemptDecision {
  const ChatAttemptGiveUp(this.terminalOutcome);

  final ChatGenerationOutcome terminalOutcome;

  @override
  List<Object?> get props => [terminalOutcome];
}

/// attempt 关键 durable save 失败。run 进 persistenceFailed。
class ChatAttemptPersistenceFailed extends ChatAttemptDecision {
  const ChatAttemptPersistenceFailed(this.error);

  final Object error;

  @override
  List<Object?> get props => [error];
}

/// 传给 [host.stop] 的中断快照。
class ChatPartialSnapshot extends Equatable {
  const ChatPartialSnapshot({
    required this.generationId,
    required this.attempt,
    required this.content,
    required this.reasoning,
    required this.finishReason,
    required this.streamingConversation,
    required this.assistantMessage,
    required this.streamingReply,
    required this.phase,
  });

  final int generationId;
  final int attempt;
  final String content;
  final String reasoning;
  final String? finishReason;
  final ChatConversation streamingConversation;
  final ChatMessage assistantMessage;
  final ChatStreamingReply? streamingReply;

  /// 发起 stop 时的 phase（preparing / streaming / retryWaiting）。
  final ChatGenerationPhase phase;

  @override
  List<Object?> get props => [
    generationId,
    attempt,
    content,
    reasoning,
    finishReason,
    streamingConversation,
    assistantMessage,
    streamingReply,
    phase,
  ];
}

/// [host.stop] 的返回决策。
sealed class ChatStopDecision extends Equatable {
  const ChatStopDecision();
}

/// stop 成功：已 durable stopped conversation。run 进 cancelled。
class ChatStopCancelled extends ChatStopDecision {
  const ChatStopCancelled(this.conversation);

  final ChatConversation conversation;

  @override
  List<Object?> get props => [conversation];
}

/// stop 落盘失败。run 进 persistenceFailed。
class ChatStopPersistenceFailed extends ChatStopDecision {
  const ChatStopPersistenceFailed(this.error);

  final Object error;

  @override
  List<Object?> get props => [error];
}

/// run 投递给 host 的 UI 投影数据。
///
/// [snapshot] 为当前 generation 生命周期快照（phase / attempt / outcome），
/// [streamingReply] 为 null 时表示清空流式增量。host 据此单向派生兼容字段
/// （isStreaming / isAutoRetryWaiting / autoRetryCount）与 state.generation。
class ChatGenerationProgress extends Equatable {
  const ChatGenerationProgress({required this.snapshot, this.streamingReply});

  final ChatGenerationSnapshot snapshot;
  final ChatStreamingReply? streamingReply;

  @override
  List<Object?> get props => [snapshot, streamingReply];
}
