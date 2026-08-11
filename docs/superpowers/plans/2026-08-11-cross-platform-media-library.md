# Windows and Android Unified Media Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留 `/sync` 媒体 Tab、现有 HTTP 协议和 Android 产品行为的前提下，让 Windows 使用已配置媒体根目录直接浏览本地目录、缩略图、图片和视频。

**Architecture:** application 层新增 transport-neutral 的 `MediaLibrary`、`MediaLibraryFactory`、活动 session 与资源值对象；data 层分别提供 `RemoteMediaLibrary` 和 `LocalMediaLibrary`；app composition 只在可信同步会话或持久化根目录处选择 source。所有路由继续只携带相对路径，presentation 只穷举 `LocalMediaResource`/`NetworkMediaResource`，不按平台选择后端。

**Tech Stack:** Flutter 3.44.6 / Dart 3.11.5 / Riverpod 3.4.2 / `package:http` 1.6.0 / `dart:io` / `video_player` 2.13.0 / proposed `video_player_win` 3.2.2 / GoRouter 17.4.0 / Flutter WidgetTester。

## Global Constraints

- 批准设计是 `docs/superpowers/specs/2026-08-11-cross-platform-media-library-design.md`；若计划与设计冲突，以设计为准并停止执行、修订计划。
- 本计划对设计第 12.3/12.4 节只做一个依赖顺序细化：Task 2 先在 data 层建立 `MediaFileItemDto` 和 `FileItem.hasThumbnail`，但在旧 application/presentation 消费者尚未迁移前保留 `FileItem` 的旧 JSON/`thumbnailUrl` 兼容成员；Task 3 实现依赖 DTO 的 `RemoteMediaLibrary`；Task 6 垂直迁移消费者后再原子删除兼容成员。任何中间提交都不得让 application/presentation 导入 data。
- 当前实现基线是 commit `9ae0fe4`；开始执行前必须重新检查 `git status --short`，不得覆盖用户后续改动。
- Task 0 的执行前提是本计划已经作为独立 docs 提交存在于执行分支；本次“撰写计划”不自动授权提交。若计划仍是 untracked，先取得用户提交指令，不得让 Task 0 的依赖提交顺带夹带计划文件。
- Windows 和 Android 都使用同步页面第三个“媒体”Tab；不得新增一级 `AppDestination.media`。
- Windows 唯一浏览根目录来自 `mediaRootDirectoryProvider`；不得实现任意磁盘浏览器。
- Windows 媒体访问不得通过 localhost、Sync HTTP Server 或 peer HTTP client 回环。
- Android authority 只能来自当前可信 `SyncClientState.server`；路由、`FileItem` 和用户输入不能提供 host/port。
- 路由只持久化规范化相对路径；Windows 盘符、绝对根目录、scheme、host 和 port 不得进入 query。
- 当前 `/api/media/list`、`image`、`video`、`videos/recursive`、`thumbnail` 协议和 JSON key 保持兼容。
- `presentation -> application -> domain` 与 `data -> application/domain` 单向依赖必须通过 `dart run tool/check_import_boundaries.dart`。
- presentation 不得 import media `data/`；application 不得 import `package:http`、`dart:io`、`video_player` 或 media `data/`。
- 不引入完整播放器引擎抽象；只增加 `MediaResource` 到 `VideoPlayerController` 的窄 factory。
- `video_player_win` gate 失败时不得自动安装 codec、启动外部播放器或迁移 `media_kit`；记录证据并停止 Windows 视频接入。
- 不实现删除、移动、重命名、复制、写入、转码、HLS、远程下载、离线同步或浏览状态持久化。
- 所有 Dart 注释使用简体中文；不得在生产代码或测试中写任务号、Phase 号或临时审查编号。
- 所有异步测试等待可观察状态、Completer 或受控 client；不得新增任意 `Future.delayed` 或通用 `pumpAndSettle()`。
- 每个任务按 red → green 验证，使用 PowerShell 7，并把 Flutter 测试输出重定向到日志。
- 每个任务提交前格式化本任务全部 Dart 文件，并运行 `dart format --output=none --set-exit-if-changed`。
- post-commit hook 会自动修改并 amend `pubspec.yaml` 版本；每次提交后重新读取 `HEAD` 与工作区，不能把 hook 版本变化误报为未提交改动。
- Windows 手工 smoke 未实际完成前必须标记 pending；自动化测试和 Windows build 不能代替真实媒体播放。

---

## 1. File and Contract Map

### 1.1 Verified existing files

以下路径均已在 `9ae0fe4` 上用 `Test-Path`/`rg --files` 确认：

| File | Baseline responsibility | Planned responsibility |
|---|---|---|
| `pubspec.yaml:30-57` | media/package dependencies | 增加通过 gate 的 `video_player_win: ^3.2.2` |
| `pubspec.lock` | resolved packages | 锁定 Windows player implementation |
| `windows/flutter/generated_plugin_registrant.cc` | Windows plugin registration | 自动注册 `video_player_win`；只接受 Flutter 生成结果 |
| `windows/flutter/generated_plugins.cmake` | Windows plugin CMake list | 自动加入 `video_player_win` |
| `lib/app/composition/cross_feature_bindings.dart:1-155,212-236` | peer HTTP 与 media server route composition | 绑定 `MediaLibraryFactory`；保留 server routes |
| `lib/app/composition/sync_workspace_screen.dart:1-138` | Sync tabs、Android media session、Windows root picker | 创建 local/remote source 并拥有 session 生命周期 |
| `lib/features/media/application/media_browser_controller.dart:1-164` | 直接 HTTP 目录浏览并持有 server | 只调用 active `MediaLibrary` |
| `lib/features/media/application/shuffle_playback_controller.dart:1-187` | 直接 HTTP 递归视频并构造 URL | 只调用 active `MediaLibrary`，返回相对路径 |
| `lib/features/media/application/media_root_directory_controller.dart` | Windows root persistence | 保持唯一 local root truth |
| `lib/features/media/domain/models/file_item.dart:1-101` | domain + HTTP JSON 混合模型 | 纯 domain；`hasThumbnail` 替代 `thumbnailUrl` |
| `lib/features/media/domain/models/media_server_info.dart` | media 内部 server authority | 删除；由 `RemoteMediaLibrarySource` 替代 |
| `lib/features/media/domain/models/video_item.dart` | recursive playlist item | 保持相对路径模型 |
| `lib/features/media/data/media_directory_scanner.dart` | server-side local scan/security | local library 与 server handler 共享 scanner |
| `lib/features/media/data/media_http_handler.dart` | list HTTP JSON | 通过 DTO 输出兼容 JSON |
| `lib/features/media/data/media_image_http_handler.dart` | image HTTP bytes | 行为不变 |
| `lib/features/media/data/media_video_http_handler.dart` | video HTTP Range | 行为不变 |
| `lib/features/media/data/media_recursive_videos_handler.dart` | recursive video HTTP JSON | 行为不变 |
| `lib/features/media/data/media_thumbnail_http_handler.dart` | thumbnail HTTP/cache | 行为不变，继续复用 generator/cache |
| `lib/features/media/data/media_thumbnail_cache.dart` | deterministic JPEG cache | local library 与 HTTP handler 共享 |
| `lib/features/media/data/media_thumbnail_generator.dart` | image/ffmpeg thumbnail generation | local library 与 HTTP handler 共享 |
| `lib/features/media/utils/path_utils.dart` | route normalization + remote URL helpers | 最终只保留 transport-neutral route normalization |
| `lib/features/media/presentation/media_browser_tab.dart` | server-aware browser UI | session-aware browser UI |
| `lib/features/media/presentation/widgets/media_grid_view.dart` | 传递 thumbnail base URL | 只传 `FileItem` |
| `lib/features/media/presentation/widgets/media_file_tile.dart` | 固定 `Image.network` thumbnail | 通过 resource provider 渲染 local/network thumbnail |
| `lib/features/media/presentation/pages/media_route_pages.dart` | 由 server 构造 image/video URL | 由 active session 解析相对资源 |
| `lib/features/media/presentation/pages/image_viewer_page.dart` | 接收 HTTP URL 列表 | 接收 `MediaAssetRequest` 列表并懒解析 |
| `lib/features/media/presentation/pages/video_player_page.dart` | 接收 URL，默认 network controller | 接收 `MediaResource`，使用窄 factory |
| `lib/features/media/presentation/pages/video_player_gesture.dart` | `Uri -> VideoPlayerController` factory | 无参数 controller factory，避免重试退回网络 |
| `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart` | 通过 non-null URL 判断导航 | 通过 non-null relative path 判断导航 |
| `lib/app/router/app_router.dart` | `/sync/media/*` routes | route matrix 不变 |
| `README.md:177-190` | Android-only media description | 说明 Windows local / Android remote |
| `docs/视频局域网广播-prd.md:19-35,38-56,286-296,891-909` | 原 Windows server + Android client PRD | 追加已批准的 Windows local extension，保留历史背景 |

### 1.2 Planned new production files

| File | Single responsibility |
|---|---|
| `lib/features/media/application/models/media_library_source.dart` | trusted local/remote source value |
| `lib/features/media/application/models/media_library_failure.dart` | finite application failure taxonomy |
| `lib/features/media/application/models/media_resource.dart` | local/network resolved resource value |
| `lib/features/media/application/models/media_resource_request.dart` | value-equal asset/thumbnail requests |
| `lib/features/media/application/ports/media_library.dart` | directory/video/resource use-case port |
| `lib/features/media/application/ports/media_library_factory.dart` | composition-owned source-to-library factory port/provider |
| `lib/features/media/application/media_library_session_controller.dart` | active session state, generation and reset |
| `lib/features/media/application/media_resource_provider.dart` | lazy resource resolution keyed by request + session |
| `lib/features/media/data/dto/media_file_item_dto.dart` | current media-list wire JSON adapter |
| `lib/features/media/data/remote_media_library.dart` | peer HTTP implementation |
| `lib/features/media/data/local_media_library.dart` | direct local filesystem implementation |
| `lib/features/media/data/default_media_library_factory.dart` | create concrete local/remote libraries |
| `lib/features/media/presentation/widgets/media_image_resource_view.dart` | render local/network image resource |
| `lib/features/media/presentation/pages/media_video_controller_factory.dart` | create file/network `VideoPlayerController` |

### 1.3 Planned new/updated tests

| File | Contract |
|---|---|
| `test/features/media/application/media_library_contracts_test.dart` | source/resource/request/failure invariants |
| `test/features/media/application/media_library_session_controller_test.dart` | stale activate/reset and session states |
| `test/features/media/application/media_resource_provider_test.dart` | active/inactive/failure/request dispatch |
| `test/features/media/helpers/fake_media_library.dart` | controlled library/factory signals and call history |
| `test/features/media/data/media_file_item_dto_test.dart` | wire compatibility |
| `test/features/media/data/remote_media_library_test.dart` | URL, timeout, status and JSON mapping |
| `test/features/media/data/local_media_library_test.dart` | local list/resource/thumbnail/security behavior |
| `test/features/media/data/default_media_library_factory_test.dart` | source selection and dependency ownership |
| `test/features/media/presentation/media_image_resource_view_test.dart` | local/network image provider selection |
| `test/features/media/presentation/media_video_controller_factory_test.dart` | file/network controller data source selection |
| existing media application/data/presentation tests | migrate from server/URL assumptions to session/resource contracts |
| existing sync screen/router tests | Android remote preservation, Windows local enablement, reset/deep-link behavior |

---

### Task 0: Gate the Windows video implementation dependency

**Files:**
- Modify: `pubspec.yaml:30-57`
- Modify: `pubspec.lock`
- Regenerate if changed by Flutter: `windows/flutter/generated_plugin_registrant.cc`
- Regenerate if changed by Flutter: `windows/flutter/generated_plugins.cmake`

