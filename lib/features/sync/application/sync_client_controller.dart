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
    Set<SyncCategory> selectedCategories = const {},
    this.errorMessage,
    this.preparedImport,
    this.sourceDeviceName,
    this.isPaired = false,
    this.sensitiveRequestConfirmed = false,
  }) : selectedCategories = Set.unmodifiable(selectedCategories);

  final SyncPhase phase;
  final DiscoveredServer? server;
  @Deprecated('Task 8 将以 catalog group ID 替换旧四分类。')
  final Set<SyncCategory> selectedCategories;
  final String? errorMessage;
  final SettingsSyncPreparedImport? preparedImport;
  final String? sourceDeviceName;
  final bool isPaired;
  final bool sensitiveRequestConfirmed;

  @override
  List<Object?> get props => [
    phase,
    (server?.deviceName, server?.ip, server?.httpPort),
    selectedCategories.map((category) => category.index).toList()..sort(),
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
    Set<SyncCategory>? selectedCategories,
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
      selectedCategories: selectedCategories ?? this.selectedCategories,
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
///
/// SyncCategory 仅是 Task 8 前的 presentation 兼容适配器；实际 wire 请求
/// 和 Settings 导入都使用稳定 group ID 与 Settings-owned prepared import。
class SyncClientController extends Notifier<SyncClientState> {
  SyncClientController({SyncClientProtocol? protocol})
    : _injectedProtocol = protocol;

  final SyncClientProtocol? _injectedProtocol;
  late final SyncClientProtocol _protocolCoordinator;
  StreamSubscription<DiscoveredServer>? _discoverySubscription;
  int _generation = 0;

  @override
  SyncClientState build() {
    _protocolCoordinator =
        _injectedProtocol ??
        SyncClientProtocolCoordinator(
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

  @Deprecated('Task 8 将改用稳定 SettingsSyncGroupId。')
  void toggleCategory(SyncCategory category) {
    final categories = Set<SyncCategory>.from(state.selectedCategories);
    if (categories.contains(category)) {
      categories.remove(category);
    } else {
      categories.add(category);
    }
    state = state.copyWith(
      phase: state.server == null ? state.phase : SyncPhase.connected,
      selectedCategories: categories,
      sensitiveRequestConfirmed: false,
      preparedImport: null,
      errorMessage: null,
    );
  }

  @Deprecated('Task 8 将改用 catalog descriptor。')
  void selectAllCategories() {
    state = state.copyWith(
      phase: state.server == null ? state.phase : SyncPhase.connected,
      selectedCategories: Set<SyncCategory>.from(SyncCategory.values),
      sensitiveRequestConfirmed: false,
      preparedImport: null,
      errorMessage: null,
    );
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
    final requestedCategories = Set<SyncCategory>.from(
      state.selectedCategories,
    );
    final requestedGroups = _groupsForCategories(requestedCategories);

    state = state.copyWith(
      phase: SyncPhase.syncing,
      errorMessage: null,
      preparedImport: null,
    );

    try {
      final document = await _protocolCoordinator.requestSettings(
        server: server,
        groups: requestedGroups,
        confirmedSensitive: state.sensitiveRequestConfirmed,
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

Set<SettingsSyncGroupId> _groupsForCategories(Set<SyncCategory> categories) {
  final groups = <SettingsSyncGroupId>{};
  for (final category in categories) {
    switch (category) {
      case SyncCategory.providers:
        groups.add(const SettingsSyncGroupId('providers'));
      case SyncCategory.presets:
        groups.add(const SettingsSyncGroupId('presets'));
      case SyncCategory.prompts:
        groups.add(const SettingsSyncGroupId('prompts'));
      case SyncCategory.other:
        groups.addAll({
          SettingsSyncGroupId('network'),
          SettingsSyncGroupId('outputProcessing'),
          SettingsSyncGroupId('other'),
        });
    }
  }
  return Set.unmodifiable(groups);
}
