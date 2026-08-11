import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/data/sync_udp_announcement_codec.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_socket.dart';

import 'sync_udp_test_fakes.dart';

/// 等待流关闭的完成信号（isDone 不在 flutter_test 导出集合内，用显式 onDone 代替）。
Future<void> streamClosed(Stream<DiscoveredServer> stream) {
  final done = Completer<void>();
  stream.listen(
    null,
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}

void main() {
  group('SyncUdpDiscovery 广播会话', () {
    late ManualSyncUdpScheduler scheduler;
    late RecordingSyncMulticastLock lock;
    late FakeSyncUdpSocket socket;
    late SyncUdpDiscovery discovery;

    setUp(() {
      scheduler = ManualSyncUdpScheduler();
      lock = RecordingSyncMulticastLock();
      socket = FakeSyncUdpSocket();
      discovery = SyncUdpDiscovery(
        socketFactory: QueuedSyncUdpSocketFactory([socket]),
        scheduler: scheduler,
        multicastLock: lock,
      );
      addTearDown(socket.close);
    });

    test('广播立即发送、周期触发后再发送、stop 后不再发送', () async {
      final session = await discovery.startBroadcasting(
        httpPort: 54321,
        deviceName: 'Test-PC',
        serverId: 'server-1',
        broadcastAddress: InternetAddress.loopbackIPv4,
        discoveryPort: 48001,
      );

      expect(socket.sent, hasLength(1));
      scheduler.periodicTasks.single.fire();
      expect(socket.sent, hasLength(2));
      await session.stop();
      scheduler.periodicTasks.single.fire();
      expect(socket.sent, hasLength(2));
      await session.done;
    });

    test('stop 两次只关闭一次 socket 并只释放一次锁', () async {
      final session = await discovery.startBroadcasting(
        httpPort: 54321,
        deviceName: 'Test-PC',
        serverId: 'server-1',
        broadcastAddress: InternetAddress.loopbackIPv4,
        discoveryPort: 48001,
      );

      await session.stop();
      await session.stop();

      expect(socket.closeCount, 1);
      expect(lock.acquireCount, 1);
      expect(lock.releaseCount, 1);
      // 广播绑定 anyIPv4:0，目标地址与发现端口由参数显式指定。
      expect(socket.sent.single.address, InternetAddress.loopbackIPv4);
      expect(socket.sent.single.port, 48001);
      await session.done;
    });
  });

  group('SyncUdpDiscovery 监听会话', () {
    late ManualSyncUdpScheduler scheduler;
    late RecordingSyncMulticastLock lock;

    setUp(() {
      scheduler = ManualSyncUdpScheduler();
      lock = RecordingSyncMulticastLock();
    });

    SyncUdpDiscovery newDiscovery(List<Object> queue) {
      return SyncUdpDiscovery(
        socketFactory: QueuedSyncUdpSocketFactory(queue),
        scheduler: scheduler,
        multicastLock: lock,
      );
    }

    test('ready 在绑定与广播使能后完成并暴露实际端口', () async {
      final socket = FakeSyncUdpSocket(port: 48001);
      final discovery = newDiscovery([socket]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        discoveryPort: 48001,
        timeout: const Duration(seconds: 6),
      );
      addTearDown(() async {
        await session.close();
        await session.done;
      });

      await session.ready;

      expect(session.port, 48001);
      expect(socket.broadcastEnabled, isTrue);
      expect(lock.acquireCount, 1);
      expect(scheduler.oneShotTasks, hasLength(1));
      expect(scheduler.oneShotTasks.single.isActive, isTrue);
    });

    test('合法公告发布一个服务端并替换截止定时器', () async {
      final socket = FakeSyncUdpSocket();
      final discovery = newDiscovery([socket]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      addTearDown(() async {
        await session.close();
        await session.done;
      });
      await session.ready;

      final firstServer = Completer<DiscoveredServer>();
      final sub = session.servers.listen((server) {
        if (!firstServer.isCompleted) firstServer.complete(server);
      });
      addTearDown(sub.cancel);

      final initialDeadline = scheduler.oneShotTasks.single;

      socket.emit(
        SyncUdpDatagram(
          data: const SyncUdpAnnouncementCodec().encode(
            httpPort: 54321,
            deviceName: 'Test-PC',
            serverId: 'server-1',
          ),
          address: InternetAddress.loopbackIPv4,
          port: 54321,
        ),
      );

      final server = await firstServer.future;
      expect(server.deviceName, 'Test-PC');
      expect(server.httpPort, 54321);
      expect(server.serverId, 'server-1');
      expect(server.ip, InternetAddress.loopbackIPv4.address);

      expect(scheduler.oneShotTasks, hasLength(2));
      expect(initialDeadline.isActive, isFalse);
      expect(scheduler.oneShotTasks.last.isActive, isTrue);
    });

    test('畸形数据报不发布服务端且保留原截止定时器', () async {
      final socket = FakeSyncUdpSocket();
      final discovery = newDiscovery([socket]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      addTearDown(() async {
        await session.close();
        await session.done;
      });
      await session.ready;

      var received = 0;
      final sub = session.servers.listen((_) => received++);
      addTearDown(sub.cancel);

      final deadline = scheduler.oneShotTasks.single;

      // 同步 fake 流：emit 返回时解码与校验已同步完成，可直接断言。
      socket.emit(
        SyncUdpDatagram(
          data: utf8.encode('{"app":"other-app"}'),
          address: InternetAddress.loopbackIPv4,
          port: 54321,
        ),
      );

      expect(received, 0);
      expect(deadline.isActive, isTrue);
      expect(scheduler.oneShotTasks, hasLength(1));
    });

    test('截止定时器触发后关闭流、释放锁并完成 done', () async {
      final socket = FakeSyncUdpSocket();
      final discovery = newDiscovery([socket]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      final streamDone = streamClosed(session.servers);
      addTearDown(() async {
        await session.close();
        await session.done;
      });
      await session.ready;

      expect(lock.acquireCount, 1);
      expect(scheduler.oneShotTasks, hasLength(1));

      scheduler.oneShotTasks.single.fire();

      await session.done;
      await streamDone;

      expect(socket.closeCount, 1);
      expect(lock.releaseCount, 1);
      expect(scheduler.oneShotTasks.single.isActive, isFalse);
    });

    test('绑定后取消订阅只清理一次资源', () async {
      final socket = FakeSyncUdpSocket();
      final discovery = newDiscovery([socket]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      addTearDown(() async {
        await session.close();
        await session.done;
      });

      final sub = session.servers.listen((_) {});
      addTearDown(sub.cancel);
      await session.ready;

      await sub.cancel();

      await session.done;
      expect(socket.closeCount, 1);
      expect(socket.listenedCount, 1);
      expect(lock.releaseCount, 1);
      expect(scheduler.oneShotTasks.single.isActive, isFalse);
    });

    test('绑定完成前 close 使 ready 抛 StateError 并关闭随后返回的 socket', () async {
      final bindCompleter = Completer<SyncUdpSocket>();
      final socket = FakeSyncUdpSocket();
      final discovery = newDiscovery([bindCompleter]);
      addTearDown(socket.close);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      final readyError = expectLater(
        session.ready,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'UDP 监听已关闭',
          ),
        ),
      );
      addTearDown(() async {
        if (!bindCompleter.isCompleted) bindCompleter.complete(socket);
        await session.close();
        await session.done;
      });

      // 让 acquire 的微任务先完成，使 close 发生在 bind 挂起期间（close-before-bind 语义）。
      await null;
      // 不 await close：清理会等待挂起的 bind 完成后才结束。
      final closeFuture = session.close();
      bindCompleter.complete(socket);
      await closeFuture;
      await readyError;

      expect(socket.closeCount, 1);
      // 绑定迟到时 socket 从未被订阅，不会发布任何事件。
      expect(socket.listenedCount, 0);
      expect(lock.acquireCount, 1);
      expect(lock.releaseCount, 1);
      await session.done;
    });

    test('绑定失败时 ready 抛出绑定错误并释放锁、关闭流、完成 done', () async {
      final bindError = StateError('绑定失败');
      final discovery = newDiscovery([bindError]);

      final session = discovery.listenForServers(
        timeout: const Duration(seconds: 6),
      );
      final readyError = expectLater(session.ready, throwsA(same(bindError)));
      final streamDone = streamClosed(session.servers);
      addTearDown(() async {
        await session.close();
        await session.done;
      });

      await readyError;
      expect(lock.acquireCount, 1);
      await streamDone;
      expect(lock.releaseCount, 1);
      expect(scheduler.oneShotTasks, isEmpty);
      await session.done;
    });
  });
}
