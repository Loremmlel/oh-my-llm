/// 后台 worker 命令协议。
///
/// feature 在自己的 Isolate entry-point 中使用这些类型与主 Isolate 通信。
/// 所有类型均为可跨 Isolate 传递的简单值对象，无 feature 依赖。
library;

/// worker 接收的命令。
sealed class WorkerCommand {}

/// 写入命令：携带唯一 ID 和 feature-specific payload。
class WriteCommand extends WorkerCommand {
  WriteCommand({required this.id, required this.payload});

  /// 递增命令 ID，用于匹配 ACK/ERROR 响应。
  final int id;

  /// 由 feature-specific codec 序列化后的 payload。
  final List<dynamic> payload;
}

/// 关闭命令：通知 worker 排空 pending 后退出。
class CloseCommand extends WorkerCommand {}

/// worker 回传的响应消息。
sealed class WorkerResponse {}

/// 写入成功 ACK。
class AckResponse extends WorkerResponse {
  AckResponse({required this.commandId});

  /// 对应的 WriteCommand.id。
  final int commandId;
}

/// 写入失败。
class ErrorResponse extends WorkerResponse {
  ErrorResponse({required this.commandId, required this.message});

  /// 对应的 WriteCommand.id。
  final int commandId;

  /// 错误描述。
  final String message;
}

/// worker 已退出（响应 CloseCommand）。
class ExitResponse extends WorkerResponse {}
