import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/discovered_server.dart';
import 'sync_multicast_lock.dart';
import 'sync_udp_announcement_codec.dart';
import 'sync_udp_scheduler.dart';
import 'sync_udp_sessions.dart';
import 'sync_udp_socket.dart';

export '../domain/models/discovered_server.dart';

/// UDP 广播发现服务。
///
/// socket、调度器与 MulticastLock 均为可注入边界：生产使用 [SyncUdpDiscovery.system]
/// （真实 UDP socket + Timer + Android 平台通道），测试注入 fake 确定性驱动生命周期。
final class SyncUdpDiscovery {
  SyncUdpDiscovery({
    required SyncUdpSocketFactory socketFactory,
    required SyncUdpScheduler scheduler,
    required SyncMulticastLock multicastLock,
    SyncUdpAnnouncementCodec codec = const SyncUdpAnnouncementCodec(),
  }) : _socketFactory = socketFactory,
       _scheduler = scheduler,
       _multicastLock = multicastLock,
       _codec = codec;

  final SyncUdpSocketFactory _socketFactory;
  final SyncUdpScheduler _scheduler;
  final SyncMulticastLock _multicastLock;
  final SyncUdpAnnouncementCodec _codec;

  /// 生产默认发现端口：监听绑定与广播目标共用。
  static const int defaultDiscoveryPort = 47280;

  /// 生产实例：真实 socket、Timer 调度器与平台 MulticastLock。
  static final SyncUdpDiscovery system = SyncUdpDiscovery(
    socketFactory: const RawSyncUdpSocketFactory(),
    scheduler: const TimerSyncUdpScheduler(),
    multicastLock: const PlatformSyncMulticastLock(),
  );

  /// 开始周期性 UDP 广播，返回可停止的会话。
  ///
  /// 广播绑定 anyIPv4 的 OS 分配端口；[broadcastAddress] 缺省回退 255.255.255.255。
  /// [broadcastInterval] 生产保持默认 2s。发送失败只记日志，不终止广播。
  Future<SyncUdpBroadcastSession> startBroadcasting({
    required int httpPort,
    required String deviceName,
    required String serverId,
    InternetAddress? broadcastAddress,
    Duration broadcastInterval = const Duration(seconds: 2),
    int discoveryPort = SyncUdpDiscovery.defaultDiscoveryPort,
  }) async {
    await _multicastLock.acquire();

    final SyncUdpSocket socket;
    try {
      socket = await _socketFactory.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      // 绑定失败：释放已获取的锁后重新抛出。
      await _multicastLock.release();
      rethrow;
    }
    socket.broadcastEnabled = true;

    final targetAddress =
        broadcastAddress ?? InternetAddress('255.255.255.255');
    final payload = _codec.encode(
      httpPort: httpPort,
      deviceName: deviceName,
      serverId: serverId,
    );

    void sendBroadcast() {
      try {
        socket.send(payload, targetAddress, discoveryPort);
      } catch (e) {
        debugPrint('UDP 广播发送失败: $e');
      }
    }

    sendBroadcast();
    final periodicTask = _scheduler.periodic(broadcastInterval, sendBroadcast);

    return _SyncUdpBroadcastSessionImpl(() async {
      periodicTask.cancel();
      await socket.close();
      await _multicastLock.release();
    });
  }

  /// 监听局域网内的服务端广播，返回显式会话。
  ///
  /// 同步返回会话并内部异步启动：获取锁 -> 绑定 -> 使能广播 -> 就绪。
  /// [bindAddress] 缺省绑定 anyIPv4；[timeout] 为无有效公告时的空闲超时，
  /// 只有成功解码的公告才会重置截止定时器。取消订阅会触发会话清理。
  SyncUdpListenSession listenForServers({
    Duration timeout = const Duration(seconds: 6),
    InternetAddress? bindAddress,
    int discoveryPort = SyncUdpDiscovery.defaultDiscoveryPort,
  }) {
    return _SyncUdpListenSessionImpl(
      socketFactory: _socketFactory,
      scheduler: _scheduler,
      multicastLock: _multicastLock,
      codec: _codec,
      bindAddress: bindAddress ?? InternetAddress.anyIPv4,
      discoveryPort: discoveryPort,
      timeout: timeout,
    );
  }
}

