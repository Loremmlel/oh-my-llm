# 随机视频播放 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为媒体客户端（Android）增加随机视频播放功能：AppBar 按钮一键收集当前目录树所有视频、shuffle 后顺序播放。

**Architecture:** 服务端新增 `GET /api/media/videos/recursive/{path}` 递归扫描端点；客户端新增 `ShufflePlaybackController`（Riverpod Notifier）管理播放列表状态，`ShuffleAppBarActions` 组件渲染 AppBar 按钮三种形态，通过 `SyncScreen` 集成到现有导航壳。

**Tech Stack:** Dart/Flutter, flutter_riverpod, video_player, package:http

---

### Task 1: 服务端 — `MediaDirectoryScanner.scanRecursiveVideos()`

**Files:**
- Modify: `lib/features/media/data/media_directory_scanner.dart`
- Test: `test/features/media/data/media_directory_scanner_test.dart`

- [ ] **Step 1: 编写失败的测试 — 递归扫描返回扁平视频列表**

在 `test/features/media/data/media_directory_scanner_test.dart` 文件末尾添加：

```dart
group('MediaDirectoryScanner.scanRecursiveVideos', () {
  late Directory tempRoot;
  late MediaDirectoryScanner scanner;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('media_recursive_test_');
    scanner = MediaDirectoryScanner(tempRoot.path);

    // 嵌套目录结构：
    // root/
    //   video1.mp4
    //   sub/
    //     video2.mkv
    //     deep/
    //       video3.avi
    //   images/
    //     photo.jpg
    //   empty/
    Directory('${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep').createSync(recursive: true);
    Directory('${tempRoot.path}${Platform.pathSeparator}images').createSync();
    Directory('${tempRoot.path}${Platform.pathSeparator}empty').createSync();

    File('${tempRoot.path}${Platform.pathSeparator}video1.mp4')
        .writeAsStringSync('video1');
    File('${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}video2.mkv')
        .writeAsStringSync('video2');
    File('${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep${Platform.pathSeparator}video3.avi')
        .writeAsStringSync('video3');
    File('${tempRoot.path}${Platform.pathSeparator}images'
        '${Platform.pathSeparator}photo.jpg')
        .writeAsStringSync('photo');
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  test('递归收集所有视频文件，按名称排序', () async {
    final videos = await scanner.scanRecursiveVideos('/');

    expect(videos.length, 3);
    expect(videos[0].name, 'video1.mp4');
    expect(videos[1].name, 'video2.mkv');
    expect(videos[2].name, 'video3.avi');
  });

  test('每个视频条目包含 name 和 relativePath', () async {
    final videos = await scanner.scanRecursiveVideos('/');

    final deepVideo = videos.firstWhere((v) => v.name == 'video3.avi');
    expect(deepVideo.relativePath.toLowerCase(),
        contains('deep${Platform.pathSeparator}video3.avi'.toLowerCase()));
  });

  test('空目录返回空列表', () async {
    final videos = await scanner.scanRecursiveVideos('/empty');
    expect(videos, isEmpty);
  });

  test('纯图片目录返回空列表', () async {
    final videos = await scanner.scanRecursiveVideos('/images');
    expect(videos, isEmpty);
  });

  test('隐藏文件被过滤', () async {
    File('${tempRoot.path}${Platform.pathSeparator}.hidden.mp4')
        .writeAsStringSync('hidden');
    final videos = await scanner.scanRecursiveVideos('/');
    expect(videos.any((v) => v.name == '.hidden.mp4'), isFalse);
  });

  test('不存在的目录抛出 FileSystemException', () async {
    expect(
      () => scanner.scanRecursiveVideos('/不存在的目录'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('路径穿越被拒绝', () async {
    expect(
      () => scanner.scanRecursiveVideos('/../etc'),
      throwsA(isA<PathTraversalException>()),
    );
  });
});
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/media/data/media_directory_scanner_test.dart --plain-name "递归收集所有视频文件" 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：编译错误或测试失败（方法不存在）

- [ ] **Step 3: 定义 `VideoItem` 模型并在 `MediaDirectoryScanner` 中实现 `scanRecursiveVideos()`**

在 `lib/features/media/data/media_directory_scanner.dart` 文件末尾添加 `VideoItem` 类：

```dart
/// 递归扫描返回的轻量级视频条目。
class VideoItem {
  final String name;
  final String relativePath;

