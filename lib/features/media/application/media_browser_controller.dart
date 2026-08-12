import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

const Object _sentinel = Object();

/// 媒体浏览器状态。
class MediaBrowserState extends Equatable {
  MediaBrowserState({
    List<FileItem> items = const [],
    this.currentPath = '/',
    List<String> pathHistory = const [],
    this.isLoading = false,
    this.errorMessage,
  }) : items = List.unmodifiable(items),
       pathHistory = List.unmodifiable(pathHistory);

  final List<FileItem> items;
  final String currentPath;
  final List<String> pathHistory;
  final bool isLoading;
  final String? errorMessage;

  @override
  List<Object?> get props => [
    items
        .map(
          (item) => (
            item.name,
            item.isDirectory,
            item.sizeBytes,
            item.relativePath,
            item.lastModified,
            item.mimeType,
            item.hasThumbnail,
          ),
        )
        .toList(),
    currentPath,
    pathHistory,
    isLoading,
    errorMessage,
  ];

  MediaBrowserState copyWith({
    List<FileItem>? items,
    String? currentPath,
    List<String>? pathHistory,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return MediaBrowserState(
      items: items ?? this.items,
      currentPath: currentPath ?? this.currentPath,
      pathHistory: pathHistory ?? this.pathHistory,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  bool get isAtRoot => currentPath == '/' || currentPath.isEmpty;
  bool get canGoBack => pathHistory.isNotEmpty;
}

final mediaBrowserControllerProvider =
    NotifierProvider<MediaBrowserController, MediaBrowserState>(
      MediaBrowserController.new,
      isAutoDispose: true,
    );

/// 客户端媒体浏览器控制器。
///
/// 目录操作必须持有活动媒体会话：会话在发起时捕获，过期结果由代数判定
/// 丢弃，保证旧会话/旧目录的在途响应不会覆盖当前状态。
/// 这是页面级 auto-dispose 会话，不保活；离开媒体页面后由 app composition reset。
class MediaBrowserController extends Notifier<MediaBrowserState> {
  int _operationGeneration = 0;
  int _sessionGeneration = 0;

  @override
  MediaBrowserState build() {
    return MediaBrowserState();
  }

  /// 从当前活动会话初始化并加载根目录。
  ///
  /// 会话不可用时发布错误并返回 false；成功后所有在途请求以本次
  /// 会话代数重新锚定。
  Future<bool> initFromActiveSession() async {
    final session = ref.read(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      state = state.copyWith(isLoading: false, errorMessage: '媒体会话不可用');
      return false;
    }
    _sessionGeneration = session.generation;
    final operation = ++_operationGeneration;
    state = MediaBrowserState();
    return _loadDirectory('/', session, operation);
  }

  /// 加载指定目录。
  Future<bool> loadDirectory(String path) {
    final session = ref.read(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      state = state.copyWith(isLoading: false, errorMessage: '媒体会话不可用');
      return Future.value(false);
    }
    final operation = ++_operationGeneration;
    return _loadDirectory(path, session, operation);
  }

  Future<bool> _loadDirectory(
    String path,
    MediaLibrarySessionActive session,
    int operation,
  ) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final items = await session.library.listDirectory(path);
      if (!_isCurrent(session, operation)) return false;
      state = state.copyWith(items: items, currentPath: path, isLoading: false);
      return true;
    } on MediaLibraryFailure catch (failure) {
      if (!_isCurrent(session, operation)) return false;
      state = state.copyWith(isLoading: false, errorMessage: failure.message);
      return false;
    } catch (_) {
      // 未知异常转固定文案：不把底层细节泄露给用户
      if (!_isCurrent(session, operation)) return false;
      state = state.copyWith(isLoading: false, errorMessage: '加载媒体目录失败');
      return false;
    }
  }

  /// 导航到子目录。
  ///
  /// 仅在加载成功后推入历史，避免失败导航污染 pathHistory。
  Future<void> navigateTo(String path) async {
    if (state.currentPath == path) return;
    final session = ref.read(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      state = state.copyWith(isLoading: false, errorMessage: '媒体会话不可用');
      return;
    }
    final previousPath = state.currentPath;
    final operation = ++_operationGeneration;
    final loaded = await _loadDirectory(path, session, operation);
    // 只有成功加载（currentPath 已更新到 path）时才推入历史
    if (_isCurrent(session, operation) && loaded) {
      state = state.copyWith(pathHistory: [...state.pathHistory, previousPath]);
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
    final session = ref.read(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      return false;
    }
    final history = List<String>.from(state.pathHistory);
    final previousPath = history.removeLast();
    state = state.copyWith(pathHistory: history);
    final operation = ++_operationGeneration;
    return _loadDirectory(previousPath, session, operation);
  }

  /// 结束当前页面会话，令所有在途响应失效。
  void reset() {
    _operationGeneration++;
    state = MediaBrowserState();
  }

  bool _isCurrent(MediaLibrarySessionActive captured, int operation) {
    final current = ref.read(mediaLibrarySessionProvider);
    return ref.mounted &&
        operation == _operationGeneration &&
        current is MediaLibrarySessionActive &&
        current.generation == captured.generation &&
        captured.generation == _sessionGeneration;
  }
}
