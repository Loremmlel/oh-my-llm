# Phase 12 - 可恢复导航契约 Implementation Plan

> 对应文档：`docs/第一轮审查/Phase 12 - 可恢复导航契约.md`
>
> 对应技术债：TD-28（仅核对了 `architecure-review.md` 中命中 TD-28 的第 288、458 行，未读取整份审查文档）
>
> 代码基线：`1f09bec`（2026-08-07）
>
> 路由依赖：`go_router 17.4.0`（`pubspec.lock` 锁定版本）

本计划只处理三件事：收藏详情 ID 路由、媒体查看/播放子路由、`StatefulShellRoute` 触发条件判定。执行者不得把第三项误解成“必须迁移 shell”。当前代码与测试证据表明触发条件**未成立**，所以本 Phase 的默认实施结果是继续保留平铺顶层 `GoRoute`，不引入 `StatefulShellRoute`。

---

## 零、执行结论（实现时不得自行改写）

### 0.1 本 Phase 的五个确定决策

1. **收藏详情使用路径 ID，不使用 `extra`。**
   - 最终 URL：`/favorites/:favoriteId`。
   - 生产导航必须调用命名路由并传 `pathParameters`；禁止手工拼接 `'/favorites/$id'`。
   - 路由 builder 只把字符串 ID 交给 `FavoriteDetailScreen`，不得读取或 cast `state.extra`。

2. **收藏详情按 ID 从 Favorites application 边界读取。**
   - 在 `FavoritesRepository` 增加同步 `loadById(String favoriteId)`。
   - 在 `favorites_controller.dart` 增加 `favoriteByIdProvider`，详情页 watch 此 provider。
   - 当前 SQLite/repository API 全部是同步的，因此本 Phase **不引入 `FutureProvider`、loading spinner 或异步 repository 改造**。Phase 文档所说的“异步状态风险”在当前实现中具体表现为“不存在/已删除”，而不是实际的异步 I/O。

3. **媒体页面成为 `/sync` 的 GoRouter 子路由，只在 URL 中携带媒体相对路径。**
   - 图片：`/sync/media/image?path=<FileItem.relativePath>`。
   - 视频：`/sync/media/video?path=<FileItem/VideoItem.relativePath>`。
   - URL 不携带 `FileItem`、`VideoItem`、`MediaServerInfo`、图片 URL 列表或任意 `extra`。
   - 网络 authority（IP/port）继续来自当前可信的 `mediaBrowserControllerProvider.server`，不得由 deep link 提供任意 host/port；这样不会把路由变成绕过既有连接边界的任意网络请求入口。

4. **媒体路由缺参或媒体会话失效时显示可返回的页面级恢复状态。**
   - 不抛异常、不强制 cast、不显示 SnackBar/Dialog。
   - 恢复页必须提供“返回局域网同步”操作。
   - 已连接且路径合法时：图片按当前目录图片列表恢复画廊；目标不在当前列表时降级为单图查看；视频直接从可信 server + relative path 重建 URL。

5. **本次不实施 `StatefulShellRoute`。**
   - Phase 10 已证明 ChatScreen 卸载/重挂后会话草稿恢复、编辑事务按设计丢弃。
   - Sync/Media 已把 tab preference 持久化，并明确要求离开媒体 tab 时 reset 页面会话。
   - 当前没有新增顶层 destination，也没有先失败的“顶层切页导致用户状态丢失”行为测试。
   - 在上述事实不变时迁移 shell 会扩大所有顶层页面回归面，并可能错误保留本应销毁的编辑、滚动或媒体会话状态。

### 0.2 明确不采用的替代方案

| 方案 | 不采用原因 |
|---|---|
| `context.push(..., extra: favorite)` | URL/刷新无法重建，正是 TD-28 根因。 |
| `extra: favorite.id` | 虽然值可序列化，但 ID 仍不在 URL；刷新/直接打开仍丢失。 |
| media route 继续传 `extra: imageUrls` | 图片列表仍依赖内存对象，换了 GoRouter API 但没有形成 URL 契约。 |
| media URL 携带任意 `host`、`port` 或绝对 `src` | deep link 会成为网络 authority 来源，绕开当前已连接 peer 的信任边界。 |
| 把全部图片 URL 重复编码进 query | 目录较大时 URL 无上限膨胀；还会复制 server authority 和过期列表。 |
| 用媒体相对路径作为 path segment | 相对路径本身含多级 `/`，依赖 `%2F` 的匹配/解码细节；query 参数更清楚、稳定。 |
| 为详情读取改成异步 repository | 当前 raw `sqlite3` API 同步；此改造没有收益且扩大 Favorites 全部调用面。 |
| 为“最佳实践”迁移 `StatefulShellRoute` | 缺少 UX 触发证据，违反 Phase 12 的条件边界。 |
| 引入第二套路由库或自建 Navigator | 直接违反 Out of Scope 与统一导航栈目标。 |

---

## 一、前置 Phase 实现审查

### 1.1 Phase 7：app/composite 与 feature ownership

| Phase 7 要求 | 当前证据 | 判定 |
|---|---|---|
| Sync + Media 组合归 app | `lib/app/composition/sync_workspace_screen.dart` 是同时组合 Sync 与 Media 的页面；`app_router.dart` 的 `/sync` 已指向它。 | 已满足 |
| Media 页面不穿透 data | `media_browser_tab.dart` 只依赖 media application/domain/utils/presentation；依赖门禁已覆盖 presentation → data。 | 已满足 |
| Chat/Favorites 通过稳定 command/facade 协作 | `favorite_source_conversation_command.dart` 与 `cross_feature_bindings.dart` 已存在；详情页跳回来源对话不再直接调 Chat controller。 | 已满足 |
| app composition 绑定 concrete repository/ports | `cross_feature_bindings.dart` 绑定 Favorites repository、Chat/Favorites bridge 与 Sync media route factory。 | 已满足 |
| 可独立测试的组合边界 | Sync screen cases 已覆盖 Android media session init/reset；Favorites command 有 application test。 | 已满足 |

提交证据：`78f2bcd refactor(app): 收敛跨功能组合边界`。Phase 12 必须沿用该方向：`app_router.dart` 负责 route matrix；媒体 routed page 只依赖 media application/domain；不得把 URL 解析或 Navigator construction 放回 Sync controller。

### 1.2 Phase 10：Chat workspace 状态所有权

