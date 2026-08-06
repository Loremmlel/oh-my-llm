import 'dart:async';
import 'dart:isolate';

import 'package:oh_my_llm/core/persistence/background_worker_command.dart';
import '../application/ports/chat_conversation_repository.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
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

    Isolate.spawn(
      chatWriterEntryPoint,
      _mainReceivePort.sendPort,
    ).then((isolate) => _isolate = isolate);

    _subscription = _mainReceivePort.listen(_handleWorkerMessage);
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerCommandPort = message;
      _isolateReady = true;
      message.send(_databasePath);
      _drainPendingOnReady();
      return;
    }

    if (message is WorkerResponse) {
      _handleWorkerResponse(message);
    }
  }

  /// 统一处理 worker 回传的响应（ACK/ERROR/EXIT）。
  void _handleWorkerResponse(WorkerResponse response) {
    switch (response) {
      case AckResponse(:final commandId):
        _pendingAcks.remove(commandId);
        _tryCompleteBatch();
      case ErrorResponse(:final commandId, :final message):
        _pendingAcks.remove(commandId);
        _degradeToInner();
        _completeBatchError(StateError(message));
      case ExitResponse():
        final completer = _closeCompleter;
        _closeCompleter = null;
        completer?.complete();
    }
  }

  /// Isolate 就绪后排空 pending 数据。
  void _drainPendingOnReady() {
    final pending = _pendingWrite;
    if (pending == null) return;
    _pendingWrite = null;

    final deletes = _pendingDeletes.toSet();
    _pendingDeletes.clear();
    for (final id in deletes) {
      pending.remove(id);
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
    // 已被删除的 ID 从 pending 中移除，避免 delete+resave 竞态
    _removeDeletedFromPending();
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
    // 已被删除的 ID 从 pending 中移除，避免 delete+resave 竞态
    _removeDeletedFromPending();
    return _scheduleDebouncedWrite();
  }

  /// 从 [_pendingWrite] 中移除已在 [_pendingDeletes] 中的 ID。
  ///
  /// 防止 delete + resave 竞态：如果同一 ID 在 80ms 窗口内先被 delete
  /// 再被 save，内层仓库已删除，而 pending 写入也会在 flush 时被
  /// _pendingDeletes 过滤掉。对于「先删后存」的场景，save 应覆盖 delete
  /// 意图，因此从 _pendingDeletes 中移除该 ID。
  void _removeDeletedFromPending() {
    if (_pendingWrite == null || _pendingDeletes.isEmpty) return;
    for (final id in _pendingWrite!.keys.toList()) {
      _pendingDeletes.remove(id);
    }
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
      // 数据可能已被 _drainPendingOnReady 提前发送（ACK 未回）：
      // 有在途 ACK 时不得提前完成，须等 ACK 回来（见 _tryCompleteBatch）。
      if (_pendingAcks.isEmpty) {
        final batch = _batchCompleter;
        _batchCompleter = null;
        batch?.complete();
      }
      return;
    }
    _sendToWorker(data.values.toList(growable: false));
  }

  void _sendToWorker(List<Map<String, dynamic>> data) {
    final command = WriteCommand(id: _nextCommandId++, payload: data);
    _sendWriteCommand(command);
  }

  void _sendWriteCommand(WriteCommand command) {
    if (_isolateReady && _workerCommandPort != null) {
      try {
        _workerCommandPort!.send(command);
        _pendingAcks[command.id] = Completer<void>();
        // 已就绪分支同样需要超时保护：ACK 偶发丢失时避免 batch 永久挂起
        _ensureBatchTimeout();
      } catch (_) {
        // send() 抛异常意味着 worker 已不可达
        _degradeToInner(command.payload);
        _completeBatchOk();
      }
    } else if (_isolateFailed) {
      // 降级路径：直接写内层
      _degradeToInner(command.payload);
      _tryCompleteBatch();
    } else {
      // Isolate 尚未就绪，缓存数据
      _pendingWrite = {
        for (final j in command.payload)
          if (j is Map<String, dynamic>) j['id'] as String: j,
      };
      // 如果有 batch Completer 等待，需在数据最终落盘后 complete；
      // 当 Isolate 就绪后 _drainPendingOnReady → _sendWriteCommand 会处理。
      // 但如果 Isolate 永远不就绪，batch Completer 会挂起。
      // 为安全起见，设置超时保护。
      _ensureBatchTimeout();
    }
  }

  /// 当所有 pending ACK 已收到时 complete batch Completer。
  void _tryCompleteBatch() {
    // 只有「无待发数据（_pendingWrite 为空）且无在途 ACK」时 batch 才算完成；
    // 否则上一个 batch 的迟到 ACK 会错误完成「数据尚未发送」的下一个 batch。
    if (_pendingWrite == null &&
        _pendingAcks.isEmpty &&
        _batchCompleter != null) {
      _completeBatchOk();
    }
  }

  /// 安全地 complete batch（成功）。
  void _completeBatchOk() {
    final batch = _batchCompleter;
    _batchCompleter = null;
    batch?.complete();
  }

  /// 安全地 complete batch（失败），同时清理 stale _pendingAcks。
  void _completeBatchError(Object error) {
    // 清理所有 stale ACK entries——worker 已不可达
    _pendingAcks.clear();
    final batch = _batchCompleter;
    _batchCompleter = null;
    batch?.completeError(error);
  }

  /// 降级到内层写入。
  ///
  /// [payload] 为可选参数：不传时仅标记 isolate 为 failed 状态，
  /// 传入时同时执行降级写入。
  void _degradeToInner([List<dynamic>? payload]) {
    _isolateReady = false;
    _workerCommandPort = null;
    _isolateFailed = true;
    if (payload != null) {
      _writeWithInner(payload);
    }
  }

  /// 为 batch Completer 设置超时保护：Isolate 未就绪或 ACK 未回均视为 worker
  /// 不可达，降级写入并 completeError。
  ///
  /// 防止 batch Completer 永久挂起导致 flush/close 卡死、进程残留锁住
  /// native assets dll 引发后续 test 连锁阻塞。
  void _ensureBatchTimeout() {
    final batch = _batchCompleter;
    if (batch == null || batch.isCompleted) return;
    Timer(const Duration(seconds: 10), () {
      if (batch.isCompleted) return;
      _degradeToInner();
      _completeBatchError(
        StateError('Background isolate timed out (no ACK within 10s)'),
      );
    });
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
    // 等待当前 batch（如果有）完成。超时或失败均不抛出：
    // _ensureBatchTimeout 已在超时后降级写入并 completeError，
    // 这里吞掉错误以保证 flush/close 不会因 batch 卡死而永久挂起。
    final batch = _batchCompleter;
    if (batch != null) {
      try {
        await batch.future.timeout(const Duration(seconds: 10));
      } catch (_) {
        // batch 超时或失败：降级路径已由 _ensureBatchTimeout 处理
      }
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
