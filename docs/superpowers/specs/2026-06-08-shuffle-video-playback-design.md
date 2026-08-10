# 随机视频播放功能 — 设计文档

> 日期：2026-06-08 | 状态：已确认

## 背景

媒体客户端目前支持按目录浏览图片和视频，点击视频文件进入全屏播放器。用户希望增加一个"随机播放"入口，一键收集当前目录树下所有视频、shuffle 后顺序播放，提升随意观看场景下的体验。

## 用户交互流程

1. 用户在媒体浏览器中浏览某个目录
2. AppBar 右侧始终显示 🔀 按钮（tooltip: "随机播放"）
3. 点击 🔀 → 按钮变为加载动画 → 服务端递归收集当前目录树下所有视频 → 客户端 shuffle → 直接全屏播放第 1 个
4. 播放器顶部短暂（~2s）显示半透明提示 "🎲 随机播放 · 第 1/N 个"
5. 用户退出播放器 → AppBar 按钮变身为「◀ 上一个 | N/M | 下一个 ▶」
6. 用户可点击上一个/下一个继续播放对应视频
7. 边界规则：
   - 第 1 个视频：只显示"下一个 ▶"
   - 最后 1 个视频：只显示"◀ 上一个"
   - 全部播完退出后：按钮自动变回 🔀，可重新随机
8. 用户导航到其他目录 → 播放列表立即清空，按钮变回 🔀
9. 用户切到其他 Tab 再切回媒体 Tab → 播放列表保持不变

## 零视频与错误场景

| 场景 | 行为 |
|------|------|
| 当前目录树下无视频文件 | 点击 🔀 后 SnackBar 提示"当前目录下未找到视频文件"，按钮保持 🔀 |
| 网络请求失败 | SnackBar 显示错误信息，按钮恢复 🔀 |
| 视频文件已被删除（播放时 404） | VideoPlayerPage 内部处理加载失败，用户返回后按钮保持 ACTIVE，可尝试下一个 |

## 状态机

```
IDLE ──点击🔀──▶ LOADING ──获取成功──▶ ACTIVE (自动播放第1个)
                   │                        │
                   │ 获取失败/0视频          │ 退出播放器
                   ▼                        ▼
                  IDLE              AppBar 显示 ◀ N/M ▶
                   ▲                        │
                   │ 全部播完退出             │ 点击上一个/下一个
                   └────────────────────────┘ (播放对应视频)

IDLE / LOADING / ACTIVE ──切换目录──▶ IDLE (清空所有状态)
IDLE / LOADING / ACTIVE ──切Tab再回──▶ 状态不变
```

## 架构设计

### 服务端变更

**新 API 端点：** `GET /api/media/videos/recursive/{encoded_path}`

- 递归扫描指定目录下所有子孙目录中的视频文件
- 返回扁平 JSON 数组：`[{ "name": "cat.mp4", "relativePath": "/videos/funny/cat.mp4" }]`
- 按名称排序后返回（shuffle 由客户端执行）
- 支持路径穿越防护（复用 `MediaDirectoryScanner` 现有逻辑）

**新 Handler：** `MediaRecursiveVideosHandler` (`lib/features/media/data/media_recursive_videos_handler.dart`)

- 实现 `canHandle()` 匹配 `GET` + `/api/media/videos/recursive` 前缀
- 在 `MediaHttpHandler` 的路由表中注册

**修改：** `MediaDirectoryScanner` (`lib/features/media/data/media_directory_scanner.dart`)

- 新增 `scanRecursiveVideos(String relativePath)` 方法
- 递归遍历子目录，只收集扩展名在 `videoExtensions` 集合中的文件
- 复用现有隐藏文件过滤、路径穿越检查

### 客户端变更

**新 Controller：** `ShufflePlaybackController` (`lib/features/media/application/shuffle_playback_controller.dart`)

- Riverpod `NotifierProvider<ShufflePlaybackController, ShufflePlaybackState>`
- 状态定义：

```dart
sealed class ShufflePlaybackState {}

class ShufflePlaybackIdle extends ShufflePlaybackState {}

class ShufflePlaybackLoading extends ShufflePlaybackState {}

class ShufflePlaybackActive extends ShufflePlaybackState {
  final List<VideoItem> playlist;   // shuffle 后的视频列表
  final int currentIndex;           // 当前播放到的索引
  final String directoryPath;       // 此列表对应的目录（用于检测目录切换）
}
```

