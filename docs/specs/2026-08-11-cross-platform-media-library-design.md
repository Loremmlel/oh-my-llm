# Windows 与 Android 统一媒体库访问设计

**日期：** 2026-08-11

**状态：** 已批准，待实现计划

**范围：** Windows 本地媒体浏览 + Android 局域网媒体浏览的统一访问边界

## 1. 背景

当前媒体浏览器只在 Android 的同步页面中显示。Android 从已连接的 Windows 同步服务端读取目录、缩略图、图片和视频；Windows 只负责配置媒体根目录并通过 HTTP 暴露资源，自身不能使用媒体浏览器。

现有实现把远端访问假设分散在多个位置：

- `MediaBrowserController` 直接发起目录列表 HTTP 请求并持有 `MediaServerInfo`；
- `ShufflePlaybackController` 直接请求递归视频接口并构造视频 URL；
- `MediaBrowserTab` 和 `MediaFileTile` 拼接缩略图服务端 URL；
- `MediaImageRoutePage` 和 `MediaVideoRoutePage` 根据服务端地址构造资源 URL；
- `ImageViewerPage` 固定使用 `Image.network`；
- `VideoPlayerPage` 固定使用 `VideoPlayerController.networkUrl`。

与此同时，Windows 服务端已有 `MediaDirectoryScanner`、`MediaThumbnailGenerator` 和 `MediaThumbnailCache`，已经覆盖根目录约束、路径穿越防护、目录排序、缩略图生成与缓存。本次应复用这些本地能力，而不是在 Windows 内部建立 HTTP 回环访问。

## 2. 已确认的产品决定

1. Windows 和 Android 都继续在同步页面的第三个“媒体”Tab 中使用媒体浏览器。
2. 不新增一级“媒体”导航入口；图片和视频仍是 `/sync` 的子路由。
3. Windows 使用连接 Tab 中已经配置的媒体根目录作为唯一逻辑根目录。
4. Windows 不提供任意磁盘浏览器；用户必须先在连接 Tab 选择根目录。
5. Windows 直接访问本地文件系统，不通过 localhost、HTTP Server 或局域网请求访问自身资源。
6. Android 继续通过当前可信同步会话访问 Windows 服务端。
7. 两个平台共享同一套浏览 controller、随机播放 controller、路由和浏览 UI。
8. 当前媒体 HTTP API 保持兼容，不因 Windows 本地访问而修改协议。

## 3. 目标与非目标

### 3.1 目标

- 将媒体浏览用例与 HTTP、本地文件系统解耦；
- 让 Windows 使用本地媒体库实现，让 Android 使用远端媒体库实现；
- 保持现有相对路径、导航历史、画廊顺序、随机播放和路由语义；
- 保持路径穿越与可信服务端 authority 的安全边界；
- 让缩略图、图片和视频以统一的资源值对象进入 presentation；
- 在不重写现有播放器 UI 的前提下支持 Windows 本地视频播放；
- 为本地/远端实现提供独立、确定性的自动化测试。

### 3.2 非目标

- 任意磁盘文件管理器；
- 删除、移动、重命名、复制或写入媒体文件；
- 新增一级媒体导航；
- Linux、macOS 或 iOS 媒体浏览；
- 修改 Sync/Media HTTP 协议；
- HLS、转码、远程下载或离线同步；
- 持久化浏览路径、播放列表或活动媒体会话；
- 自动安装 Windows codec；
- 在本阶段抽象一套完整的播放器引擎接口；
- `video_player_win` 验证失败后自动扩大为 `media_kit` 迁移。

## 4. 方案比较与结论

### 4.1 Windows 通过 localhost 复用 HTTP

优点是 Android 客户端链路几乎不变。缺点是 Windows 明明能够直接读文件，却仍需承担 HTTP Server、端口、Range、会话和错误映射；本地浏览还会错误依赖同步服务是否启动。该方案不采用。

### 4.2 分别抽象 FileService、ImageService 和 VideoService

