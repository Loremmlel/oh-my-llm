import '../domain/models/discovered_server.dart';

/// 广播会话：stop 幂等且共享一次清理，done 在资源释放完成后完成。
abstract interface class SyncUdpBroadcastSession {
  Future<void> stop();
  Future<void> get done;
}

/// 监听会话：ready 在锁获取、绑定与广播使能后完成；port 暴露实际绑定端口；
/// 取消 servers 流会触发 close；done 在清理完成后完成。
abstract interface class SyncUdpListenSession {
  Stream<DiscoveredServer> get servers;
  Future<void> get ready;
  int get port;
  Future<void> close();
  Future<void> get done;
}
