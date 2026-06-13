import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/http/http_route_handler.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../../settings/application/auto_retry_settings_controller.dart';
import '../../settings/application/custom_headers_controller.dart';
import '../../settings/application/fixed_prompt_sequences_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/memory_prompts_controller.dart';
import '../../settings/application/preset_prompts_controller.dart';
import '../../settings/application/template_prompts_controller.dart';
import '../../settings/domain/models/settings_export_data.dart';
import '../../media/application/media_root_directory_controller.dart';
import '../../media/data/media_directory_scanner.dart';
import '../../media/data/media_http_handler.dart';
import '../../media/data/media_image_http_handler.dart';
import '../../media/data/media_video_http_handler.dart';
import '../../media/data/media_recursive_videos_handler.dart';
import '../../media/data/media_thumbnail_cache.dart';
import '../../media/data/media_thumbnail_generator.dart';
import '../../media/data/media_thumbnail_http_handler.dart';
import '../data/sync_http_handler.dart';
import '../data/sync_http_server.dart';
import '../data/sync_udp_discovery.dart';
import '../domain/models/network_interface_info.dart';
import '../domain/models/sync_message.dart';
import '../domain/models/sync_types.dart';
import 'network_interface_provider.dart';

const String _deviceNameKey = 'sync.device_name';

const Object _sentinel = Object();

class SyncServerState {
  const SyncServerState({
    this.isRunning = false,
    this.deviceName = '',
    this.httpPort,
    this.servedRequestCount = 0,
    this.lastError,
    this.selectedInterface,
  });

  final bool isRunning;
  final String deviceName;
  final int? httpPort;
  final int servedRequestCount;
  final String? lastError;
  final NetworkInterfaceInfo? selectedInterface;

  SyncServerState copyWith({
    bool? isRunning,
    String? deviceName,
    Object? httpPort = _sentinel,
    int? servedRequestCount,
    Object? lastError = _sentinel,
    Object? selectedInterface = _sentinel,
  }) {
    return SyncServerState(
      isRunning: isRunning ?? this.isRunning,
      deviceName: deviceName ?? this.deviceName,
      httpPort: identical(httpPort, _sentinel) ? this.httpPort : httpPort as int?,
      servedRequestCount: servedRequestCount ?? this.servedRequestCount,
      lastError: identical(lastError, _sentinel) ? this.lastError : lastError as String?,
      selectedInterface: identical(selectedInterface, _sentinel) ? this.selectedInterface : selectedInterface as NetworkInterfaceInfo?,
    );
  }
}

final syncServerControllerProvider =
    NotifierProvider<SyncServerController, SyncServerState>(
      SyncServerController.new,
    );

/// 同步服务端控制器，管理 HTTP 服务端和 UDP 广播的生命周期。
class SyncServerController extends Notifier<SyncServerState> {
  final SyncHttpServer _httpServer = SyncHttpServer();
  Future<void> Function()? _stopBroadcasting;
  Future<void>? _pendingRestart;
  KeepAliveLink? _keepAliveLink;

  @override
  SyncServerState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedName = prefs.getString(_deviceNameKey);
    final deviceName = savedName ?? Platform.localHostname;

    ref.onDispose(_cleanup);