该方案按内容类型拆分直观，但目录扫描、根目录安全、资源定位、缩略图和随机播放会跨越多个服务。本地/远端判断也容易在三个接口与 UI 中重复。该方案不采用。

### 4.3 统一 MediaLibrary 端口，两种数据适配器

该方案按“媒体库从哪里读取”建立边界：application 只表达目录、递归视频和资源解析能力，data 提供本地与远端实现。它与仓库既有 `presentation -> application <- data` 结构一致，并能把平台判断限制在 app composition。该方案为批准方案。

## 5. 总体架构

```text
SyncWorkspaceScreen (app composition)
             │ creates trusted source
             ▼
MediaLibrarySessionController
             │ owns active session + generation
             ▼
MediaBrowserController / ShufflePlaybackController / mediaResourceProvider
             │
             ▼
        MediaLibrary
        ┌─────┴─────┐
        │           │
LocalMediaLibrary  RemoteMediaLibrary
Windows dart:io    Android peer HTTP
```

平台选择只允许发生在 app composition：

- Windows 从 `mediaRootDirectoryProvider` 创建本地 source；
- Android 从当前可信 `SyncClientState.server` 创建远端 source；
- media application 和 presentation 不出现 `Platform.isWindows`、`TargetPlatform.android` 或等价平台分支。

## 6. Application 契约

### 6.1 文件组织

```text
lib/features/media/application/
├── models/
│   ├── media_library_source.dart
│   ├── media_library_failure.dart
│   ├── media_resource.dart
│   └── media_resource_request.dart
├── ports/
│   ├── media_library.dart
│   └── media_library_factory.dart
├── media_library_session_controller.dart
└── media_resource_provider.dart
```

### 6.2 MediaLibrarySource

`MediaLibrarySource` 是 sealed value，用于把 app composition 已验证的访问来源传给 factory：

```dart
sealed class MediaLibrarySource {
  const MediaLibrarySource();
}

final class LocalMediaLibrarySource extends MediaLibrarySource {
  const LocalMediaLibrarySource(this.rootDirectory);
  final String rootDirectory;
}

final class RemoteMediaLibrarySource extends MediaLibrarySource {
  const RemoteMediaLibrarySource(this.baseUri);
  final Uri baseUri;
}

enum MediaSourceKind { local, remote }
```

约束：

- source 只能由 app composition 根据受信设置或同步会话创建；
- GoRouter query 不能创建或覆盖 source；
- source 不持久化为另一份配置；
- local source 的根目录在一次媒体会话内不可变；
- remote source 的 authority 在一次媒体会话内不可变。

### 6.3 MediaResource

资源使用 sealed value 表达本地文件与网络资源，避免把 Flutter 或播放器类型引入 application：

```dart
sealed class MediaResource {
  const MediaResource();
  Uri get uri;
}

final class LocalMediaResource extends MediaResource {
  const LocalMediaResource(this.uri);
  @override
  final Uri uri;
}

final class NetworkMediaResource extends MediaResource {
  const NetworkMediaResource(this.uri, {this.headers = const {}});
  @override
  final Uri uri;
  final Map<String, String> headers;
}
```

`LocalMediaResource.uri` 必须是绝对 `file:` URI；`NetworkMediaResource.uri` 必须是 `http` 或 `https` URI。构造时验证 scheme，错误输入立即失败，不允许 presentation 猜测或修复。

本地绝对路径只存在于内存中的 `LocalMediaResource`，不得进入路由、持久化状态或常规日志。

### 6.4 MediaResourceRequest

资源请求使用共同的 sealed 基类和值相等模型：

```dart
enum MediaAssetKind { image, video }

sealed class MediaResourceRequest extends Equatable {
  const MediaResourceRequest();
}

final class MediaAssetRequest extends MediaResourceRequest {
  final MediaAssetKind kind;
  final String relativePath;
}

final class MediaThumbnailRequest extends MediaResourceRequest {
  final String relativePath;
  final int sizeBytes;
  final int lastModified;
  final bool hasThumbnail;
}
```

