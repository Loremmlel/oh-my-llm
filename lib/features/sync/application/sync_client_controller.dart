import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../settings/application/fixed_prompt_sequences_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/memory_prompts_controller.dart';
import '../../settings/application/preset_prompts_controller.dart';
import '../../settings/application/settings_import_deduplicator.dart';
import '../../settings/application/settings_import_executor.dart';
import '../../settings/application/template_prompts_controller.dart';
import '../../settings/domain/models/settings_export_data.dart';
import '../data/sync_udp_discovery.dart';
import '../domain/models/sync_message.dart';
import '../domain/models/sync_types.dart';

enum SyncPhase { idle, discovering, connected, syncing, received, noNewData, done, error }

const Object _sentinel = Object();

class SyncClientState {
  const SyncClientState({
    this.phase = SyncPhase.idle,
    this.server,
    this.selectedCategories = const {},
    this.errorMessage,
    this.deduplicatedData,
    this.sourceDeviceName,
  });

  final SyncPhase phase;
  final DiscoveredServer? server;
  final Set<SyncCategory> selectedCategories;
  final String? errorMessage;
  final SettingsExportData? deduplicatedData;
  final String? sourceDeviceName;

  SyncClientState copyWith({
    SyncPhase? phase,
    Object? server = _sentinel,
    Set<SyncCategory>? selectedCategories,
    Object? errorMessage = _sentinel,
    Object? deduplicatedData = _sentinel,
    Object? sourceDeviceName = _sentinel,
  }) {
    return SyncClientState(
      phase: phase ?? this.phase,
      server: identical(server, _sentinel) ? this.server : server as DiscoveredServer?,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      errorMessage: identical(errorMessage, _sentinel) ? this.errorMessage : errorMessage as String?,
      deduplicatedData: identical(deduplicatedData, _sentinel) ? this.deduplicatedData : deduplicatedData as SettingsExportData?,
      sourceDeviceName: identical(sourceDeviceName, _sentinel) ? this.sourceDeviceName : sourceDeviceName as String?,
    );
  }
}

final syncClientControllerProvider =
    NotifierProvider<SyncClientController, SyncClientState>(
      SyncClientController.new,
    );

/// 同步客户端控制器，管理设备发现、同步请求和数据导入流程。
class SyncClientController extends Notifier<SyncClientState> {
  StreamSubscription<DiscoveredServer>? _discoverySubscription;

  @override
  SyncClientState build() {
    ref.onDispose(() {
      _discoverySubscription?.cancel();
      _discoverySubscription = null;
    });
    return const SyncClientState();
  }

  Future<void> startDiscovery() async {
    _discoverySubscription?.cancel();
    state = const SyncClientState(phase: SyncPhase.discovering);

    _discoverySubscription = SyncUdpDiscovery.listenForServers().listen(
      (server) {
        _discoverySubscription?.cancel();
        _discoverySubscription = null;
        state = state.copyWith(
          phase: SyncPhase.connected,
          server: server,
          sourceDeviceName: server.deviceName,
        );
      },
      onDone: () {
        if (state.phase == SyncPhase.discovering) {
          state = state.copyWith(
            phase: SyncPhase.error,
            errorMessage: '未发现服务端，请确认服务端已启动且在同一局域网内',
          );
        }
      },
      onError: (Object e) {
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
  }

  void selectAllCategories() {
    state = state.copyWith(
      selectedCategories: Set<SyncCategory>.from(SyncCategory.values),
    );
  }

  Future<void> requestSync() async {
    if (state.phase == SyncPhase.syncing) return;
    final server = state.server;
    if (server == null || state.selectedCategories.isEmpty) return;

    state = state.copyWith(
      phase: SyncPhase.syncing,
      errorMessage: null,
      deduplicatedData: null,
    );

    final request = SyncMessage.request(
      type: SyncMessageType.settingsSyncRequest,
      payload: {
        'categories':
            state.selectedCategories.map((c) => c.payloadKey).toList(),
      },
    );

    try {
      final uri = Uri.parse('http://${server.ip}:${server.httpPort}/sync');
      final body = SyncMessageCodec.encode(request);

      final response = await http
          .post(uri, body: body, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));

      final responseMessage = SyncMessageCodec.tryDecode(response.body);
      if (responseMessage == null) {
        state = state.copyWith(
          phase: SyncPhase.error,
          errorMessage: '响应格式错误',
        );
        return;
      }

      if (responseMessage.type == SyncMessageType.error) {
        state = state.copyWith(
          phase: SyncPhase.error,
          errorMessage: responseMessage.payload['message'] as String? ??
              '服务端返回错误',
        );
        return;
      }

      if (responseMessage.type != SyncMessageType.settingsSyncResponse) {
        state = state.copyWith(
          phase: SyncPhase.error,
          errorMessage: '未知的响应类型: ${responseMessage.type}',
        );
        return;
      }

      final dataJson = responseMessage.payload['data'] as String?;
      final exportData = SettingsExportData.tryParseJson(dataJson);
      if (exportData == null) {
        state = state.copyWith(
          phase: SyncPhase.error,
          errorMessage: '数据解析失败',
        );
        return;
      }

      final deduplicated = _deduplicate(exportData);
      if (!deduplicated.hasContent) {
        state = state.copyWith(phase: SyncPhase.noNewData);
        return;
      }

      state = state.copyWith(
        phase: SyncPhase.received,
        deduplicatedData: deduplicated,
      );
    } on TimeoutException {
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: '请求超时，请检查网络连接',
      );
    } catch (e) {
      state = state.copyWith(
        phase: SyncPhase.error,
        errorMessage: '同步失败: $e',
      );
    }
  }

  /// 执行导入并返回是否成功。
  Future<bool> executeImport() async {
    final data = state.deduplicatedData;
    if (data == null) return false;

    final success = await const SettingsImportExecutor().executeImport(ref, data: data);
    if (success) {
      state = state.copyWith(phase: SyncPhase.done);
    }
    return success;
  }

  void resetToConnected() {
    state = state.copyWith(
      phase: SyncPhase.connected,
      deduplicatedData: null,
      errorMessage: null,
    );
  }

  void cancelAndReset() {
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    state = const SyncClientState();
  }

  SettingsExportData _deduplicate(SettingsExportData data) {
    const deduplicator = SettingsImportDeduplicator();
    return deduplicator.deduplicate(
      data: data,
      existingProviders: ref.read(llmProviderConfigsProvider),
      existingMemoryPrompts: ref.read(memoryPromptsProvider),
      existingPresetPrompts: ref.read(presetPromptsProvider),
      existingTemplatePrompts: ref.read(templatePromptsProvider),
      existingSequences: ref.read(fixedPromptSequencesProvider),
    );
  }
}
