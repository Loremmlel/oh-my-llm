import 'dart:isolate';

import '../../application/ports/history_page_query.dart';

/// read worker 启动消息：主 isolate 提供 response port 与数据库路径。
final class HistoryReaderBootstrap {
  HistoryReaderBootstrap({
    required this.responsePort,
    required this.databasePath,
  });

  final SendPort responsePort;
  final String databasePath;
}

/// worker 完成自有连接初始化后回传的命令通道。
final class HistoryReaderReady {
  HistoryReaderReady({required this.commandPort});

  final SendPort commandPort;
}

/// worker 打开数据库失败时回传；此后 worker 自行退出。
final class HistoryReaderStartupError {
  HistoryReaderStartupError({required this.message});

  final String message;
}

/// 主 isolate → worker 的命令。
sealed class HistoryReaderCommand {
  const HistoryReaderCommand();
}

/// 执行一次完整窗口查询。
final class HistoryReaderQuery extends HistoryReaderCommand {
  HistoryReaderQuery({required this.id, required this.request});

  final int id;
  final HistoryPageRequest request;
}

/// 关闭 worker；当前同步查询完成后释放连接并回 [HistoryReaderExit]。
final class HistoryReaderClose extends HistoryReaderCommand {
  const HistoryReaderClose();
}

/// worker → 主 isolate 的响应。
sealed class HistoryReaderResponse {
  const HistoryReaderResponse();
}

final class HistoryReaderSuccess extends HistoryReaderResponse {
  HistoryReaderSuccess({required this.id, required this.result});

  final int id;
  final HistoryPageResult result;
}

final class HistoryReaderFailure extends HistoryReaderResponse {
  HistoryReaderFailure({required this.id, required this.message});

  final int id;
  final String message;
}

/// worker 正常关闭的终结响应。
final class HistoryReaderExit extends HistoryReaderResponse {
  const HistoryReaderExit();
}