| Phase 10 要求 | 当前证据 | 对 Phase 12 的意义 |
|---|---|---|
| 草稿按会话由 Provider owner | `ComposerDraftController` 持有 `conversationId → ComposerDraft`。 | ChatScreen 被顶层 `context.go` 销毁后，草稿不是由 widget instance 唯一持有。 |
| 页面资源与编辑事务是瞬态 | `ChatScreen` 本地持有 controllers/focus/scroll/editing draft，并在 dispose 清理。 | 迁移 stateful shell 反而会改变“页面销毁即清理”的既定语义。 |
| 页面卸载/重挂恢复草稿 | `chat_screen_workspace_ownership_cases.dart` 已有“ChatScreen 卸载后在同 scope 重挂，body 草稿恢复”。 | 已有行为证据表明 shell keep-alive 不是恢复草稿的必要条件。 |
| 编辑中卸载不错误恢复编辑态 | 同文件已有“编辑后卸载重挂丢弃编辑模式，草稿恢复为会话级值”。 | 不得用持久 shell 无意延长编辑事务生命周期。 |
| workspace 参数与 intent 已收敛 | `ChatWorkspaceViewState`、`ChatWorkspaceBindings`、composer/favorite commands 已存在。 | Phase 12 无需触碰 Chat workspace 实现。 |

提交证据：`4060947`、`381b379`、`0500a65`、`66bf178` 及其后续修复/测试提交。Phase 10 前置依赖已满足，没有阻塞 Phase 12。

### 1.3 当前 shell 触发条件判定

| 可观察条件 | 当前情况 | 是否触发 |
|---|---|---|
| 顶层切页导致会话草稿丢失 | 已有卸载/重挂恢复测试；ProviderScope 位于 Router 上方。 | 否 |
| 顶层切页导致持久 preference 丢失 | Chat sidebar/collapse 与 Sync tab 已有 SharedPreferences owner。 | 否 |
| 必须保持多个独立 Navigator back stack | 当前产品没有此明确需求；详情/media 只需父页 + 子页栈。 | 否 |
| 新增顶层模块，现有 flat routes 难以管理 | `AppDestination` 仍为 chat/history/favorites/settings/sync 五项。 | 否 |
| 有先失败的用户行为测试证明 live page 必须保活 | 不存在。 | 否 |

**结论：** 本 Phase 不新增 shell migration task，不修改 `app_shell_scaffold.dart` 的顶层切换方式。最终审计只确认没有误引入 `StatefulShellRoute`。若执行期间发现真实失败场景，必须先停止并记录用户可见行为、最小失败测试及受影响 destinations，再由维护者决定是否扩大范围；不得在媒体/收藏提交中夹带 shell 迁移。

---

## 二、当前实现问题清单

| 位置 | 当前行为 | 缺陷 | 本 Phase 处理 |
|---|---|---|---|
| `app_router.dart` | `/favorites/detail` builder 执行 `state.extra as Favorite`。 | 直接打开/刷新无 extra 时抛 cast error。 | 改成 `/favorites/:favoriteId` 子路由。 |
| `favorites_screen.dart` | `context.push('/favorites/detail', extra: favorite)`。 | URL 没有实体标识，详情依赖列表页内存。 | 改用 `pushNamed + pathParameters`。 |
| `FavoriteDetailScreen` | 构造器接收 `Favorite`，本地 `_favorite` 镜像。 | URL 无法恢复；本地对象可陈旧；详情更新依赖当前 filtered `favoritesProvider` 恰好包含该 ID。 | 构造器只接收 ID，watch 独立 by-ID read model。 |
| `FavoritesRepository` | 只有 `loadAll`。 | 详情只能扫描列表或依赖当前 filter。 | 增加 `loadById` 精确查询。 |
| `media_browser_tab.dart` | 图片/视频使用 `Navigator.push(MaterialPageRoute(...))`。 | 与 GoRouter 平行栈；地址不可观察/恢复。 | 改用媒体命名子路由。 |
| `shuffle_appbar_actions.dart` | 随机播放也使用 `Navigator.push(MaterialPageRoute(...))`。 | 仍有第二个媒体入口绕过 route matrix。 | 改用同一个 video named route，并保留 await/pop 后的 `onPlayerExited()`。 |
| media leaf pages | 构造器要求 URL/list；返回用当前 Navigator pop。 | leaf page 本身不是问题，问题是 route 参数无法重建。 | 新增 routed adapter 解析 session + relative path；不重写播放器/查看器功能。 |
| `app_router.dart` errorBuilder | 只显示未找到 URI。 | 不适合作为已匹配详情/媒体路由的缺参状态。 | 缺参由各 routed screen 内联恢复；全局 404 不承担业务实体缺失。 |

另外，工作区当前已有四个 `.opencode/plans/*.md` 删除改动。它们属于用户现有 worktree，实施 Phase 12 时不得 restore、stage 或提交这些文件。

---

## 三、最终路由矩阵

### 3.1 路由表

| 用途 | route name | GoRoute 配置 path | 最终 URL 示例 | 参数来源 | 打开方式 |
|---|---|---|---|---|---|
| 收藏列表 | `AppDestination.favorites.name` | `/favorites` | `/favorites` | 无 | 顶层 `context.go` |
| 收藏详情 | `AppRouteName.favoriteDetail` | favorites 下的 `:favoriteId` | `/favorites/1714220012345678-a3f9c012` | `pathParameters['favoriteId']` | `context.pushNamed` |
| Sync workspace | `AppDestination.sync.name` | `/sync` | `/sync` | 无 | 顶层 `context.go` |
| 图片查看 | `AppRouteName.mediaImage` | sync 下的 `media/image` | `/sync/media/image?path=%2F相册%2F猫.jpg` | `uri.queryParameters['path']` | `context.pushNamed` |
| 视频播放 | `AppRouteName.mediaVideo` | sync 下的 `media/video` | `/sync/media/video?path=%2F视频%2Fdemo.mp4` | `uri.queryParameters['path']` | `context.pushNamed` |

注意：上表的百分号编码由 GoRouter/`Uri` 根据 `queryParameters` 完成。业务代码传入原始 `relativePath`（例如 `/相册/猫.jpg`），不得预先调用 `Uri.encodeComponent`，否则会双重编码。

### 3.2 `app_destination.dart` 中新增的公共常量

在现有 `AppDestination` 后增加仅包含字符串常量的 route contract，不把 feature model 放入 app navigation：

```dart
abstract final class AppRouteName {
  static const favoriteDetail = 'favoriteDetail';
  static const mediaImage = 'mediaImage';
  static const mediaVideo = 'mediaVideo';
}

abstract final class AppRouteParameter {
  static const favoriteId = 'favoriteId';
  static const mediaPath = 'path';
}
```

执行者可按项目命名习惯微调类名，但必须满足：

- route builder、导航发起方和测试共享同一常量；
- 不在多个文件重复裸字符串 `favoriteId` / `path` / route name；
- `AppDestination` 仍只表示顶层导航项，详情/media 不加入 `AppDestination.values`，否则会错误出现在 NavigationRail/NavigationBar。

### 3.3 `app_router.dart` 的结构

将路由创建提取为可测试工厂，并由 provider 生产默认实例：