thumbnail request 的等价键必须包含 `relativePath + sizeBytes + lastModified + hasThumbnail`，与现有缓存失效语义一致。

### 6.5 MediaLibrary

```dart
abstract interface class MediaLibrary {
  Future<List<FileItem>> listDirectory(String relativePath);

  Future<List<VideoItem>> listVideosRecursively(String relativePath);

  Future<MediaResource?> resolveThumbnail(
    MediaThumbnailRequest request,
  );

  Future<MediaResource> resolveAsset(MediaAssetRequest request);
}
```

契约语义：

- 所有输入都是以 `/` 开头的逻辑相对路径；
- 实现必须执行自己的边界校验，不能信任 caller 已校验；
- `listDirectory` 保持“目录在前、文件在后、同类名称忽略大小写升序”；
- `listVideosRecursively` 只返回支持扩展名的视频相对路径；
- `resolveThumbnail` 在文件不支持缩略图时返回 `null`；应有缩略图但生成或访问失败时抛出 typed failure；
- `resolveAsset` 必须验证请求 kind 与扩展名一致；
- 远端资源解析只构造可信 URL，不为图片或视频额外发起预检 GET；
- 本地资源解析必须经过 `MediaDirectoryScanner.resolvePath` 并确认目标文件存在。

### 6.6 MediaLibraryFactory

```dart
abstract interface class MediaLibraryFactory {
  Future<MediaLibrary> open(MediaLibrarySource source);
}
```

factory 异步是为了允许本地实现取得默认缩略图缓存目录。factory 不拥有或关闭全局 `peerHttpClientProvider`；远端实现借用该 client。

### 6.7 活动媒体会话

`MediaLibrarySessionController` 使用页面级 auto-dispose provider，并保留显式 reset：

```dart
sealed class MediaLibrarySessionState {}
final class MediaLibrarySessionInactive extends MediaLibrarySessionState {}
final class MediaLibrarySessionOpening extends MediaLibrarySessionState {}
final class MediaLibrarySessionActive extends MediaLibrarySessionState {
  final MediaSourceKind sourceKind;
  final MediaLibrary library;
  final int generation;
}
final class MediaLibrarySessionFailed extends MediaLibrarySessionState {
  final MediaLibraryFailure failure;
}
```

`activate(source)` 的行为固定为：

1. 增加 generation；
2. 发布 `Opening`；
3. 调用 factory；
4. 只有 generation 仍匹配时发布 `Active` 或 `Failed`；
5. 旧 factory Future 完成后不得恢复过期 session。

`reset()` 增加 generation 并发布 `Inactive`。

`MediaBrowserController` 和 `ShufflePlaybackController` 不保存 `MediaLibrary` 副本；每次操作读取当前 active session，并在完成时同时检查自己的 operation generation 与 session generation。

### 6.8 资源 Provider

`mediaResourceProvider` 是 `FutureProvider.autoDispose.family<MediaResource?, MediaResourceRequest>`。它 watch 当前 session：

- inactive/opening/failed 时返回对应 typed failure；
- active 时调用同一 `MediaLibrary`；
- session generation 变化后 Riverpod 自动废弃旧 provider 实例；
- 图片页和缩略图 tile 按实际可见项懒解析资源。

## 7. Data 实现

### 7.1 文件组织

```text
lib/features/media/data/
├── local_media_library.dart
├── remote_media_library.dart
├── default_media_library_factory.dart
└── dto/
    └── media_file_item_dto.dart
```

### 7.2 LocalMediaLibrary

构造依赖：

- `MediaDirectoryScanner`；
- `MediaThumbnailCache`；
- `MediaThumbnailGenerator`。

行为：

