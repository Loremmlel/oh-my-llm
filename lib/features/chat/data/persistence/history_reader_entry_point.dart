import 'dart:async';
import 'dart:isolate';

import 'package:oh_my_llm/core/constants/app_page_sizes.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';

import '../../application/ports/history_page_query.dart';
import 'history_reader_protocol.dart';
import 'sqlite_chat_conversation_repository.dart';

/// 历史页 read worker 入口。
///
/// 持有 [AppDatabase.forPath] 打开的独立连接，与 writer isolate 的连接
/// 并行；文件库为 WAL 模式，读事务不阻塞 writer 提交。一次只处理一条
/// query，controller 的有界调度保证主路径不会堆入任意数量的旧请求。
@pragma('vm:entry-point')
void historyReaderEntryPoint(HistoryReaderBootstrap bootstrap) {
  final AppDatabase database;
  try {
    database = AppDatabase.forPath(bootstrap.databasePath);
  } catch (error) {
    bootstrap.responsePort.send(
      HistoryReaderStartupError(message: error.toString()),
    );
    return;
  }

  final repository = SqliteChatConversationRepository(database);
  final commandPort = ReceivePort();
  late final StreamSubscription subscription;
  subscription = commandPort.listen((message) {
    switch (message) {
      case HistoryReaderQuery(:final id, :final request):
        try {
          bootstrap.responsePort.send(
            HistoryReaderSuccess(
              id: id,
              result: executeHistoryPageWindow(
                database: database,
                repository: repository,
                request: request,
              ),
            ),
          );
        } catch (error) {
          bootstrap.responsePort.send(
            HistoryReaderFailure(id: id, message: error.toString()),
          );
        }
      case HistoryReaderClose():
        // 当前同步 query 完成后才会处理本命令；先关库再确认 Exit。
        subscription.cancel().then((_) {
          commandPort.close();
          database.close();
          bootstrap.responsePort.send(const HistoryReaderExit());
        });
    }
  });
  bootstrap.responsePort.send(
    HistoryReaderReady(commandPort: commandPort.sendPort),
  );
}

/// 在调用 isolate 自有连接上执行一次完整窗口查询。
///
/// count 与 page SELECT 包在同一 `BEGIN DEFERRED` 读事务内：同一 WAL 读
/// 快照保证「总数 → 夹取页码 → 该页数据」一致，writer 可并行提交。
HistoryPageResult executeHistoryPageWindow({
  required AppDatabase database,
  required SqliteChatConversationRepository repository,
  required HistoryPageRequest request,
}) {
  database.connection.execute('BEGIN DEFERRED;');
  try {
    final totalItems = repository.countHistorySummaries(
      keyword: request.keyword,
    );
    final totalPages = totalPagesForItems(totalItems, request.pageSize);
    final committedPage = clampPageToValidRange(
      request.requestedPage,
      totalPages,
    );
    final items = repository.loadHistorySummaries(
      keyword: request.keyword,
      limit: request.pageSize,
      offset: (committedPage - 1) * request.pageSize,
    );
    database.connection.execute('COMMIT;');
    return HistoryPageResult(
      items: items,
      totalItems: totalItems,
      committedPage: committedPage,
    );
  } catch (_) {
    database.connection.execute('ROLLBACK;');
    rethrow;
  }
}