/// 监听会话实现：独占绑定、空闲超时与清理状态机。
///
/// 状态单向推进：starting -> ready -> cleaning（任一步失败或关闭都进入 cleaning）。
/// 清理 Future 共享且幂等：定时任务、socket 订阅、socket、锁、流都只释放一次，
/// 取消订阅（onCancel）、close 与超时走同一条清理路径。
///
/// 生命周期完成规则：
/// - 绑定成功 -> 记录端口 -> 完成 ready；
/// - 绑定完成前关闭 -> ready 以 StateError('UDP 监听已关闭') 完成，迟到的 socket 立即关闭；
/// - 绑定失败 -> ready 以绑定错误完成，关闭流、释放锁、完成 done；
/// - 超时 -> 经共享清理关闭流并完成 done。
final class _SyncUdpListenSessionImpl implements SyncUdpListenSession {
  _SyncUdpListenSessionImpl({
    required SyncUdpSocketFactory socketFactory,
    required SyncUdpScheduler scheduler,
    required SyncMulticastLock multicastLock,
    required SyncUdpAnnouncementCodec codec,
    required InternetAddress bindAddress,
    required int discoveryPort,
    required Duration timeout,
  }) : _socketFactory = socketFactory,
       _scheduler = scheduler,
       _multicastLock = multicastLock,
       _codec = codec,
       _bindAddress = bindAddress,
       _discoveryPort = discoveryPort,
       _timeout = timeout {
    // 控制器须在构造体内创建：onCancel 闭包访问实例状态，字段初始化器不允许。
    _serversController = StreamController<DiscoveredServer>(
      onCancel: () {
        // onCancel 在消费方取消订阅或清理自身关闭流时触发；返回 void 而非清理
        // Future，避免 close 的 done 投递等待清理 Future 形成循环等待。
        if (_closed) return;
        unawaited(_cleanup());
      },
    );
    _startupFuture = _start();
  }

  final SyncUdpSocketFactory _socketFactory;
  final SyncUdpScheduler _scheduler;
  final SyncMulticastLock _multicastLock;
  final SyncUdpAnnouncementCodec _codec;
  final InternetAddress _bindAddress;
  final int _discoveryPort;
  final Duration _timeout;

  late final StreamController<DiscoveredServer> _serversController;

  final _ready = Completer<void>();
  final _done = Completer<void>();

  /// 进行中的启动流程；清理会等待它，保证 close-before-bind 时 done 在
  /// 迟到的 socket 关闭之后才完成。
  Future<void>? _startupFuture;
  Future<void>? _cleanupFuture;
  SyncUdpSocket? _socket;
  SyncUdpScheduledTask? _deadlineTask;
  StreamSubscription<SyncUdpDatagram>? _socketSub;
  int _port = 0;
  bool _closed = false;
  bool _lockReleased = false;

  @override
  Stream<DiscoveredServer> get servers => _serversController.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  int get port => _port;

  @override
  Future<void> close() => _cleanup();

  @override
  Future<void> get done => _done.future;

