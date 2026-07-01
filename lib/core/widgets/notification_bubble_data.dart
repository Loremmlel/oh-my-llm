import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../utils/id_generator.dart';

/// 通知气泡的语义类型，决定默认图标、色调和停留时间。
enum NotificationBubbleType {
  /// 一般信息提示。
  info,

  /// 操作成功提示。
  success,

  /// 警告提示。
  warning,

  /// 错误提示。
  error;

  /// 类型对应的默认 Material 图标。
  IconData get icon {
    return switch (this) {
      NotificationBubbleType.info => Icons.info_outline,
      NotificationBubbleType.success => Icons.check_circle_outline,
      NotificationBubbleType.warning => Icons.warning_amber,
      NotificationBubbleType.error => Icons.error_outline,
    };
  }

  /// 类型对应的装饰色。
  ///
  /// 暗黑模式下自动降低饱和度以保证可读性。
  Color iconColor(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return switch (this) {
      NotificationBubbleType.info => cs.primary,
      NotificationBubbleType.success =>
        isDark ? const Color(0xFF66BB6A) : const Color(0xFF43A047),
      NotificationBubbleType.warning =>
        isDark ? const Color(0xFFFFCA28) : const Color(0xFFEF6C00),
      NotificationBubbleType.error => cs.error,
    };
  }

  /// 无操作按钮时的默认自动消失时间。
  Duration get defaultDuration {
    return switch (this) {
      NotificationBubbleType.info => const Duration(seconds: 3),
      NotificationBubbleType.success => const Duration(seconds: 3),
      NotificationBubbleType.warning => const Duration(seconds: 5),
      NotificationBubbleType.error => const Duration(seconds: 6),
    };
  }
}

/// 通知气泡内的操作按钮（如"撤销"）。
@immutable
class NotificationBubbleAction extends Equatable {
  const NotificationBubbleAction({
    required this.label,
    required this.onPressed,
  });

  /// 按钮文字。
  final String label;

  /// 点击回调，执行完毕后气泡会自动关闭。
  final VoidCallback onPressed;

  @override
  List<Object?> get props => [label];
}

/// 通知气泡的不可变数据模型。
///
/// [id] 自动生成，[duration] 为 null 时使用类型的默认值。
@immutable
class NotificationBubbleData extends Equatable {
  NotificationBubbleData({
    String? id,
    required this.message,
    this.type = NotificationBubbleType.info,
    this.action,
    this.duration,
  }) : id = id ?? generateEntityId();

  /// 唯一标识。
  final String id;

  /// 通知文本内容。
  final String message;

  /// 语义类型。
  final NotificationBubbleType type;

  /// 可选的操作按钮。
  final NotificationBubbleAction? action;

  /// 自定义停留时间；null 时按类型 + 是否有操作按钮自动决定。
  final Duration? duration;

  /// 实际生效的停留时间。
  Duration get effectiveDuration {
    if (duration != null) return duration!;
    // 带操作按钮的通知默认停留更久。
    if (action != null) return const Duration(seconds: 8);
    return type.defaultDuration;
  }

  @override
  List<Object?> get props => [id, message, type, action, duration];
}
