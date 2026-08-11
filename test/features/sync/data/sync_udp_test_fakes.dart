import 'dart:async';
import 'dart:io';

import 'package:oh_my_llm/features/sync/data/sync_multicast_lock.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_scheduler.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_socket.dart';

/// 手动调度任务：fire 显式触发回调；一次性任务触发后立即失效。
final class ManualSyncUdpTask implements SyncUdpScheduledTask {
  ManualSyncUdpTask(this.delay, this._callback, {required this.repeating});
  final Duration delay;
  final void Function() _callback;
  final bool repeating;
  var _active = true;
  @override
  bool get isActive => _active;
  void fire() {
    if (!_active) return;
    if (!repeating) _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;
}

/// 手动调度器：任务只登记不运行，由测试显式 fire 驱动。
final class ManualSyncUdpScheduler implements SyncUdpScheduler {
  final oneShotTasks = <ManualSyncUdpTask>[];
  final periodicTasks = <ManualSyncUdpTask>[];

  @override
  SyncUdpScheduledTask schedule(Duration delay, void Function() callback) {
    final task = ManualSyncUdpTask(delay, callback, repeating: false);
    oneShotTasks.add(task);
    return task;
  }

  @override
  SyncUdpScheduledTask periodic(Duration interval, void Function() callback) {
    final task = ManualSyncUdpTask(interval, callback, repeating: true);
    periodicTasks.add(task);
    return task;
  }
}

/// 假 socket：同步流式投递数据报，记录发送与关闭调用，供测试断言。
final class FakeSyncUdpSocket implements SyncUdpSocket {
  FakeSyncUdpSocket({this.port = 0, this.broadcastEnabled = false});

  @override
  final int port;
  bool broadcastEnabled;

  /// close 调用次数；close 本身幂等（重复调用安全）。
  int closeCount = 0;

  /// datagrams getter 被获取的次数；close-before-bind 场景应为 0。
  int listenedCount = 0;

  /// 记录 send 的载荷与目标，供断言。
  final sent = <({List<int> data, InternetAddress address, int port})>[];

  /// 同步广播控制器：emit 在调用帧内完成投递，测试无需等待即可断言。
  final _controller = StreamController<SyncUdpDatagram>.broadcast(sync: true);

  @override
  Stream<SyncUdpDatagram> get datagrams {
    listenedCount++;
    return _controller.stream;
  }

  @override
  int send(List<int> data, InternetAddress address, int port) {
    sent.add((data: data, address: address, port: port));
    return data.length;
  }

  @override
  Future<void> close() {
    closeCount++;
    return _controller.close();
  }

  void emit(SyncUdpDatagram datagram) => _controller.add(datagram);

  void emitError(Object error) => _controller.addError(error);
}

/// 队列化 socket 工厂：条目按顺序出队，可为 socket、待完成 Completer 或错误。
final class QueuedSyncUdpSocketFactory implements SyncUdpSocketFactory {
  QueuedSyncUdpSocketFactory(List<Object> queue) : _queue = [...queue];

  final List<Object> _queue;

  /// 记录每次 bind 请求的地址与端口。
  final requested = <({InternetAddress address, int port})>[];

  @override
  Future<SyncUdpSocket> bind(InternetAddress address, int port) {
    requested.add((address: address, port: port));
    final entry = _queue.removeAt(0);
    final socket = entry;
    if (socket is SyncUdpSocket) return Future.value(socket);
    final completer = entry;
    if (completer is Completer<SyncUdpSocket>) return completer.future;
    return Future<SyncUdpSocket>.error(entry);
  }
}

/// 记录型 MulticastLock：计数 acquire/release，可脚本化抛出错误。
final class RecordingSyncMulticastLock implements SyncMulticastLock {
  int acquireCount = 0;
  int releaseCount = 0;
  Object? acquireError;
  Object? releaseError;

  @override
  Future<void> acquire() async {
    acquireCount++;
    final error = acquireError;
    if (error != null) throw error;
  }

  @override
  Future<void> release() async {
    releaseCount++;
    final error = releaseError;
    if (error != null) throw error;
  }
}