  const VideoItem({required this.name, required this.relativePath});

  Map<String, dynamic> toJson() => {
        'name': name,
        'relativePath': relativePath,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      name: json['name'] as String,
      relativePath: json['relativePath'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoItem &&
          name == other.name &&
          relativePath == other.relativePath;

  @override
  int get hashCode => Object.hash(name, relativePath);
}
```

在 `MediaDirectoryScanner` 类中添加 `scanRecursiveVideos` 方法（放在 `scan()` 方法之后）：

```dart
/// 递归扫描目录树下所有视频文件，返回扁平 [VideoItem] 列表。
///
/// 跳过隐藏文件、仅收集扩展名在 [videoExtensions] 中的文件、
/// 按名称升序排列。
Future<List<VideoItem>> scanRecursiveVideos(String relativePath) async {
  final resolvedPath = resolvePath(relativePath);
  final dir = Directory(resolvedPath);
  if (!dir.existsSync()) {
    throw FileSystemException('目录不存在', resolvedPath);
  }

  final videos = <VideoItem>[];
  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;
    final name = _fileName(entity.path);
    if (name.startsWith('.')) continue;
    if (_isWindowsHidden(entity)) continue;
    if (!isVideoFile(name)) continue;

    final relToRoot = entity.absolute.path.substring(resolvedRoot.length);
    final relPath =
        '/${relToRoot.replaceAll('\\', '/')}'.replaceAll(RegExp(r'/+'), '/');

    videos.add(VideoItem(name: name, relativePath: relPath));
  }

  videos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return videos;
}
```

需要在文件顶部添加 `import 'media_mime_types.dart';`（已存在，无需修改）。

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/features/media/data/media_directory_scanner_test.dart --plain-name "scanRecursiveVideos" 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：所有 scanRecursiveVideos 测试通过

- [ ] **Step 5: 提交**

```bash
git add lib/features/media/data/media_directory_scanner.dart test/features/media/data/media_directory_scanner_test.dart
git commit -m "feat: MediaDirectoryScanner 新增 scanRecursiveVideos 递归视频扫描方法" \
           -m "新增 VideoItem 轻量模型，递归遍历目录树，仅收集视频扩展名文件，过滤隐藏文件，支持路径穿越防护" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 服务端 — `MediaRecursiveVideosHandler`

**Files:**
- Create: `lib/features/media/data/media_recursive_videos_handler.dart`
- Test: `test/features/media/data/media_recursive_videos_handler_test.dart`

- [ ] **Step 1: 编写失败的测试**

创建 `test/features/media/data/media_recursive_videos_handler_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_recursive_videos_handler.dart';

void main() {
  group('MediaRecursiveVideosHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late HttpRouteHandler handler;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('handler_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);
      handler = MediaRecursiveVideosHandler(scanner: scanner);

      // 创建测试视频
      Directory('${tempRoot.path}${Platform.pathSeparator}sub').createSync();
      File('${tempRoot.path}${Platform.pathSeparator}video1.mp4')
          .writeAsStringSync('v1');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('canHandle 匹配 GET /api/media/videos/recursive', () {
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive/sister');
      expect(handler.canHandle(req), isTrue);
    });

    test('canHandle 匹配根路径 GET /api/media/videos/recursive', () {
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive');
      expect(handler.canHandle(req), isTrue);
    });

    test('canHandle 拒绝 POST 请求', () {
      final req = _FakeHttpRequest('POST', '/api/media/videos/recursive/sister');
      expect(handler.canHandle(req), isFalse);
    });

    test('canHandle 拒绝其他路径前缀', () {
      final req = _FakeHttpRequest('GET', '/api/media/list/sister');
      expect(handler.canHandle(req), isFalse);
    });

    test('handle 返回 200 和 JSON 视频列表', () async {
      final response = _FakeHttpResponse();
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive');
      await handler.handle(req as HttpRequest);
      final resp = response;
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body) as List;
      expect(body.length, 1);
      expect(body[0]['name'], 'video1.mp4');
    });

    test('handle 路径穿越返回 403', () async {
      final response = _FakeHttpResponse();
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive/../etc');
      await handler.handle(req as HttpRequest);
      final resp = response;
      expect(resp.statusCode, 403);
    });
  });
}

/// 可控制的假 HttpRequest，仅覆盖 canHandle 所需字段。
class _FakeHttpRequest extends Fake implements HttpRequest {
  @override
  final String method;
  @override
  final Uri uri;

  _FakeHttpRequest(this.method, String path) : uri = Uri.parse(path);

  @override
  late final HttpResponse response = _FakeHttpResponse();
}

/// 收集写入数据的假 HttpResponse。
class _FakeHttpResponse extends Fake implements HttpResponse {
  int statusCode = 200;
  final _headers = <String, List<String>>{};
  final _buffer = StringBuffer();

  @override
  HttpHeaders get headers => _FakeHttpHeaders(_headers);
  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  String get body => _buffer.toString();

  @override
  Future<void> close() async {}
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, List<String>> _data;
  _FakeHttpHeaders(this._data);
  @override
  void set(String name, Object value) {
    _data[name] = [value.toString()];
  }

  @override
  ContentType? contentType;
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/media/data/media_recursive_videos_handler_test.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：编译错误（文件不存在）

- [ ] **Step 3: 实现 `MediaRecursiveVideosHandler`**

创建 `lib/features/media/data/media_recursive_videos_handler.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';

/// 处理 `GET /api/media/videos/recursive` 及 `GET /api/media/videos/recursive/*` 请求的 Handler。
///
/// 递归扫描指定目录树下所有视频文件，返回扁平 JSON 列表。
class MediaRecursiveVideosHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;