```dart
GoRouter createAppRouter({
  String initialLocation = AppDestination.chat.path,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      // chat/history/settings 保持现状
      GoRoute(
        path: AppDestination.favorites.path,
        name: AppDestination.favorites.name,
        builder: (_, _) => const FavoritesScreen(),
        routes: [
          GoRoute(
            path: ':favoriteId',
            name: AppRouteName.favoriteDetail,
            builder: (_, state) => FavoriteDetailScreen(
              favoriteId: state.pathParameters[AppRouteParameter.favoriteId],
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppDestination.sync.path,
        name: AppDestination.sync.name,
        builder: (_, _) => const SyncWorkspaceScreen(),
        routes: [
          GoRoute(
            path: 'media/image',
            name: AppRouteName.mediaImage,
            builder: (_, state) => MediaImageRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (_, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
        ],
      ),
    ],
  );
}
```

上面是 contract 形状，不要求逐字复制。实现必须遵守：

- route 参数类型使用 `String?` 进入 routed screen，不能在 builder 中 `!` 或 `as`；缺失值由页面恢复状态处理；
- favorites/media route 是各自父 route 的 child，使 `pushNamed` 后 pop 回到父页面；
- 不使用 `extra`，包括“仅作首帧优化”的 extra；否则会形成 URL 数据与内存数据双 owner；
- `appRouterProvider` 可在 dispose 时释放创建的 router；测试创建的 router 由 test teardown 显式 dispose；
- `errorBuilder` 继续只处理未知 URL。不要把 favorite not-found 重定向为全局 404，也不要 redirect 形成循环。

### 3.4 `go` 与 `push` 的唯一语义

| 场景 | API | 原因 |
|---|---|---|
| NavigationRail/NavigationBar 顶层切页 | `context.go(destination.path)` | 替换当前顶层 location，不制造跨 destination 返回栈。 |
| 收藏列表 → 详情 | `context.pushNamed(...)` | 详情是列表的子页面，返回必须回列表。 |
| 媒体浏览 → viewer/player | `context.pushNamed(...)` | viewer/player 是 sync workspace 的子页面，返回必须回媒体浏览上下文。 |
| 收藏详情 → 来源对话 | 先执行既有 source command，再 `context.go('/chat')` | 这是跨顶层 destination 跳转，不保留详情栈。 |
| 恢复页返回 | 能 pop 时 pop；否则 go 到所属父 route | 同时支持正常 push 和直接 deep link。 |

---

## 四、Favorites 详情读取与恢复契约

### 4.1 Repository contract

在 `FavoritesRepository` 增加：

```dart
/// 按 ID 读取单条收藏；记录不存在时返回 null。
Favorite? loadById(String favoriteId);
```

SQLite 实现使用参数化精确查询：

```sql
SELECT * FROM favorites WHERE id = ? LIMIT 1;
```

禁止事项：

- 不用 `loadAll().where(...)` 代替 SQL 精确查询；
- 不抛“记录不存在”异常；不存在是详情路由的正常可恢复状态；
- 不改变 schema、migration 或 Favorite domain model；
- 不引入缓存，SQLite 仍是详情事实源。

### 4.2 `favoriteByIdProvider`

provider 必须与当前 filtered 列表解耦，但要在 Favorites mutations 后重新读取：

```dart
final favoriteByIdProvider = Provider.family<Favorite?, String>((ref, id) {
  ref.watch(favoritesProvider); // 仅作为 add/remove/move/rename 的失效信号
  return ref.watch(favoritesRepositoryProvider).loadById(id);
});
```

可采用等价实现，但必须同时满足以下行为：

1. 当前 filter 为另一个收藏夹时，仍能按 ID 打开详情；
2. rename 后详情标题立即更新；
3. move 后详情 collection 立即更新，即使移动后该收藏不再属于当前 filter；
4. remove 后 provider 返回 null；
5. 直接打开旧 ID 时不依赖 FavoritesScreen 曾经 build。

不得把 `favoritesProvider` 当前列表本身当作 by-ID 唯一数据源；它受 `favoritesFilterProvider` 影响，会漏掉合法收藏。

### 4.3 `FavoriteDetailScreen` 状态

构造器改成：

```dart
const FavoriteDetailScreen({required this.favoriteId, super.key});
final String? favoriteId;
```

页面 build 的确定分支：

| 输入/读取结果 | 页面标题 | 内容 | 操作 |
|---|---|---|---|
| `favoriteId == null` 或 `trim().isEmpty` | `收藏详情` | `AppEmptyState`：标题“收藏链接无效”，说明“链接中缺少有效的收藏 ID。” | “返回收藏列表” |
| ID 非空、`favoriteByIdProvider(id) == null` | `收藏详情` | `AppEmptyState`：标题“收藏不存在”，说明“这条收藏可能已被删除。” | “返回收藏列表” |
| 找到 Favorite | 当前自定义标题或“收藏详情” | 原 `FavoriteCard`、reasoning、collection、source metadata | 原 rename/move/delete/source actions |

恢复 UI 是页面正文，不是 dialog、SnackBar 或 notification bubble。动作规则：

```text
if GoRouter canPop -> pop
else -> go(AppDestination.favorites.path)
```

正常详情分支删除本地 `late Favorite _favorite` 与 `_refreshFavorite()`。所有 dialog/action 方法都接收 build 时的当前 `Favorite`，mutation 后由 provider 重读：

- `_showRenameDialog(context, favorite)`；
- `_showMoveDialog(context, favorite, collections)`；
- `_confirmDelete(context, favorite.id)`；
- `_goToConversation(context, favorite)`。

删除确认成功后仍 pop；来源对话仍先执行 `favoriteSourceConversationCommandProvider` 再 go chat。不得改变收藏业务规则、对话定位或确认文案。

### 4.4 Favorites navigation source

`favorites_screen.dart` 的 item callback 改为：

```dart
onTap: () => context.pushNamed(
  AppRouteName.favoriteDetail,
  pathParameters: {
    AppRouteParameter.favoriteId: favorite.id,
  },
),
```

不传 `extra`，不手工 encode ID，不捕获整个 `Favorite` 给 route builder。

---

## 五、Media routed adapter 与恢复契约

### 5.1 为什么新增 routed adapter，而不改 leaf page 产品 API

`ImageViewerPage` 的 leaf contract 是“给定有序 URL 列表与初始 index，展示画廊”；`VideoPlayerPage` 的 leaf contract 是“给定 URL 与文件名，播放视频”。这两个 contract 已有大量手势、资源释放和错误测试，不应为路由重写。

新增 `lib/features/media/presentation/pages/media_route_pages.dart`，包含：

- `MediaImageRoutePage`：`relativePath + MediaBrowserState -> ImageViewerPage/恢复页`；
- `MediaVideoRoutePage`：`relativePath + MediaBrowserState -> VideoPlayerPage/恢复页`；
- 私有或同文件共享的 media route recovery scaffold。

