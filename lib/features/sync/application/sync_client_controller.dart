import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/models/settings_export_data.dart';
import 'ports/settings_sync_facade.dart';
import 'ports/sync_client_transport.dart';
import 'ports/sync_clock.dart';
import 'ports/sync_crypto.dart';
import 'ports/sync_pairing_repository.dart';
import 'sync_client_protocol_coordinator.dart';
import '../domain/models/discovered_server.dart';
import '../domain/models/sync_types.dart';
import '../domain/models/sync_protocol_failure.dart';

enum SyncPhase {
  idle,
  discovering,
  connected,
  syncing,
  received,
  noNewData,
  imported,
  error,
}

const Object _sentinel = Object();

class SyncClientState extends Equatable {
  SyncClientState({
    this.phase = SyncPhase.idle,
    this.server,
    Set<SyncCategory> selectedCategories = const {},
    this.errorMessage,
    this.deduplicatedData,
    this.sourceDeviceName,
    this.isPaired = false,
    this.sensitiveRequestConfirmed = false,
  }) : selectedCategories = Set.unmodifiable(selectedCategories);

  final SyncPhase phase;
  final DiscoveredServer? server;
  final Set<SyncCategory> selectedCategories;
  final String? errorMessage;
  final SettingsExportData? deduplicatedData;
  final String? sourceDeviceName;
  final bool isPaired;
  final bool sensitiveRequestConfirmed;

  @override
  List<Object?> get props => [
    phase,
    (server?.deviceName, server?.ip, server?.httpPort),
    selectedCategories.map((category) => category.index).toList()..sort(),
    errorMessage,
    deduplicatedData?.toJsonString(),
    sourceDeviceName,
    isPaired,
    sensitiveRequestConfirmed,
  ];

  SyncClientState copyWith({
    SyncPhase? phase,
    Object? server = _sentinel,
    Set<SyncCategory>? selectedCategories,
    Object? errorMessage = _sentinel,
    Object? deduplicatedData = _sentinel,
    Object? sourceDeviceName = _sentinel,
    bool? isPaired,
    bool? sensitiveRequestConfirmed,
  }) {
    return SyncClientState(
      phase: phase ?? this.phase,
      server: identical(server, _sentinel)
          ? this.server
          : server as DiscoveredServer?,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      deduplicatedData: identical(deduplicatedData, _sentinel)
          ? this.deduplicatedData
          : deduplicatedData as SettingsExportData?,
      sourceDeviceName: identical(sourceDeviceName, _sentinel)
          ? this.sourceDeviceName
          : sourceDeviceName as String?,
      isPaired: isPaired ?? this.isPaired,
      sensitiveRequestConfirmed:
          sensitiveRequestConfirmed ?? this.sensitiveRequestConfirmed,
    );
  }
}

final syncClientControllerProvider =
    NotifierProvider<SyncClientController, SyncClientState>(
      SyncClientController.new,
      isAutoDispose: true,
    );

/// 同步客户端控制器，管理 Sync 页面会话内的发现、请求和导入流程。
///
/// 该 Provider 是页面级 auto-dispose 状态：页面观察者离开后会取消 UDP
/// 发现并在下次进入时从 idle 重建。每轮发现或请求都绑定 generation，避免
/// 已取消会话的异步回调重新写入 state。
class SyncClientController extends Notifier<SyncClientState> {
  StreamSubscription<DiscoveredServer>? _discoverySubscription;
  late final SyncClientProtocolCoordinator _protocolCoordinator;
  int _generation = 0;

  @override
  SyncClientState build() {
    _protocolCoordinator = SyncClientProtocolCoordinator(
      transport: ref.read(syncClientTransportProvider),
      pairingRepository: ref.read(syncPairingRepositoryProvider),
      crypto: ref.read(syncCryptoProvider),
      clock: ref.read(syncClockProvider),
    );
    ref.onDispose(_invalidateDiscovery);
    return SyncClientState();
  }

  Future<void> startDiscovery() async {
    final generation = _invalidateDiscovery();
    state = SyncClientState(phase: SyncPhase.discovering);

    _discoverySubscription = ref
        .read(syncClientTransportProvider)
        .discoverServers()
        .listen(
          (server) async {
            if (!_isCurrent(generation)) return;
            _discoverySubscription?.cancel();
            _discoverySubscription = null;
            if (!server.isProtocolCompatible) {
              state = state.copyWith(
                phase: SyncPhase.error,
                errorMessage: '设备版本不兼容，需要更新',
              );
              return;
            }
            final isPaired = await _protocolCoordinator.isPaired(server);
            if (!_isCurrent(generation)) return;
            state = state.copyWith(
              phase: SyncPhase.connected,
              server: server,
              sourceDeviceName: server.deviceName,
              isPaired: isPaired,
              sensitiveRequestConfirmed: false,
            );
          },
          onDone: () {
            if (!_isCurrent(generation)) return;
            if (state.phase == SyncPhase.discovering) {
              state = state.copyWith(
                phase: SyncPhase.error,
                errorMessage: '未发现服务端，请确认服务端已启动且在同一局域网内',
              );
            }
          },
          onError: (Object e) {
            if (!_isCurrent(generation)) return;
            state = state.copyWith(
              phase: SyncPhase.error,
              errorMessage: '发现过程出错: $e',
            );
          },
        );
  }