- `listDirectory` 委托 `scanner.scan`；
- `listVideosRecursively` 委托 `scanner.scanRecursiveVideos`；
- 图片和视频资源先经 scanner 安全解析，再确认 `File` 存在，返回 `Uri.file(resolvedPath, windows: true)` 所代表的本地资源；实际实现应使用 Dart 提供的文件 URI 构造方式，不手写 `file:///` 字符串；
- 缩略图先按 `relativePath + size + lastModified` 查 cache，未命中则调用 generator 并写 cache；
- 根目录不存在、权限失败、路径越界与资源不存在分别映射为 typed failure；
- 不使用 `peerHttpClientProvider`，不启动 HTTP Server。

`MediaDirectoryScanner` 从“服务端目录扫描器”更名为注释意义上的“本地媒体目录扫描器”，类名本次可保留，避免无价值的文件/类型重命名。现有路径安全、隐藏文件过滤和排序实现继续作为本地与 HTTP 服务端的共同底层。

### 7.3 RemoteMediaLibrary

构造依赖：

- 已验证的 base URI；
- `peerHttpClientProvider` 提供的 client；
- 固定的目录与递归列表超时策略。

行为：

- 目录列表请求 `/api/media/list/{encodedPath}`；
- 递归视频请求 `/api/media/videos/recursive/{encodedPath}`；
- 缩略图资源构造 `/api/media/thumbnail/{encodedPath}`；
- 图片资源构造 `/api/media/image/{encodedPath}`；
- 视频资源构造 `/api/media/video/{encodedPath}`；
- 每个相对路径段单独编码，保持中文与空格路径；
- 路径不能改变 scheme、host 或 port；
- 非 2xx、超时、`ClientException` 和 malformed JSON 映射为 typed failure；
- 不读取用户 LLM 自定义 Header，只使用 peer HTTP 信任域。

### 7.4 HTTP DTO 与 domain 清理

当前 `FileItem.thumbnailUrl` 把 HTTP endpoint 泄漏到通用 domain。最终模型改为 `hasThumbnail`：

```dart
final bool hasThumbnail;
```

`MediaFileItemDto` 独占当前 JSON 字段，包括 `thumbnailUrl`：

- server handler：`FileItem -> MediaFileItemDto -> JSON`；
- remote library：`JSON -> MediaFileItemDto -> FileItem`；
- 现有 JSON key、相对 API 路径和 Android 协议兼容性不变；
- domain 不再提供 HTTP JSON 的 `toJson/listFromJson`；
- malformed/兼容测试放在 DTO/remote adapter 层，不放 domain 模型测试。

`buildMediaResourceUrl` 和 API prefix 编码移入 `RemoteMediaLibrary` 或其私有 helper；`path_utils.dart` 只保留 transport-neutral 的路由相对路径规范化。

## 8. Presentation 与 Controller 改造

### 8.1 MediaBrowserController

- 删除 `package:http` 和 `peerHttpClientProvider` 依赖；
- 删除 `MediaServerInfo`；
- `MediaBrowserState.server` 删除，不用另一字段复制 session；
- 是否存在活动会话由 session provider 派生；
- 目录成功后才更新 current path；
- 失败导航不写入 history；
- session/operation generation 不匹配时丢弃结果；
- reset 清空 items、path、history、loading 和 error。

### 8.2 ShufflePlaybackController

- 删除 HTTP 请求与 URL 构造；
- 通过 active library 获取递归视频列表；
- playlist 始终只保存 `VideoItem` 相对路径；
- previous/next 只更新索引并把相对路径交给 route；
- session 变化、目录变化或离开媒体 Tab 时清理；
- 不提前解析整个列表的资源，避免根目录路径或 URL 被长期保存。

### 8.3 缩略图

`MediaGridView` 删除 `thumbnailBaseUrl`。`MediaFileTile` 改为 Consumer widget，并按 `MediaThumbnailRequest` watch resource provider。

新增窄 presentation adapter `lib/features/media/presentation/widgets/media_image_resource_view.dart`：

