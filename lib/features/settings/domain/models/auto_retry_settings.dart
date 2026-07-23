import 'package:equatable/equatable.dart';

/// 自动重试的间隔模式。
enum RetryMode {
  /// 每分钟窗口：每分钟在前 n 秒内随机一个毫秒重试。
  perMinuteWindow,

  /// 固定间隔：每 n 秒 + 随机 1000ms 抖动重试。
  fixedInterval,
}

/// 自动重试的全局设置。
class AutoRetrySettings extends Equatable {
  const AutoRetrySettings({
    this.maxJitterSeconds = 15,
    this.maxRetryCount = 0,
    this.retryMode = RetryMode.perMinuteWindow,
    this.retryOnAbnormalFinishReason = false,
    this.retryOnTimeout = false,
    this.timeoutSeconds = 30,
  });

  /// 随机抖动上限秒数，范围 0-60，默认 15。
  /// 在 [RetryMode.perMinuteWindow] 下表示每分钟窗口内的抖动上限；
  /// 在 [RetryMode.fixedInterval] 下表示基础间隔秒数。
  final int maxJitterSeconds;

  /// 最大重试次数，0 表示不限，默认 0。
  final int maxRetryCount;

  /// 重试间隔模式，默认 [RetryMode.perMinuteWindow]。
  final RetryMode retryMode;

  /// 当 finish_reason 不是正常值（stop、tool_calls）时是否自动重试。
  final bool retryOnAbnormalFinishReason;

  /// 是否启用超时自动重试。
  ///
  /// 开启后，若 SSE 流在 [timeoutSeconds] 秒内没有任何新数据，
  /// 则自动断开连接并重试。仅在自动重试模式下生效。
  final bool retryOnTimeout;

  /// SSE 流空闲超时秒数，范围 1-300，默认 30。
  ///
  /// 仅当 [retryOnTimeout] 为 true 时有意义。
  final int timeoutSeconds;

  AutoRetrySettings copyWith({
    int? maxJitterSeconds,
    int? maxRetryCount,
    RetryMode? retryMode,
    bool? retryOnAbnormalFinishReason,
    bool? retryOnTimeout,
    int? timeoutSeconds,
    bool clearMaxJitterSeconds = false,
    bool clearMaxRetryCount = false,
    bool clearRetryMode = false,
    bool clearRetryOnAbnormalFinishReason = false,
    bool clearRetryOnTimeout = false,
    bool clearTimeoutSeconds = false,
  }) {
    return AutoRetrySettings(
      maxJitterSeconds: clearMaxJitterSeconds
          ? 15
          : maxJitterSeconds ?? this.maxJitterSeconds,
      maxRetryCount: clearMaxRetryCount
          ? 0
          : maxRetryCount ?? this.maxRetryCount,
      retryMode: clearRetryMode
          ? RetryMode.perMinuteWindow
          : retryMode ?? this.retryMode,
      retryOnAbnormalFinishReason: clearRetryOnAbnormalFinishReason
          ? false
          : retryOnAbnormalFinishReason ?? this.retryOnAbnormalFinishReason,
      retryOnTimeout: clearRetryOnTimeout
          ? false
          : retryOnTimeout ?? this.retryOnTimeout,
      timeoutSeconds: clearTimeoutSeconds
          ? 30
          : timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxJitterSeconds': maxJitterSeconds,
      'maxRetryCount': maxRetryCount,
      'retryMode': retryMode.name,
      'retryOnAbnormalFinishReason': retryOnAbnormalFinishReason,
      'retryOnTimeout': retryOnTimeout,
      'timeoutSeconds': timeoutSeconds,
    };
  }

  factory AutoRetrySettings.fromJson(Map<String, dynamic> json) {
    RetryMode parsedMode = RetryMode.perMinuteWindow;
    final modeStr = json['retryMode'] as String?;
    if (modeStr != null) {
      try {
        parsedMode = RetryMode.values.byName(modeStr);
      } catch (_) {
        // 未知模式名时回退到默认值
      }
    }

    return AutoRetrySettings(
      maxJitterSeconds: (json['maxJitterSeconds'] as int?) ?? 15,
      maxRetryCount: (json['maxRetryCount'] as int?) ?? 0,
      retryMode: parsedMode,
      retryOnAbnormalFinishReason:
          (json['retryOnAbnormalFinishReason'] as bool?) ?? false,
      retryOnTimeout: (json['retryOnTimeout'] as bool?) ?? false,
      timeoutSeconds: ((json['timeoutSeconds'] as int?) ?? 30).clamp(1, 300),
    );
  }

  @override
  List<Object?> get props => [
        maxJitterSeconds,
        maxRetryCount,
        retryMode,
        retryOnAbnormalFinishReason,
        retryOnTimeout,
        timeoutSeconds,
      ];
}

/// finish_reason 的正常值：模型正常完成或请求工具调用。
const normalFinishReasons = {'stop', 'tool_calls'};

/// 判断 [finishReason] 是否为异常值。
///
/// `stop` 和 `tool_calls` 为正常值，`null` 视为正常（流未结束时为 null），
/// 其余所有值（如 `length`、`content_filter`）均视为异常。
bool isAbnormalFinishReason(String? finishReason) {
  if (finishReason == null) return false;
  return !normalFinishReasons.contains(finishReason);
}