`MediaVideoRoutePage` 暴露与 leaf page 相同的可选 `VideoPlayerController Function(Uri)? controllerFactory`，正常 production route 不传，route-page widget test 传 shared fake。这个参数只替换播放器 platform adapter，不成为 route state，也不得写入 URL/provider。

依赖方向为 `media presentation -> media application/domain/utils`，不导入 data 或 core persistence，符合现有架构门禁。

### 5.2 相对路径验证

在 `lib/features/media/utils/path_utils.dart` 增加一个纯函数，语义固定为：

```text
输入 null / 空 / 仅空白             -> invalid
不以 / 开头                         -> invalid
去掉首尾/重复分隔后没有文件段        -> invalid
任一路径段精确等于 . 或 ..           -> invalid
其他                                -> 返回规范化、以 / 开头的路径
```

路径中的中文、空格、`..` 作为普通文件名子串（例如 `photo..jpg`）必须保留；只拒绝完整的 `.`/`..` 段。该函数只验证 route contract，不做文件系统访问。

新增/复用 URI helper，用 `MediaServerInfo` 的可信 `ip/httpPort` 与合法 relative path 构建 image/video URL。URL 编码只发生一次；测试必须覆盖中文与空格。禁止把 query 中的 path 当成完整 URL，也禁止读取 query host/port。

### 5.3 `MediaImageRoutePage` 分支

| 条件 | 结果 |
|---|---|
| path 缺失/非法/扩展名不是图片 | 恢复页：“媒体链接无效” |
| `mediaBrowserControllerProvider.server == null` | 恢复页：“媒体会话已失效”，提示返回 Sync 重新连接 |
| server 存在，target 在当前 `state.items` 图片集合中 | 按当前 items 顺序构造全部 image URLs，以 target 的 index 打开 `ImageViewerPage` |
| server 存在，target 不在当前图片集合中 | 用 target 构造单元素 URL 列表、index 0；资源若已删除，由 `ImageViewerPage` 现有 broken-image 状态呈现，仍可返回 |

这里不把“当前目录列表为空”直接当成 route error，因为 direct link/rebuild 时内存列表可能尚未恢复，但可信 server + 合法 path 已足以尝试单图。不得为了恢复画廊而把完整列表持久化到 URL/SharedPreferences。

### 5.4 `MediaVideoRoutePage` 分支

| 条件 | 结果 |
|---|---|
| path 缺失/非法/扩展名不是视频 | 恢复页：“媒体链接无效” |
| media server 缺失 | 恢复页：“媒体会话已失效” |
| server + path 合法 | 用可信 server 重建 video URL；文件名取 path 最后一个 segment；构造 `VideoPlayerPage` |
| 文件已删除/服务端不可达 | 沿用 `VideoPlayerPage` 现有 inline 加载失败 + 重试 + 返回行为 |

不得用 `state.items` 强制验证 video 一定存在，因为随机播放列表可能来自递归接口，当前目录 `items` 不一定包含目标视频。

### 5.5 恢复页返回行为

媒体恢复页使用 `Scaffold + AppBar + AppEmptyState`，至少包含：

- 标题：图片用“图片查看”，视频用“视频播放”；
- 清楚的失效原因；
- `FilledButton` 文案“返回局域网同步”；
- 有父 route 可 pop 时 pop，否则 go `/sync`。

不得在恢复页自动 redirect。自动 redirect 会让测试与用户看不到原因，并可能在 direct deep link 时形成反复导航。

### 5.6 两个导航发起方

#### `MediaBrowserTab`

- 目录点击仍调用 `controller.navigateTo`；
- 图片点击不再计算/传递 `imageUrls`，只传被点击 `FileItem.relativePath`；
- 视频点击只传 `relativePath`；
- server 缺失时不导航，保持当前防御行为；
- 删除 `_buildMediaUrl` 和 `Navigator.push(MaterialPageRoute(...))`。

#### `ShuffleAppBarActions`

- `startShuffle` / `playNext` / `playPrevious` 的 application contract 暂不改；返回 URL 仍可作为成功/null 判定，避免扩大 controller 回归面；
- 当 state 为 `ShufflePlaybackActive` 时，从 `state.currentVideo.relativePath` 传给 `AppRouteName.mediaVideo`；
- `_navigateToPlayer` 必须 `await context.pushNamed(...)`；Future 完成后且 context 仍 mounted，调用原 `controller.onPlayerExited()`；
- 不因改路由丢失“退出最后一条视频后回 Idle”的现有语义。

### 5.7 leaf page 返回

`ImageViewerPage`/`VideoPlayerPage` 当前通过所在 Navigator pop 返回；它们被 GoRouter 创建的 page 承载后仍只 pop 当前 page，不会形成第二套 push 栈。本 Phase 的硬性删除对象是 feature 内的 `Navigator.push(MaterialPageRoute)`，不要求为了形式统一把 dialog/leaf 内部的 `Navigator.pop` 全部改写。

同时更新 `image_viewer_page_test.dart` 中“通过 Navigator.push 进入”的过时注释，使测试描述只陈述“关闭当前 routed page 后返回父页面”，不保留已不存在的实现说明。

---

## 六、文件改动清单

### 6.1 新增生产文件

| 文件 | 职责 |
|---|---|
| `lib/features/media/presentation/pages/media_route_pages.dart` | 将可序列化 media relative path + 当前可信媒体会话解析成现有 viewer/player，或展示恢复状态。 |

### 6.2 修改生产文件

| 文件 | 精确修改 |
|---|---|
| `lib/app/navigation/app_destination.dart` | 增加非顶层 route names 与 parameter keys；不改变 `AppDestination.values`。 |
| `lib/app/router/app_router.dart` | 提取可测试 router factory；favorites/sync 下挂子路由；删除 Favorite domain import/extra cast；接入 media routed pages。 |
| `lib/features/favorites/application/ports/favorites_repository.dart` | 增加 `Favorite? loadById(String favoriteId)`。 |
| `lib/features/favorites/data/sqlite_favorites_repository.dart` | 参数化实现 `loadById`，复用 `_rowToFavorite`。 |
| `lib/features/favorites/application/favorites_controller.dart` | 增加 `favoriteByIdProvider`，以 repository 精确读取、以 favorites state 作为 mutation 失效信号。 |
| `lib/features/favorites/presentation/favorites_screen.dart` | item tap 改用 favorite detail named route/path parameter。 |
| `lib/features/favorites/presentation/favorite_detail_screen.dart` | 构造器改收 ID；删除本地 Favorite 镜像；增加 invalid/not-found 恢复 UI；CRUD 读取当前 provider value。 |
| `lib/features/media/utils/path_utils.dart` | 增加 media route path validation、文件名/可信资源 URL helper（按最终最小实现选择拆分函数）。 |
| `lib/features/media/presentation/media_browser_tab.dart` | 两种文件点击改用 media named route；删除 MaterialPageRoute 和 URL/list 组装。 |
| `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart` | 随机播放入口改用同一 video route，保留 awaited exit callback。 |
| `lib/features/media/application/shuffle_playback_controller.dart` | 仅在 URL helper 被集中时改为复用；不改变 public state/method/result。 |
| `lib/features/media/presentation/pages/image_viewer_page.dart` | 原则上不改；只有 routed adapter 暴露出的直接、必要兼容修复才允许。 |
| `lib/features/media/presentation/pages/video_player_page.dart` | 原则上不改；不重写 playback/gesture/lifecycle。 |
| `lib/app/shell/app_shell_scaffold.dart` | **不修改**；列入审查范围仅为了确认 shell 条件未触发。 |