**Interfaces:**
- Consumes: existing `video_player: ^2.13.0` and locked `video_player_platform_interface 6.9.0`.
- Produces: resolved `video_player_win: ^3.2.2` Windows platform implementation. No production Dart API is introduced in this task.

- [ ] **Step 1: Confirm the repository is clean and the dependency still resolves**

Run:

```powershell
git status --short
flutter pub add --dry-run "video_player_win:^3.2.2"
```

Expected:

- `git status --short` has no output;
- resolver exits `0` and includes `+ video_player_win 3.2.2` plus `Would change 1 dependency`.

Stop if resolution changes/downgrades `video_player`, `video_player_platform_interface`, Flutter SDK constraints, or any unrelated direct dependency. Do not choose another player package without revising the approved design.

- [ ] **Step 2: Add the exact dependency and let Flutter regenerate plugin files**

Run:

```powershell
flutter pub add "video_player_win:^3.2.2"
flutter pub get
git status --short
```

Expected changed files are limited to `pubspec.yaml`, `pubspec.lock`, and Windows generated plugin registrant/CMake files. If another tracked file changes, inspect it before proceeding; do not stage unexplained output.

- [ ] **Step 3: Verify registration and the resolved platform interface**

Run:

```powershell
rg -n "video_player_win|video_player_platform_interface" pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
```

Expected:

- `pubspec.yaml` contains `video_player_win: ^3.2.2`;
- `pubspec.lock` contains `video_player_win 3.2.2` and still resolves `video_player_platform_interface 6.9.0` unless pub resolution selects a newer compatible 6.x version;
- Windows generated registration names the plugin exactly as generated by Flutter.

- [ ] **Step 4: Build both Windows configurations as the dependency gate**

Run:

```powershell
flutter build windows --debug
flutter build windows --release
```

Expected: both commands exit `0` and produce Windows bundles. A Debug-only success is insufficient.

Failure diagnosis:

- CMake/MSBuild failure mentioning `video_player_win`: record the first native error and stop Task 0;
- dependency/interface method mismatch: keep the resolver output, revert only Task 0 files with a user-approved recoverable operation, and stop;
- unrelated stale build artifact: run `flutter clean`, `flutter pub get`, then retry once; a second identical failure is a real gate failure.

- [ ] **Step 5: Commit the dependency gate**

Run:

```powershell
git add pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
git diff --cached --check
git commit -m "chore(media): add Windows video player implementation"
git status --short
```

Expected: commit succeeds; post-commit hook amends the version; final status is clean.

---

### Task 1: Add transport-neutral media library contracts

**Files:**
- Create: `lib/features/media/application/models/media_library_source.dart`
- Create: `lib/features/media/application/models/media_library_failure.dart`
- Create: `lib/features/media/application/models/media_resource.dart`
- Create: `lib/features/media/application/models/media_resource_request.dart`
- Create: `lib/features/media/application/ports/media_library.dart`
- Create: `lib/features/media/application/ports/media_library_factory.dart`
- Create: `test/features/media/application/media_library_contracts_test.dart`
- Create: `test/features/media/helpers/fake_media_library.dart`

**Interfaces:**
- Consumes: `FileItem`, `VideoItem`, Equatable, Riverpod `Provider`.
- Produces:
  - `MediaLibrarySource`, `LocalMediaLibrarySource`, `RemoteMediaLibrarySource`, `MediaSourceKind`;
  - `MediaLibraryFailureCode`, `MediaLibraryFailure`;
  - `MediaResource`, `LocalMediaResource`, `NetworkMediaResource`;
  - `MediaResourceRequest`, `MediaAssetRequest`, `MediaThumbnailRequest`, `MediaAssetKind`;
  - `MediaLibrary`, `MediaLibraryFactory`, `mediaLibraryFactoryProvider`;
  - controlled `FakeMediaLibrary` and `FakeMediaLibraryFactory` for all later tests.

- [ ] **Step 1: Write failing value-contract tests**

Create `media_library_contracts_test.dart` with these cases:

```dart
void main() {
  test('source values compare by immutable local root or remote base URI', () {
    expect(
      const LocalMediaLibrarySource(r'D:\Media'),
      const LocalMediaLibrarySource(r'D:\Media'),
    );
    expect(
      RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
      RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
    );
  });

  test('resource rejects the wrong URI scheme', () {
    expect(
      () => LocalMediaResource(Uri.parse('http://localhost/a.jpg')),
      throwsArgumentError,
    );
    expect(
      () => NetworkMediaResource(Uri.file(r'D:\Media\a.jpg')),
      throwsArgumentError,
    );
  });

  test('network headers are copied and cannot be mutated', () {
    final headers = {'Authorization': 'peer'};
    final resource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/image/a.jpg'),
      headers: headers,
    );
    headers['Authorization'] = 'changed';
    expect(resource.headers['Authorization'], 'peer');
    expect(() => resource.headers['x'] = 'y', throwsUnsupportedError);
  });

  test('thumbnail request equality covers every cache invalidator', () {
    const base = MediaThumbnailRequest(
      relativePath: '/a.jpg',
      sizeBytes: 10,
      lastModified: 20,
      hasThumbnail: true,
    );
    expect(base, const MediaThumbnailRequest(
      relativePath: '/a.jpg',
      sizeBytes: 10,
      lastModified: 20,
      hasThumbnail: true,
    ));
    expect(base, isNot(const MediaThumbnailRequest(
      relativePath: '/a.jpg',
      sizeBytes: 11,
      lastModified: 20,
      hasThumbnail: true,
    )));
  });
}
```

- [ ] **Step 2: Run the contract test and confirm red**

Run:

```powershell
flutter test test/features/media/application/media_library_contracts_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task1-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 80 task1-red.log
```

Expected: non-zero because the new media application types do not exist. If it fails for an environment error before compilation, fix the environment first; that is not valid red evidence.

- [ ] **Step 3: Implement the exact source and failure contracts**

Implement `media_library_source.dart` as Equatable sealed values with immutable fields:

```dart
enum MediaSourceKind { local, remote }

sealed class MediaLibrarySource extends Equatable {
  const MediaLibrarySource();
  MediaSourceKind get kind;
}

final class LocalMediaLibrarySource extends MediaLibrarySource {
  const LocalMediaLibrarySource(this.rootDirectory);
  final String rootDirectory;
  @override
  MediaSourceKind get kind => MediaSourceKind.local;
  @override
  List<Object?> get props => [rootDirectory];
}

final class RemoteMediaLibrarySource extends MediaLibrarySource {
  const RemoteMediaLibrarySource(this.baseUri);
  final Uri baseUri;
  @override
  MediaSourceKind get kind => MediaSourceKind.remote;
  @override
  List<Object?> get props => [baseUri];
}
```

Implement `media_library_failure.dart` without raw filesystem/HTTP causes in the user-facing object:

```dart
enum MediaLibraryFailureCode {
  sourceUnavailable,
  invalidPath,
  notFound,
  accessDenied,
  networkUnavailable,
  timeout,
  invalidResponse,
  unsupportedMedia,
  thumbnailUnavailable,
}

final class MediaLibraryFailure implements Exception {
  const MediaLibraryFailure(this.code, this.message);
  final MediaLibraryFailureCode code;
  final String message;
  @override
  String toString() => message;
}
```

- [ ] **Step 4: Implement resource and request values**

Implement URI validation and defensive header copying:

```dart
sealed class MediaResource extends Equatable {
  const MediaResource();
  Uri get uri;
}

final class LocalMediaResource extends MediaResource {
  LocalMediaResource(this.uri) {
    if (!uri.isAbsolute || uri.scheme != 'file') {
      throw ArgumentError.value(uri, 'uri', '必须是绝对 file URI');
    }
  }
  @override
  final Uri uri;
  @override
  List<Object?> get props => [uri];
}

final class NetworkMediaResource extends MediaResource {
  NetworkMediaResource(this.uri, {Map<String, String> headers = const {}})
    : headers = Map.unmodifiable(headers) {
    if (!uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(uri, 'uri', '必须是绝对 HTTP(S) URI');
    }
  }
  @override
  final Uri uri;
  final Map<String, String> headers;
  @override
  List<Object?> get props => [uri, headers];
}
```

Implement request props exactly:

```dart
enum MediaAssetKind { image, video }

sealed class MediaResourceRequest extends Equatable {
  const MediaResourceRequest();
}

final class MediaAssetRequest extends MediaResourceRequest {
  const MediaAssetRequest({required this.kind, required this.relativePath});
  final MediaAssetKind kind;
  final String relativePath;
  @override
  List<Object?> get props => [kind, relativePath];
}

final class MediaThumbnailRequest extends MediaResourceRequest {
  const MediaThumbnailRequest({
    required this.relativePath,
    required this.sizeBytes,
    required this.lastModified,
    required this.hasThumbnail,
  });
  final String relativePath;
  final int sizeBytes;
  final int lastModified;
  final bool hasThumbnail;
  @override
  List<Object?> get props => [
    relativePath,
    sizeBytes,
    lastModified,
    hasThumbnail,
  ];
}
```

- [ ] **Step 5: Implement the ports and required provider**

`media_library.dart`:

```dart
abstract interface class MediaLibrary {
  Future<List<FileItem>> listDirectory(String relativePath);
  Future<List<VideoItem>> listVideosRecursively(String relativePath);
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request);
  Future<MediaResource> resolveAsset(MediaAssetRequest request);
}
```

`media_library_factory.dart`:

```dart
abstract interface class MediaLibraryFactory {
  Future<MediaLibrary> open(MediaLibrarySource source);
}

final mediaLibraryFactoryProvider = Provider<MediaLibraryFactory>((ref) {
  throw StateError('MediaLibraryFactory 尚未由应用组合层绑定');
});
```

- [ ] **Step 6: Add reusable controlled fakes**

Create `fake_media_library.dart` with:

- maps for `directoryResults` and `recursiveVideoResults`;
- maps for asset/thumbnail resources;
- call-history lists for all four methods;
- optional Completers for list and factory opening;
- optional `MediaLibraryFailure` per operation;
- `FakeMediaLibraryFactory.openedSources` and a queue of library/failure/completer results.

The public surface must include these exact members for later tasks:

```dart
final class FakeMediaLibrary implements MediaLibrary {
  final Map<String, List<FileItem>> directoryResults = {};
  final Map<String, List<VideoItem>> recursiveVideoResults = {};
  final Map<MediaAssetRequest, MediaResource> assetResults = {};
  final Map<MediaThumbnailRequest, MediaResource?> thumbnailResults = {};
  final List<String> listDirectoryCalls = [];
  final List<String> listVideosRecursivelyCalls = [];
  final List<MediaAssetRequest> resolveAssetCalls = [];
  final List<MediaThumbnailRequest> resolveThumbnailCalls = [];
  Completer<List<FileItem>>? pendingDirectory;
  Completer<List<VideoItem>>? pendingVideos;
  MediaLibraryFailure? directoryFailure;
  MediaLibraryFailure? videoFailure;
  MediaLibraryFailure? assetFailure;
  MediaLibraryFailure? thumbnailFailure;
}

final class FakeMediaLibraryFactory implements MediaLibraryFactory {
  FakeMediaLibraryFactory(this.library);
  final MediaLibrary library;
  final List<MediaLibrarySource> openedSources = [];
  Completer<MediaLibrary>? pendingOpen;
  MediaLibraryFailure? failure;
}
```

Implement each method deterministically: record the call first, then throw configured failure, await configured Completer, or return the configured map/default empty list.

- [ ] **Step 7: Run green tests and the architecture gate**

Run:

