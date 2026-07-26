import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/http/http_route_handler.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../../settings/application/auto_retry_settings_controller.dart';
import '../../settings/application/custom_headers_controller.dart';
import '../../settings/application/fixed_prompt_sequences_controller.dart';
import '../../settings/application/font_size_settings_controller.dart';
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
import 'broadcast_prefix_length_provider.dart';
import 'network_interface_provider.dart';

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
  });

  final bool isRunning;
  final String deviceName;
  final int? httpPort;
  final int servedRequestCount;
  final String? lastError;
  final NetworkInterfaceInfo? selectedInterface;

  @override
  List<Object?> get props => [
    isRunning,
    deviceName,
    httpPort,
    servedRequestCount,
    lastError,
    (selectedInterface?.name, selectedInterface?.ip),
  ];

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
/// 成功启动后以唯一的 keep-alive link 跨页面保活；显式停止、应用销毁时按
/// UDP、HTTP 顺序释放。请求 handlers 及其引用的 scanner、缩略图 cache/generator
/// 都由 [_httpServer] 的运行会话拥有，不是独立全局资源。
class SyncServerController extends Notifier<SyncServerState> {
  final SyncHttpServer _httpServer = SyncHttpServer();
  Future<void> Function()? _stopBroadcasting;
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
          if (!_isCurrent(generation)) return;
          handlers.add(
            MediaThumbnailHttpHandler(
              scanner: scanner,
              generator: MediaThumbnailGenerator(scanner: scanner),
              cache: thumbnailCache,
            ),
          );
        }
      }
      final port = await _httpServer.start(handlers: handlers);
      if (!_isCurrent(generation)) {
        await _cleanup();
        return;
      }
      _stopBroadcasting = await SyncUdpDiscovery.startBroadcasting(
        httpPort: port,
        deviceName: state.deviceName,
        broadcastAddress: broadcastAddr,
      );
      if (!_isCurrent(generation)) {
        await _cleanup();
        return;
      }
      _keepAliveLink ??= ref.keepAlive();
      state = state.copyWith(
        isRunning: true,
        httpPort: port,
        lastError: null,
        selectedInterface: selectedIface,
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
      );
    }
    keepAliveLink?.close();
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

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
    final categories =
        (request.payload['categories'] as List<dynamic>?)?.cast<String>() ??
        const [];
    final categorySet = categories.toSet();

    final exportData = _buildExportData(categorySet);
    final json = exportData.toJsonString();

    state = state.copyWith(servedRequestCount: state.servedRequestCount + 1);

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
      fontSizeSettings: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(fontSizeSettingsProvider)
          : null,
    );
  }
}