### 6.3 新增/修改测试文件

| 文件 | 覆盖内容 |
|---|---|
| `test/app/router/app_router_test.dart`（新增） | 生产 route matrix、direct favorite URL、fresh router rebuild、not-found/invalid、favorite/media push-pop 与 URL 参数。 |
| `test/features/favorites/data/sqlite_favorites_repository_test.dart` | `loadById` found/missing，字段完整 round-trip。 |
| `test/features/favorites/application/favorites_controller_test.dart` | by-ID 跨 filter、rename/move/remove 后重读。 |
| `test/features/favorites/favorites_screen_test_helpers.dart` | 测试 route 改为 ID contract；删除 Favorite extra cast。 |
| `test/features/favorites/favorites_screen_detail_cases.dart` | 保留正常详情行为，补 invalid/deleted/direct reconstruction 所需 cases（可与 app router test 分工，避免重复）。 |
| `test/features/favorites/favorites_screen_basics_cases.dart` | item tap 后 route/detail 行为保持。 |
| `test/features/media/utils/path_utils_test.dart` | null/blank/no-leading-slash/dot-segment/中文空格/编码一次。 |
| `test/features/media/presentation/media_route_pages_test.dart`（新增） | image gallery/single fallback、video URL/name、missing path、session missing、返回 recovery。 |
| `test/features/media/presentation/media_browser_navigation_test.dart`（新增） | 点击图片/视频后 GoRouter URI 变化、页面出现、pop 回浏览器。 |
| `test/features/media/presentation/shuffle_appbar_actions_test.dart`（新增或扩展合适现有文件） | video route 使用 current relativePath；pop 完成后调用 `onPlayerExited`。 |
| `test/features/media/helpers/fake_video_player_controller.dart`（新增） | 从现有 video player test 提取可复用 fake，供 leaf 与 routed adapter tests 共用；不复制第二份 fake。 |
| `test/features/media/presentation/image_viewer_page_test.dart` | 只更新已过时的导航描述；原手势/画廊测试保持。 |
| `test/features/media/presentation/video_player_page_test.dart` | 删除文件内 fake 定义并 import shared fake；其余 leaf 行为测试保持。 |
| `test/app/shell/app_shell_scaffold_test.dart` | 原 top-level go 行为保持；不新增“必须保活所有页面”的测试。 |

如果执行者发现不需要修改某个“原则上不改”的文件，应保持未修改，不能为了符合清单制造无意义 diff。

---

## 七、分任务实施顺序

### Task 1：收藏详情形成完整 ID vertical slice

**目标：** 不依赖任何列表页内存对象，直接打开 `/favorites/:id` 能从 SQLite 恢复详情；无效/已删除 ID 有稳定页面状态。

#### Step 1：先写 repository 与 provider 红灯测试

1. 在 repository test 增加：
   - 保存一条 Favorite 后 `loadById(id)` 返回字段完整对象；
   - 不存在 ID 返回 null；
   - 两条记录时读取目标 ID，不依赖 createdAt 排序。
2. 在 application test 增加：
   - filter 选中 collection A，但 by-ID 仍能读取 collection B 的 favorite；
   - rename 后 by-ID title 更新；
   - move 后 by-ID collectionId 更新；
   - remove 后 by-ID 为 null。
3. 红灯应是缺少 method/provider 或行为不满足；不得用 `skip`、conditional return 或放宽 expect。

单文件验证命令：

```powershell
flutter test test/features/favorites/data/sqlite_favorites_repository_test.dart test/features/favorites/application/favorites_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-favorites-data.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-favorites-data.log
```

#### Step 2：实现 repository 与 by-ID read model

1. 修改 application-owned repository port；
2. 修改唯一 concrete `SqliteFavoritesRepository`；当前仓库没有其他 `implements FavoritesRepository` fake，无需创建无价值 fake；
3. 增加 `favoriteByIdProvider`；
4. 运行 Step 1 tests 到 `EXIT=0`；
5. 执行 `rg -n "implements FavoritesRepository" lib test`，确认所有实现已同步。

#### Step 3：写详情 route/recovery 红灯测试

在 `test/app/router/app_router_test.dart` 使用真实内存 DB、`pumpTestApp` production composition 和可测试 router factory，覆盖：

1. **direct URL：** seed `fav-direct`，直接以 `initialLocation: '/favorites/fav-direct'` 创建 router，不传 extra，显示完整用户/助手内容；
2. **fresh rebuild：** 记录同一 URL，dispose 第一个 router，使用同一 database/preferences 创建全新 router + widget tree，仍显示详情；此 case 才是“重建后不依赖 extra”的证据；
3. **invalid ID：** `/favorites/%20` 进入“收藏链接无效”；
4. **deleted/missing：** seed 后通过 repository API 删除，再直接打开旧 URL，进入“收藏不存在”；
5. **normal push/back：** 从 FavoritesScreen 点击 item，GoRouter URI 变为 `/favorites/<id>`；点击 app bar back，回到 `/favorites` 与原列表；
6. **delete from detail：** 确认删除后回列表，repository `loadById` 为 null；
7. **source conversation：** 既有 test 继续证明 command + go chat，不把来源跳转改成 detail pop。

测试不得检查 `state.extra` 内部字段；应通过 direct location、可见文案、router URI 和 repository 结果证明 contract。

#### Step 4：实现 app route + FavoriteDetailScreen

按第三、四节 contract 修改 route constants、router、FavoritesScreen、FavoriteDetailScreen 与测试 helper。注意顺序：

1. 本 Task 只加入 `favoriteDetail` / `favoriteId` 常量；`mediaImage` / `mediaVideo` / `mediaPath` 留到 Task 2，保证第一个 commit 不夹带媒体 contract；
2. 先让 detail screen 接受 nullable ID 并能渲染 recovery；
3. 再把 production/custom test route builder 改成 path ID；
4. 最后替换列表页 navigation source；
5. 删除 `app_router.dart` 对 Favorite domain model 的 import；
6. 删除 `_favorite`、`_refreshFavorite()` 与文档中“通过 GoRouter extra 接收”的过时说明。

