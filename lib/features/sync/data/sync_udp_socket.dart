import 'dart:io';

/// UDP 数据报的传输边界值：载荷字节、来源地址与来源端口。
final class SyncUdpDatagram {
  const SyncUdpDatagram({
    required this.data,
    required this.address,
    required this.port,
  });

  final List<int> data;
  final InternetAddress address;
  final int port;
}

/// 数据报 socket 边界：隔离 RawDatagramSocket 与 RawSocketEvent。
abstract interface class SyncUdpSocket {
  Stream<SyncUdpDatagram> get datagrams;
  int get port;
  set broadcastEnabled(bool value);
  int send(List<int> data, InternetAddress address, int port);
  Future<void> close();
}

/// socket 工厂边界：测试可注入脚本化 socket 或绑定错误。
abstract interface class SyncUdpSocketFactory {
  Future<SyncUdpSocket> bind(InternetAddress address, int port);
}

/// 生产 socket 工厂：用 [RawDatagramSocket.bind] 绑定并包装为 [SyncUdpSocket]。
///
/// 全项目唯一直接操作 [RawDatagramSocket] 的代码。
final class RawSyncUdpSocketFactory implements SyncUdpSocketFactory {
  const RawSyncUdpSocketFactory();

  @override
  Future<SyncUdpSocket> bind(InternetAddress address, int port) async {
    final socket = await RawDatagramSocket.bind(address, port);
    return _RawSyncUdpSocket(socket);
  }
}

/// [RawDatagramSocket] 的适配器：read 事件转为 [SyncUdpDatagram]，close 幂等。
final class _RawSyncUdpSocket implements SyncUdpSocket {
  _RawSyncUdpSocket(this._socket) {
    _datagrams = _readLoop(_socket);
  }

  final RawDatagramSocket _socket;
  late final Stream<SyncUdpDatagram> _datagrams;

  /// 逐个消费 socket 事件；receive 为空（并发关闭）时跳过。
  static Stream<SyncUdpDatagram> _readLoop(RawDatagramSocket socket) async* {
    await for (final event in socket) {
      if (event != RawSocketEvent.read) continue;
      final datagram = socket.receive();
      if (datagram == null) continue;
      yield SyncUdpDatagram(
        data: datagram.data,
        address: datagram.address,
        port: datagram.port,
      );
    }
  }

  @override
  Stream<SyncUdpDatagram> get datagrams => _datagrams;

  @override
  int get port => _socket.port;

  @override
  set broadcastEnabled(bool value) => _socket.broadcastEnabled = value;

  @override
  int send(List<int> data, InternetAddress address, int port) =>
      _socket.send(data, address, port);

  var _closed = false;

  @override
  Future<void> close() {
    if (_closed) return Future.value();
    _closed = true;
    _socket.close();
    return Future.value();
  }
}
