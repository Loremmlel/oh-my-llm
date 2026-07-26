import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../core/persistence/background_worker_command.dart';
import '../../../core/persistence/sqlite_replace_all.dart';
import 'chat_sql_codec.dart';

/// 后台 Isolate 入口：打开独立 sqlite3 连接，处理 chat 写入请求。
///
/// 处理三种消息类型：
/// - `String`：数据库路径，触发打开连接并排空 pending 写入
/// - [WriteCommand]：执行 chat 会话写入，回传 [AckResponse] 或 [ErrorResponse]
/// - [CloseCommand]：排空 pending 后关闭连接，回传 [ExitResponse]
@pragma('vm:entry-point')
void chatWriterEntryPoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  sqlite.Database? db;
  final pendingWrites = <WriteCommand>[];

  commandPort.listen((message) {
    if (message is String) {
      try {
        db?.close();
      } catch (_) {}
      try {
        db = sqlite.sqlite3.open(message);
        final currentDb = db!;
        configureSqlitePragmas(currentDb, isInMemory: message == ':memory:');
        for (final pending in pendingWrites) {
          _executeWrite(currentDb, pending, mainSendPort);
        }
        pendingWrites.clear();
      } catch (_) {
        db = null;
      }
    } else if (message is WriteCommand) {
      final currentDb = db;
      if (currentDb != null) {
        _executeWrite(currentDb, message, mainSendPort);
      } else {
        pendingWrites.add(message);
      }
    } else if (message is CloseCommand) {
      // 先排空所有 pending 写入
      final currentDb = db;
      if (currentDb != null) {
        for (final pending in pendingWrites) {
          _executeWrite(currentDb, pending, mainSendPort);
        }
        pendingWrites.clear();
      }
      try {
        db?.close();
      } catch (_) {}
      db = null;
      mainSendPort.send(ExitResponse());
      commandPort.close();
    }
  });
}

void _executeWrite(
  sqlite.Database db,
  WriteCommand command,
  SendPort mainSendPort,
) {
  try {
    executeSaveFromPayload(db, command.payload);
    mainSendPort.send(AckResponse(commandId: command.id));
  } catch (e) {
    mainSendPort.send(
      ErrorResponse(commandId: command.id, message: e.toString()),
    );
  }
}