    return SyncServerState(deviceName: deviceName);
  }

  Future<void> start() async {
    if (state.isRunning) return;

    try {
      // 获取用户选择的网络接口
      final interfaces = await ref.read(availableInterfacesProvider.future);
      final selectedIndex = ref.read(selectedInterfaceIndexProvider);
      NetworkInterfaceInfo? selectedIface;
      InternetAddress? broadcastAddr;

      if (interfaces.isNotEmpty) {
        selectedIface =
            interfaces[selectedIndex.clamp(0, interfaces.length - 1)];
        broadcastAddr = InternetAddress(selectedIface.broadcast);
      }

      final handlers = <HttpRouteHandler>[
        SyncHttpHandler(onRequest: _handleRequest),
      ];
      // 媒体文件服务仅在 Windows 服务端启用
      if (Platform.isWindows) {
        final rootDir = ref.read(mediaRootDirectoryProvider);
        if (rootDir != null && rootDir.isNotEmpty) {
          // 三个 Handler 共享同一个 scanner 实例，避免重复解析符号链接
          final scanner = MediaDirectoryScanner(rootDir);
          handlers.add(MediaHttpHandler(scanner: scanner));
          handlers.add(MediaImageHttpHandler(scanner: scanner));
          handlers.add(MediaVideoHttpHandler(scanner: scanner));
          handlers.add(MediaRecursiveVideosHandler(scanner: scanner));
          final thumbnailCache = await MediaThumbnailCache.defaultLocation();
          handlers.add(MediaThumbnailHttpHandler(
            scanner: scanner,
            generator: MediaThumbnailGenerator(scanner: scanner),
            cache: thumbnailCache,
          ));
        }
      }
      final port = await _httpServer.start(handlers: handlers);
      _stopBroadcasting = await SyncUdpDiscovery.startBroadcasting(
        httpPort: port,
        deviceName: state.deviceName,
        broadcastAddress: broadcastAddr,
      );
      state = state.copyWith(
        isRunning: true,
        httpPort: port,
        lastError: null,
        selectedInterface: selectedIface,
      );
      _keepAliveLink = ref.keepAlive();
    } catch (e) {
      await _cleanup();
      state = state.copyWith(
        isRunning: false,
        httpPort: null,
        lastError: '启动失败: $e',
        selectedInterface: null,
      );
    }
  }

  Future<void> stop() async {
    _keepAliveLink?.close();
    _keepAliveLink = null;
    await _cleanup();
    state = state.copyWith(
      isRunning: false,
      httpPort: null,
      servedRequestCount: 0,
    );
  }

  Future<void> _cleanup() async {
    await _stopBroadcasting?.call();
    _stopBroadcasting = null;
    await _httpServer.stop();
  }

  Future<void> updateDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.deviceName) return;
    state = state.copyWith(deviceName: trimmed);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_deviceNameKey, trimmed);

    if (state.isRunning) {
      _pendingRestart = (_pendingRestart ?? Future<void>.value()).then((_) async {
        if (!state.isRunning) return;
        await _cleanup();
        state = state.copyWith(isRunning: false, httpPort: null);
        await start();
      });
      await _pendingRestart;
    }
  }

  Future<SyncMessage> _handleRequest(SyncMessage request) async {
    switch (request.type) {
      case SyncMessageType.settingsSyncRequest:
        return _handleSettingsSyncRequest(request);
      default:
        return SyncMessage.error(
          requestId: request.requestId,
          code: SyncErrorCode.unknownType,
          message: '不支持的消息类型: ${request.type}',
        );
    }
  }

  Future<SyncMessage> _handleSettingsSyncRequest(SyncMessage request) async {
    final categories = (request.payload['categories'] as List<dynamic>?)
            ?.cast<String>() ??
        const [];
    final categorySet = categories.toSet();

    final exportData = _buildExportData(categorySet);
    final json = exportData.toJsonString();

    state = state.copyWith(
      servedRequestCount: state.servedRequestCount + 1,
    );

    return SyncMessage.response(
      type: SyncMessageType.settingsSyncResponse,
      requestId: request.requestId,
      payload: {'data': json},
    );
  }

  SettingsExportData _buildExportData(Set<String> categories) {
    return SettingsExportData(
      modelProviders: categories.contains(SyncCategory.providers.payloadKey)
          ? ref.read(llmProviderConfigsProvider)
          : const [],
      presetPrompts: categories.contains(SyncCategory.presets.payloadKey)
          ? ref.read(presetPromptsProvider)
          : const [],
      memoryPrompts: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(memoryPromptsProvider)
          : const [],
      templatePrompts: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(templatePromptsProvider)
          : const [],
      fixedPromptSequences: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(fixedPromptSequencesProvider)
          : const [],
      autoRetrySettings: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(autoRetrySettingsProvider)
          : null,
      customHeadersConfig: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(customHeadersProvider)
          : null,
    );
  }
}