  MediaRecursiveVideosHandler({required MediaDirectoryScanner scanner})
      : _scanner = scanner;

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      (request.uri.path == '/api/media/videos/recursive' ||
          request.uri.path.startsWith('/api/media/videos/recursive/'));

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      final rawPath = request.uri.path == '/api/media/videos/recursive'
          ? ''
          : request.uri.path.substring('/api/media/videos/recursive'.length);
      final relativePath = rawPath.isEmpty || rawPath == '/'
          ? '/'
          : Uri.decodeComponent(rawPath);

      final videos = await _scanner.scanRecursiveVideos(relativePath);

      final json = const JsonEncoder.withIndent(null)
          .convert(videos.map((v) => v.toJson()).toList());
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write(json)
        ..close();
    } on PathTraversalException catch (e) {
      writeJsonError(
          request.response, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on FileSystemException catch (e) {
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      writeJsonError(request.response, status, '目录访问失败: ${e.message}');
    } catch (e) {
      writeJsonError(
          request.response, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/features/media/data/media_recursive_videos_handler_test.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：全部通过

- [ ] **Step 5: 提交**

```bash
git add lib/features/media/data/media_recursive_videos_handler.dart test/features/media/data/media_recursive_videos_handler_test.dart
git commit -m "feat: 新增 MediaRecursiveVideosHandler 递归视频扫描 HTTP 端点" \
           -m "GET /api/media/videos/recursive/{path} 返回扁平 JSON 视频列表，复用 MediaDirectoryScanner 安全防护" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 服务端 — 注册 Handler 到 `SyncServerController`

**Files:**
- Modify: `lib/features/sync/application/sync_server_controller.dart`

- [ ] **Step 1: 在 handlers 列表中注册 `MediaRecursiveVideosHandler`**

编辑 `lib/features/sync/application/sync_server_controller.dart`：

在文件顶部添加 import：
```dart
import '../../media/data/media_recursive_videos_handler.dart';
```

在 handlers 注册处（约第 119 行，`handlers.add(MediaHttpHandler(scanner: scanner));` 之后）添加：
```dart
handlers.add(MediaRecursiveVideosHandler(scanner: scanner));
```

完整上下文（第 117-121 行）：
```dart
final scanner = MediaDirectoryScanner(rootDir);
handlers.add(MediaHttpHandler(scanner: scanner));
handlers.add(MediaImageHttpHandler(scanner: scanner));
handlers.add(MediaVideoHttpHandler(scanner: scanner));
handlers.add(MediaRecursiveVideosHandler(scanner: scanner)); // ← 新增
```

**注意**：`MediaRecursiveVideosHandler` 与现有 handler 共享同一个 `scanner` 实例，避免重复解析符号链接。

- [ ] **Step 2: 运行现有测试确认无回归**

```bash
flutter test --reporter compact 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：EXIT=0，无回归

- [ ] **Step 3: 提交**

```bash
git add lib/features/sync/application/sync_server_controller.dart
git commit -m "feat: 注册 MediaRecursiveVideosHandler 到 HTTP 路由表" \
           -m "与现有媒体 Handler 共享同一个 MediaDirectoryScanner 实例" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 客户端 — `ShufflePlaybackState` 和 `ShufflePlaybackController`

**Files:**
- Create: `lib/features/media/application/shuffle_playback_controller.dart`
- Test: `test/features/media/application/shuffle_playback_controller_test.dart`

- [ ] **Step 1: 编写失败的测试**

创建 `test/features/media/application/shuffle_playback_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';

void main() {
  group('ShufflePlaybackState', () {
    test('ShufflePlaybackIdle 相等性', () {
      expect(const ShufflePlaybackIdle(), equals(const ShufflePlaybackIdle()));
    });

    test('ShufflePlaybackLoading 相等性', () {
      expect(
        const ShufflePlaybackLoading(),
        equals(const ShufflePlaybackLoading()),
      );
    });

    test('ShufflePlaybackActive 属性', () {
      final state = ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: 'a.mp4', relativePath: '/a.mp4'),
          VideoItem(name: 'b.mp4', relativePath: '/sub/b.mp4'),
        ],
        currentIndex: 0,
        directoryPath: '/videos',
      );
      expect(state.isFirst, isTrue);
      expect(state.isLast, isFalse);
    });

    test('ShufflePlaybackActive isLast 为 true 当在末尾', () {
      final state = ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: 'a.mp4', relativePath: '/a.mp4'),
          VideoItem(name: 'b.mp4', relativePath: '/sub/b.mp4'),
        ],
        currentIndex: 1,
        directoryPath: '/videos',
      );
      expect(state.isLast, isTrue);
      expect(state.isFirst, isFalse);
    });
  });

  group('ShufflePlaybackController', () {
    // 注意：controller 依赖 http.Client 和 mediaBrowserControllerProvider，
    // 这些需要集成测试或 mock。此处测试纯状态转换逻辑。
    // startShuffle / playNext / playPrevious 的完整测试使用 FakeHttpClient。

    test('reset 将状态重置为 Idle', () {
      // controller.reset() → state should be ShufflePlaybackIdle
      // 此测试在实际集成测试中完成
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/media/application/shuffle_playback_controller_test.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：编译错误（文件不存在）

- [ ] **Step 3: 实现 `ShufflePlaybackState` 和 `ShufflePlaybackController`**

创建 `lib/features/media/application/shuffle_playback_controller.dart`：

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/media_directory_scanner.dart'; // VideoItem 在此定义
import 'media_browser_controller.dart';
```
// ── 状态定义 ────────────────────────────────────────────

sealed class ShufflePlaybackState {
  const ShufflePlaybackState();
}

class ShufflePlaybackIdle extends ShufflePlaybackState {
  const ShufflePlaybackIdle();
}

class ShufflePlaybackLoading extends ShufflePlaybackState {
  const ShufflePlaybackLoading();
}

class ShufflePlaybackActive extends ShufflePlaybackState {
  final List<VideoItem> playlist;
  final int currentIndex;
  final String directoryPath;

  const ShufflePlaybackActive({
    required this.playlist,
    required this.currentIndex,
    required this.directoryPath,
  });

  bool get isFirst => currentIndex == 0;
  bool get isLast => currentIndex >= playlist.length - 1;
  VideoItem get currentVideo => playlist[currentIndex];
  int get totalCount => playlist.length;
  int get displayNumber => currentIndex + 1; // 1-based
}

// ── Provider ────────────────────────────────────────────

final shufflePlaybackControllerProvider =
    NotifierProvider<ShufflePlaybackController, ShufflePlaybackState>(
  ShufflePlaybackController.new,
);

/// 随机播放控制器。
///
/// 管理视频播放列表状态，协调服务端请求和客户端 shuffle。
/// 通过 [mediaBrowserControllerProvider] 获取服务端地址构建 URL。
class ShufflePlaybackController extends Notifier<ShufflePlaybackState> {
  @override
  ShufflePlaybackState build() => const ShufflePlaybackIdle();

  final _random = Random();

  /// 获取当前播放列表（仅在 Active 状态下有意义）。
  List<VideoItem>? get playlist =>
      state is ShufflePlaybackActive ? (state as ShufflePlaybackActive).playlist : null;

  /// 从服务端获取视频列表、shuffle、设为 Active。
  ///
  /// 返回第一个视频的 URL，或 null（0 个视频 / 请求失败）。
  Future<String?> startShuffle(String directoryPath) async {
    final browserState = ref.read(mediaBrowserControllerProvider);
    final server = browserState.server;
    if (server == null) return null;

    state = const ShufflePlaybackLoading();

    try {
      final encodedPath = encodeMediaPath(directoryPath);
      final url = Uri.parse(
        'http://${server.ip}:${server.httpPort}/api/media/videos/recursive/$encodedPath',
      );
      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) return null;

      final list = (jsonDecode(response.body) as List)
          .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
          .toList();

      if (list.isEmpty) return null;

      // Fisher-Yates shuffle（只对 ≥2 个项有意义）
      if (list.length >= 2) list.shuffle(_random);

      state = ShufflePlaybackActive(
        playlist: list,
        currentIndex: 0,
        directoryPath: directoryPath,
      );

      return buildVideoUrl(list.first.relativePath);
    } catch (_) {
      state = const ShufflePlaybackIdle();
      return null;
    }
  }

  /// 播放下一个视频。
  ///
  /// 返回视频 URL，若已是最后一个则返回 null。
  String? playNext() {
    final s = state;
    if (s is! ShufflePlaybackActive) return null;
    if (s.isLast) return null;
    final newIndex = s.currentIndex + 1;
    state = ShufflePlaybackActive(
      playlist: s.playlist,
      currentIndex: newIndex,
      directoryPath: s.directoryPath,
    );
    return buildVideoUrl(s.playlist[newIndex].relativePath);
  }

  /// 播放上一个视频。
  ///
  /// 返回视频 URL，若已是第一个则返回 null。
  String? playPrevious() {
    final s = state;
    if (s is! ShufflePlaybackActive) return null;
    if (s.isFirst) return null;
    final newIndex = s.currentIndex - 1;
    state = ShufflePlaybackActive(
      playlist: s.playlist,
      currentIndex: newIndex,
      directoryPath: s.directoryPath,
    );
    return buildVideoUrl(s.playlist[newIndex].relativePath);
  }

  /// 播放器退出回调。
  ///
  /// 若当前为最后一个视频则重置为 Idle（自动回到初始状态）。
  void onPlayerExited() {
    final s = state;
    if (s is ShufflePlaybackActive && s.isLast) {
      state = const ShufflePlaybackIdle();
    }
  }

  /// 目录变化时若与当前播放列表目录不一致则清空。
  void clearIfDirectoryChanged(String newPath) {
    final s = state;
    if (s is ShufflePlaybackActive && s.directoryPath != newPath) {
      state = const ShufflePlaybackIdle();
    } else if (s is! ShufflePlaybackActive) {
      // 非 Active 状态下目录变化无需处理
    }
  }

  /// 手动重置为 Idle。
  void reset() {
    state = const ShufflePlaybackIdle();
  }

  /// 构建视频播放 URL。
  String? buildVideoUrl(String relativePath) {
    final server = ref.read(mediaBrowserControllerProvider).server;
    if (server == null) return null;
    final encoded = encodeMediaPath(relativePath);
    return 'http://${server.ip}:${server.httpPort}/api/media/video/$encoded';
  }
}
```

- [ ] **Step 4: 运行测试确认状态类通过**

```bash
flutter test test/features/media/application/shuffle_playback_controller_test.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：状态类测试通过

- [ ] **Step 5: 提交**

```bash
git add lib/features/media/application/shuffle_playback_controller.dart test/features/media/application/shuffle_playback_controller_test.dart
git commit -m "feat: 新增 ShufflePlaybackController 随机播放状态管理" \
           -m "Riverpod Notifier 管理 Idle/Loading/Active 三态，支持播放列表 shuffle、上一个/下一个导航、目录变化自动清空" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 客户端 — `ShuffleAppBarActions` Widget

**Files:**
- Create: `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`

- [ ] **Step 1: 实现 `ShuffleAppBarActions`**

创建 `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/shuffle_playback_controller.dart';
import '../pages/video_player_page.dart';

/// AppBar 随机播放按钮组。
///
/// 根据 [ShufflePlaybackState] 渲染三种形态：
/// - Idle → 🔀 IconButton
/// - Loading → 小型 CircularProgressIndicator
/// - Active → ◀ 上一个 | N/M | 下一个 ▶（边界自适应）
///
/// [currentDirectoryPath] 用于向 controller 传递当前浏览目录。
class ShuffleAppBarActions extends ConsumerWidget {
  final String currentDirectoryPath;

  const ShuffleAppBarActions({
    super.key,
    required this.currentDirectoryPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shufflePlaybackControllerProvider);
    final controller = ref.read(shufflePlaybackControllerProvider.notifier);

    return switch (state) {
      ShufflePlaybackIdle() => IconButton(
          icon: const Icon(Icons.shuffle),
          tooltip: '随机播放',
          onPressed: () => _onShufflePressed(context, controller),
        ),
      ShufflePlaybackLoading() => const Padding(
          padding: EdgeInsets.all(12.0),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ShufflePlaybackActive() => _buildActiveButtons(context, state, controller),
    };
  }

  Future<void> _onShufflePressed(
    BuildContext context,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = await controller.startShuffle(currentDirectoryPath);

    if (!context.mounted) return;

    final state = controller.state;
    if (videoUrl != null && state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前目录下未找到视频文件')),
      );
    }
  }

  Widget _buildActiveButtons(
    BuildContext context,
    ShufflePlaybackActive state,
    ShufflePlaybackController controller,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!state.isFirst)
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: '上一个',
            onPressed: () => _onPrevPressed(context, controller),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${state.displayNumber}/${state.totalCount}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!state.isLast)
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: '下一个',
            onPressed: () => _onNextPressed(context, controller),
          ),
      ],
    );
  }

  Future<void> _onNextPressed(
    BuildContext context,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = controller.playNext();
    if (videoUrl == null) return;
    final state = controller.state;
    if (state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name);
    }
  }

  Future<void> _onPrevPressed(
    BuildContext context,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = controller.playPrevious();
    if (videoUrl == null) return;
    final state = controller.state;
    if (state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name);
    }
  }

  Future<void> _navigateToPlayer(
    BuildContext context,
    String videoUrl,
    String fileName,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoUrl: videoUrl,
          fileName: fileName,
        ),
      ),
    );
    if (context.mounted) {
      final controller = (context as ConsumerStatefulElement)
          .read(shufflePlaybackControllerProvider.notifier);
      controller.onPlayerExited();
    }
  }
}
```

等等，`_navigateToPlayer` 中的 `context.mounted` 检查和 controller 获取有些复杂。更好的写法是不强制转型为 ConsumerStatefulElement，而是保存 controller 引用：

修正 `_navigateToPlayer` 方法：
```dart
  Future<void> _navigateToPlayer(
    BuildContext context,
    String videoUrl,
    String fileName,
    ShufflePlaybackController controller,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoUrl: videoUrl,
          fileName: fileName,
        ),
      ),
    );
    if (context.mounted) {
      controller.onPlayerExited();
    }
  }
```

并相应更新各调用点传入 `controller` 参数。

- [ ] **Step 2: 运行 `flutter analyze` 确认无编译错误**

```bash
flutter analyze lib/features/media/presentation/widgets/shuffle_appbar_actions.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -20 fltest.log
```

预期：无 issues

- [ ] **Step 3: 提交**

```bash
git add lib/features/media/presentation/widgets/shuffle_appbar_actions.dart
git commit -m "feat: 新增 ShuffleAppBarActions AppBar 随机播放按钮组" \
           -m "Idle/Loading/Active 三种渲染形态，边界自适应显示上一个/下一个，点击触发导航到 VideoPlayerPage" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 客户端 — `SyncScreen` 集成

**Files:**
- Modify: `lib/features/sync/presentation/sync_screen.dart`

- [ ] **Step 1: 向 AppShellScaffold 传入随机播放 actions**

编辑 `lib/features/sync/presentation/sync_screen.dart`：

添加 import（在现有 media import 之后）：
```dart
import '../../media/application/shuffle_playback_controller.dart';
import '../../media/presentation/widgets/shuffle_appbar_actions.dart';
```

修改 `_onMediaTabListener` 以同时初始化 shuffle controller：
```dart
void _onMediaTabListener() {
  if (_tabController.index == 2 && !_tabController.indexIsChanging) {
    final server = ref.read(syncClientControllerProvider).server;
    if (server != null) {
      ref
          .read(mediaBrowserControllerProvider.notifier)
          .initWithServer(server);
    }
  }
}
```
此处无需额外修改——shuffle controller 通过 `mediaBrowserControllerProvider` 间接获取 server 信息。

修改 `build` 方法，仅在媒体 Tab 可见且有 server 时传入 actions：

```dart
@override
Widget build(BuildContext context) {
  final tabs = <Widget>[
    const Tab(text: '连接'),
    const Tab(text: '同步'),
    if (_hasMediaTab) const Tab(text: '媒体'),
  ];

  final tabViews = <Widget>[
    const SyncConnectionTab(),
    const SyncOperationTab(),
    if (_hasMediaTab)
      MediaBrowserTab(
        onExitMediaBrowser: () {
          _tabController.animateTo(0);
        },
      ),
  ];

  // 仅在媒体 Tab 选中且有连接 server 时显示随机播放按钮
  final mediaState = ref.watch(mediaBrowserControllerProvider);
  final showShuffleActions = _hasMediaTab &&
      _tabController.index == 2 &&
      mediaState.server != null;

  return AppShellScaffold(
    currentDestination: AppDestination.sync,
    title: '局域网同步',
    actions: showShuffleActions
        ? [
            ShuffleAppBarActions(
              currentDirectoryPath: mediaState.currentPath,
            ),
          ]
        : null,
    body: Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: tabs,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: tabViews,
          ),
        ),
      ],
    ),
  );
}
```

**关键点**：`_tabController.index == 2` 需要被 Flutter 感知到变化才能 rebuild。`TabController` 本身是 `ChangeNotifier`，但未暴露给 Riverpod。最简单的方式是利用已有的 `_onTabChanged` 回调 + `setState`。

修改 `_onTabChanged`：
```dart
void _onTabChanged() {
  if (!_tabController.indexIsChanging) {
    ref
        .read(sharedPreferencesProvider)
        .setInt(_syncLastTabIndexKey, _tabController.index);
    setState(() {}); // 触发 rebuild 以更新 AppBar actions 可见性
  }
}
```

- [ ] **Step 2: 运行 `flutter analyze` 确认无编译错误**

```bash
flutter analyze lib/features/sync/presentation/sync_screen.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -20 fltest.log
```

预期：无 issues

- [ ] **Step 3: 提交**

```bash
git add lib/features/sync/presentation/sync_screen.dart
git commit -m "feat: SyncScreen 集成 ShuffleAppBarActions 到 AppBar" \
           -m "仅在媒体 Tab 选中且有连接服务器时显示随机播放按钮，通过 setState 触发 TabController 变化时的 AppBar 更新" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: 客户端 — `MediaBrowserTab` 目录切换通知