- `LocalMediaResource` 使用 `Image.file`/`FileImage`；
- `NetworkMediaResource` 使用 `Image.network`/`NetworkImage` 并传递 headers；
- loading、fit 和 error fallback 由 caller 配置；
- 单个 thumbnail failure 只回退该 tile 的文件类型图标；
- thumbnail failure 不写入 `MediaBrowserState.errorMessage`。

### 8.4 图片查看

`ImageViewerPage` 不再接收 `List<String> imageUrls`，改为当前目录的 `List<MediaAssetRequest>`。

- `initialIndex` 语义不变；
- 每页按需解析资源；
- 相邻图片顺序继续来自当前 `browser.items`；
- 本地和网络图片共用相同缩放、手势与错误 UI；
- direct link 目标不在当前列表时仍建立单图请求；
- 资源删除时 leaf page 显示 broken-image 状态，仍可返回。

需要缩放状态的 `_ZoomableImagePage` 可改为 `ConsumerStatefulWidget`，但缩放矩阵、hysteresis 与页面 race 处理不改变。

### 8.5 视频播放

`MediaVideoRoutePage` 验证相对路径和活动 session 后，通过 resource provider 解析一个视频资源，再构建 `VideoPlayerPage`。

新增窄 factory `lib/features/media/presentation/pages/media_video_controller_factory.dart`：

```dart
VideoPlayerController createMediaVideoController(MediaResource resource) {
  return switch (resource) {
    LocalMediaResource() =>
      VideoPlayerController.file(File.fromUri(resource.uri)),
    NetworkMediaResource() => VideoPlayerController.networkUrl(
      resource.uri,
      httpHeaders: resource.headers,
    ),
  };
}
```

`VideoPlayerPage` 接收 `MediaResource` 和可测试 factory。初始化与“重试”按钮必须调用同一个私有创建方法，禁止初始化走 local factory、重试却退回固定 `networkUrl`。

现有 `VideoPlayerGestureController`、`VideoPlayerUiState`、控制栏、键盘、Semantics 和手势逻辑继续使用 `VideoPlayerController`，本次不抽象完整播放器引擎。

### 8.6 路由与恢复页

继续使用：

```text
/sync/media/image?path=/相册/猫.jpg
/sync/media/video?path=/视频/demo.mp4
```

约束：

- query 只含规范化相对路径；
- 不含 Windows 盘符、本地根目录、scheme、host 或 port；
- 没有活动 session 的冷启动 deep link 继续进入恢复页；
- 不根据路由自动创建 local/remote source；
- 恢复文案泛化为“请返回同步页重新打开媒体浏览器”，同时适配本地和远端。

## 9. App composition 与生命周期

### 9.1 Provider 绑定

`cross_feature_bindings.dart` 绑定 `MediaLibraryFactory`：

- 借用 `peerHttpClientProvider` 创建 remote library；
- 本地 source 创建 scanner、默认 cache 和 generator；
- factory 是 application port 的唯一生产实现；
- presentation 不 import `data/`。

### 9.2 Windows 进入媒体 Tab

1. Windows 与 Android 均显示第三个媒体 Tab；
2. 进入媒体 Tab 时读取 `mediaRootDirectoryProvider`；
3. 未配置时不创建 session，显示“尚未配置媒体根目录”，提供返回连接 Tab 的操作；
4. 已配置时创建 `LocalMediaLibrarySource` 并 activate；
5. session active 后 browser 加载 `/`；
6. 根目录是本次 session 的不可变快照；
7. 用户离开媒体 Tab 后才能在连接 Tab 修改根目录，再进入时创建全新 session。

### 9.3 Android 进入媒体 Tab

1. 读取当前可信 `SyncClientState.server`；
2. 未连接时不创建 session，显示“未连接到服务端”；
3. 已连接时由 server IP/port 创建 `RemoteMediaLibrarySource`；
4. activate 后 browser 加载 `/`；
5. authority 只来自同步会话，不来自 route 或 media domain。

### 9.4 子路由与离开媒体 Tab