#### Step 5：范围审计与提交

```powershell
rg -n "state\.extra|extra:\s*favorite|FavoriteDetailScreen\(favorite:" lib/app lib/features/favorites test/features/favorites test/app
rg -n "'/favorites/detail'|\"/favorites/detail\"" lib test
```

两条命令在 Phase 12 相关路径内应无旧 contract 命中。然后格式化本任务 Dart 文件并提交：

```bash
git add lib/app/navigation/app_destination.dart \
        lib/app/router/app_router.dart \
        lib/features/favorites/application/ports/favorites_repository.dart \
        lib/features/favorites/application/favorites_controller.dart \
        lib/features/favorites/data/sqlite_favorites_repository.dart \
        lib/features/favorites/presentation/favorites_screen.dart \
        lib/features/favorites/presentation/favorite_detail_screen.dart \
        test/app/router/app_router_test.dart \
        test/features/favorites/application/favorites_controller_test.dart \
        test/features/favorites/data/sqlite_favorites_repository_test.dart \
        test/features/favorites/favorites_screen_test_helpers.dart \
        test/features/favorites/favorites_screen_basics_cases.dart \
        test/features/favorites/favorites_screen_detail_cases.dart
git status --short
git diff --cached --name-only
git commit -m "refactor(favorites): 以 ID 恢复收藏详情路由"
```

提交只包含 Task 1 文件和 hook 自动产生的 `pubspec.yaml` 版本变化；不得包含 `.opencode/plans` 删除或 media 改动。

---

### Task 2：媒体 viewer/player 纳入 GoRouter 子路由

**目标：** 所有媒体页面入口共享 `/sync/media/*` route matrix，只携带 relative path，并在 session/参数缺失时恢复。

#### Step 1：写 path 与 routed adapter 红灯测试

1. `path_utils_test.dart` 参数化覆盖：
   - `null`、`''`、空白；
   - `photo.jpg`（缺 leading slash）；
   - `/a/../b.jpg`、`/./b.jpg`；
   - `/相册/我的 猫.jpg`；
   - `/a/photo..jpg` 合法；
   - 构造的资源 URL 中文/空格只编码一次。
2. `media_route_pages_test.dart` 使用 seeded `mediaBrowserControllerProvider`：
   - 两张当前目录图片，target 为第二张，出现 `2 / 2`；
   - target 不在 items 时显示单图且不崩溃；
   - video path 通过 optional controller factory 使用 shared fake，成功初始化并显示正确文件名；测试不访问真实网络/platform channel；
   - path null/非法/类型不匹配显示“媒体链接无效”；
   - server null 显示“媒体会话已失效”；
   - recovery button 回 `/sync`。

#### Step 2：实现 media route pages

1. 增加 pure path validation/URI helper；
2. 增加 `media_route_pages.dart`；
3. 将现有 `video_player_page_test.dart` 的 fake controller 原样提取到 shared test helper，并让原测试先恢复全绿；
4. 使用 `ref.watch(mediaBrowserControllerProvider)` 获取可信 server/items；
5. 图片正常路径复用 `ImageViewerPage`，视频正常路径复用 `VideoPlayerPage`，仅把可选 controller factory 原样下传；
6. 不修改图片缩放、视频 gesture、orientation、system UI、controller dispose；
7. 运行 routed adapter tests 到 `EXIT=0`。

#### Step 3：把 routes 加入生产 router

先在 `app_destination.dart` 增加 `mediaImage` / `mediaVideo` / `mediaPath` 常量，再在 `/sync` 的 `routes` 下增加两个相对子路由。测试 `createAppRouter`：

1. `pushNamed(mediaImage, queryParameters: {'path': '/相册/猫.jpg'})` 后 URI path 为 `/sync/media/image`，decoded query path 等于原始字符串；
2. `pushNamed(mediaVideo, ...)` 同理；
3. 两个 route 的 `state.extra` 都不需要；
4. 缺 query 仍匹配 route 并显示 recovery，而不是抛 builder 异常；
5. pop 后回 `/sync`。

#### Step 4：迁移 MediaBrowserTab

新增 `media_browser_navigation_test.dart`，测试使用最小 GoRouter parent + production routed pages、seeded media state；video child builder 把 shared fake factory传给 `MediaVideoRoutePage`，不访问 platform channel：

1. 点击图片文件名，router URI 包含 `media/image` 与原始 relative path，显示 viewer；
2. back 后同一浏览列表可见；
3. 点击视频文件名，router URI 包含 `media/video`，显示对应文件名；
4. back 后回浏览页；
5. 点击 directory 仍只改变 browser path，不产生 media child route；
6. server null 时点击媒体文件不导航。

随后替换生产 `Navigator.push(MaterialPageRoute)`，删除浏览页中的 URL/list 构造与无用 imports。

#### Step 5：迁移 ShuffleAppBarActions 并保留 exit contract

新增/扩展 widget test；其最小 GoRouter 的 video child 同样注入 shared fake factory：

1. seeded active playlist 至少两条；
2. 点“下一个”后 controller currentIndex 前进，router 打开 `mediaVideo` 且 query path 等于新的 `currentVideo.relativePath`；
3. pop player；
4. recording controller 证明 `onPlayerExited()` 恰好调用一次；
5. context 在等待期间卸载时不调用 disposed UI，但 controller lifecycle 不产生异常。

实现中只迁导航，不改 shuffle/random/index/URL 返回 contract。

#### Step 6：运行 media 定向回归

```powershell
flutter test test/features/media/utils/path_utils_test.dart test/features/media/presentation/media_route_pages_test.dart test/features/media/presentation/media_browser_navigation_test.dart test/features/media/presentation/shuffle_appbar_actions_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-media-routes.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-media-routes.log
flutter test test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/application/shuffle_playback_controller_behavior_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-media-leaf.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-media-leaf.log
flutter test test/features/sync/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-sync-workspace.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-sync-workspace.log
```

每条预期 `EXIT=0`。若测试文件最终采用不同的最小组织，命令同步为真实路径，但仍必须重定向。

#### Step 7：静态审计与提交

```powershell
rg -n "Navigator\.push|MaterialPageRoute|state\.extra|extra:" lib/features/media/presentation lib/app/router
rg -n "MediaServerInfo|host|httpPort|imageUrls|videoUrl" lib/app/router lib/app/navigation
```

判读规则：

- 第一条在 media production navigation source 中不得再命中 push/MaterialPageRoute/extra；dialog pop 不在检查对象内；
- 第二条不得显示 app route contract 携带 server authority、URL list 或 absolute media URL；route builder 只应传 relative path；
- `VideoPlayerPage(videoUrl: ...)` 在 routed adapter 内是允许命中，因为它是 URL 解析后的 leaf contract，不是 URL route 参数。