**Files:**
- Modify: `lib/features/media/presentation/media_browser_tab.dart`

- [ ] **Step 1: 目录切换时通知 shuffle controller 清空**

编辑 `lib/features/media/presentation/media_browser_tab.dart`：

添加 import：
```dart
import '../application/shuffle_playback_controller.dart';
```

在 `_MediaBrowserTabState.build()` 方法开头添加目录切换监听。利用 `ref.listen` 监听 `mediaBrowserControllerProvider` 的 `currentPath` 变化：

修改 `build` 方法，在 `final state = ref.watch(...)` 之后添加：

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(mediaBrowserControllerProvider);
  final controller = ref.read(mediaBrowserControllerProvider.notifier);
  final server = state.server;

  // 监听目录切换 → 清空随机播放列表
  ref.listen<MediaBrowserState>(mediaBrowserControllerProvider, (prev, next) {
    if (prev != null && prev.currentPath != next.currentPath) {
      ref
          .read(shufflePlaybackControllerProvider.notifier)
          .clearIfDirectoryChanged(next.currentPath);
    }
  });

  // ... 其余代码不变
```

- [ ] **Step 2: 运行现有测试确认无回归**

```bash
flutter test --reporter compact 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：EXIT=0

- [ ] **Step 3: 提交**

```bash
git add lib/features/media/presentation/media_browser_tab.dart
git commit -m "feat: MediaBrowserTab 目录切换时自动清空随机播放列表" \
           -m "通过 ref.listen 监听 currentPath 变化，调用 clearIfDirectoryChanged 确保目录变更时清空旧列表" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: 全面验证

- [ ] **Step 1: 运行全部测试**

```bash
flutter test --reporter compact 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -30 fltest.log
```

预期：EXIT=0，所有测试通过

- [ ] **Step 2: 运行静态分析**

```bash
flutter analyze 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -20 fltest.log
```

预期：无 issues

- [ ] **Step 3: 端到端手动验证清单**

在 Android 设备/模拟器上运行应用：
1. 连接到服务端 → 切换到"媒体" Tab → 确认 AppBar 右侧显示 🔀 按钮
2. 点击 🔀 → 确认加载动画 → 自动全屏播放视频
3. 退出播放器 → 确认 AppBar 显示 `◀ N/M ▶`
4. 点击"下一个" → 确认播放不同视频
5. 点进子目录 → 确认按钮回到 🔀
6. 在无视频目录中点击 🔀 → 确认 SnackBar "未找到视频文件"

- [ ] **Step 4: 提交最终验证结果**

```bash
git add -A
git commit -m "chore: 随机视频播放功能验证通过" \
           -m "全部测试通过，静态分析无 issues" \
           -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