图片或视频子路由压在 `/sync` 上方时，父 `SyncWorkspaceScreen` 与 session 保持存活。关闭子路由返回媒体列表时，不重新建立 session。

真正切离媒体 Tab 时，固定顺序为：

1. `MediaLibrarySessionController.reset()`，增加 session generation；
2. `MediaBrowserController.reset()`；
3. `ShufflePlaybackController.reset()`；
4. 让 auto-dispose watcher 释放剩余页面资源 provider。

session 必须先失效，确保后续完成的图片、缩略图、目录或 factory Future 都无法恢复旧状态。

AppBar 随机播放 actions 根据 active session 和当前媒体 Tab 派生，不再检查 `MediaBrowserState.server`。

## 10. 错误模型

端口统一抛出 `MediaLibraryFailure`，禁止 controller 把任意异常 `$e` 直接显示给用户：

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
```

映射：

| 原始失败 | Application failure | UI 行为 |
|---|---|---|
| 根目录未配置、被删除或移动 | `sourceUnavailable` | 媒体页提示返回连接 Tab 重新配置 |
| `PathTraversalException` | `invalidPath` | 显示“媒体路径无效”，不暴露根目录 |
| 本地权限错误 | `accessDenied` | 显示无访问权限 |
| 本地文件或 HTTP 404 | `notFound` | leaf 资源显示不存在；目录加载显示错误 |
| `ClientException` | `networkUnavailable` | 远端媒体页显示网络不可用 |
| 请求 timeout | `timeout` | 显示请求超时并允许重试 |
| malformed JSON | `invalidResponse` | 显示服务端响应无效 |
| kind/扩展名不匹配 | `unsupportedMedia` | route recovery 或 leaf error |
| thumbnail 生成/读取失败 | `thumbnailUnavailable` | 单 tile 回退图标 |
| 播放器 codec/initialize 失败 | 不属于 library failure | 播放页局部错误与重试 |

目录导航失败时 current path 与 history 保持最后一次成功状态。现有 grid error 呈现可以保留；本阶段不同时重设计全局媒体错误 UI。

## 11. Windows 视频播放依赖

官方 [`video_player 2.13.0`](https://pub.dev/packages/video_player) 不提供 Windows implementation。推荐先验证 [`video_player_win`](https://pub.dev/packages/video_player_win)，因为它实现同一个 platform interface，能够保留现有 `VideoPlayerController`、播放器 UI 和测试替身。

验证必须覆盖：

- Flutter 3.44.6 下依赖解析；
- Windows Debug 与 Release 构建；
- 本地 H.264/AAC MP4；
- 中文目录和中文文件名；
- pause、seek、volume、倍速和播放结束；
- 关闭页面、失败重试、连续切换视频；
- 用户实际媒体样本的主要编码。

停止条件：

- 依赖无法与当前 `video_player`/Flutter 版本解析；
- Debug 或 Release 构建失败；
- 常规播放/释放出现稳定崩溃；
- 用户主要媒体编码需要额外安装 codec 才能工作；
- 中文文件路径不能稳定播放。

命中停止条件后不得在本任务中自动安装 codec、启动外部播放器或迁移 [`media_kit`](https://pub.dev/packages/media_kit)。应报告证据，并另行批准播放器迁移范围。媒体库访问抽象仍然有效，不需要回退。

## 12. 实施顺序与提交边界

### 12.1 Task 0：Windows 播放器可行性验证

在正式改造前验证 `video_player_win`。验证不混入媒体库架构提交；若必须创建最小 spike，验证后只保留最终需要的依赖与生产接入，不提交临时代码。

### 12.2 Task 1：提取媒体库契约

- 新增 source、resource、request、failure、library 和 factory 契约；
- 新增 fake library/factory；
- 不改变 Android 产品行为。

建议提交：`refactor(media): 提取媒体库访问契约`

### 12.3 Task 2：收敛远端媒体访问

- 实现 `RemoteMediaLibrary`；
- controller 移除直接 HTTP；
- 搬迁 URL/编码规则；
- 保持当前 HTTP API 与 Android 行为。

建议提交：`refactor(media): 将远端媒体访问收敛到数据适配器`

### 12.4 Task 3：清理 HTTP DTO

- 增加 `MediaFileItemDto`；
- `FileItem.thumbnailUrl` 改为 `hasThumbnail`；
- handler 与 remote adapter 使用 DTO；
- 协议 JSON 不变。

该任务可与 Task 2 同提交，前提是 diff 仍可独立审查；否则使用单独 `refactor(media): 隔离媒体文件 HTTP DTO`。

### 12.5 Task 4：实现本地媒体库

- 复用 scanner/cache/generator；
- 实现本地列表、递归视频、缩略图、图片和视频资源；
- 覆盖路径安全与文件系统失败。

建议提交：`feat(media): 实现本地媒体库访问`

### 12.6 Task 5：统一活动 session 与资源渲染

- 加入 session controller 和 resource provider；
- browser/shuffle/route 统一读取 session；
- thumbnail 与 image 支持 local/network resource；
- 保持 Android UI 行为。

建议提交：`feat(media): 支持本地与远端媒体资源`

### 12.7 Task 6：Windows 视频与媒体 Tab

- 接入通过验证的 Windows video implementation；
- 加入 resource 型 controller factory；
- Windows 显示媒体 Tab 并使用本地 root；
- 补齐缺 root、session reset 和本地 smoke。

建议提交：`feat(media): 在 Windows 启用媒体浏览器`

### 12.8 Task 7：文档

- 更新 README 的平台行为；
- 更新原媒体 PRD 中“仅 Android 客户端”的过时说明；
- 记录 Windows 播放 codec 的实际验证范围，不声称未验证格式可用。

文档可并入最后一个功能提交，或使用独立 `docs(media): 记录 Windows 本地媒体浏览行为`。

## 13. 测试设计

### 13.1 Application

- fake library 驱动根目录加载成功、失败、返回和历史；
- 失败导航不污染 history；
- controller reset 后旧 Future 不写回；
- session replacement 后旧 Future 不写回；
- factory 过期 completion 不恢复旧 session；
- shuffle 只保存相对路径；
- local/remote session 切换清除旧 playlist；
- resource provider 随 session generation 失效。

### 13.2 Local data

- 根目录与子目录扫描；
- 中文、空格和特殊字符路径；
- `..` 路径穿越拒绝；
- 符号链接指向根外时拒绝；
- 根目录、目录或文件不存在；
- 权限不足；
- 图片与视频生成正确 file URI；
- kind 与扩展名不匹配；
- 缩略图 cache hit；
- 缩略图生成、写入与 cache key 失效；
- thumbnail generator failure 映射；
- 递归视频扫描不逃逸根目录。

### 13.3 Remote data

- 五类 API 路径与逐段编码；
- DTO round-trip 和 malformed JSON；
- 非 2xx 状态映射；
- 404、timeout 和 `ClientException`；
- 只使用 peer HTTP client；
- 相对路径不能覆盖 base authority；
- 资源解析不发额外预检请求。

### 13.4 Presentation 与 composition

- Windows 与 Android 均显示媒体 Tab；
- Windows 无根目录时显示配置提示；
- Android 未连接时显示连接提示；
- Windows local browse 在 peer HTTP client 被配置为“一调用即失败”时仍成功，证明没有网络回环；
- 本地和远端缩略图正确选择 image adapter；
- 单 thumbnail failure 只回退单 tile；
- 图片画廊保持当前目录顺序；
- direct link 不在当前列表时使用单图；
- local video 使用 file controller factory；
- remote video 使用 network controller factory；
- retry 继续使用相同 factory；
- route 只含相对路径，不含盘符或 authority；
- 子路由期间 session 保活；
- 切离媒体 Tab 后 session、browser 与 shuffle 清理；
- 冷启动 media deep link 无 session 时进入恢复页。

### 13.5 Windows 手工 smoke

使用用户实际媒体根目录执行：

1. 连接 Tab 选择根目录；
2. 媒体 Tab 打开 `/`；
3. 逐级进入目录并使用路径栏/返回键；
4. 打开中文路径图片，左右切换、双击和双指缩放；
5. 打开中文路径视频，验证播放、暂停、seek、音量和倍速；
6. 验证随机播放、上一条、下一条与结束；
7. 返回列表后状态正确；
8. 切离媒体 Tab 再进入，重新从根目录建立 session；
9. 删除或移动测试资源后显示受控错误；
10. 关闭页面和应用时无播放器崩溃。

手工 smoke 未实际执行前必须标记为 pending，不得以 Widget 测试或 Windows build 代替。

## 14. 验证命令

定向测试与全量测试均按仓库要求重定向输出：

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
flutter test test/features/media test/features/sync/sync_screen_test.dart test/app/router/app_router_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 media-tests.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 media-tests.log
dart run tool/check_import_boundaries.dart
flutter analyze --no-pub
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
flutter build windows --debug
flutter build windows --release
```

