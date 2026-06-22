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
  });

  /// 随机抖动上限秒数，范围 0-60，默认 15。
  /// 在 [RetryMode.perMinuteWindow] 下表示每分钟窗口内的抖动上限；
  /// 在 [RetryMode.fixedInterval] 下表示基础间隔秒数。
  final int maxJitterSeconds;

  /// 最大重试次数，0 表示不限，默认 0。
  final int maxRetryCount;

  /// 重试间隔模式，默认 [RetryMode.perMinuteWindow]。
  final RetryMode retryMode;

  AutoRetrySettings copyWith({
    int? maxJitterSeconds,
    int? maxRetryCount,
    RetryMode? retryMode,
    bool clearMaxJitterSeconds = false,
    bool clearMaxRetryCount = false,
    bool clearRetryMode = false,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxJitterSeconds': maxJitterSeconds,
      'maxRetryCount': maxRetryCount,
      'retryMode': retryMode.name,
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
    );
  }

  @override
  List<Object?> get props => [maxJitterSeconds, maxRetryCount, retryMode];
}