```powershell
dart format lib/features/media/application/models lib/features/media/application/ports test/features/media/application/media_library_contracts_test.dart test/features/media/helpers/fake_media_library.dart
flutter test test/features/media/application/media_library_contracts_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task1-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 80 task1-green.log
dart run tool/check_import_boundaries.dart
```

Expected: test exit `0`; import gate exit `0`.

- [ ] **Step 8: Commit the application contracts**

Run:

```powershell
git add lib/features/media/application/models lib/features/media/application/ports test/features/media/application/media_library_contracts_test.dart test/features/media/helpers/fake_media_library.dart
dart format --output=none --set-exit-if-changed lib/features/media/application/models lib/features/media/application/ports test/features/media/application/media_library_contracts_test.dart test/features/media/helpers/fake_media_library.dart
git diff --cached --check
git commit -m "refactor(media): extract media library access contracts"
git status --short
```

Expected: clean status after post-commit version amend.

---

### Task 2: Introduce the data-owned media-list DTO with bounded compatibility

**Files:**
- Create: `lib/features/media/data/dto/media_file_item_dto.dart`
- Create: `test/features/media/data/media_file_item_dto_test.dart`
- Modify: `lib/features/media/domain/models/file_item.dart:1-101`
- Modify: `lib/features/media/data/media_directory_scanner.dart:124-137`
- Modify: `lib/features/media/data/media_http_handler.dart:18-29`
- Modify: `test/features/media/domain/models/file_item_test.dart`
- Modify: `test/features/media/data/media_directory_scanner_test.dart`
- Modify: `test/features/media/data/media_http_handler_test.dart`

**Interfaces:**
- Consumes: `FileItem` wire fields currently emitted by `/api/media/list`.
- Produces: transport-neutral `FileItem.hasThumbnail`; data-owned `MediaFileItemDto.fromDomain`, `toDomain`, `toJson`, `fromJson`, `listFromJson`; byte-for-byte compatible JSON keys/semantics. `FileItem` 的旧 JSON/`thumbnailUrl` 成员是明确受限的过渡兼容面，只允许现有 application/presentation 消费者继续使用到 Task 6。

- [ ] **Step 1: Copy existing wire assertions into a failing DTO test**

Create `media_file_item_dto_test.dart` and copy the current file/directory/default/list wire cases into the data-layer adapter test. Do not delete the old `FileItem` wire tests in this task because the old application controller still exercises that compatibility path until Task 6. Use these key assertions:

```dart
test('file JSON remains protocol compatible', () {
  const item = FileItem(
    name: 'test.mp4',
    isDirectory: false,
    sizeBytes: 1024,
    relativePath: '/test.mp4',
    lastModified: 1712345678,
    mimeType: 'video/mp4',
    hasThumbnail: true,
  );
  final json = MediaFileItemDto.fromDomain(item).toJson();
  expect(json, {
    'type': 'file',
    'name': 'test.mp4',
    'relativePath': '/test.mp4',
    'size': 1024,
    'lastModified': 1712345678,
    'mimeType': 'video/mp4',
    'thumbnailUrl': '/api/media/thumbnail/test.mp4',
  });
});

test('directory omits file-only keys', () {
  final json = MediaFileItemDto.fromDomain(const FileItem(
    name: 'subdir',
    isDirectory: true,
    sizeBytes: 0,
    relativePath: '/subdir',
  )).toJson();
  expect(json.containsKey('mimeType'), isFalse);
  expect(json.containsKey('thumbnailUrl'), isFalse);
});
```

- [ ] **Step 2: Run the DTO test and confirm red**

Run the single file with redirected output. Expected: compile failure because `hasThumbnail` and `MediaFileItemDto` do not exist.

```powershell
flutter test test/features/media/data/media_file_item_dto_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task2-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 80 task2-red.log
```

- [ ] **Step 3: Add the transport-neutral thumbnail signal without breaking the old consumer**

In `file_item.dart`:

- add `final bool hasThumbnail` with default `false`;
- retain `dart:convert`, `thumbnailUrl`, `toJson`, `fromJson`, and `listFromJson` unchanged for the current controller/tile;
- retain name/directory/size/path/modified/MIME/formattedSize/toString behavior;
- add a Task 6 plan assertion—not a production task marker—that these compatibility members are deleted in the same vertical migration that removes their final consumers.

The temporary constructor target is deliberately dual-shaped:

Constructor target:

```dart
const FileItem({
  required this.name,
  required this.isDirectory,
  required this.sizeBytes,
  required this.relativePath,
  this.lastModified = 0,
  this.mimeType,
  this.hasThumbnail = false,
  this.thumbnailUrl,
});
```

`FileItem.fromJson` continues setting `thumbnailUrl` exactly as today and additionally sets `hasThumbnail: json['thumbnailUrl'] != null`. `toJson` continues emitting the legacy field from `thumbnailUrl`, so the old controller and tile behave unchanged. No application or presentation file may import `MediaFileItemDto`.

- [ ] **Step 4: Implement the exact wire adapter**

`MediaFileItemDto` owns the existing protocol fields and derives the endpoint rather than storing it in domain:

```dart
final class MediaFileItemDto {
  const MediaFileItemDto({
    required this.item,
    required this.thumbnailUrl,
  });

  final FileItem item;
  final String? thumbnailUrl;

  factory MediaFileItemDto.fromDomain(FileItem item) => MediaFileItemDto(
    item: item,
    thumbnailUrl: item.hasThumbnail
        ? '/api/media/thumbnail${item.relativePath}'
        : null,
  );

  FileItem toDomain() => FileItem(
    name: item.name,
    isDirectory: item.isDirectory,
    sizeBytes: item.sizeBytes,
    relativePath: item.relativePath,
    lastModified: item.lastModified,
    mimeType: item.mimeType,
    hasThumbnail: thumbnailUrl != null,
  );
}
```

Implement `fromJson`, `toJson`, and `listFromJson(String)` with the exact legacy defaults: missing `size`/`lastModified` become `0`; missing optional fields become null/false; malformed required `name`/`relativePath` remains a decoding failure for the remote adapter to map later.

- [ ] **Step 5: Rewire the scanner and HTTP handler inside data only**

Use these replacements:

```dart
// scanner
final hasThumbnail = !isDir && (isImageFile(name) || isVideoFile(name));
// FileItem constructor fields during the bounded transition:
hasThumbnail: hasThumbnail,
thumbnailUrl: hasThumbnail ? '/api/media/thumbnail$relativePath' : null,

// MediaHttpHandler
final json = jsonEncode([
  for (final item in items) MediaFileItemDto.fromDomain(item).toJson(),
]);
```

`MediaBrowserController` keeps calling `FileItem.listFromJson`; `MediaFileTile` keeps reading `item.thumbnailUrl`. This is intentional until Task 6 and prevents an application → data import. The handler output must remain identical.

- [ ] **Step 6: Update existing tests and verify wire compatibility**

Update scanner/DTO fixtures to set both fields where the transitional legacy endpoint is observable. `file_item_test.dart` retains its existing wire compatibility cases and adds assertions that `fromJson` derives `hasThumbnail` while old JSON output is unchanged. `media_http_handler_test.dart` must continue asserting the literal `thumbnailUrl` JSON key and path.

Run:

```powershell
$Files = @(
  'test/features/media/data/media_file_item_dto_test.dart',
  'test/features/media/domain/models/file_item_test.dart',
  'test/features/media/data/media_directory_scanner_test.dart',
  'test/features/media/data/media_http_handler_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task2-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 100 task2-green.log
```

Expected: exit `0`; handler JSON assertions are unchanged from the client protocol perspective.

- [ ] **Step 7: Run a narrow protocol diff audit**

Run:

```powershell
rg -n "thumbnailUrl|toJson\(|fromJson\(|listFromJson" lib/features/media test/features/media
```

Expected:

- `MediaFileItemDto` imports/usages exist only under `lib/features/media/data/` and `test/features/media/data/`;
- `media_browser_controller.dart` still calls `FileItem.listFromJson` and has no data import;
- `media_file_tile.dart` still reads the transitional `FileItem.thumbnailUrl` and has no data import;
- no new application/presentation → data edge exists;
- handler wire keys and paths are unchanged.

Run the boundary-specific audit explicitly:

```powershell
rg -n "features/media/data|\.\./data|data/dto/media_file_item_dto" `
  lib/features/media/application lib/features/media/presentation
```

Expected: no matches introduced by Task 2. If the controller imports the DTO, stop and restore `FileItem.listFromJson` until Task 6.

- [ ] **Step 8: Format, verify, and commit**

Run the four targeted tests again after formatting, then:

```powershell
dart run tool/check_import_boundaries.dart
git add lib/features/media test/features/media
git diff --cached --check
git commit -m "refactor(media): isolate media file HTTP DTO"
git status --short
```

Expected: import checker reports `0` violations and the commit leaves a clean worktree after version amend. Any `APPLICATION_TO_DATA` result is a Task 2 stop condition: do not commit; inspect staged imports and restore the old application parser.

---
### Task 3: Implement the remote peer-HTTP media library

**Files:**
- Create: `lib/features/media/data/remote_media_library.dart`
- Create: `test/features/media/data/remote_media_library_test.dart`
- Reuse: `lib/features/media/data/dto/media_file_item_dto.dart`
- Reuse: `lib/features/media/utils/path_utils.dart` (`encodeMediaPath` remains until Task 6 cleanup)

**Interfaces:**
- Consumes: `MediaLibrary`, `RemoteMediaLibrarySource.baseUri`, `http.Client`, `MediaFileItemDto`, `VideoItem`.
- Produces: `RemoteMediaLibrary({required Uri baseUri, required http.Client httpClient, Duration directoryTimeout, Duration recursiveTimeout})` implementing all four port methods without reading global providers.

- [ ] **Step 1: Write failing URL and no-preflight tests**

Use `MockClient` with request history:

```dart
test('encodes each directory segment and parses the list DTO', () async {
  final requests = <http.Request>[];
  final library = RemoteMediaLibrary(
    baseUri: Uri.parse('http://192.168.1.5:8080'),
    httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response('[{"type":"file","name":"猫.jpg",'
          '"relativePath":"/相册/猫.jpg","size":10,'
          '"lastModified":20,"mimeType":"image/jpeg",'
          '"thumbnailUrl":"/api/media/thumbnail/相册/猫.jpg"}]', 200);
    }),
  );

  final items = await library.listDirectory('/相册/旅行 2026');
  expect(requests.single.url.toString(),
      'http://192.168.1.5:8080/api/media/list/%E7%9B%B8%E5%86%8C/'
      '%E6%97%85%E8%A1%8C%202026');
  expect(items.single.hasThumbnail, isTrue);
});