提交：

```bash
git add lib/app/navigation/app_destination.dart \
        lib/app/router/app_router.dart \
        lib/features/media/application/shuffle_playback_controller.dart \
        lib/features/media/presentation/media_browser_tab.dart \
        lib/features/media/presentation/pages/media_route_pages.dart \
        lib/features/media/presentation/widgets/shuffle_appbar_actions.dart \
        lib/features/media/utils/path_utils.dart \
        test/app/router/app_router_test.dart \
        test/features/media/presentation/image_viewer_page_test.dart \
        test/features/media/presentation/media_browser_navigation_test.dart \
        test/features/media/presentation/media_route_pages_test.dart \
        test/features/media/presentation/shuffle_appbar_actions_test.dart \
        test/features/media/helpers/fake_video_player_controller.dart \
        test/features/media/presentation/video_player_page_test.dart \
        test/features/media/utils/path_utils_test.dart
git status --short
git diff --cached --name-only
git commit -m "refactor(media): 统一媒体查看与播放路由"
```

如果 `shuffle_playback_controller.dart` 最终没有为复用 URL helper 而修改，或现有 leaf test 没有实际 diff，先从上面的 `git add` 参数中删除对应路径；禁止为了让命令成功制造空改动。提交只包含 Task 2 与 hook version bump。

---

### Task 3：验证 shell 条件未触发并完成全量门禁

**目标：** 以已有 ownership tests 证明 flat top-level routes 仍满足当前 UX；不创建无证据的 shell diff。

#### Step 1：运行 Phase 10 恢复证据

```powershell
flutter test test/features/chat/chat_screen_test.dart --plain-name "ChatScreen 卸载后在同 scope 重挂，body 草稿恢复" --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-chat-remount.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-chat-remount.log
flutter test test/features/chat/chat_screen_test.dart --plain-name "编辑后卸载重挂丢弃编辑模式，草稿恢复为会话级值" --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-chat-edit-remount.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-chat-edit-remount.log
```

两条均 `EXIT=0` 即为“不触发 StatefulShellRoute”的当前行为证据。不要新增“切页后滚动 controller 必须是同一实例”之类实现细节测试。

#### Step 2：route matrix 集成回归

```powershell
flutter test test/app/router/app_router_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/favorites/favorites_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-navigation.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-navigation.log
```

必须覆盖并通过：

- favorite direct/rebuild/invalid/deleted/push/back；
- media image/video push/back/missing path/session；
- desktop rail 与 compact navigation bar 仍切换顶层 destination；
- favorite 来源对话仍 go chat；
- Sync Android media session init/reset 仍保持 Phase 7/6 语义。

#### Step 3：生产代码范围审计

```powershell
rg -n "state\.extra\s+as\s+Favorite|extra:\s*favorite|/favorites/detail" lib test
rg -n "Navigator\.push|MaterialPageRoute" lib/features/media/presentation
rg -n "StatefulShellRoute|StatefulNavigationShell" lib/app
rg -n "features/.*/data|core/persistence" lib/features/favorites/presentation lib/features/media/presentation
```

预期：

1. 旧 favorite extra contract 零命中；
2. media feature 不再有页面 push/MaterialPageRoute；
3. app 仍无 StatefulShellRoute（这是本次明确判定结果，不是遗漏）；
4. 新 routed pages 不穿透 data/persistence。

`showDialog` 内部 `Navigator.pop`、viewer/player 自身 pop 不是第二套 push 栈，不应机械删除。

#### Step 4：格式化与暂存后复检

```powershell
git diff --name-only -- '*.dart'
dart format <上一步列出的本 Phase Dart 文件>
git diff --check
```

暂存时使用精确文件列表，先检查：

```powershell
git status --short
git diff --cached --name-only
```

确认 `.opencode/plans/*.md` 删除不在 staged set。随后对 staged Dart 文件执行：

```powershell
dart format --output=none --set-exit-if-changed <全部 staged Dart 文件>
```

非零退出不得提交。

#### Step 5：架构门禁与 analyze

```powershell
flutter test test/architecture/import_boundary_checker_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase12-architecture.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase12-architecture.log
flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase12.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase12.log
```

预期均 `EXIT=0`，analyze 输出 `No issues found!`。

#### Step 6：强制格式全量测试

严格使用项目规定的一条复合命令：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

- `EXIT=0`：通过；
- `EXIT≠0`：先用 `Select-String -Pattern " -[1-9]" -Path fltest.log` 定位失败，再只修复本 Phase 引入的回归；
- 禁止直接运行不重定向的全量 `flutter test`，禁止用 `tee`。

#### Step 7：最终提交策略

正常情况下 Task 1、Task 2 已分别形成完整提交，Task 3 不应产生生产代码。如果最终门禁发现本 Phase 自身回归，使用最小独立提交：

```bash
git commit -m "fix(navigation): 修复可恢复路由回归"
```

不得把 shell migration、UI redesign、媒体播放增强或 unrelated lint cleanup 放入该提交。

---

## 八、测试矩阵

### 8.1 Favorites

| 场景 | 输入 | 可观察结果 | 测试层 |
|---|---|---|---|
| 列表正常打开详情 | tap favorite | URI 含 ID；详情完整 | Widget/router |
| direct deep link | 初始 `/favorites/<id>`，无 extra | 详情完整 | Router widget |
| fresh router rebuild | 新 GoRouter + 同 URL/DB | 详情仍完整 | Router widget |
| invalid ID | blank decoded path parameter | “收藏链接无效” + 返回 | Router widget |
| missing ID entity | 合法非空 ID，DB 无记录 | “收藏不存在” + 返回 | Provider/router |
| deleted bookmark | 旧 URL 对应记录已删 | 同 missing state，不崩溃 | Repository/router |
| active filter excludes entity | filter A，detail 属于 B | 仍显示 B | Application |
| rename | detail 内确认新标题 | app bar/card 使用新标题 | Widget/provider |
| move out of active filter | detail 内移动 | detail 保持、collection 更新 | Widget/provider |
| delete from pushed detail | 确认删除 | pop 回列表，DB null | Widget/repository |
| source conversation | 点击来源 | command 收到 IDs，go chat | Existing widget/command |

### 8.2 Media

| 场景 | 输入 | 可观察结果 | 测试层 |
|---|---|---|---|
| 图片点击 | current FileItem relativePath | GoRouter image URI，正确 initial index | Widget/router |
| 图片 direct route + active session | path query + server | viewer 可重建 | Route page |
| 图片不在 current items | valid path + server | 单图 fallback | Route page |
| 图片缺 path | 无 query | recovery，不抛异常 | Router widget |
| 图片 session 失效 | valid path + server null | session recovery | Route page |
| 视频点击 | video relativePath | GoRouter video URI，文件名正确 | Widget/router |
| 视频 service failure | valid route，资源不可达 | 现有 inline error/retry | Existing leaf + route smoke |
| 随机播放 next/prev | active playlist | route path 使用新 current video | Widget/application |
| player pop | GoRouter child pop | 回 media parent；exit callback 一次 | Widget/router |
| path traversal | `/a/../b.mp4` | invalid recovery，不构造 URL | Unit/route page |
| 中文/空格 | `/相册/我的 猫.jpg` | query round-trip；resource URL 单次编码 | Unit/router |

