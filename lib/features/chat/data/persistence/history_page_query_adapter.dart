import 'dart:async';
import 'dart:isolate';

import 'package:oh_my_llm/core/persistence/app_database.dart';

import '../../application/ports/history_page_query.dart';
import 'history_reader_entry_point.dart';
import 'history_reader_protocol.dart';
import 'sqlite_chat_conversation_repository.dart';

/// [HistoryPageQuery] 的 SQLite 生产实现。
///
/// 文件库：查询委托独立 read worker isolate（[AppDatabase.forPath] 自有连
/// 接），把同步 SQL 移出 UI isolate；`:memory:`：内存库无法跨 isolate 共
/// 享，复用传入 [AppDatabase] 的同一连接同步执行——只保持接口语义一致，
/// 不承诺消除 UI isolate 阻塞。
class SqliteHistoryPageQueryAdapter implements HistoryPageQuery {
  SqliteHistoryPageQueryAdapter(AppDatabase database) : _database = database {
    if (database.path == ':memory:') {
      _inProcess = _InProcessHistoryPageQuery(database);
    }
  }

  final AppDatabase _database;
  _InProcessHistoryPageQuery? _inProcess;

  static const _startupTimeout = Duration(seconds: 5);

  Isolate? _isolate;
  SendPort? _commandPort;
  Completer<void>? _readyCompleter;
  Future<void>? _ready;
  Timer? _startupTimer;
  bool _disposed = false;
  bool _gracefulExit = false;
  Completer<void>? _exited;

  final _responsePort = ReceivePort();
  final _isolateErrorPort = ReceivePort();
  final _isolateExitPort = ReceivePort();
  StreamSubscription? _responseSubscription;
  StreamSubscription? _isolateErrorSubscription;
  StreamSubscription? _isolateExitSubscription;
  final Map<int, Completer<HistoryPageResult>> _pending = {};
  int _nextCommandId = 0;

  @override
  Future<HistoryPageResult> load(HistoryPageRequest request) {
    final inProcess = _inProcess;
    if (inProcess != null) {
      return inProcess.load(request);
    }
    if (_disposed) {
      return Future<HistoryPageResult>.error(
        const HistoryPageQueryException('HistoryPageQuery 已 dispose'),
      );
    }
    return _loadViaWorker(request);
  }

  Future<HistoryPageResult> _loadViaWorker(HistoryPageRequest request) async {
    await _ensureReady();
    if (_disposed) {
      throw const HistoryPageQueryException('HistoryPageQuery 已 dispose');
    }
    final id = _nextCommandId++;
    final completer = Completer<HistoryPageResult>();
    _pending[id] = completer;
    try {
      _commandPort!.send(HistoryReaderQuery(id: id, request: request));
    } catch (error) {
      _pending.remove(id);
      throw HistoryPageQueryException('发送历史页查询命令失败: $error');
    }
    return completer.future;
  }

  /// 首次 load 时才 spawn worker；所有 load 共享同一个 readiness Future，
  /// 启动失败/超时会被缓存，后续 load 立即失败而不是反复重试。
  Future<void> _ensureReady() {
    final existing = _ready;
    if (existing != null) {
      return existing;
    }
    final completer = Completer<void>();
    _readyCompleter = completer;
    _ready = completer.future;

    _responseSubscription = _responsePort.listen(_handleResponse);
    _isolateErrorSubscription = _isolateErrorPort.listen((error) {
      _workerDied(HistoryPageQueryException('历史页 read worker 异常退出: $error'));
    });
    _isolateExitSubscription = _isolateExitPort.listen((_) {
      if (!_gracefulExit) {
        _workerDied(const HistoryPageQueryException('历史页 read worker 意外退出'));
      }
    });
    _startupTimer = Timer(_startupTimeout, () {
      if (!completer.isCompleted) {
        _killWorker();
        completer.completeError(
          const HistoryPageQueryException('历史页 read worker 启动超时'),
        );
      }
    });

    Isolate.spawn(
      historyReaderEntryPoint,
      HistoryReaderBootstrap(
        responsePort: _responsePort.sendPort,
        databasePath: _database.path,
      ),
      onError: _isolateErrorPort.sendPort,
      onExit: _isolateExitPort.sendPort,
      errorsAreFatal: true,
    ).then(
      (isolate) {
        _isolate = isolate;
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(
            HistoryPageQueryException('历史页 read worker spawn 失败: $error'),
          );
        }
      },
    );

    return completer.future;
  }

  void _handleResponse(dynamic message) {
    switch (message) {
      case HistoryReaderReady(:final commandPort):
        _commandPort = commandPort;
        _startupTimer?.cancel();
        _startupTimer = null;
        final completer = _readyCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case HistoryReaderStartupError(:final message):
        _killWorker();
        final completer = _readyCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            HistoryPageQueryException('历史页 read worker 启动失败: $message'),
          );
        }
      case HistoryReaderSuccess(:final id, :final result):
        _pending.remove(id)?.complete(result);
      case HistoryReaderFailure(:final id, :final message):
        _pending.remove(id)?.completeError(HistoryPageQueryException(message));
      case HistoryReaderExit():
        _gracefulExit = true;
        _completeAllPending(
          const HistoryPageQueryException('历史页 read worker 已关闭'),
        );
        _exited?.complete();
    }
  }

  /// worker 不可达（异常退出/spawn 失败）时使 readiness 与全部在途查询失败。
  void _workerDied(HistoryPageQueryException error) {
    _commandPort = null;
    _startupTimer?.cancel();
    _startupTimer = null;
    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
    _completeAllPending(error);
  }

  void _completeAllPending(HistoryPageQueryException error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  void _killWorker() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final inProcess = _inProcess;
    if (inProcess != null) {
      await inProcess.dispose();
      return;
    }

    _startupTimer?.cancel();
    _startupTimer = null;
    final commandPort = _commandPort;
    if (commandPort != null) {
      _exited = Completer<void>();
      try {
        commandPort.send(const HistoryReaderClose());
      } catch (_) {
        // worker 不可达：走下方 kill 兜底。
      }
    }
    try {
      final exited = _exited;
      if (exited != null) {
        await exited.future.timeout(_startupTimeout);
      }
    } catch (_) {
      // 等待 Exit 超时：kill 兜底，不永久阻塞 dispose。
    }
    _killWorker();

    await _responseSubscription?.cancel();
    await _isolateErrorSubscription?.cancel();
    await _isolateExitSubscription?.cancel();
    _responseSubscription = null;
    _isolateErrorSubscription = null;
    _isolateExitSubscription = null;
    _responsePort.close();
    _isolateErrorPort.close();
    _isolateExitPort.close();
    _completeAllPending(
      const HistoryPageQueryException('HistoryPageQuery 已 dispose'),
    );
  }
}

/// `:memory:` 库的进程内实现：同一连接同步执行，语义与 worker 完全一致。
final class _InProcessHistoryPageQuery implements HistoryPageQuery {
  _InProcessHistoryPageQuery(AppDatabase database)
    : _database = database,
      _repository = SqliteChatConversationRepository(database);

  final AppDatabase _database;
  final SqliteChatConversationRepository _repository;

  @override
  Future<HistoryPageResult> load(HistoryPageRequest request) {
    try {
      return Future.value(
        executeHistoryPageWindow(
          database: _database,
          repository: _repository,
          request: request,
        ),
      );
    } catch (error) {
      return Future.error(HistoryPageQueryException('$error'));
    }
  }

  @override
  Future<void> dispose() async {
    // 复用调用方传入的连接，不在此处关闭。
  }
}