如果 `flutter analyze` 在依赖解析后停滞，按仓库约定重试 `flutter analyze --no-pub`。任何测试、analyze、架构门禁或 Windows build 非零时不得进入完成状态。

## 15. 验收标准

以下条件全部满足才算实现完成：

1. Windows 同步页显示媒体 Tab，并直接浏览已配置媒体根目录；
2. Windows 媒体操作不发起 localhost 或 peer HTTP 请求；
3. Android 继续通过可信同步 peer 访问相同逻辑媒体根目录；
4. browser、shuffle 和 route 不直接 import `package:http` 或构造媒体 API URL；
5. application/presentation 不按 Windows/Android 选择数据实现；
6. 目录、缩略图、图片、视频和递归视频全部经过 `MediaLibrary`；
7. 路由只包含相对路径；
8. 本地绝对路径不持久化、不进入路由、不写入常规日志；
9. 路径穿越和根外符号链接被拒绝；
10. thumbnail failure 不破坏目录浏览；
11. 本地/远端图片和视频选择正确 presentation adapter；
12. Windows 视频插件通过规定的真实样本验证；
13. Android 既有定向测试保持通过；
14. import boundary、analyze、全量测试和 Windows Debug/Release build 通过；
15. Windows 手工 smoke 已执行并记录，或明确标记为 pending 而不声称功能完成。

