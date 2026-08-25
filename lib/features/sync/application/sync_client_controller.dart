import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_data.dart';

import 'ports/settings_sync_facade.dart';
import 'ports/sync_client_protocol.dart';
import 'ports/sync_client_transport.dart';
import 'ports/sync_clock.dart';
import 'ports/sync_crypto.dart';
import 'ports/sync_pairing_repository.dart';
import 'sync_client_protocol_coordinator.dart';
import '../domain/models/discovery/discovered_server.dart';
import '../domain/models/protocol/sync_protocol_failure.dart';
import '../domain/models/protocol/sync_types.dart';

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

/// 服务端断开时的统一提示文案，状态与全局气泡共用。
const _disconnectedMessage = '服务端已断开，请重新搜索';

class SyncClientState extends Equatable {
  SyncClientState({
    this.phase = SyncPhase.idle,
    this.server,
    Iterable<SettingsSyncGroupDescriptor> availableGroups = const [],
    Iterable<SettingsSyncGroupId> selectedGroups = const {},
    this.errorMessage,
    this.preparedImport,
    this.sourceDeviceName,
    this.isPaired = false,
    this.sensitiveRequestConfirmed = false,
  }) : availableGroups = List.unmodifiable(availableGroups),
       selectedGroups = Set.unmodifiable(selectedGroups);

  final SyncPhase phase;
  final DiscoveredServer? server;
  final List<SettingsSyncGroupDescriptor> availableGroups;
  final Set<SettingsSyncGroupId> selectedGroups;
  final String? errorMessage;
  final SettingsSyncPreparedImport? preparedImport;
  final String? sourceDeviceName;
  final bool isPaired;
  final bool sensitiveRequestConfirmed;

  @override
  List<Object?> get props => [
    phase,
    (server?.deviceName, server?.ip, server?.httpPort),
    availableGroups
        .map(
          (group) =>
              (group.id.value, group.label, group.order, group.sensitivity),
        )
        .toList(),
    selectedGroups.map((group) => group.value).toList()..sort(),
    errorMessage,
    preparedImport == null
        ? null
        : (preparedImport!.containsSensitive, preparedImport!.summaries),
    sourceDeviceName,
    isPaired,
    sensitiveRequestConfirmed,
  ];

