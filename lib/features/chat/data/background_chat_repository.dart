import 'dart:async';
import 'dart:isolate';

import '../../../core/persistence/background_worker_command.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import 'chat_conversation_repository.dart';
import 'chat_writer_entry_point.dart';
import 'sqlite_chat_conversation_repository.dart';

/// 将全量写入委托给后台 Isolate 的 [ChatConversationRepository] 代理。
///
/// 读取操作仍由 [SqliteChatConversationRepository] 在主 Isolate 同步完成；
/// 写入操作序列化后通过 [SendPort] 发送到独立 Isolate，避免阻塞 UI。
///
/// **完成语义**：[saveConversation] / [saveConversations] 返回的 [Future]
/// 在 debounce 触发、命令发送到 worker、且 worker 回传 [AckResponse] 后完成。
/// 同一 80ms debounce 窗口内的多次 save 共享同一个 batch Completer。
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
  Isolate? _isolate;

  Map<String, Map<String, dynamic>>? _pendingWrite;
  Timer? _debounceTimer;
  final Set<String> _pendingDeletes = {};
  int _nextCommandId = 0;

  /// 同一 debounce 窗口内所有 save 调用共享的 Completer。
  /// debounce 触发后、ACK 回来后，所有等待此 batch 的调用者 Future 同时 complete。
  Completer<void>? _batchCompleter;

  /// 等待 worker ACK 的 command ID → Completer 映射。
  final Map<int, Completer<void>> _pendingAcks = {};

  /// close() 等待 worker [ExitResponse] 的 Completer。
  Completer<void>? _closeCompleter;

  final ReceivePort _mainReceivePort = ReceivePort();
  StreamSubscription? _subscription;

  void _spawnIsolate() {
    if (_databasePath == ':memory:') {
      return; // 内存数据库无法跨 Isolate 共享
    }

    Isolate.spawn(chatWriterEntryPoint, _mainReceivePort.sendPort)
        .then((isolate) => _isolate = isolate);

    _subscription = _mainReceivePort.listen(_handleWorkerMessage);
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerCommandPort = message;
      _isolateReady = true;
      message.send(_databasePath);
      final pending = _pendingWrite;
      if (pending != null) {
        _pendingWrite = null;
        final deletes = _pendingDeletes.toSet();
        _pendingDeletes.clear();
        if (deletes.isNotEmpty) {
          for (final id in deletes) {
            pending.remove(id);
          }
        }
        if (pending.isNotEmpty) {
          _sendWriteCommand(
            WriteCommand(
              id: _nextCommandId++,
              payload: pending.values.toList(growable: false),
            ),
          );
        }
      }
      return;
    }

    if (message is AckResponse) {
      final completer = _pendingAcks.remove(message.commandId);
      if (completer != null) {
        completer.complete();
        // 如果此 ACK 对应的是当前 batch，也 complete batch Completer
        if (_batchCompleter != null && _pendingAcks.isEmpty) {
          final batch = _batchCompleter;
          _batchCompleter = null;
          batch!.complete();
        }
      }
      return;
    }

    if (message is ErrorResponse) {
      final completer = _pendingAcks.remove(message.commandId);
      if (completer != null) {
        completer.completeError(StateError(message.message));
        // batch Completer 也传播错误
        if (_batchCompleter != null && _pendingAcks.isEmpty) {
          final batch = _batchCompleter;
          _batchCompleter = null;
          batch!.completeError(StateError(message.message));
        }
      }
      return;
    }

    if (message is ExitResponse) {
      if (_closeCompleter != null) {
        final completer = _closeCompleter;
        _closeCompleter = null;
        completer!.complete();
      }
    }
  }

  // ── 读取操作：直接委托内层 ─────────────────────────────────────────

  @override
  List<ChatConversation> loadAll() => _inner.loadAll();

  @override
  ChatConversation? loadConversation(String id) => _inner.loadConversation(id);

  @override
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) {
    return _inner.loadHistorySummaries(
      keyword: keyword,
      limit: limit,
      offset: offset,
    );
  }

  @override
  int countHistorySummaries({String keyword = ''}) =>
      _inner.countHistorySummaries(keyword: keyword);

  // ── 删除操作 ──────────────────────────────────────────────────────

  @override
  Future<void> deleteConversations(List<String> ids) {
    _pendingDeletes.addAll(ids);
    return _inner.deleteConversations(ids);
  }

  // ── 写入操作：debounce + ACK 语义 ──────────────────────────────────

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) {
    if (_databasePath == ':memory:') {
      return _inner.saveConversations(conversations);
    }
    _pendingWrite ??= {};
    for (final c in conversations) {
      _pendingWrite![c.id] = c.toJson();
    }
    return _scheduleDebouncedWrite();
  }

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    final shouldSave =
        conversation.hasMessages ||
        conversation.checkpoints.isNotEmpty ||
        (conversation.title?.trim().isNotEmpty ?? false);
    if (!shouldSave) return;
    if (_databasePath == ':memory:') {
      return _inner.saveConversations([conversation]);
    }
    _pendingWrite ??= {};
    _pendingWrite![conversation.id] = conversation.toJson();
    return _scheduleDebouncedWrite();
  }

  /// 安排一次 debounce 写入，返回在 ACK 后完成的 Future。
  ///
  /// 同一 80ms 窗口内的多次调用共享同一个 [_batchCompleter]：
  /// debounce 触发后合并为单个 [WriteCommand]，ACK 回来后所有调用者
  /// 的 Future 同时 complete。
  Future<void> _scheduleDebouncedWrite() {
    _batchCompleter ??= Completer<void>();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _flushWrite);
    return _batchCompleter!.future;
  }

  void _flushWrite() {
    final data = _pendingWrite;
    _pendingWrite = null;
    final deletes = _pendingDeletes.toSet();
    _pendingDeletes.clear();
    if (deletes.isNotEmpty) {
      for (final id in deletes) {
        data?.remove(id);
      }
    }
    if (data == null || data.isEmpty) {
      // 无数据需要写入，直接 complete 当前 batch
      final batch = _batchCompleter;
      _batchCompleter = null;
      batch?.complete();
      return;
    }
    _sendToWorker(data.values.toList(growable: false));
  }

  void _sendToWorker(List<Map<String, dynamic>> data) {
    final command = WriteCommand(
      id: _nextCommandId++,
      payload: data,
    );
    _sendWriteCommand(command);
  }

  void _sendWriteCommand(WriteCommand command) {
    if (_isolateReady && _workerCommandPort != null) {
      try {
        _workerCommandPort!.send(command);
        _pendingAcks[command.id] = Completer<void>();
        // 当所有 ACK 收到后 complete batch
        _pendingAcks[command.id]!.future.then((_) {
          _tryCompleteBatch();
        }, onError: (Object error) {
          // ACK 错误时降级写入并 complete batch with error
          _writeWithInner([command.payload]);
          final batch = _batchCompleter;
          _batchCompleter = null;
          batch?.completeError(error);
          _isolateReady = false;
          _workerCommandPort = null;
          _isolateFailed = true;
        });
      } catch (_) {
        _writeWithInner([command.payload]);
        _isolateReady = false;
        _workerCommandPort = null;
        _isolateFailed = true;
        final batch = _batchCompleter;
        _batchCompleter = null;
        batch?.complete();
      }
    } else if (_isolateFailed) {
      _writeWithInner([command.payload]);
      _tryCompleteBatch();
    } else {
      // Isolate 尚未就绪，缓存数据
      _pendingWrite = {
        for (final j in command.payload)
          if (j is Map<String, dynamic>) j['id'] as String: j,
      };
    }
  }

  /// 当所有 pending ACK 已收到时 complete batch Completer。
  void _tryCompleteBatch() {
    if (_pendingAcks.isEmpty && _batchCompleter != null) {
      final batch = _batchCompleter;
      _batchCompleter = null;
      batch!.complete();
    }
  }

  void _writeWithInner(List<dynamic> payload) {
    final conversations = payload
        .whereType<Map<String, dynamic>>()
        .map((j) => ChatConversation.fromJson(Map<String, dynamic>.from(j)))
        .toList(growable: false);
    _inner
        .saveConversations(conversations)
        // ignore: avoid_print
        .catchError((e) => print('[BackgroundWriter] 降级写入失败: $e'));
  }

  // ── 生命周期操作 ──────────────────────────────────────────────────

  @override
  Future<void> flush() async {
    if (_databasePath == ':memory:') return;
    // 取消 debounce timer，立即触发写入
    _debounceTimer?.cancel();
    _flushWrite();
    // 等待当前 batch（如果有）完成
    if (_batchCompleter != null) {
      await _batchCompleter!.future;
    }
  }

  @override
  Future<void> close() async {
    if (_databasePath == ':memory:') return;

    // 1. flush 所有 pending writes
    await flush();

    // 2. 发送 CloseCommand
    if (_isolateReady && _workerCommandPort != null) {
      _closeCompleter = Completer<void>();
      _workerCommandPort!.send(CloseCommand());

      // 3. 等待 ExitResponse，5 秒超时后 kill isolate
      try {
        await _closeCompleter!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        _isolate?.kill(priority: Isolate.immediate);
      }
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }

    _isolateReady = false;
    _workerCommandPort = null;
    await _subscription?.cancel();
    _subscription = null;
    _mainReceivePort.close();
  }
}
