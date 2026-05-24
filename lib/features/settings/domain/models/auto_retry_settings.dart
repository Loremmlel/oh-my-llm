import 'package:equatable/equatable.dart';

/// 自动重试的全局设置。
class AutoRetrySettings extends Equatable {
  const AutoRetrySettings({
    this.maxJitterSeconds = 15,
    this.maxRetryCount = 0,
  });

  /// 随机抖动上限秒数，范围 0-60，默认 15。
  final int maxJitterSeconds;

  /// 最大重试次数，0 表示不限，默认 0。
  final int maxRetryCount;

  AutoRetrySettings copyWith({
    int? maxJitterSeconds,
    int? maxRetryCount,
    bool clearMaxJitterSeconds = false,
    bool clearMaxRetryCount = false,
  }) {
    return AutoRetrySettings(
      maxJitterSeconds: clearMaxJitterSeconds
          ? 15
          : maxJitterSeconds ?? this.maxJitterSeconds,
      maxRetryCount: clearMaxRetryCount
          ? 0
          : maxRetryCount ?? this.maxRetryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxJitterSeconds': maxJitterSeconds,
      'maxRetryCount': maxRetryCount,
    };
  }

  factory AutoRetrySettings.fromJson(Map<String, dynamic> json) {
    return AutoRetrySettings(
      maxJitterSeconds: (json['maxJitterSeconds'] as int?) ?? 15,
      maxRetryCount: (json['maxRetryCount'] as int?) ?? 0,
    );
  }

  @override
  List<Object?> get props => [maxJitterSeconds, maxRetryCount];
}