test('resolving image video and thumbnail performs no HTTP preflight', () async {
  var requestCount = 0;
  final library = RemoteMediaLibrary(
    baseUri: Uri.parse('http://192.168.1.5:8080'),
    httpClient: MockClient((_) async {
      requestCount++;
      return http.Response('', 500);
    }),
  );
  final image = await library.resolveAsset(const MediaAssetRequest(
    kind: MediaAssetKind.image,
    relativePath: '/相册/猫.jpg',
  ));
  final video = await library.resolveAsset(const MediaAssetRequest(
    kind: MediaAssetKind.video,
    relativePath: '/视频/猫.mp4',
  ));
  final thumb = await library.resolveThumbnail(const MediaThumbnailRequest(
    relativePath: '/视频/猫.mp4',
    sizeBytes: 1,
    lastModified: 2,
    hasThumbnail: true,
  ));
  expect(requestCount, 0);
  expect(image.uri.path, '/api/media/image/相册/猫.jpg');
  expect(video.uri.path, '/api/media/video/视频/猫.mp4');
  expect(thumb!.uri.path, '/api/media/thumbnail/视频/猫.mp4');
});
```

- [ ] **Step 2: Write failing failure-mapping tests**

Parameterize these status branches instead of duplicating setup:

```dart
final statusCases = <({int status, MediaLibraryFailureCode code})>[
  (status: 400, code: MediaLibraryFailureCode.invalidPath),
  (status: 403, code: MediaLibraryFailureCode.invalidPath),
  (status: 404, code: MediaLibraryFailureCode.notFound),
  (status: 408, code: MediaLibraryFailureCode.timeout),
  (status: 500, code: MediaLibraryFailureCode.invalidResponse),
];
```

Also add deterministic tests for:

- `MockClient` throwing `http.ClientException` → `networkUnavailable`;
- a never-completing client with a 1ms injected timeout → `timeout` using a Completer released in tearDown, not `Future.delayed`;
- status 200 malformed list JSON → `invalidResponse`;
- invalid relative paths without leading `/`, containing `.`/`..`, or mismatched image/video extensions → `invalidPath`/`unsupportedMedia` without sending a request;
- base URI with query, fragment, userInfo, non-HTTP scheme, or non-root path → constructor `ArgumentError`;
- `hasThumbnail == false` → `resolveThumbnail` returns null.

- [ ] **Step 3: Run the remote tests and confirm red**

```powershell
flutter test test/features/media/data/remote_media_library_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task3-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 100 task3-red.log
```

Expected: compile failure because `RemoteMediaLibrary` does not exist.

- [ ] **Step 4: Implement trusted URI construction**

The constructor validates the base once. Build resource URIs with `pathSegments`, never string-concatenate authority:

```dart
final class RemoteMediaLibrary implements MediaLibrary {
  RemoteMediaLibrary({
    required Uri baseUri,
    required http.Client httpClient,
    this.directoryTimeout = const Duration(seconds: 10),
    this.recursiveTimeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri),
       _httpClient = httpClient;

  final Uri _baseUri;
  final http.Client _httpClient;
  final Duration directoryTimeout;
  final Duration recursiveTimeout;

  Uri _mediaUri(String route, String relativePath) {
    final segments = _relativeSegments(relativePath);
    return _baseUri.replace(
      pathSegments: ['api', 'media', route, ...segments],
      query: null,
      fragment: null,
    );
  }
}
```

`_relativeSegments` must require a leading `/`, reject empty asset paths, and reject `.`/`..`. Directory root `/` returns an empty list. `_validateBaseUri` requires HTTP(S), non-empty host, no userInfo/query/fragment, and path `''` or `'/'`.

- [ ] **Step 5: Implement list operations and typed HTTP failures**

Implement one private GET helper that maps status before decoding:

```dart
Future<http.Response> _get(Uri uri, Duration timeout) async {
  try {
    final response = await _httpClient.get(uri).timeout(timeout);
    if (response.statusCode == 200) return response;
    throw switch (response.statusCode) {
      400 || 403 => const MediaLibraryFailure(
          MediaLibraryFailureCode.invalidPath, '媒体路径无效'),
      404 => const MediaLibraryFailure(
          MediaLibraryFailureCode.notFound, '媒体资源不存在'),
      408 || 504 => const MediaLibraryFailure(
          MediaLibraryFailureCode.timeout, '媒体请求超时'),
      _ => const MediaLibraryFailure(
          MediaLibraryFailureCode.invalidResponse, '媒体服务响应失败'),
    };
  } on TimeoutException {
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.timeout,
      '媒体请求超时',
    );
  } on http.ClientException {
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.networkUnavailable,
      '无法连接媒体服务',
    );
  }
}
```

Do not catch an already-mapped `MediaLibraryFailure` in a broad catch. Wrap JSON decoding separately as `invalidResponse`.

`listDirectory` calls `MediaFileItemDto.listFromJson`; `listVideosRecursively` decodes a JSON list and maps `VideoItem.fromJson`.

- [ ] **Step 6: Implement resource resolution**

```dart
@override
Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) async {
  if (!request.hasThumbnail) return null;
  return NetworkMediaResource(_mediaUri('thumbnail', request.relativePath));
}