- 关键方法：
  - `startShuffle(String directoryPath)` — 请求服务端 → shuffle → 将状态设为 Active（currentIndex=0）
  - `playNext()` — currentIndex + 1，更新状态（越界不操作，返回 false）
  - `playPrevious()` — currentIndex - 1，更新状态（越界不操作，返回 false）
  - `onPlayerExited()` — 播放器退出回调：若当前为最后一个视频（currentIndex == last）则重置为 Idle
  - `clearIfDirectoryChanged(String newPath)` — 目录变化时重置为 Idle
  - `reset()` — 手动重置为 Idle
  - URL 构建：通过 `ref.read(mediaBrowserControllerProvider).server` 获取服务器信息，复用现有 `_buildMediaUrl` 模式

**新 Widget：** `ShuffleAppBarActions` (`lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`)

- 根据 `ShufflePlaybackState` 渲染不同按钮组：
  - Idle → 单个 `IconButton(icon: Icons.shuffle)`
  - Loading → 小型 `CircularProgressIndicator`（padding 与 IconButton 一致）
  - Active → `Row([prevButton, progressText, nextButton])`，边界自适应显示/隐藏

**修改 SyncScreen** (`lib/features/sync/presentation/sync_screen.dart`)

- 传入 `actions` 参数到 `AppShellScaffold`：当媒体 Tab 被选中时，actions 包含 `ShuffleAppBarActions`
- 仅在 `_hasMediaTab` 为 true 且有已连接服务器时显示

**修改 MediaBrowserTab** (`lib/features/media/presentation/media_browser_tab.dart`)

- 在目录切换（`navigateTo`、`goBack`、初始加载）时调用 `shufflePlaybackController.clearIfDirectoryChanged(newPath)`

**导航协调机制：**

- `ShuffleAppBarActions`（AppBar 层）同时负责按钮渲染、状态管理和触发导航（AppBar 与 MediaBrowserTab 处于同一 GoRouter Navigator，`Navigator.push` 效果一致）
- 点击 🔀 → controller 获取视频列表 → 状态变为 Active → 按钮所在 context 直接 `Navigator.push(VideoPlayerPage(...))`
- 点击 ◀/▶ → controller 更新索引 → 同样直接 `Navigator.push`
- `MediaBrowserTab` 仅负责目录切换时通知 controller 清空列表，不参与导航

## 数据模型

```dart
// 服务端返回 + 客户端使用的视频条目（轻量，仅用于播放列表）
class VideoItem {
  final String name;         // 文件名，如 "cat.mp4"
  final String relativePath; // 相对路径，如 "/videos/funny/cat.mp4"
}
```

URL 构建复用 `MediaBrowserTab._buildMediaUrl('video', item.relativePath)` 的模式，提取为公共工具函数。

## 文件清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新增 | `lib/features/media/data/media_recursive_videos_handler.dart` | 递归视频扫描 HTTP handler |
| 新增 | `lib/features/media/application/shuffle_playback_controller.dart` | 随机播放状态管理 |
| 新增 | `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart` | AppBar 按钮组 Widget |
| 修改 | `lib/features/media/data/media_http_handler.dart` | 注册新 handler |
| 修改 | `lib/features/media/data/media_directory_scanner.dart` | 新增 `scanRecursiveVideos()` |
| 修改 | `lib/features/sync/presentation/sync_screen.dart` | 向 AppShellScaffold 传入 actions |
| 修改 | `lib/features/media/presentation/media_browser_tab.dart` | 目录切换时通知清空 |

## 待实现细节（实现阶段决定）

- 播放器顶部 "🎲 随机播放 · 第N/M个" 的提示 Widget 实现方式（overlay vs 修改 VideoPlayerPage）
- 视频数量较大（>100）时的加载性能与 UI 反馈
- 缩略图列表展示（如需要）
- `VideoItem` 与 `FileItem` 之间的代码复用策略

## 验证方案

1. **服务端单元测试**：`scanRecursiveVideos()` 递归收集正确性、路径穿越防护、空目录/纯图片目录返回空列表
2. **客户端单元测试**：`ShufflePlaybackController` 状态转换、边界条件（prev at 0、next at last、clear on dir change）
3. **Widget 测试**：AppBar 按钮三种形态渲染、边界条件可见性
4. **端到端手动验证**：
   - 点击 🔀 → 确认自动播放视频
   - 退出 → 确认 AppBar 显示上一个/下一个
   - 点击下一个 → 确认播放不同视频
   - 切换目录 → 确认按钮回到 🔀
   - 0 视频目录 → 确认 SnackBar 提示
