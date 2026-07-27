import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/network_interface_info.dart';
import '../domain/models/sync_pairing.dart';
import 'broadcast_prefix_length_provider.dart';
import 'network_interface_provider.dart';
import 'ports/settings_sync_facade.dart';
import 'ports/sync_media_route_factory.dart';
import 'ports/sync_server_transport.dart';
import 'ports/sync_clock.dart';
import 'ports/sync_crypto.dart';
import 'ports/sync_pairing_repository.dart';
import 'sync_server_protocol_coordinator.dart';
import '../domain/models/sync_protocol_message.dart';
import '../domain/models/sync_types.dart';

const String _deviceNameKey = 'sync.device_name';

const Object _sentinel = Object();

class SyncServerState extends Equatable {
  const SyncServerState({
    this.isRunning = false,
    this.deviceName = '',
    this.httpPort,
    this.servedRequestCount = 0,
    this.lastError,
    this.selectedInterface,
    this.pairedPeers = const [],
    this.pendingAuthorizations = const [],
  });

  final bool isRunning;
  final String deviceName;
  final int? httpPort;
  final int servedRequestCount;
  final String? lastError;
  final NetworkInterfaceInfo? selectedInterface;
  final List<SyncPairingRecord> pairedPeers;
  final List<SyncAuthorizationRequest> pendingAuthorizations;

  @override
  List<Object?> get props => [
    isRunning,
    deviceName,
    httpPort,
    servedRequestCount,
    lastError,
    (selectedInterface?.name, selectedInterface?.ip),
    pairedPeers,
    pendingAuthorizations,
  ];

  SyncServerState copyWith({
    bool? isRunning,
    String? deviceName,
    Object? httpPort = _sentinel,
    int? servedRequestCount,
    Object? lastError = _sentinel,
    Object? selectedInterface = _sentinel,
    List<SyncPairingRecord>? pairedPeers,
    List<SyncAuthorizationRequest>? pendingAuthorizations,
  }) {
    return SyncServerState(
      isRunning: isRunning ?? this.isRunning,
      deviceName: deviceName ?? this.deviceName,
      httpPort: identical(httpPort, _sentinel)
          ? this.httpPort
          : httpPort as int?,
      servedRequestCount: servedRequestCount ?? this.servedRequestCount,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      selectedInterface: identical(selectedInterface, _sentinel)
          ? this.selectedInterface
          : selectedInterface as NetworkInterfaceInfo?,
      pairedPeers: pairedPeers ?? this.pairedPeers,
      pendingAuthorizations:
          pendingAuthorizations ?? this.pendingAuthorizations,
    );
  }
}

final syncServerControllerProvider =
    NotifierProvider<SyncServerController, SyncServerState>(
      SyncServerController.new,
      isAutoDispose: true,
    );

/// 同步服务端是否正在广播的派生 Provider。
///
/// 只在 [SyncServerState.isRunning] 变化时通知监听者，
/// 避免 widget 因 deviceName、httpPort 等无关字段变化而重建。
final isSyncServerRunningProvider = Provider<bool>(
  (ref) => ref.watch(syncServerControllerProvider.select((s) => s.isRunning)),
);

/// 同步服务端控制器，管理 HTTP 服务端和 UDP 广播的运行会话。
///
/// 成功启动后以唯一的 keep-alive link 跨页面保活；显式停止、应用销毁时由
/// transport 按 UDP、HTTP 顺序释放。媒体路由及其 scanner、缩略图 cache/generator
/// 的组装归 app composition 所有，不是 controller 全局资源。
class SyncServerController extends Notifier<SyncServerState> {
  late final SyncServerTransport _transport;
  late final SyncServerProtocolCoordinator _protocolCoordinator;
  Future<void>? _pendingRestart;
  Future<void>? _startInFlight;
  Future<void> _shutdownFuture = Future<void>.value();
  KeepAliveLink? _keepAliveLink;
  int _generation = 0;
  bool _isStopping = false;

  /// 当前停止流程；容器销毁后可等待它确认 HTTP/UDP 均已释放。
  Future<void> get shutdownFuture => _shutdownFuture;

  @override
  SyncServerState build() {
    _transport = ref.read(syncServerTransportProvider);
    _protocolCoordinator = SyncServerProtocolCoordinator(
      pairingRepository: ref.read(syncPairingRepositoryProvider),
      crypto: ref.read(syncCryptoProvider),
      clock: ref.read(syncClockProvider),
      settingsFacade: ref.read(settingsSyncFacadeProvider),
    );
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedName = prefs.getString(_deviceNameKey);
    final deviceName = savedName ?? Platform.localHostname;

    ref.onDispose(() {
      unawaited(_beginStop(publishState: false));
    });

    return SyncServerState(deviceName: deviceName);
  }

  Future<void> start() {
    if (_isStopping) {
      return _shutdownFuture.then((_) {
        if (!ref.mounted) return Future<void>.value();
        return start();
      });
    }
    if (state.isRunning) return Future<void>.value();
    final pendingStart = _startInFlight;
    if (pendingStart != null) return pendingStart;

    final generation = ++_generation;
    late final Future<void> startFuture;
    startFuture = _start(generation).whenComplete(() {
      if (identical(_startInFlight, startFuture)) {
        _startInFlight = null;
      }
    });
    _startInFlight = startFuture;
    return startFuture;
  }

