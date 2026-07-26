import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../features/chat/data/chat_sql_codec.dart';
import 'sqlite_replace_all.dart';

/// 后台 Isolate 入口：打开独立 sqlite3 连接，处理全量写入请求。
@pragma('vm:entry-point')
void chatWriterEntryPoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  sqlite.Database? db;
  final pendingWrites = <List<dynamic>>[];

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
          executeSaveFromPayload(currentDb, pending);
        }
        pendingWrites.clear();
      } catch (_) {
        db = null; // 打开失败，重置引用避免后续在已关闭连接上操作
      }
    } else if (message is List) {
      final currentDb = db;
      if (currentDb != null) {
        try {
          executeSaveFromPayload(currentDb, message);
        } catch (e) {
          // ignore: avoid_print
          print('[BackgroundWriter] 写入失败: $e');
        }
      } else {
        pendingWrites.add(message);
      }
    }
  });
}
