import 'dart:async';
import 'dart:isolate';

import '../../../core/persistence/background_sqlite_writer.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import 'chat_conversation_repository.dart';
import 'sqlite_chat_conversation_repository.dart';

/// 将全量写入委托给后台 Isolate 的 [ChatConversationRepository] 代理。
///
/// 读取操作仍由 [SqliteChatConversationRepository] 在主 Isolate 同步完成；
/// 写入操作序列化为 JSON 后通过 [SendPort] 发送到独立 Isolate，避免阻塞 UI。
class BackgroundChatConversationRepository
    implements ChatConversationRepository {
  BackgroundChatConversationRepository(this._inner, this._databasePath) {
    _spawnIsolate();
  }

  final SqliteChatConversationRepository _inner;
  final String _databasePath;

  static const _debounceDuration = Duration(milliseconds: 80);

  SendPort? _workerCommandPort;
  bool _isolateReady = false;
  bool _isolateFailed = false;

  List<Map<String, dynamic>>? _pendingWrite;
  Timer? _debounceTimer;

  final ReceivePort _mainReceivePort = ReceivePort();

  void _spawnIsolate() {
    if (_databasePath == ':memory:') {
      return; // 内存数据库无法跨 Isolate 共享
    }

    Isolate.spawn(chatWriterEntryPoint, _mainReceivePort.sendPort);

    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _workerCommandPort = message;
        _isolateReady = true;
        message.send(_databasePath);
        final pending = _pendingWrite;
        if (pending != null) {
          _pendingWrite = null;
          message.send(pending);
        }
      }
    });
  }

  @override
  List<ChatConversation> loadAll() => _inner.loadAll();

  @override
  ChatConversation? loadConversation(String id) => _inner.loadConversation(id);

  @override
  List<ChatConversationSummary> loadHistorySummaries({String keyword = ''}) {
    return _inner.loadHistorySummaries(keyword: keyword);
  }

  @override
  Future<void> saveAll(List<ChatConversation> conversations) {
    if (_databasePath == ':memory:') {
      _inner.saveAll(conversations);
      return Future.value();
    }
    _pendingWrite =
        conversations.map((c) => c.toJson()).toList(growable: false);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _flushWrite);
    return Future.value();
  }

  void _flushWrite() {
    final data = _pendingWrite;
    if (data == null) {
      return;
    }
    _pendingWrite = null;
    _sendToWorker(data);
  }

  void _sendToWorker(List<Map<String, dynamic>> data) {
    if (_isolateReady && _workerCommandPort != null) {
      try {
        _workerCommandPort!.send(data);
      } catch (_) {
        _writeWithInner(data); // 降级：Isolate 失效，主线程直接写入
        _isolateReady = false;
        _workerCommandPort = null;
        _isolateFailed = true;
      }
    } else if (_isolateFailed) {
      _writeWithInner(data); // 降级：Isolate 创建失败，直接写入
    } else {
      _pendingWrite = data; // Isolate 尚未就绪，重新缓冲
    }
  }

  void _writeWithInner(List<Map<String, dynamic>> data) {
    _inner
        .saveAll(
          data
              .map(
                (j) =>
                    ChatConversation.fromJson(Map<String, dynamic>.from(j)),
              )
              .toList(growable: false),
        )
        // ignore: avoid_print
        .catchError((e) => print('[BackgroundWriter] 降级写入失败: $e'));
  }

}