  Future<void> _start(int generation) async {
    if (!_isCurrent(generation)) return;

    try {
      // 获取用户选择的网络接口与子网掩码，计算子网广播地址
      final interfaces = await ref.read(availableInterfacesProvider.future);
      if (!_isCurrent(generation)) return;
      final selectedIndex = ref.read(selectedInterfaceIndexProvider);
      final prefix = ref.read(selectedBroadcastPrefixLengthProvider);
      NetworkInterfaceInfo? selectedIface;
      InternetAddress? broadcastAddr;

      if (interfaces.isNotEmpty) {
        selectedIface =
            interfaces[selectedIndex.clamp(0, interfaces.length - 1)];
        broadcastAddr = prefix.computeBroadcast(
          InternetAddress(selectedIface.ip),
        );
      }

      final mediaRoutes = await ref
          .read(syncMediaRouteFactoryProvider)
          .createRoutes();
      if (!_isCurrent(generation)) return;
      final handle = await _transport.start(
        SyncServerStartRequest(
          deviceName: state.deviceName,
          serverId:
              (await ref
                      .read(syncPairingRepositoryProvider)
                      .ensureLocalIdentity(
                        ref.read(syncCryptoProvider).randomBytes(16),
                      ))
                  .id,
          broadcastAddress: broadcastAddr,
          onRequest: _handleRequest,
          mediaRoutes: mediaRoutes,
        ),
      );
      if (!_isCurrent(generation)) {
        await _cleanup();
        return;
      }
      _keepAliveLink ??= ref.keepAlive();
      state = state.copyWith(
        isRunning: true,
        httpPort: handle.httpPort,
        lastError: null,
        selectedInterface: selectedIface,
        pairedPeers: await _protocolCoordinator.pairedPeers(),
        pendingAuthorizations: _protocolCoordinator.pendingAuthorizations(),
      );
    } catch (e) {
      await _cleanup();
      if (!_isCurrent(generation)) return;
      final keepAliveLink = _keepAliveLink;
      _keepAliveLink = null;
      state = state.copyWith(
        isRunning: false,
        httpPort: null,
        lastError: '启动失败: $e',
        selectedInterface: null,
      );
      keepAliveLink?.close();
    }
  }

  Future<void> stop() => _beginStop(publishState: true);

  Future<void> _beginStop({required bool publishState}) {
    if (_isStopping) return _shutdownFuture;
    _generation++;
    _isStopping = true;
    final startInFlight = _startInFlight;
    final shutdown =
        _stopAfterStart(
          startInFlight: startInFlight,
          publishState: publishState,
        ).whenComplete(() {
          _isStopping = false;
        });
    _shutdownFuture = shutdown;
    return shutdown;
  }

  Future<void> _stopAfterStart({
    required Future<void>? startInFlight,
    required bool publishState,
  }) async {
    await startInFlight;
    final keepAliveLink = _keepAliveLink;
    _keepAliveLink = null;
    await _cleanup();
    if (publishState && ref.mounted) {
      state = state.copyWith(
        isRunning: false,
        httpPort: null,
        servedRequestCount: 0,
        pendingAuthorizations: const [],
      );
    }
    keepAliveLink?.close();
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> _cleanup() async {
    _protocolCoordinator.invalidateAllSessions();
    await _transport.stop();
  }

  Future<void> updateDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.deviceName) return;
    state = state.copyWith(deviceName: trimmed);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_deviceNameKey, trimmed);

    if (state.isRunning) {
      final restartGeneration = _generation;
      _pendingRestart = (_pendingRestart ?? Future<void>.value()).then((
        _,
      ) async {
        if (!_isCurrent(restartGeneration) || !state.isRunning) return;
        await _cleanup();
        if (!_isCurrent(restartGeneration) || !state.isRunning) return;
        state = state.copyWith(isRunning: false, httpPort: null);
        await start();
      });
      await _pendingRestart;
    }
  }

  /// 配对码仅返回给本地 UI；不写入 state、持久化或日志。
  Future<String?> generatePairingCode() async {
    if (!state.isRunning) return null;
    return _protocolCoordinator.generatePairingCode();
  }

  Future<void> grantPeer(
    String peerId,
    Set<SyncCategory> categories, {
    required bool confirmedSensitive,
  }) async {
    await _protocolCoordinator.grant(
      peerId: peerId,
      categories: categories,
      confirmedSensitive: confirmedSensitive,
    );
    await _refreshSecurityState();
  }

  void denyAuthorization(String peerId) {
    _protocolCoordinator.denyAuthorization(peerId);
    state = state.copyWith(
      pendingAuthorizations: _protocolCoordinator.pendingAuthorizations(),
    );
  }

  Future<void> revokePeer(String peerId) async {
    await _protocolCoordinator.revoke(peerId);
    await _refreshSecurityState();
  }

  Future<SyncProtocolMessage> _handleRequest(
    SyncProtocolMessage request,
  ) async {
    final result = await _protocolCoordinator.handle(request);
    if (ref.mounted) {
      await _refreshSecurityState(servedSnapshot: result.servedSnapshot);
    }
    return result.message;
  }

  Future<void> _refreshSecurityState({bool servedSnapshot = false}) async {
    final peers = await _protocolCoordinator.pairedPeers();
    if (!ref.mounted) return;
    state = state.copyWith(
      servedRequestCount: servedSnapshot
          ? state.servedRequestCount + 1
          : state.servedRequestCount,
      pairedPeers: peers,
      pendingAuthorizations: _protocolCoordinator.pendingAuthorizations(),
    );
  }
}