  SyncClientState copyWith({
    SyncPhase? phase,
    Object? server = _sentinel,
    Iterable<SettingsSyncGroupDescriptor>? availableGroups,
    Iterable<SettingsSyncGroupId>? selectedGroups,
    Object? errorMessage = _sentinel,
    Object? preparedImport = _sentinel,
    Object? sourceDeviceName = _sentinel,
    bool? isPaired,
    bool? sensitiveRequestConfirmed,
  }) {
    return SyncClientState(
      phase: phase ?? this.phase,
      server: identical(server, _sentinel)
          ? this.server
          : server as DiscoveredServer?,
      availableGroups: availableGroups ?? this.availableGroups,
      selectedGroups: selectedGroups ?? this.selectedGroups,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      preparedImport: identical(preparedImport, _sentinel)
          ? this.preparedImport
          : preparedImport as SettingsSyncPreparedImport?,
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
    );

/// 同步客户端控制器，管理 Sync 页面会话内的发现、请求和导入流程。
class SyncClientController extends Notifier<SyncClientState> {
  SyncClientController({SyncClientProtocol? protocol})
    : _injectedProtocol = protocol;

  final SyncClientProtocol? _injectedProtocol;
  late final SyncClientProtocol _protocolCoordinator;
  StreamSubscription<DiscoveredServer>? _discoverySubscription;
  int _generation = 0;

  @override
  SyncClientState build() {
    final settingsFacade = ref.read(settingsSyncFacadeProvider);
    _protocolCoordinator =
        _injectedProtocol ??
        SyncClientProtocolCoordinator(
          transport: ref.read(syncClientTransportProvider),
          pairingRepository: ref.read(syncPairingRepositoryProvider),
          crypto: ref.read(syncCryptoProvider),
          clock: ref.read(syncClockProvider),
        );
    ref.onDispose(_invalidateDiscovery);
    return SyncClientState(availableGroups: settingsFacade.availableGroups);
  }

  Future<void> startDiscovery() async {
    final generation = _invalidateDiscovery();
    state = state.copyWith(
      phase: SyncPhase.discovering,
      errorMessage: null,
      preparedImport: null,
    );

    _discoverySubscription = ref
        .read(syncClientTransportProvider)
        .discoverServers()
        .listen(
          (server) async {
            if (!_isCurrent(generation)) return;
            if (!server.isProtocolCompatible) {
              state = state.copyWith(
                phase: SyncPhase.error,
                errorMessage: '设备版本不兼容，需要更新',
              );
              return;
            }
            final alreadyConnected = state.server != null;
            final isPaired = alreadyConnected
                ? state.isPaired
                : await _protocolCoordinator.isPaired(server);
            if (!_isCurrent(generation)) return;
            state = state.copyWith(
              phase: state.phase == SyncPhase.discovering
                  ? SyncPhase.connected
                  : null,
              server: server,
              sourceDeviceName: server.deviceName,
              isPaired: alreadyConnected ? null : isPaired,
              sensitiveRequestConfirmed: alreadyConnected ? null : false,
            );
          },
          onDone: () {
            if (!_isCurrent(generation)) return;
            if (state.phase == SyncPhase.discovering && state.server == null) {
              state = state.copyWith(
                phase: SyncPhase.error,
                errorMessage: '未发现服务端，请确认服务端已启动且在同一局域网内',
              );
            } else if (state.server != null) {
              state = state.copyWith(
                phase: SyncPhase.error,
                server: null,
                sourceDeviceName: null,
                isPaired: false,
                preparedImport: null,
                errorMessage: _disconnectedMessage,
              );
              ref
                  .read(notificationBubblesProvider.notifier)
                  .show(
                    message: _disconnectedMessage,
                    type: NotificationBubbleType.error,
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

  /// 切换一个由 Settings catalog 提供的稳定分组。
  ///
  /// 未知 ID 可能来自过期的页面事件或测试数据，忽略它可以避免把不在
  /// 当前 catalog 中的内容送入请求，同时不清除仍然有效的用户确认。
  void toggleGroup(SettingsSyncGroupId id) {
    if (!state.availableGroups.any((group) => group.id == id)) return;

    final groups = Set<SettingsSyncGroupId>.from(state.selectedGroups);
    if (groups.contains(id)) {
      groups.remove(id);
    } else {
      groups.add(id);
    }
    _setSelectedGroups(groups);
  }

  /// 选择当前 catalog 中的全部分组，顺序由 [availableGroups] 保留。
  void selectAllGroups() {
    _setSelectedGroups(state.availableGroups.map((group) => group.id).toSet());
  }

  void _setSelectedGroups(Set<SettingsSyncGroupId> groups) {
    state = state.copyWith(
      phase: state.server == null ? state.phase : SyncPhase.connected,
      selectedGroups: groups,
      sensitiveRequestConfirmed: false,
      preparedImport: null,
      errorMessage: null,
    );
  }

  /// 仅将本次请求的用户意图保留在内存中；分组或连接变化会清除它。
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
    if (server == null || state.selectedGroups.isEmpty) return;
    final generation = _generation;
    final requestedGroups = Set<SettingsSyncGroupId>.unmodifiable(
      state.selectedGroups,
    );
    final confirmedSensitive = state.sensitiveRequestConfirmed;

    state = state.copyWith(
      phase: SyncPhase.syncing,
      errorMessage: null,
      preparedImport: null,
    );

    try {
      final document = await _protocolCoordinator.requestSettings(
        server: server,
        groups: requestedGroups,
        confirmedSensitive: confirmedSensitive,
      );
      if (!_isCurrent(generation)) return;

      final prepared = ref
          .read(settingsSyncFacadeProvider)
          .prepareIncoming(document, requestedGroups: requestedGroups);
      if (!_isCurrent(generation)) return;

      state = state.copyWith(
        phase: SyncPhase.received,
        preparedImport: prepared,
      );
    } on SettingsSyncNoNewDataException {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(phase: SyncPhase.noNewData, preparedImport: null);
    } on SettingsSyncPreparationException catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: SyncPhase.error,
        preparedImport: null,
        errorMessage: error.safeMessage,
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

  /// 执行接收阶段的一次性 prepared import，并把安全结果投影回页面状态。
  Future<SettingsSyncImportExecutionResult> executePreparedImport({
    required bool confirmedSensitive,
  }) async {
    final prepared = state.preparedImport;
    if (prepared == null) {
      return const SettingsSyncImportAlreadyConsumed();
    }
    final generation = _generation;

    try {
      final result = await prepared.execute(
        confirmedSensitive: confirmedSensitive,
      );
      if (!_isCurrent(generation)) return result;
      switch (result) {
        case SettingsSyncImportSuccess():
          state = state.copyWith(
            phase: SyncPhase.imported,
            preparedImport: null,
          );
        case SettingsSyncImportStalePreview(:final refreshedImport):
          state = state.copyWith(
            phase: SyncPhase.received,
            preparedImport: refreshedImport,
          );
        case SettingsSyncImportSensitiveConfirmationRequired():
        case SettingsSyncImportFailure():
        case SettingsSyncImportPartialFailure():
        case SettingsSyncImportAlreadyConsumed():
          state = state.copyWith(phase: SyncPhase.received);
      }
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) {
        return const SettingsSyncImportFailure(
          failedLabel: '导入',
          safeReason: '导入未完成，请重试',
        );
      }
      state = state.copyWith(phase: SyncPhase.error, errorMessage: '导入失败: $e');
      return SettingsSyncImportFailure(
        failedLabel: '导入',
        safeReason: '导入未完成，请重试',
      );
    }
  }

  void resetToConnected() {
    state = state.copyWith(
      phase: SyncPhase.connected,
      preparedImport: null,
      errorMessage: null,
      sensitiveRequestConfirmed: false,
    );
  }

  void cancelAndReset() {
    _invalidateDiscovery();
    _protocolCoordinator.clearSessions();
    if (!ref.mounted) return;
    state = SyncClientState(availableGroups: state.availableGroups);
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