## 16. 风险与控制

| 风险 | 控制 |
|---|---|
| 抽象层仍泄漏 HTTP URL | domain 使用 `hasThumbnail`，HTTP 字段只留 DTO |
| 本地绝对路径进入路由 | route adapter 只接收 relativePath，资源只存在于 session 内存 |
| source 切换后旧异步结果写回 | session generation + operation generation 双重检查 |
| Windows 本地浏览意外依赖网络 | local 实现零 HTTP 依赖，并用 fail-on-call peer client 测试 |
| 缩略图生成拖垮整页 | tile 级 auto-dispose provider，失败局部回退 |
| Windows 播放格式不兼容 | 实施前真实样本 gate；失败时停止并另行评估 media_kit |
| 为切换播放器过度设计 | 本阶段只抽资源与 controller factory，不抽完整播放引擎 |
| Android 行为在大改中回归 | 先完成远端等价迁移，再开启 Windows；分提交验证 |

## 17. 范围审计

本设计只改变媒体读取来源与 Windows 入口能力。它不修改聊天、收藏、历史、设置同步、Sync 协议、安全配对、HTTP 服务生命周期或媒体内容算法。现有 HTTP handlers 只因 DTO 边界做等价调整；现有 scanner/cache/generator 只被复用，不提前引入其他平台、转码或文件管理能力。

若实施中发现必须修改 Sync 协议、引入完整播放器迁移、改变一级导航或增加写文件能力，均视为超出本设计，必须停止并请求新的范围批准。
