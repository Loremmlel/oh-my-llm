import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../sync/data/sync_udp_discovery.dart';
import '../domain/models/file_item.dart';

const Object _sentinel = Object();

/// 对媒体路径的每段进行 URI 编码，以支持中文等非 ASCII 字符。
///
/// 根路径 `/` 返回空字符串。
String encodeMediaPath(String path) {
  if (path == '/') return '';
  return path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
}

/// 媒体浏览器状态。
class MediaBrowserState {
  const MediaBrowserState({
    this.items = const [],
    this.currentPath = '/',
    this.pathHistory = const [],
    this.isLoading = false,
    this.errorMessage,
    this.server,
  });

  final List<FileItem> items;
  final String currentPath;
  final List<String> pathHistory;
  final bool isLoading;
  final String? errorMessage;
  final DiscoveredServer? server;

  MediaBrowserState copyWith({
    List<FileItem>? items,
    String? currentPath,
    List<String>? pathHistory,
    bool? isLoading,
    Object? errorMessage = _sentinel,
    Object? server = _sentinel,
  }) {
    return MediaBrowserState(
      items: items ?? this.items,
      currentPath: currentPath ?? this.currentPath,
      pathHistory: pathHistory ?? this.pathHistory,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _sentinel) ? this.errorMessage : errorMessage as String?,
      server: identical(server, _sentinel) ? this.server : server as DiscoveredServer?,
    );
  }

  bool get isAtRoot => currentPath == '/' || currentPath.isEmpty;
  bool get canGoBack => pathHistory.isNotEmpty;
}

final mediaBrowserControllerProvider =
    NotifierProvider<MediaBrowserController, MediaBrowserState>(
  MediaBrowserController.new,
);

/// 客户端媒体浏览器控制器。
///
/// 管理浏览状态并通过 HTTP 调用服务端 API 获取目录内容。
class MediaBrowserController extends Notifier<MediaBrowserState> {
  @override
  MediaBrowserState build() {
    return const MediaBrowserState();
  }

  /// 初始化：从同步客户端状态获取服务端地址。
  void initWithServer(DiscoveredServer server) {
    // server 未变且正在加载或有数据 → 跳过
    if (state.server?.ip == server.ip &&
        state.server?.httpPort == server.httpPort) {
      if (state.isLoading || state.items.isNotEmpty) return;
    }
    state = state.copyWith(server: server);
    loadDirectory('/');
  }

  /// 加载指定目录。
  Future<void> loadDirectory(String path) async {
    final server = state.server;
    if (server == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '未连接到服务端',
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 路径每段单独编码以支持中文
      final encodedPath = encodeMediaPath(path);
      final url = Uri.parse(
        'http://${server.ip}:${server.httpPort}/api/media/list/$encodedPath',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final items = FileItem.listFromJson(response.body);
        state = state.copyWith(
          items: items,
          currentPath: path,
          isLoading: false,
        );
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final error = body?['error'] as String? ?? '未知错误';
        state = state.copyWith(
          isLoading: false,
          errorMessage: error,
        );
      }
    } on http.ClientException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '网络错误: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '加载失败: $e',
      );
    }
  }

  /// 导航到子目录。
  ///
  /// 仅在加载成功后推入历史，避免失败导航污染 pathHistory。
  Future<void> navigateTo(String path) async {
    if (state.currentPath == path) return;
    final previousPath = state.currentPath;
    await loadDirectory(path);
    // 只有成功加载（currentPath 已更新到 path）时才推入历史
    if (state.currentPath == path && state.errorMessage == null) {
      state = state.copyWith(
        pathHistory: [...state.pathHistory, previousPath],
      );
    }
  }

  /// 返回上一级目录。
  ///
  /// 返回 `true` 表示成功返回上一级，`false` 表示已在根目录无法再退。
  Future<bool> goBack() async {
    if (state.pathHistory.isEmpty) {
      // 已在根目录 → 不能退，由调用者处理（退出媒体浏览器 Tab）
      return false;
    }
    final history = List<String>.from(state.pathHistory);
    final previousPath = history.removeLast();
    state = state.copyWith(pathHistory: history);
    await loadDirectory(previousPath);
    return true;
  }
}