@override
Future<MediaResource> resolveAsset(MediaAssetRequest request) async {
  final supported = switch (request.kind) {
    MediaAssetKind.image => isImageFile(request.relativePath),
    MediaAssetKind.video => isVideoFile(request.relativePath),
  };
  if (!supported) {
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.unsupportedMedia,
      '不支持的媒体类型',
    );
  }
  final route = request.kind == MediaAssetKind.image ? 'image' : 'video';
  return NetworkMediaResource(_mediaUri(route, request.relativePath));
}
```

- [ ] **Step 7: Run green tests and existing path tests**

```powershell
dart format lib/features/media/data/remote_media_library.dart test/features/media/data/remote_media_library_test.dart
$Files = @(
  'test/features/media/data/remote_media_library_test.dart',
  'test/features/media/utils/path_utils_test.dart',
  'test/features/media/data/media_file_item_dto_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task3-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 100 task3-green.log
dart run tool/check_import_boundaries.dart
```

Expected: exit `0`; existing path tests remain green.

- [ ] **Step 8: Commit the remote adapter**

```powershell
git add lib/features/media/data/remote_media_library.dart test/features/media/data/remote_media_library_test.dart
dart format --output=none --set-exit-if-changed lib/features/media/data/remote_media_library.dart test/features/media/data/remote_media_library_test.dart
git diff --cached --check
git commit -m "refactor(media): add remote media library adapter"
git status --short
```

---

### Task 4: Implement local filesystem media access and the default factory

**Files:**
- Create: `lib/features/media/data/local_media_library.dart`
- Create: `lib/features/media/data/default_media_library_factory.dart`
- Create: `test/features/media/data/local_media_library_test.dart`
- Create: `test/features/media/data/default_media_library_factory_test.dart`
- Modify: `lib/features/media/data/media_directory_scanner.dart:13-23` (documentation only: shared local scanner)

**Interfaces:**
- Consumes: `MediaDirectoryScanner`, `MediaThumbnailCache`, `MediaThumbnailGenerator`, `ThumbnailProcessRunner`, `RemoteMediaLibrary`, `MediaLibraryFactory`.
- Produces:
  - `LocalMediaLibrary({required scanner, required cache, required generator})`;
  - `DefaultMediaLibraryFactory({required peerHttpClient, cacheFactory, processRunner})`;
  - no HTTP dependency in `LocalMediaLibrary`.

- [ ] **Step 1: Write failing local list and resource tests**

Create a fresh temp directory in each test and clean it with `addTearDown`. Cover:

```dart
test('lists root and resolves Chinese local image/video file URIs', () async {
  final root = await Directory.systemTemp.createTemp('omll_local_media_');
  addTearDown(() => root.delete(recursive: true));
  final album = Directory('${root.path}${Platform.pathSeparator}相册')
    ..createSync();
  final image = File('${album.path}${Platform.pathSeparator}猫.jpg')
    ..writeAsBytesSync([1, 2, 3]);
  final video = File('${album.path}${Platform.pathSeparator}猫.mp4')
    ..writeAsBytesSync([4, 5, 6]);
  final library = buildLocalLibraryForTest(root);

  final items = await library.listDirectory('/相册');
  final imageResource = await library.resolveAsset(const MediaAssetRequest(
    kind: MediaAssetKind.image,
    relativePath: '/相册/猫.jpg',
  ));
  final videoResource = await library.resolveAsset(const MediaAssetRequest(
    kind: MediaAssetKind.video,
    relativePath: '/相册/猫.mp4',
  ));

  expect(items.map((item) => item.name), containsAll(['猫.jpg', '猫.mp4']));
  expect(File.fromUri(imageResource.uri).absolute.path, image.absolute.path);
  expect(File.fromUri(videoResource.uri).absolute.path, video.absolute.path);
});
```

Define the test helper in the same file so it never opens platform channels or ffmpeg:

```dart
LocalMediaLibrary buildLocalLibraryForTest(Directory root) {
  final scanner = MediaDirectoryScanner(root.path);
  return LocalMediaLibrary(
    scanner: scanner,
    cache: MediaThumbnailCache.custom(
      Directory('${root.path}${Platform.pathSeparator}.thumbnail-test-cache'),
    ),
    generator: MediaThumbnailGenerator(
      scanner: scanner,
      processRunner: const DartThumbnailProcessRunner(),
    ),
  );
}
```

The listing/asset cases never call the generator. Thumbnail cases replace it with the controlled fake described in Step 2.

Add failures for:

- `../outside.jpg` → `invalidPath`;
- missing root/target → `sourceUnavailable` for root, `notFound` for asset;
- image request for `.mp4` → `unsupportedMedia`;
- recursive videos delegate and preserve relative paths;
- local resources have `file` scheme and never contain an HTTP authority.

- [ ] **Step 2: Write failing thumbnail cache/generator tests**

Define this controlled fake in `local_media_library_test.dart`; it never reads the source file and therefore cannot enter `package:image` or ffmpeg code:

```dart
final class FakeMediaThumbnailGenerator extends MediaThumbnailGenerator {
  FakeMediaThumbnailGenerator(MediaDirectoryScanner scanner)
    : super(
        scanner: scanner,
        processRunner: const DartThumbnailProcessRunner(),
      );

  final List<String> calls = [];
  List<int> bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  ThumbnailException? failure;

  @override
  Future<List<int>> generate(String relativePath) async {
    calls.add(relativePath);
    final configuredFailure = failure;
    if (configuredFailure != null) throw configuredFailure;
    return bytes;
  }
}
```

Import `dart:convert`, the scanner/generator/process-runner production files, and use a fresh fake per test. Assert:

1. `hasThumbnail == false` returns null and does not call generator;
2. first resolve generates bytes, writes cache, returns cached file resource;
3. second identical request is a cache hit and generator call count remains one;
4. size/modified change uses a different cache key and calls generator again;
5. `ThumbnailException` maps to `thumbnailUnavailable`.

Use `MediaThumbnailCache.custom(Directory(...))`; never invoke real ffmpeg in this test.

- [ ] **Step 3: Write failing factory selection tests**

Inject a temp cache factory and `MockClient`. Assert:

```dart
final factory = DefaultMediaLibraryFactory(
  peerHttpClient: client,
  cacheFactory: () async => MediaThumbnailCache.custom(cacheDir),
  processRunner: const DartThumbnailProcessRunner(),
);
expect(await factory.open(LocalMediaLibrarySource(root.path)),
    isA<LocalMediaLibrary>());
expect(await factory.open(RemoteMediaLibrarySource(
  Uri.parse('http://192.168.1.5:8080'))), isA<RemoteMediaLibrary>());
```

Also prove opening a local source makes zero calls to `MockClient`.

- [ ] **Step 4: Run the new tests and confirm red**

```powershell
$Files = @(
  'test/features/media/data/local_media_library_test.dart',
  'test/features/media/data/default_media_library_factory_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task4-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 100 task4-red.log
```

Expected: compile failure because local library/factory do not exist.

- [ ] **Step 5: Implement LocalMediaLibrary with fixed failure mapping**

Core implementation:

```dart
final class LocalMediaLibrary implements MediaLibrary {
  LocalMediaLibrary({
    required MediaDirectoryScanner scanner,
    required MediaThumbnailCache cache,
    required MediaThumbnailGenerator generator,
  }) : _scanner = scanner,
       _cache = cache,
       _generator = generator;

  final MediaDirectoryScanner _scanner;
  final MediaThumbnailCache _cache;
  final MediaThumbnailGenerator _generator;

  @override
  Future<List<FileItem>> listDirectory(String relativePath) =>
      _mapFileSystem(() => _scanner.scan(relativePath), rootOperation: true);

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) =>
      _mapFileSystem(
        () => _scanner.scanRecursiveVideos(relativePath),
        rootOperation: true,
      );
}
```

Implement `_mapFileSystem` with these deterministic branches:

- `PathTraversalException` → `invalidPath` / `媒体路径无效`;
- `FileSystemException` errorCode 2 or 3 during root/list operation → `sourceUnavailable` / `媒体根目录不可用`;
- errorCode 2 or 3 during asset operation → `notFound` / `媒体资源不存在`;
- errorCode 5 or 13 → `accessDenied` / `没有媒体访问权限`;
- any other `FileSystemException` → `sourceUnavailable` with safe fixed message;
- never interpolate `exception.path` into failure.message.

- [ ] **Step 6: Implement local asset and thumbnail resolution**

Asset sequence is fixed: validate kind/extension → `scanner.resolvePath` → `File.exists` → `LocalMediaResource(file.absolute.uri)`. Do not hand-build `file:///` or branch on the platform when constructing the URI.

Thumbnail sequence:

```dart
@override
Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) async {
  if (!request.hasThumbnail) return null;
  final hit = _cache.get(
    request.relativePath,
    request.sizeBytes,
    request.lastModified,
  );
  if (hit != null) return LocalMediaResource(hit.absolute.uri);
  try {
    final bytes = await _generator.generate(request.relativePath);
    final file = await _cache.put(
      request.relativePath,
      request.sizeBytes,
      request.lastModified,
      bytes,
    );
    return LocalMediaResource(file.absolute.uri);
  } on ThumbnailException {
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.thumbnailUnavailable,
      '缩略图不可用',
    );
  }
}
```

Map `FileSystemException` from cache/generator through the same safe mapper.

- [ ] **Step 7: Implement DefaultMediaLibraryFactory**

```dart
typedef MediaThumbnailCacheFactory = Future<MediaThumbnailCache> Function();

final class DefaultMediaLibraryFactory implements MediaLibraryFactory {
  DefaultMediaLibraryFactory({
    required http.Client peerHttpClient,
    MediaThumbnailCacheFactory? cacheFactory,
    ThumbnailProcessRunner processRunner = const DartThumbnailProcessRunner(),
  }) : _peerHttpClient = peerHttpClient,
       _cacheFactory = cacheFactory ?? MediaThumbnailCache.defaultLocation,
       _processRunner = processRunner;

  final http.Client _peerHttpClient;
  final MediaThumbnailCacheFactory _cacheFactory;
  final ThumbnailProcessRunner _processRunner;

  @override
  Future<MediaLibrary> open(MediaLibrarySource source) async => switch (source) {
    LocalMediaLibrarySource(:final rootDirectory) => _openLocal(rootDirectory),
    RemoteMediaLibrarySource(:final baseUri) => RemoteMediaLibrary(
        baseUri: baseUri,
        httpClient: _peerHttpClient,
      ),
  };
}
```

`_openLocal` constructs one scanner, one cache, and one generator that shares the same scanner. It must not inspect `Platform` or open the peer client.

- [ ] **Step 8: Run local/factory green tests plus scanner/cache regressions**

```powershell
dart format lib/features/media/data/local_media_library.dart lib/features/media/data/default_media_library_factory.dart test/features/media/data/local_media_library_test.dart test/features/media/data/default_media_library_factory_test.dart
$Files = @(
  'test/features/media/data/local_media_library_test.dart',
  'test/features/media/data/default_media_library_factory_test.dart',
  'test/features/media/data/media_directory_scanner_test.dart',
  'test/features/media/data/media_thumbnail_cache_test.dart',
  'test/features/media/data/media_thumbnail_generator_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task4-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 120 task4-green.log
dart run tool/check_import_boundaries.dart
```

Expected: exit `0`; no real ffmpeg needed outside the existing controlled generator tests.

- [ ] **Step 9: Commit local access and the factory**

```powershell
git add lib/features/media/data/local_media_library.dart lib/features/media/data/default_media_library_factory.dart lib/features/media/data/media_directory_scanner.dart test/features/media/data/local_media_library_test.dart test/features/media/data/default_media_library_factory_test.dart
git diff --cached --check
git commit -m "feat(media): implement local media library access"
git status --short
```

---

### Task 5: Add active media sessions and lazy resource resolution

**Files:**
- Create: `lib/features/media/application/media_library_session_controller.dart`
- Create: `lib/features/media/application/media_resource_provider.dart`
- Create: `test/features/media/application/media_library_session_controller_test.dart`
- Create: `test/features/media/application/media_resource_provider_test.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart:50-155`
- Modify: `test/helpers/test_harness.dart:30-165`

**Interfaces:**
- Consumes: `mediaLibraryFactoryProvider`, `MediaLibrarySource`, `MediaLibrary`, `MediaResourceRequest`.
- Produces:
  - `mediaLibrarySessionProvider`;
  - `MediaLibrarySessionInactive`, `Opening`, `Active`, `Failed`;
  - `activate`, `fail`, `reset` with monotonically increasing generation;
  - `mediaResourceProvider` dispatching asset/thumbnail requests;
  - `bindMediaLibraryFactory` composition/harness switch for tests.

- [ ] **Step 1: Write failing session race tests**

Test with `ProviderContainer` and `FakeMediaLibraryFactory`:

```dart
test('reset makes a pending activate result stale', () async {
  final library = FakeMediaLibrary();
  final factory = FakeMediaLibraryFactory(library)
    ..pendingOpen = Completer<MediaLibrary>();
  final container = ProviderContainer(overrides: [
    mediaLibraryFactoryProvider.overrideWithValue(factory),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
  addTearDown(sub.close);

  final activation = container
      .read(mediaLibrarySessionProvider.notifier)
      .activate(const LocalMediaLibrarySource(r'D:\Media'));
  expect(container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionOpening>());
  container.read(mediaLibrarySessionProvider.notifier).reset();
  factory.pendingOpen!.complete(library);
  expect(await activation, isFalse);
  expect(container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionInactive>());
});
```

Add:

- successful activation returns true and stores source kind/library/generation;
- newer activate beats older pending activate;
- factory `MediaLibraryFailure` produces `Failed` with the same safe failure;
- unknown factory exception maps to `sourceUnavailable` without exception text;
- `fail(failure)` increments generation and publishes Failed;
- releasing the last listener and rebuilding produces Inactive.

- [ ] **Step 2: Write failing resource-provider dispatch tests**

Cover:

- inactive/opening → `sourceUnavailable`;
- failed session rethrows its exact `MediaLibraryFailure`;
- asset request calls `resolveAsset` once;
- thumbnail request calls `resolveThumbnail` once;
- session reset/replacement invalidates a pending provider result and a fresh read uses the new library.

Use `container.read(mediaResourceProvider(request).future)` and controlled Completers; do not wait fixed durations.

- [ ] **Step 3: Run both files and confirm red**

```powershell
$Files = @(
  'test/features/media/application/media_library_session_controller_test.dart',
  'test/features/media/application/media_resource_provider_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task5-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 100 task5-red.log
```

- [ ] **Step 4: Implement session state and generation checks**

Use immutable state classes. `Active` contains `sourceKind`, `library`, and public `generation`; `Opening` and `Failed` also contain generation so tests and UI can distinguish fresh states.

```dart
sealed class MediaLibrarySessionState {
  const MediaLibrarySessionState();
}

final class MediaLibrarySessionInactive extends MediaLibrarySessionState {
  const MediaLibrarySessionInactive();
}

final class MediaLibrarySessionOpening extends MediaLibrarySessionState {
  const MediaLibrarySessionOpening(this.generation);
  final int generation;
}

final class MediaLibrarySessionActive extends MediaLibrarySessionState {
  const MediaLibrarySessionActive({
    required this.sourceKind,
    required this.library,
    required this.generation,
  });
  final MediaSourceKind sourceKind;
  final MediaLibrary library;
  final int generation;
}

final class MediaLibrarySessionFailed extends MediaLibrarySessionState {
  const MediaLibrarySessionFailed(this.generation, this.failure);
  final int generation;
  final MediaLibraryFailure failure;
}

final mediaLibrarySessionProvider = NotifierProvider<
  MediaLibrarySessionController,
  MediaLibrarySessionState
>(MediaLibrarySessionController.new, isAutoDispose: true);

class MediaLibrarySessionController extends Notifier<MediaLibrarySessionState> {
  int _generation = 0;

  @override
  MediaLibrarySessionState build() => const MediaLibrarySessionInactive();

  Future<bool> activate(MediaLibrarySource source) async {
    final generation = ++_generation;
    state = MediaLibrarySessionOpening(generation);
    try {
      final library = await ref.read(mediaLibraryFactoryProvider).open(source);
      if (!_isCurrent(generation)) return false;
      state = MediaLibrarySessionActive(
        sourceKind: source.kind,
        library: library,
        generation: generation,
      );
      return true;
    } on MediaLibraryFailure catch (failure) {
      if (_isCurrent(generation)) {
        state = MediaLibrarySessionFailed(generation, failure);
      }
      return false;
    } catch (_) {
      if (_isCurrent(generation)) {
        state = MediaLibrarySessionFailed(
          generation,
          const MediaLibraryFailure(
            MediaLibraryFailureCode.sourceUnavailable,
            '媒体来源不可用',
          ),
        );
      }
      return false;
    }
  }

  void fail(MediaLibraryFailure failure) {
    final generation = ++_generation;
    state = MediaLibrarySessionFailed(generation, failure);
  }

  void reset() {
    _generation++;
    state = const MediaLibrarySessionInactive();
  }

  bool _isCurrent(int generation) =>
      ref.mounted && generation == _generation;
}
```

- [ ] **Step 5: Implement the resource provider**

```dart
final mediaResourceProvider = FutureProvider.autoDispose.family<
  MediaResource?,
  MediaResourceRequest
>((ref, request) async {
  final session = ref.watch(mediaLibrarySessionProvider);
  if (session case MediaLibrarySessionFailed(:final failure)) throw failure;
  if (session is! MediaLibrarySessionActive) {
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.sourceUnavailable,
      '媒体会话不可用',
    );
  }
  return switch (request) {
    MediaAssetRequest() => session.library.resolveAsset(request),
    MediaThumbnailRequest() => session.library.resolveThumbnail(request),
  };
});
```

Do not catch and stringify library failures here.

- [ ] **Step 6: Bind the default factory without blocking test overrides**

Add `bool bindMediaLibraryFactory = true` to `appCompositionOverrides`. Add this override before feature controllers:

```dart
if (bindMediaLibraryFactory)
  mediaLibraryFactoryProvider.overrideWith(
    (ref) => DefaultMediaLibraryFactory(
      peerHttpClient: ref.watch(peerHttpClientProvider),
    ),
  ),
```

Thread the same named boolean through `pumpTestApp`, `pumpTestAppScope`, and `_buildTestScope`; when a test supplies `mediaLibraryFactoryProvider` in `extraOverrides`, it must call `bindMediaLibraryFactory: false`. Default remains true, so existing tests and production bootstrap need no call-site changes.

- [ ] **Step 7: Run session/provider tests and harness regressions**

```powershell
dart format lib/features/media/application/media_library_session_controller.dart lib/features/media/application/media_resource_provider.dart lib/app/composition/cross_feature_bindings.dart test/helpers/test_harness.dart test/features/media/application/media_library_session_controller_test.dart test/features/media/application/media_resource_provider_test.dart
$Files = @(
  'test/features/media/application/media_library_session_controller_test.dart',
  'test/features/media/application/media_resource_provider_test.dart',
  'test/integration/bootstrap_integration_test.dart',
  'test/app/router/app_router_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task5-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 120 task5-green.log
dart run tool/check_import_boundaries.dart
```

Expected: exit `0`; no duplicate Riverpod override error.

- [ ] **Step 8: Commit session infrastructure**

```powershell
git add lib/features/media/application/media_library_session_controller.dart lib/features/media/application/media_resource_provider.dart lib/app/composition/cross_feature_bindings.dart test/helpers/test_harness.dart test/features/media/application/media_library_session_controller_test.dart test/features/media/application/media_resource_provider_test.dart
git diff --cached --check
git commit -m "refactor(media): add active media library sessions"
git status --short
```

---

### Task 6: Migrate the Android media flow end-to-end onto the active library

**Files:**
- Modify: `lib/features/media/application/media_browser_controller.dart`
- Modify: `lib/features/media/application/shuffle_playback_controller.dart`
- Modify: `lib/features/media/domain/models/file_item.dart`
- Delete after all references are removed: `lib/features/media/domain/models/media_server_info.dart`
- Modify: `lib/features/media/presentation/media_browser_tab.dart`
- Modify: `lib/features/media/presentation/widgets/media_grid_view.dart`
- Modify: `lib/features/media/presentation/widgets/media_file_tile.dart`
- Create: `lib/features/media/presentation/widgets/media_image_resource_view.dart`
- Modify: `lib/features/media/presentation/pages/media_route_pages.dart`
- Modify: `lib/features/media/presentation/pages/image_viewer_page.dart`
- Create: `lib/features/media/presentation/pages/media_video_controller_factory.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `lib/features/media/presentation/pages/video_player_gesture.dart`
- Modify: `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`
- Modify: `lib/features/media/utils/path_utils.dart`
- Modify: `lib/app/composition/sync_workspace_screen.dart` (Android remote branch only; Windows enablement is Task 7)
- Modify: `test/features/media/helpers/media_test_helpers.dart`
- Modify: `test/features/media/application/media_browser_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_behavior_test.dart`
- Modify: `test/features/media/domain/models/file_item_test.dart`
- Create: `test/features/media/presentation/media_image_resource_view_test.dart`
- Create: `test/features/media/presentation/media_video_controller_factory_test.dart`
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`
- Modify: `test/features/media/presentation/media_route_pages_test.dart`
- Modify: `test/features/media/presentation/image_viewer_page_test.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`
- Modify: `test/features/media/presentation/shuffle_appbar_actions_test.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_test_helpers.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/features/media/utils/path_utils_test.dart`

**Interfaces:**
- Consumes: `MediaLibrary` port/resource values from Task 1 and active session/provider from Task 5. Only app composition reaches the concrete factory/data adapters; application and presentation do not consume `RemoteMediaLibrary` directly.
- Produces:
  - `MediaBrowserController.initFromActiveSession()` and session-safe directory operations;
  - shuffle methods returning relative paths, never URLs;
  - final transport-neutral `FileItem` with `hasThumbnail` and no JSON/endpoint members;
  - `MediaImageResourceView`;
  - `ImageViewerPage(imageRequests:, initialIndex:)`;
  - `MediaVideoControllerFactory` and `VideoPlayerPage(resource:, fileName:, controllerFactory:)`;
  - Android Sync media Tab activates `RemoteMediaLibrarySource`;
  - no remaining `MediaServerInfo` or media URL construction outside `RemoteMediaLibrary`/HTTP server adapters.

This is one vertical task because removing `MediaBrowserState.server` breaks thumbnail, image, video, shuffle, route and Sync composition simultaneously. Do not commit a temporary state where presentation derives authority from another field.

- [ ] **Step 1: Rewrite browser controller tests against an active fake library (red)**

Replace `createMediaTestContainer(httpClient:)` with a helper that overrides `mediaLibraryFactoryProvider` using `FakeMediaLibraryFactory`, activates a `RemoteMediaLibrarySource`, then calls `initFromActiveSession()`.

Put these exact helpers in `test/features/media/helpers/media_test_helpers.dart`. The helper retains every auto-dispose controller used by the application tests and owns teardown, so individual tests must not register duplicate disposal:

```dart
ProviderContainer createMediaLibraryTestContainer(FakeMediaLibrary library) {
  final container = ProviderContainer(
    overrides: [
      mediaLibraryFactoryProvider.overrideWithValue(
        FakeMediaLibraryFactory(library),
      ),
    ],
  );
  final sessionSubscription =
      container.listen(mediaLibrarySessionProvider, (_, _) {});
  final browserSubscription =
      container.listen(mediaBrowserControllerProvider, (_, _) {});
  final shuffleSubscription =
      container.listen(shufflePlaybackControllerProvider, (_, _) {});
  addTearDown(() {
    sessionSubscription.close();
    browserSubscription.close();
    shuffleSubscription.close();
    container.dispose();
  });
  return container;
}

Future<void> activateTestMediaSession(ProviderContainer container) async {
  final activated = await container
      .read(mediaLibrarySessionProvider.notifier)
      .activate(
        RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
      );
  expect(activated, isTrue);
  expect(
    container.read(mediaLibrarySessionProvider),
    isA<MediaLibrarySessionActive>(),
  );
}
```

The browser tests must cover:

```dart
test('active session loads root and never exposes server state', () async {
  const image = FileItem(
    name: '猫.jpg',
    isDirectory: false,
    sizeBytes: 1,
    relativePath: '/猫.jpg',
    hasThumbnail: true,
  );
  final library = FakeMediaLibrary()
    ..directoryResults['/'] = [image];
  final container = createMediaLibraryTestContainer(library);
  await activateTestMediaSession(container);
  await container
      .read(mediaBrowserControllerProvider.notifier)
      .initFromActiveSession();
  final state = container.read(mediaBrowserControllerProvider);
  expect(state.items, [image]);
  expect(library.listDirectoryCalls, ['/']);
});
```

Keep existing behavior tests for history, failed navigation, root back, reset, auto-dispose, and stale request. Add a new stale-session case: session A has a pending list; activate session B and complete A; A must not update browser state.

Expected red: `initFromActiveSession` does not exist and old state still requires server.

- [ ] **Step 2: Rewrite shuffle tests against an active fake library (red)**

Keep state behavior, but replace HTTP setup and URL expectations:

```dart
test('startShuffle loads videos and returns first relative path', () async {
  final library = FakeMediaLibrary()
    ..recursiveVideoResults['/视频'] = const [
      VideoItem(name: 'only.mp4', relativePath: '/视频/only.mp4'),
    ];
  final container = createMediaLibraryTestContainer(library);
  await activateTestMediaSession(container);
  final path = await container
      .read(shufflePlaybackControllerProvider.notifier)
      .startShuffle('/视频');
  expect(path, '/视频/only.mp4');
  expect(library.listVideosRecursivelyCalls, ['/视频']);
});
```

Change `playNext`/`playPrevious` expectations from media URL to the selected `relativePath`. Delete all `buildVideoUrl` tests. Add session replacement/reset stale-list tests.

- [ ] **Step 3: Implement session-safe MediaBrowserController**

Remove `dart:convert`, `package:http`, `peerHttpClientProvider`, `path_utils`, DTO, and `MediaServerInfo` imports. Remove `server` from state constructor/copyWith/props.

Use this capture pattern for every request:

```dart
Future<bool> initFromActiveSession() async {
  final session = ref.read(mediaLibrarySessionProvider);
  if (session is! MediaLibrarySessionActive) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: '媒体会话不可用',
    );
    return false;
  }
  _sessionGeneration = session.generation;
  final operation = ++_operationGeneration;
  state = MediaBrowserState();
  return _loadDirectory('/', session, operation);
}

bool _isCurrent(
  MediaLibrarySessionActive captured,
  int operation,
) {
  final current = ref.read(mediaLibrarySessionProvider);
  return ref.mounted &&
      operation == _operationGeneration &&
      current is MediaLibrarySessionActive &&
      current.generation == captured.generation &&
      captured.generation == _sessionGeneration;
}
```

`_loadDirectory` calls `captured.library.listDirectory(path)`, catches only `MediaLibraryFailure`, and publishes `failure.message`. Unknown exceptions become fixed `加载媒体目录失败`, never `$e`. Preserve “success before history mutation” semantics. `reset` increments operation generation and returns exactly `MediaBrowserState()`.

- [ ] **Step 4: Implement session-safe ShufflePlaybackController**

Remove `dart:convert`, `package:http`, `peerHttpClientProvider`, path utils and browser-server coupling. Keep injected/random behavior already used by tests.

Signatures become:

```dart
Future<String?> startShuffle(String directoryPath);
String? playNext();
String? playPrevious();
```

`startShuffle` captures active session + operation generation, calls `listVideosRecursively`, shuffles only when length is at least two, publishes `Active`, and returns `list.first.relativePath`. On typed/unknown failure it returns Idle/null with no raw error. `playNext/Previous` return the new current video's relative path. Delete `buildVideoUrl` completely.

- [ ] **Step 5: Write and run failing image-resource adapter tests**

Create `media_image_resource_view_test.dart`:

```dart
testWidgets('local resource uses FileImage and network resource uses NetworkImage headers',
    (tester) async {
  final dir = await Directory.systemTemp.createTemp('omll_image_view_');
  addTearDown(() => dir.delete(recursive: true));
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
    'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  final file = File('${dir.path}${Platform.pathSeparator}a.jpg')
    ..writeAsBytesSync(pngBytes);

  await tester.pumpWidget(MaterialApp(home: MediaImageResourceView(
    resource: LocalMediaResource(file.absolute.uri),
    fit: BoxFit.contain,
  )));
  expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());

  await tester.pumpWidget(MaterialApp(home: MediaImageResourceView(
    resource: NetworkMediaResource(
      Uri.parse('http://peer/api/media/image/a.jpg'),
      headers: const {'X-Peer': 'token'},
    ),
    fit: BoxFit.contain,
  )));
  final provider = tester.widget<Image>(find.byType(Image)).image as NetworkImage;
  expect(provider.headers, {'X-Peer': 'token'});
});
```

Import `dart:convert` for `base64Decode`; do not depend on network or repo assets. Run the single file and confirm compile red.

- [ ] **Step 6: Implement MediaImageResourceView and thumbnail tiles**

`MediaImageResourceView` accepts `resource`, `fit`, optional width/height, an `ImageErrorWidgetBuilder`, and optional loading widget. Its switch is exhaustive:

```dart
return switch (resource) {
  LocalMediaResource() => Image.file(
      File.fromUri(resource.uri),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
      frameBuilder: _frameBuilder,
    ),
  NetworkMediaResource() => Image.network(
      resource.uri.toString(),
      headers: resource.headers,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
      loadingBuilder: _loadingBuilder,
    ),
};
```

Define the two builders in the same widget; both share the caller-supplied loading widget and never replace a completed child:

```dart
Widget _loading(BuildContext context) =>
    loading ?? const Center(child: CircularProgressIndicator(strokeWidth: 2));

Widget _frameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) => wasSynchronouslyLoaded || frame != null ? child : _loading(context);

Widget _loadingBuilder(
  BuildContext context,
  Widget child,
  ImageChunkEvent? progress,
) => progress == null ? child : _loading(context);
```

Change `MediaFileTile` to `ConsumerWidget`. For media files, build a `MediaThumbnailRequest` from all four fields and watch `mediaResourceProvider`. Loading shows the existing 2px spinner; null/error shows `_fallbackIcon`; data uses `MediaImageResourceView`. Remove `thumbnailBaseUrl` from tile and grid constructors.

Run the adapter test plus media browser navigation smoke after this step.

- [ ] **Step 7: Write failing video-controller factory tests**

Create `media_video_controller_factory_test.dart`:

```dart
test('local uses file data source and remote preserves headers', () {
  final local = createMediaVideoController(
    LocalMediaResource(Uri.file(r'D:\Media\demo.mp4', windows: true)),
  );
  expect(local.dataSourceType.name, 'file');
  expect(local.dataSource, contains('demo.mp4'));

  final remote = createMediaVideoController(NetworkMediaResource(
    Uri.parse('http://peer/api/media/video/demo.mp4'),
    headers: const {'X-Peer': 'token'},
  ));
  expect(remote.dataSourceType.name, 'network');
  expect(remote.httpHeaders, {'X-Peer': 'token'});
});
```

Do not call `initialize`; this is a pure constructor-selection test and must not touch platform channels. Run and confirm compile red.

- [ ] **Step 8: Implement the narrow video factory and make retry use it once**

Create:

```dart
typedef MediaVideoControllerFactory =
    VideoPlayerController Function(MediaResource resource);

VideoPlayerController createMediaVideoController(MediaResource resource) =>
    switch (resource) {
      LocalMediaResource() =>
        VideoPlayerController.file(File.fromUri(resource.uri)),
      NetworkMediaResource() => VideoPlayerController.networkUrl(
          resource.uri,
          httpHeaders: resource.headers,
        ),
    };
```

Change `VideoPlayerPage` fields to:

```dart
final MediaResource resource;
final String fileName;
final MediaVideoControllerFactory controllerFactory;
```

Use this constructor so tests can inject a controller without touching platform channels:

```dart
const VideoPlayerPage({
  super.key,
  required this.resource,
  required this.fileName,
  this.controllerFactory = createMediaVideoController,
});
```

Add one `_initPlayer()` method used by both `initState` and Retry:

```dart
void _initPlayer() {
  _gesture.initPlayer(() => widget.controllerFactory(widget.resource));
}
```

Change `VideoPlayerGestureController.initPlayer` to accept `VideoPlayerController Function()` and create the controller by calling `factory()`. No URI remains in gesture/state code.

Update all existing video tests to pass `NetworkMediaResource(Uri.parse('http://localhost/test.mp4'))` and factories shaped `(resource) => fakeController`. Add an assertion to the retry test that the same resource reaches the factory twice.

- [ ] **Step 9: Migrate image and video route pages to lazy resources**

`MediaImageRoutePage`:

1. normalize/query validate as today;
2. require `MediaLibrarySessionActive`, otherwise recovery page;
3. map current directory images to `MediaAssetRequest(kind: image, relativePath: ...)`;
4. if target exists, pass the list and target index;
5. otherwise pass a one-item list for the direct link.

`ImageViewerPage` constructor becomes:

```dart
ImageViewerPage({
  super.key,
  required this.imageRequests,
  this.initialIndex = 0,
});
final List<MediaAssetRequest> imageRequests;
```

`_ZoomableImagePage` becomes `ConsumerStatefulWidget` and watches `mediaResourceProvider(widget.request)`. Loading renders a white progress indicator; `MediaResource` renders `MediaImageResourceView`; null/failure renders the existing broken-image state. Reset zoom/error state when `request` changes, not when a URL changes.

`MediaVideoRoutePage` accepts an optional `MediaVideoControllerFactory? controllerFactory` test seam and watches `mediaResourceProvider(MediaAssetRequest(kind: video, ...))`:

- loading → page-level progress scaffold;
- typed error/null → `MediaRouteRecoveryPage` with safe reason;
- data → `VideoPlayerPage(resource: resource, fileName: ..., controllerFactory: controllerFactory ?? createMediaVideoController)`.

Generalize recovery copy to `媒体会话已失效，请返回同步页重新打开媒体浏览器。` and button `返回同步页` while preserving pop-or-go behavior.

- [ ] **Step 10: Migrate MediaBrowserTab and shuffle navigation**

`MediaBrowserTab` watches both browser and session state:

- Opening → centered progress;
- Failed → `AppEmptyState` with `failure.message` and action calling `onExitMediaBrowser`;
- Inactive → `AppEmptyState(title: '媒体会话不可用', ...)`;
- Active → path bar + grid.

Remove server/base URL logic. A media file tap only requires active session; then route by relative path. Directory navigation remains controller-only.

`ShuffleAppBarActions` treats the non-null return from start/next/previous as a relative path and passes it directly to the existing named route. It must never call a resource resolver itself.

- [ ] **Step 11: Migrate Android Sync composition without enabling Windows yet**

Keep `_hasMediaTab => defaultTargetPlatform == TargetPlatform.android` in this task. Replace `_initMediaSession` with an async remote activation:

```dart
Future<void> _initMediaSession() async {
  if (!mounted || !_hasMediaTab || _tabController.index != 2) return;
  final server = ref.read(syncClientControllerProvider).server;
  if (server == null) {
    ref.read(mediaLibrarySessionProvider.notifier).fail(
      const MediaLibraryFailure(
        MediaLibraryFailureCode.sourceUnavailable,
        '未连接到服务端',
      ),
    );
    return;
  }
  final activated = await ref
      .read(mediaLibrarySessionProvider.notifier)
      .activate(RemoteMediaLibrarySource(Uri(
        scheme: 'http',
        host: server.ip,
        port: server.httpPort,
      )));
  if (!mounted || _tabController.index != 2 || !activated) return;
  await ref
      .read(mediaBrowserControllerProvider.notifier)
      .initFromActiveSession();
}
```

On leaving media: reset session first, then browser, then shuffle. AppBar actions are visible only when current tab is media and session is Active.

- [ ] **Step 12: Remove obsolete transport types/helpers and migrate the enumerated test files**

After all references compile:

- remove `dart:convert`, `thumbnailUrl`, `toJson`, `fromJson`, and `listFromJson` from `file_item.dart`; its final constructor is the Task 2 constructor without `thumbnailUrl`;
- delete the legacy wire cases from `file_item_test.dart`; keep domain defaults, equality-independent model behavior, formatted-size and `hasThumbnail` cases. `media_file_item_dto_test.dart` remains the sole file-list wire contract test;
- delete `media_server_info.dart` with `apply_patch`;
- remove `encodeMediaPath` and `buildMediaResourceUrl` from `path_utils.dart` because only `RemoteMediaLibrary` owns URL paths; retain `normalizeMediaRoutePath`;
- replace `testServer` with a `RemoteMediaLibrarySource`/fake active session helper;
- update fake controller overrides from `initWithServer` to `initFromActiveSession`;
- update all `MediaBrowserState(server:)` constructors;
- update route/video factory signatures from `(Uri)` to `(MediaResource)`;
- update image viewer tests from fake URLs to `MediaAssetRequest` plus fake library asset results;
- update Android sync tests to assert active remote source/factory call, not `browser.state.server`.

Run this audit:

```powershell
rg -n "MediaServerInfo|initWithServer|thumbnailBaseUrl|buildMediaResourceUrl|encodeMediaPath|videoUrl|imageUrls|state\.server|server:" lib/features/media lib/app/composition test/features/media test/features/sync/sync_screen
rg -n "FileItem\.(listFromJson|fromJson)|\.thumbnailUrl|thumbnailUrl:" lib/features/media test/features/media
```

Expected: no obsolete production references; `thumbnailUrl` remains only inside `MediaFileItemDto`, its data-layer tests, and HTTP protocol assertions. Test fixture text may contain `http://localhost` only inside explicit `NetworkMediaResource` construction.

- [ ] **Step 13: Run the full media + Sync screen + router targeted suite**

```powershell
$Files = @(
  'test/features/media',
  'test/features/sync/sync_screen_test.dart',
  'test/app/router/app_router_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 task6-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 task6-green.log
dart run tool/check_import_boundaries.dart
flutter analyze --no-pub
```

Expected: targeted exit `0`, import gate `0`, analyze `0`. If video tests fail because a platform controller initialized, the test failed to inject `FakeVideoPlayerController`; fix the test seam rather than adding timing waits.

- [ ] **Step 14: Perform the trust-boundary audit**

```powershell
rg -n "package:http|peerHttpClientProvider|/api/media/|http://|https://" lib/features/media/application lib/features/media/presentation
rg -n "dart:io|video_player|Platform|TargetPlatform" lib/features/media/application lib/features/media/presentation
```

Expected:

- no HTTP or `/api/media/` references in application/presentation;
- application has no `dart:io`, `video_player`, `Platform`, or `TargetPlatform`;
- presentation `dart:io`/`video_player` appears only in `media_image_resource_view.dart`, video controller factory, and existing player implementation;
- no platform selection in media presentation.

- [ ] **Step 15: Format and commit the Android vertical migration**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
git add lib/features/media lib/app/composition/sync_workspace_screen.dart test/features/media test/features/sync/sync_screen test/app/router/app_router_test.dart
git diff --cached --check
git commit -m "refactor(media): route Android media through library sessions"
git status --short
```

Expected: commit is reviewable as one vertical transport migration; Android media behavior remains green; Windows media is still hidden until Task 7.

---

### Task 7: Enable the Windows local media Tab and validate runtime playback

**Files:**
- Modify: `lib/app/composition/sync_workspace_screen.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_test_helpers.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`
- Verify only: `test/features/media/presentation/media_browser_navigation_test.dart` (Task 6 already owns its final resource/session assertions)

**Interfaces:**
- Consumes: `LocalMediaLibrarySource`, persisted root provider, active session, local image/video adapters, registered `video_player_win`.
- Produces: Windows third media Tab using direct local filesystem; no peer/server requirement; missing-root recovery; local session reset/re-entry.

- [ ] **Step 1: Write failing Windows platform selection tests**

Add test helpers that always set/reset `debugDefaultTargetPlatformOverride` inside the test body and tearDown. Add:

```dart
testWidgets('Windows shows media tab and missing root returns to Connection',
    (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await pumpSyncScreen(tester, preferences: preferences);

  await tester.tap(find.descendant(
    of: find.byType(TabBar),
    matching: find.text('媒体'),
  ));
  await settleTabTransition(tester);
  expect(find.text('尚未配置媒体根目录'), findsOneWidget);
  expect(find.text('返回连接'), findsOneWidget);
  debugDefaultTargetPlatformOverride = null;
});
```

Expected red: Windows currently has only two tabs.

- [ ] **Step 2: Write failing Windows local-source and lifecycle tests**

Seed the preference with `SharedPreferences.setMockInitialValues({mediaRootDirectoryStorageKey: r'D:\Media'});`, obtain it through `SharedPreferences.getInstance()`, override `mediaLibraryFactoryProvider` with `FakeMediaLibraryFactory`, and call the harness with `bindMediaLibraryFactory: false`.

Assert:

- entering media opens exactly `LocalMediaLibrarySource(r'D:\Media')`;
- browser loads `/` from fake local library without a Sync client server;
- AppBar shuffle action becomes visible only after Active;
- leaving media publishes Inactive and resets browser/shuffle;
- re-entering opens a fresh local session and loads root again;
- changing the preference while the media session is active does not change the active source; only leave/re-enter picks up the new root.

Add an Android preservation case asserting Android still opens a `RemoteMediaLibrarySource` from `connectedSyncState()`.

- [ ] **Step 3: Enable Windows using one app-composition platform decision**

In `SyncWorkspaceScreen`, define:

```dart
bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
bool get _hasMediaTab => _isAndroid || _isWindows;
```

Remove `dart:io show Platform` from this widget. Use `_isWindows` for the root-directory configuration section.

Source selection inside `_initMediaSession`:

```dart
MediaLibrarySource? _mediaSource() {
  if (_isWindows) {
    final root = ref.read(mediaRootDirectoryProvider)?.trim();
    if (root == null || root.isEmpty) return null;
    return LocalMediaLibrarySource(root);
  }
  if (_isAndroid) {
    final server = ref.read(syncClientControllerProvider).server;
    if (server == null) return null;
    return RemoteMediaLibrarySource(Uri(
      scheme: 'http',
      host: server.ip,
      port: server.httpPort,
    ));
  }
  return null;
}
```

When source is null, publish the platform-specific safe failure:

- Windows: `尚未配置媒体根目录`;
- Android: `未连接到服务端`.

Do not make local browsing conditional on `syncServerControllerProvider.isRunning`.

- [ ] **Step 4: Run Windows/Android composition tests**

```powershell
dart format lib/app/composition/sync_workspace_screen.dart test/features/sync/sync_screen
flutter test test/features/sync/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task7-sync.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 task7-sync.log
```

Expected: exit `0`; every test resets `debugDefaultTargetPlatformOverride` before its body finishes.

- [ ] **Step 5: Prove local composition does not require peer HTTP**

Run the `DefaultMediaLibraryFactory` test that opens a local source with a `MockClient` whose callback throws `StateError('local source used peer HTTP')`. Then run a Windows Sync widget test with the same local source and fake library.

Expected:

- factory local open and local list succeed;
- peer callback count remains zero;
- no Sync server is started;
- no localhost URI appears in application/browser state.

- [ ] **Step 6: Rebuild Windows with the completed local path**

```powershell
flutter build windows --debug
flutter build windows --release
```

Expected: both exit `0`. If native player linking now fails, apply Task 0 stop conditions; do not replace the package in this task.

- [ ] **Step 7: Execute the mandatory Windows manual smoke**

Start the real app:

```powershell
flutter run -d windows
```

In the visible app, perform and record all results before claiming completion:

1. Connection Tab chooses the actual media root;
2. media Tab opens root without starting Sync server;
3. enter nested Chinese/space directories and use path chips/back;
4. open at least two real images, swipe, double-click zoom, pan, and return;
5. open a real H.264/AAC MP4 under a Chinese path;
6. play, pause, seek, volume, speed, completion, retry, and close;
7. use shuffle, previous, next, and final exit;
8. switch away and back; root session rebuilds;
9. temporarily rename/remove a disposable test file outside the app, then confirm controlled not-found UI;
10. close player/app without a native crash.

Do not rename/delete any user file from within the app; use only a disposable test copy for step 9.

Runtime stop conditions:

- reproducible native crash during initialize/dispose/switch;
- Chinese path cannot play;
- user's primary codec fails without installing an external codec pack;
- seek/volume/speed/completion contract is broken.

If any stop condition occurs, keep the media-library work, mark Windows video blocked with exact evidence, and request a separately scoped `media_kit` decision. Do not claim the feature complete.

- [ ] **Step 8: Commit Windows enablement only after automated gates**

If automated tests/builds pass, commit the code even if manual smoke is pending, but label the task status pending in the handoff. If manual smoke fails, include the failure evidence and do not mark the overall plan complete.

```powershell
git add lib/app/composition/sync_workspace_screen.dart test/features/sync/sync_screen
git diff --cached --check
git commit -m "feat(media): enable local media browsing on Windows"
git status --short
```

---

### Task 8: Update product documentation and run final gates

**Files:**
- Modify: `README.md:177-190,239-245,321`
- Modify: `docs/视频局域网广播-prd.md:19-35,38-56,286-296,891-909,1000-1047`
- Verify only: `docs/superpowers/specs/2026-08-11-cross-platform-media-library-design.md`
- Verify only: `AGENTS.md`

**Interfaces:**
- Consumes: completed behavior and actual Windows smoke evidence from Tasks 0-7.
- Produces: current platform documentation, complete automated verification evidence, scope audit, and an honest manual-smoke status.

- [ ] **Step 1: Update README without overstating runtime support**

Change the Sync description to state:

```markdown
Windows 与 Android 均提供连接、同步和媒体 Tab：Windows 直接浏览已配置的本地媒体根目录；Android 通过已配对的局域网 peer 浏览同一逻辑根目录。
```

The media section must state directory/image/video/shuffle capabilities and the actual Windows video formats validated in Task 7. If manual smoke is pending, write only that Windows local browsing support is implemented; do not claim real video playback validation.

- [ ] **Step 2: Update the original media PRD as an explicit extension**

Preserve the original Windows-server/Android-client history, then add a dated extension section containing these fixed decisions:

- Windows also exposes the same media Tab;
- Windows source is the existing configured root;
- Windows uses direct file APIs, Android uses peer HTTP;
- routes stay under `/sync` and contain only relative paths;
- no arbitrary disk browser, file writes, localhost loopback, protocol change, codec installation, or media-kit migration.

Do not rewrite old phase history as if Windows local browsing had always existed.

- [ ] **Step 3: Run formatting and static architecture checks**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
if ($DartFiles) {
  dart format $DartFiles
  dart format --output=none --set-exit-if-changed $DartFiles
}
dart run tool/check_import_boundaries.dart
flutter analyze --no-pub
```

Expected: all exit `0`.

- [ ] **Step 4: Run the complete targeted suite**

```powershell
$Files = @(
  'test/features/media',
  'test/features/sync/sync_screen_test.dart',
  'test/app/router/app_router_test.dart',
  'test/integration/bootstrap_integration_test.dart',
  'test/architecture/import_boundary_checker_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 media-final.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 media-final.log
```

Expected: `EXIT=0`. Diagnose any failure from `media-final.log`; do not proceed on a truncated console summary.

- [ ] **Step 5: Run the full test suite**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 fltest.log
```

Expected: `EXIT=0`. If startup stalls before tests begin, run `./scripts/kill-stale-test-processes.ps1` and retry once. If failures remain, use:

```powershell
Select-String -Pattern " -[1-9]" -Path fltest.log
```

Fix only failures caused by this change. Stop and report unrelated baseline failures instead of expanding scope.

- [ ] **Step 6: Run final Windows builds**

```powershell
flutter build windows --debug
flutter build windows --release
```

Expected: both exit `0` after the final source tree, not merely after Task 0.

- [ ] **Step 7: Execute the final scope and security audit**

Run:

```powershell
rg -n "package:http|peerHttpClientProvider|/api/media/|http://|https://" lib/features/media/application lib/features/media/presentation
rg -n "Platform|TargetPlatform" lib/features/media/application lib/features/media/presentation
rg -n "MediaServerInfo|thumbnailUrl|buildMediaResourceUrl|encodeMediaPath|initWithServer" lib test
rg -n "AppDestination\.media|path: '/media'" lib/features/media lib/app
git diff 9ae0fe4 --unified=0 -- lib/features/media | Select-String -Pattern '^\+.*(delete\(|rename\(|writeAs)'
git diff --check HEAD
git status --short
```

Expected interpretation:

- HTTP/API references are confined to data/HTTP server code and explicit network test fixtures;
- media application/presentation has no platform backend selection;
- `thumbnailUrl` remains only in DTO/protocol tests/docs;
- no `MediaServerInfo`, URL builder, or old init method remains;
- no top-level media destination or new file-write product API exists;
- working tree contains only the planned documentation changes before the docs commit.

- [ ] **Step 8: Commit documentation**

```powershell
git add README.md docs/视频局域网广播-prd.md
git diff --cached --check
git commit -m "docs(media): document Windows local media browsing"
git status --short
```

Expected: clean status after version amend.

- [ ] **Step 9: Final completion gate**

The implementer must report a checklist with evidence for every item:

- dependency dry-run/build gate passed;
- Android remote targeted tests passed;
- Windows local factory used zero peer HTTP calls;
- route audit found no absolute path/authority;
- path traversal/symlink tests passed;
- thumbnail failures remained tile-local;
- local/network image and video factory tests passed;
- import boundary, analyze, targeted suite, full suite, Debug build, Release build passed;
- manual Windows smoke passed, failed with evidence, or is explicitly pending;
- final commit hashes and post-hook version;
- clean worktree.

Overall status can be **complete** only when manual smoke passed. If it is pending, status is **implemented and automated gates passed; manual Windows smoke pending**. If a player stop condition occurred, status is **media library implemented; Windows video blocked**, and no automatic next-player migration begins.

---

## 2. Failure Diagnosis Index

| Symptom | Likely cause | Required action |
|---|---|---|
| `video_player_win` dependency conflict | platform interface/Flutter incompatibility | stop Task 0; record resolver output; do not select another plugin |
| Windows CMake/MSBuild native error | plugin registration/toolchain/cache | inspect first native error; clean/retry once; repeat means gate failure |
| Riverpod duplicate override | production factory and test fake both bound | set `bindMediaLibraryFactory: false` in that harness call |
| browser old result appears after source switch | only operation generation checked | also compare active session generation before every state write |
| thumbnail failure blanks whole grid | error propagated into browser state | keep failure inside tile-level resource provider and render fallback icon |
| local browse calls peer client | factory/source branch leakage | reproduce with fail-on-call MockClient; local library must have no client field/import |
| remote path changes host/port | URL string concatenation or untrusted URI parse | construct with trusted base `replace(pathSegments:)`; reject route authority |
| image test hangs/requests network | fake session lacks asset result or adapter not injected | return deterministic local resource/fake network failure; do not add delay |
| video test invokes platform channel | default controller factory used in Widget test | inject `FakeVideoPlayerController` through resource-shaped factory |
| retry switches local video to network | retry reconstructs `networkUrl` directly | call the same `_initPlayer` and `controllerFactory(resource)` as initState |
| Windows media tab opens remote session | platform/source selection mixed in media feature | source selection belongs only in `SyncWorkspaceScreen` app composition |
| full test suite stalls at startup | stale sqlite native-assets process | run `./scripts/kill-stale-test-processes.ps1`, retry once |
| manual media format fails | Windows Media Foundation codec limitation | apply runtime stop condition; do not install codec or migrate player implicitly |

## 3. Acceptance Criteria

1. Windows and Android both expose the third media Tab under `/sync`.
2. Windows reads the persisted root directly with `LocalMediaLibrary`; local unit/composition tests prove zero peer HTTP calls.
3. Android uses `RemoteMediaLibrary` with authority derived only from `SyncClientState.server`.
4. `MediaBrowserController`, `ShufflePlaybackController`, routes, tiles and viewers do not import `package:http` or build `/api/media` URLs.
5. `FileItem` contains `hasThumbnail` and no HTTP JSON methods/endpoint fields; wire JSON remains compatible through `MediaFileItemDto`.
6. All five operations—list, recursive videos, thumbnail, image, video—flow through `MediaLibrary`.
7. route query contains only normalized relative path; no local absolute path or remote authority is persisted/logged.
8. local path traversal and root-outside symlinks are rejected by shared scanner protections.
9. session and operation generations prevent old factory/list/video-list/resource results from restoring stale state.
10. thumbnail generation/network failure affects only its tile.
11. local image uses file provider; remote image uses network provider with headers.
12. local video uses `VideoPlayerController.file`; remote video uses `networkUrl`; retry uses the same factory/resource.
13. leaving the media Tab invalidates session first, then resets browser and shuffle; child image/video routes keep session alive.
14. missing Windows root and missing Android server show safe, actionable states.
15. existing media HTTP handlers and Range behavior remain green.
16. import gate, analyze, targeted tests, full tests, Windows Debug and Release builds pass.
17. manual Windows smoke is recorded honestly; completion is not claimed while pending.

## 4. Final Scope Audit

Before handoff, compare the complete diff with the approved spec and answer each question explicitly:

- Did any change add a top-level media destination? It must be no.
- Did any local path use localhost/peer HTTP? It must be no.
- Did any route, persisted object, or regular log gain an absolute path/authority? It must be no.
- Did any production API add file deletion/move/rename/write? It must be no.
- Did the HTTP wire shape or Range behavior change? It must be no.
- Did the work add Linux/macOS/iOS, HLS, transcoding, download, codec installation, or `media_kit`? It must be no.
- Did the work create a second media-root truth or persist session/browser state? It must be no.
- Are all new data implementations behind application-owned ports and bound only in app composition? It must be yes.
- Are manual runtime results distinguished from automated evidence? It must be yes.

Any unexpected “yes” to a prohibited item is a scope violation: stop, revert the out-of-scope portion with a recoverable targeted edit, rerun the affected task gates, and report it before continuing.