  void toggleCategory(SyncCategory category) {
    final categories = Set<SyncCategory>.from(state.selectedCategories);
    if (categories.contains(category)) {
      categories.remove(category);
    } else {
      categories.add(category);
    }
    state = state.copyWith(selectedCategories: categories);
    state = state.copyWith(sensitiveRequestConfirmed: false);
  }

  void selectAllCategories() {
    state = state.copyWith(
      selectedCategories: Set<SyncCategory>.from(SyncCategory.values),
    );
    state = state.copyWith(sensitiveRequestConfirmed: false);
  }

  /// 仅将本次请求的用户意图保留在内存中；类别或连接变化会清除它。
  void confirmSensitiveRequest() {
    state = state.copyWith(sensitiveRequestConfirmed: true);
  }

  Future<void> pairWithCode(String code, {String displayName = '本机'}) async {
    final server = state.server;
    if (server == null || code.trim().isEmpty) return;
    final generation = _generation;
    state = state.copyWith(phase: SyncPhase.syncing, errorMessage: null);
    try {
      await _protocolCoordinator.pair(
        server: server,
        code: code.trim(),
        displayName: displayName,
      );
      if (!_isCurrent(generation)) return;
      state = state.copyWith(phase: SyncPhase.connected, isPaired: true);
    } on SyncProtocolFailure catch (failure) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: failure.userMessage,
      );
    } on SyncTransportException catch (failure) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: failure.userMessage,
      );
    }
  }

  Future<void> requestSync() async {
    if (state.phase == SyncPhase.syncing) return;
    final server = state.server;
    if (server == null || state.selectedCategories.isEmpty) return;
    final generation = _generation;

    state = state.copyWith(
      phase: SyncPhase.syncing,
      errorMessage: null,
      deduplicatedData: null,
    );

    try {
      final exportData = await _protocolCoordinator.requestSettings(
        server: server,
        categories: state.selectedCategories,
        confirmedSensitive: state.sensitiveRequestConfirmed,
      );
      if (!_isCurrent(generation)) return;

      final deduplicated = ref
          .read(settingsSyncFacadeProvider)
          .deduplicateIncoming(exportData);
      if (!deduplicated.hasContent) {
        state = state.copyWith(phase: SyncPhase.noNewData);
        return;
      }

      state = state.copyWith(
        phase: SyncPhase.received,
        deduplicatedData: deduplicated,
      );
    } on SyncProtocolFailure catch (e) {
      if (!_isCurrent(generation)) return;
      final pairingLost =
          e.code == SyncProtocolErrorCode.pairingRequired ||
          e.code == SyncProtocolErrorCode.pairingRejected;
      if (pairingLost) {
        await _protocolCoordinator.forgetPairing(server);
        if (!_isCurrent(generation)) return;
      }
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: e.userMessage,
        isPaired: pairingLost ? false : null,
      );
    } on SyncTransportException catch (e) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: e.userMessage,
      );
    } catch (e) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(phase: SyncPhase.error, errorMessage: '同步失败: $e');
    }
  }

  /// 执行导入并返回是否成功。
  Future<bool> executeImport() async {
    final data = state.deduplicatedData;
    if (data == null) return false;
    final generation = _generation;

    try {
      final success = await ref
          .read(settingsSyncFacadeProvider)
          .importDeduplicated(data);
      if (success && _isCurrent(generation)) {
        state = state.copyWith(phase: SyncPhase.imported);
      }
      return success;
    } catch (e) {
      if (!_isCurrent(generation)) return false;
      state = state.copyWith(phase: SyncPhase.error, errorMessage: '导入失败: $e');
      return false;
    }
  }

  void resetToConnected() {
    state = state.copyWith(
      phase: SyncPhase.connected,
      deduplicatedData: null,
      errorMessage: null,
      sensitiveRequestConfirmed: false,
    );
  }

  void cancelAndReset() {
    _invalidateDiscovery();
    _protocolCoordinator.clearSessions();
    if (!ref.mounted) return;
    state = SyncClientState();
  }

  int _invalidateDiscovery() {
    _generation++;
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    return _generation;
  }

  bool _isCurrent(int generation) {
    return ref.mounted && generation == _generation;
  }
}