  Future<void> _start() async {
    try {
      await _multicastLock.acquire();
    } catch (error) {
      await _failStart(error);
      return;
    }
    if (_closed) return;

    final SyncUdpSocket socket;
    try {
      socket = await _socketFactory.bind(_bindAddress, _discoveryPort);
    } catch (error) {
      if (_closed) return;
      await _failStart(error);
      return;
    }

    // 绑定完成前已关闭：迟到的 socket 立即关闭，不发布任何事件。
    if (_closed) {
      await socket.close();
      return;
    }

    // 绑定后初始化（broadcastEnabled / 调度 / 订阅）抛异常时走失败路径：
    // 关闭已绑定 socket、以 ready 错误暴露问题、释放锁并完成 done，保证
    // _startupFuture 不以错误完成、清理路径的 done 永不挂起。
    try {
      _socket = socket;
      _port = socket.port;
      socket.broadcastEnabled = true;
      _armDeadline();
      _socketSub = socket.datagrams.listen(_onDatagram);
      if (!_ready.isCompleted) _ready.complete();
    } catch (error) {
      _socket = null;
      // 关闭失败不阻断失败路径（仅注入 fake 可达，生产 socket 关闭不抛）。
      await socket.close().then<void>((_) {}, onError: (Object _) {});
      await _failStart(error);
    }
  }

  void _onDatagram(SyncUdpDatagram datagram) {
    final server = _codec.decode(
      data: datagram.data,
      sourceAddress: datagram.address.address,
    );
    if (server == null) return;
    _serversController.add(server);
    _armDeadline();
  }

  /// 重置空闲截止定时器：只有成功解码的公告才调用（替换旧的一次性任务）。
  void _armDeadline() {
    _deadlineTask?.cancel();
    _deadlineTask = _scheduler.schedule(_timeout, () {
      unawaited(_cleanup());
    });
  }

  /// 启动失败：ready 以错误完成，关闭流、释放锁并完成 done。
  Future<void> _failStart(Object error) async {
    if (!_ready.isCompleted) _ready.completeError(error);
    unawaited(_serversController.close());
    await _releaseLock();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _releaseLock() async {
    if (_lockReleased) return;
    _lockReleased = true;
    await _multicastLock.release();
  }

  Future<void> _cleanup() {
    final running = _cleanupFuture;
    if (running != null) return running;
    _closed = true;
    return _cleanupFuture = _runCleanup();
  }

  Future<void> _runCleanup() async {
    _deadlineTask?.cancel();
    _deadlineTask = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close();
    await _releaseLock();
    // 不 await 关闭 Future：无人订阅的控制器 close 永不完成（挂起的 done 需等
    // 后续订阅者），且 onCancel 已不返回清理 Future，done 投递不会等待清理。
    unawaited(_serversController.close());
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('UDP 监听已关闭'));
    }
    // 启动失败（注入的 socket/scheduler 抛异常）不阻塞 done：错误已由 ready
    // 完成错误或 _failStart 投递，清理路径只须吞掉启动错误、保证 done 必完成。
    await _startupFuture?.catchError((Object _) {});
    if (!_done.isCompleted) _done.complete();
  }
}

/// 广播会话实现：stop 触发清理且幂等，共享同一个清理 Future；done 为纯被动
/// 信号，不触发清理，只等待 stop 创建的清理 Future 完成（与监听会话的
/// 被动 done 对称）；从未 stop 的会话 await done 会一直挂起。
final class _SyncUdpBroadcastSessionImpl implements SyncUdpBroadcastSession {
  _SyncUdpBroadcastSessionImpl(this._cleanup);

  final Future<void> Function() _cleanup;
  Future<void>? _cleanupFuture;
  final _done = Completer<void>();

  @override
  Future<void> stop() => _runCleanup();

  @override
  Future<void> get done => _done.future;

  Future<void> _runCleanup() {
    final running = _cleanupFuture;
    if (running != null) return running;
    final cleanup = _cleanup();
    _cleanupFuture = cleanup;
    // 清理无论成败都投递 done 完成（错误吞掉，由 stop 的返回值向调用方
    // 投递），等待 done 的调用方不会因注入的 socket/锁异常而挂起。
    unawaited(
      cleanup.then<void>(
        (_) => _done.complete(),
        onError: (Object _) => _done.complete(),
      ),
    );
    return cleanup;
  }
}