### 8.3 Shell 条件

| 场景 | 预期 | 证据 |
|---|---|---|
| Chat widget 销毁/重建 | session draft 恢复 | Phase 10 existing test |
| 编辑中销毁/重建 | editing 瞬态丢弃，普通 draft 恢复 | Phase 10 existing test |
| Sync media tab 离开 | media/shuffle session reset | Existing Sync screen test |
| 顶层 navigation | rail/bar 继续 go destinations | Existing AppShell test |
| Stateful shell | 不存在 | 触发条件矩阵 + final grep |

---

## 九、提交序列与回滚

| 顺序 | Commit | 独立价值 | 回滚影响 |
|---|---|---|---|
| 1 | `refactor(favorites): 以 ID 恢复收藏详情路由` | 收藏 URL 可直接恢复，missing/deleted 安全。 | 只回退 Favorites 详情 contract，不影响 media。 |
| 2 | `refactor(media): 统一媒体查看与播放路由` | 两个媒体入口进入同一 GoRouter 子栈。 | 只回退媒体 navigation，不影响 favorite ID。 |
| 3（仅必要） | `fix(navigation): 修复可恢复路由回归` | 最终门禁最小修复。 | 按具体修复独立回退。 |

每次 commit 都会触发 post-commit version bump；不要手工预改版本。提交用 Bash、多段 message 用多个 `-m`，不得使用 PowerShell here-string。

回滚原则：

- Favorites 与 Media 两个 vertical slice 不合并到一个巨型 commit；
- 任何回滚都不得恢复 `state.extra as Favorite` 或 `MaterialPageRoute` 作为“临时兼容”；如果必须回滚，应整体回滚对应 commit；
- 不提供旧 `/favorites/detail` 兼容 redirect。新动态 ID route 会把 `detail` 当作普通 ID 并稳定进入“收藏不存在”恢复页；不得猜测或恢复旧 extra。

---

## 十、风险、停止条件与禁止扩展

### 10.1 主要风险与控制

| 风险 | 控制 |
|---|---|
| by-ID provider 因 filter 漏实体 | repository 精确查询，filter list 只作 invalidation signal。 |
| 详情本地对象陈旧 | 删除 `_favorite` 镜像，build 只用 provider 当前值。 |
| query path 双编码 | `pushNamed(queryParameters: rawPath)`；只在资源 URL helper 编码 path segments。 |
| media deep link 注入任意 host | route 不接收 host/port/src，authority 只来自 active trusted session。 |
| gallery rebuild 丢 sibling list | active session 用 current items；无列表降级单图，不持久化大列表。 |
| shuffle pop 后状态不清理 | 保持 await route Future + mounted check + `onPlayerExited()`。 |
| nested child direct open 无返回目标 | child route 同时构建 parent；recovery action仍提供 pop-or-go fallback。 |
| shell 误保活纯瞬态状态 | 本次不迁 StatefulShellRoute；已有 ownership tests 作门禁。 |
| 新 routed page 穿透 data | 只 import media application/domain/utils；运行 architecture checker。 |

### 10.2 必须停止并请求重新定界的情况

执行者遇到以下任一情况时不得自行扩大实现：

1. 为恢复 media route 需要持久化 peer IP、port、pairing credential 或整个媒体列表；这属于 Sync/session/security 设计，不是本 Phase 可顺手加入的 route 参数。
2. 发现必须改变 `ImageViewerPage` 缩放/PageView 或 `VideoPlayerPage` playback/gesture/orientation 才能接路由；先证明 routed adapter 无法适配，再单独报告。
3. 出现真实顶层状态丢失 UX，且现有 Phase 10/Sync ownership 无法恢复；先提交失败行为测试与影响矩阵，不能直接开始 StatefulShellRoute 迁移。
4. 需要修改 Favorite schema/domain/business rules 才能 loadById；当前设计只需 repository 查询，出现该需求说明范围已偏离。
5. 需要让 feature presentation import data/core persistence；应修正边界设计，而不是加入 architecture allowlist。

### 10.3 严格 Out of Scope

- 不修改 Chat generation、消息树、Prompt 顺序、streaming、inline error 或收藏业务规则；
- 不改变 Favorites model/schema、collection cascade 或标题生成；
- 不增强 media playback、shuffle 算法、thumbnail、HTTP handler 或资源生命周期；
- 不迁移 `StatefulShellRoute`、不新增 branch navigator/global key；
- 不重做 AppShell 视觉/响应式断点；
- 不提前实施 Phase 13/14/16 的响应式、可访问性或 device smoke；
- 不清理与路由无关的存量测试反模式或注释；
- 不处理用户现有 `.opencode/plans` 删除。

---

## 十一、完成定义（Definition of Done）

- [ ] `/favorites/:favoriteId` 是唯一收藏详情 production route；旧 `/favorites/detail` 和 Favorite extra contract 已删除。
- [ ] `FavoritesRepository.loadById`、SQLite 实现、by-ID provider 与 tests 完整。
- [ ] 详情 direct URL、fresh router rebuild、invalid ID、missing/deleted ID、正常 push/back 均有行为测试。
- [ ] FavoriteDetailScreen 不保存 route 传入 Favorite 镜像；rename/move/delete 后读取结果一致。
- [ ] 图片与视频分别位于 `/sync/media/image`、`/sync/media/video` 子路由，URL 只携带 relative path query。
- [ ] MediaBrowserTab 与 ShuffleAppBarActions 不再调用 `Navigator.push(MaterialPageRoute)`。
- [ ] media path 缺失/非法、server/session 缺失都有页面级恢复 UI 和返回操作。
- [ ] 图片正常画廊、single fallback、视频播放/错误、shuffle exit lifecycle 保持现有产品行为。
- [ ] `AppDestination.values` 未增加详情/media；NavigationRail/NavigationBar 仍只显示五个顶层入口。
- [ ] StatefulShellRoute 触发条件已明确判定为未触发；未产生 shell migration diff。
- [ ] 新 routed pages 通过 import boundary checker。
- [ ] 所有改动 Dart 文件已 format，staged 后格式复检通过。
- [ ] `flutter analyze` 为 `EXIT=0`。
- [ ] 全量测试按重定向规范执行并得到 `EXIT=0`。
- [ ] commits 按 Favorites/Media 两个 vertical slice 分开，未包含现有 unrelated worktree 改动。
