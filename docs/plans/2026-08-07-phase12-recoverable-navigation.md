# 可恢复导航契约（Phase 12）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让收藏详情与媒体查看/播放页面通过 URL 契约可恢复——`/favorites/:favoriteId` 与 `/sync/media/image|video?path=...`，参数缺失/实体不存在时显示可返回的页面级恢复状态，并确认不迁移 `StatefulShellRoute`。

**Architecture:** 收藏详情从「列表页内存对象 + `state.extra`」改为「路径 ID + 按 ID 的 repository 精确读取（`favoriteByIdProvider`）」。媒体查看/播放从 feature 内 `Navigator.push(MaterialPageRoute)` 平行栈改为 GoRouter 子路由，URL 只携带媒体相对路径，网络 authority 继续只来自 `mediaBrowserControllerProvider.server` 的可信会话。新增 routed adapter 页面解析「relative path + 可信会话」为现有 leaf page（`ImageViewerPage` / `VideoPlayerPage`）或恢复页，不改写 leaf page 功能。顶层保持平铺 `GoRoute`，不引入 `StatefulShellRoute`。

**Tech Stack:** Flutter ≥ 3.11.5 / Dart ≥ 3.x · go_router 17.4.0（`pubspec.lock` 锁定）· Riverpod 3（`NotifierProvider` / `Provider.family`）· `sqlite3`（原始包，同步 API）· 测试框架 `flutter_test`

## Global Constraints

- **路由契约**：route 参数类型用 `String?` 进入 routed screen，builder 中不得 `!` 或 `as`；不使用 `extra`；业务代码传原始 `relativePath`，不得预先 `Uri.encodeComponent`（query 编码由 GoRouter/`Uri` 完成，资源 URL 编码只在 helper 内发生一次）。
- **架构门禁**：`favorites/media` 的 presentation 层不得 import `data/` 或 `core/persistence`；routed adapter 只依赖 media application/domain/utils。`AppDestination.values` 保持不变（仍五个顶层入口），详情/media route name 只加入 `AppRouteName` 字符串常量。
- **不实施 `StatefulShellRoute`**：不得新增 shell migration task、不得修改 `app_shell_scaffold.dart` 的顶层切换方式；最终审计确认未误引入即可。
- **不做的事**：不改 Favorite schema/domain/business rules、不改 `ImageViewerPage` 缩放/PageView、不改 `VideoPlayerPage` playback/gesture/orientation、不把媒体列表/host/port 持久化进 URL 或 SharedPreferences、不清理无关存量测试反模式、不 restore/stage/commit 工作区已有的 `.opencode/plans/*.md` 删除改动。
- **测试输出**：所有 `flutter test` 必须重定向（bash 复合命令 `> xxx.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 xxx.log`），禁止直接运行。
- **提交前格式**：对本次改动所有 Dart 文件执行 `dart format`，暂存后 `dart format --output=none --set-exit-if-changed <staged dart 文件>` 非零退出不得提交。
- **提交规范**：Bash 中执行 `git commit`（禁用 PowerShell here-string），多段 message 用多个 `-m`；版本号由 post-commit hook 自动 bump，不手工预改；每个 vertical slice 单独提交。
- **代码注释**：简体中文，写「为什么」不写「做了什么」；禁止出现审查/计划编号引用（如 `Phase 12`、`P1-2`、`第一轮审查` 字样）。
- **架构基线**：代码基线 `1f09bec`；`FavoritesRepository` 当前仓库只有 `SqliteFavoritesRepository` 一个实现，`implements FavoritesRepository` 全量搜索确认后方可继续。

---

## 前置背景（执行者必读）

### 当前相关代码事实

- `lib/app/navigation/app_destination.dart`：`enum AppDestination`（chat/history/favorites/settings/sync），含 `path`/`name`/`label`/`icon`。
- `lib/app/router/app_router.dart`：`appRouterProvider = Provider<GoRouter>` 直接创建 GoRouter；`/favorites/detail` builder 执行 `state.extra as Favorite`（**本次要删除**）；`errorBuilder` 只处理未知 URL。
- `lib/features/favorites/application/ports/favorites_repository.dart`：`favoritesRepositoryProvider`（无默认绑定，抛 `StateError`）+ `abstract interface class FavoritesRepository`，方法 `loadAll/save/delete/moveToCollection/updateTitle/existsByAssistantContent`。
- `lib/features/favorites/data/sqlite_favorites_repository.dart`：唯一实现，`_rowToFavorite(Map)` 可复用。
- `lib/features/favorites/application/favorites_controller.dart`：`favoritesFilterProvider`（`NotifierProvider<String?>`，null=全部/''=未分类）+ `favoritesProvider`（`NotifierProvider<List<Favorite>>`，`FavoritesController` 有 `add/remove/moveTo/rename`，内部 `_refresh()` 按 filter 重读）。
- `lib/features/favorites/presentation/favorite_detail_screen.dart`：`FavoriteDetailScreen({required this.favorite})`，`late Favorite _favorite = widget.favorite` 本地镜像 + `_refreshFavorite()`（**本次要删除**）；dialog 方法 `_showRenameDialog/_showMoveDialog/_confirmDelete/_goToConversation` 全部读写 `_favorite`。
- `lib/features/favorites/presentation/favorites_screen.dart`：item `onTap: () => context.push('/favorites/detail', extra: favorite)`（**本次要改**）。
- `lib/features/media/presentation/media_browser_tab.dart`：图片/视频点击分别 `Navigator.push(MaterialPageRoute(builder: (_) => ImageViewerPage(...)))` / `VideoPlayerPage(...)`（**本次要改**）；`_buildMediaUrl(type, relativePath)` 构造 `http://{ip}:{port}/api/media/{type}/{encodedPath}`；server 为 null 时图片不导航。
- `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`：`_navigateToPlayer` 用 `Navigator.push`，`await` 后 `if (context.mounted) controller.onPlayerExited()`（exit contract 要保留）。
- `lib/features/media/application/shuffle_playback_controller.dart`：`ShufflePlaybackActive.currentVideo`（`VideoItem`，含 `relativePath`）；`startShuffle/playNext/playPrevious` 返回 video URL 作为成功/null 判定（**contract 不改**）；`buildVideoUrl(relativePath)` 内部拼 URL。
- `lib/features/media/utils/path_utils.dart`：只有 `encodeMediaPath`（每段 `Uri.encodeComponent`，根路径返回空串）。
- `lib/features/media/presentation/pages/image_viewer_page.dart`：`ImageViewerPage({imageUrls, initialIndex = 0})`，assert `imageUrls.isNotEmpty` 与 index 边界；broken-image 状态在 `_ZoomableImagePage` 内部。
- `lib/features/media/presentation/pages/video_player_page.dart`：`VideoPlayerPage({videoUrl, fileName, controllerFactory})`——**已有** `controllerFactory`（`VideoPlayerController Function(Uri)?`）注入点，默认 `VideoPlayerController.networkUrl`。
- `lib/features/media/application/media_browser_controller.dart`：`mediaBrowserControllerProvider`（autoDispose `NotifierProvider`），`MediaBrowserState`（`items`/`currentPath`/`server` 等），`initWithServer`/`reset`。
- `lib/features/media/domain/media_file_classification.dart`：`isImageFile(name)` / `isVideoFile(name)` / `extensionFromFileName`。
- `lib/core/widgets/app_empty_state.dart`：`AppEmptyState({icon, title, description, action})`。
- `lib/app/composition/cross_feature_bindings.dart`：`appCompositionOverrides(...)` 绑定 `favoritesRepositoryProvider -> SqliteFavoritesRepository` 等（`pumpTestApp` 自动注入）。
- `test/helpers/test_harness.dart`：`pumpTestApp(tester, {child|router, preferences, database, extraOverrides, ...})` 与 `pumpTestAppScope(...)`（返回可手动管理存活周期的 `ProviderScope`，适合 fresh rebuild 测试）。
- `test/features/favorites/favorites_screen_test_helpers.dart`：`pumpFavoritesScreen` 自定义 GoRouter（含 `/favorites/detail` + `state.extra as Favorite` 的 test route，**要改**）；`setUpFavoritesScreen`；`seedFavorite`/`seedCollection`（走 Repository API）。
- `test/features/media/helpers/media_test_helpers.dart`：`testServer = MediaServerInfo(ip: '192.168.1.5', httpPort: 8080)`、`fileListJson`、`okMockClient`、`createMediaTestContainer`。
- `test/features/media/presentation/video_player_page_test.dart`：文件内定义 `FakeVideoPlayerController`（第 15–114 行，**要原样提取**到 `test/features/media/helpers/fake_video_player_controller.dart`）。
- `test/features/media/presentation/image_viewer_page_test.dart`：第 234 行注释「通过 Navigator.push 进入」**已过时，要改**。
- `FavoritesRepository` 实现搜索（任务 1 执行时运行）：`rg -n "implements FavoritesRepository" lib test` 预期只命中 `SqliteFavoritesRepository`。

### 测试运行约定（本项目强制）

```bash
# 单文件/多文件
flutter test <files...> --reporter compact > fltest-phase12-xxx.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-xxx.log
# 失败定位
grep -nE " -[1-9]" fltest-phase12-xxx.log
```

`EXIT=0` 全过；`EXIT≠0` 失败摘要在 tail。widget 测试 setup 用 `pump()` 不用 `pumpAndSettle()`；仅测试 body 需要等路由转场动画时用 `pumpAndSettle(const Duration(milliseconds: 250))`（现有 favorites/media 测试均如此）。

---

## Task 1：收藏详情形成完整 ID vertical slice

**目标：** 不依赖任何列表页内存对象，直接打开 `/favorites/:id` 能从 SQLite 恢复详情；无效/已删除 ID 有稳定页面状态。

**Files:**
- Modify: `lib/features/favorites/application/ports/favorites_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_favorites_repository.dart`
- Modify: `lib/features/favorites/application/favorites_controller.dart`
- Modify: `lib/app/navigation/app_destination.dart`（只加 `favoriteDetail`/`favoriteId`）
- Modify: `lib/app/router/app_router.dart`（提取 `createAppRouter` 工厂；favorites 子路由；删 Favorite import 与 extra cast）
- Modify: `lib/features/favorites/presentation/favorite_detail_screen.dart`
- Modify: `lib/features/favorites/presentation/favorites_screen.dart`
- Modify: `test/features/favorites/data/sqlite_favorites_repository_test.dart`
- Modify: `test/features/favorites/application/favorites_controller_test.dart`
- Modify: `test/features/favorites/favorites_screen_test_helpers.dart`
- Modify: `test/features/favorites/favorites_screen_basics_cases.dart`
- Create: `test/app/router/app_router_test.dart`

**Interfaces:**
- Consumes: 现有 `FavoritesRepository`、`favoritesProvider`/`favoritesFilterProvider`、`Favorite`（`lib/features/favorites/domain/models/favorite.dart`）、`AppEmptyState`、`pumpTestApp`/`pumpTestAppScope`、`seedFavorite`/`createEmptyPreferences`。
- Produces:
  - `FavoritesRepository.loadById(String favoriteId) -> Favorite?`
  - `favoriteByIdProvider = Provider.family<Favorite?, String>`（`lib/features/favorites/application/favorites_controller.dart`）
  - `AppRouteName.favoriteDetail = 'favoriteDetail'`、`AppRouteParameter.favoriteId = 'favoriteId'`（`lib/app/navigation/app_destination.dart`）
  - `GoRouter createAppRouter({String initialLocation = AppDestination.chat.path})`（`lib/app/router/app_router.dart`），`appRouterProvider` 改为 `Provider<GoRouter>` 且 `ref.onDispose(router.dispose)`
  - `FavoriteDetailScreen({required String? favoriteId, super.key})`
  - `pumpFavoritesScreen` 增加可选 `String initialLocation = AppDestination.favorites.path`

### Step 1: 写 repository 红灯测试（loadById）

在 `test/features/favorites/data/sqlite_favorites_repository_test.dart` 的 `main()` 内、`SqliteFavoritesRepository - updateTitle` group 之后新增 group：

```dart
group('SqliteFavoritesRepository - loadById', () {
  test('save 后 loadById 返回字段完整对象', () {
    repository.save(
      _makeFavorite(
        id: 'fav-load-1',
        collectionId: 'col-1',
        assistantContent: '助手回复',
        userMessageContent: '用户消息',
        assistantReasoningContent: '推理过程',
        assistantModelDisplayName: 'DeepSeek V4 Flash',
        sourceConversationId: 'conv-1',
        sourceConversationTitle: '原始对话',
        sourceAssistantMessageId: 'msg-1',
        title: '自定义标题',
      ),
    );

    final loaded = repository.loadById('fav-load-1');

    expect(loaded, isNotNull);
    expect(loaded!.id, 'fav-load-1');
    expect(loaded.collectionId, 'col-1');
    expect(loaded.userMessageContent, '用户消息');
    expect(loaded.assistantContent, '助手回复');
    expect(loaded.assistantReasoningContent, '推理过程');
    expect(loaded.assistantModelDisplayName, 'DeepSeek V4 Flash');
    expect(loaded.sourceConversationId, 'conv-1');
    expect(loaded.sourceConversationTitle, '原始对话');
    expect(loaded.sourceAssistantMessageId, 'msg-1');
    expect(loaded.title, '自定义标题');
  });

  test('不存在 ID 返回 null', () {
    expect(repository.loadById('missing-id'), isNull);
  });

  test('两条记录时按 ID 精确读取，不依赖 createdAt 排序', () {
    repository.save(_makeFavorite(id: 'older', createdAt: DateTime(2026, 1, 1)));
    repository.save(_makeFavorite(id: 'newer', createdAt: DateTime(2026, 1, 2)));

    expect(repository.loadById('older')!.createdAt, DateTime(2026, 1, 1));
    expect(repository.loadById('newer')!.createdAt, DateTime(2026, 1, 2));
  });
});
```

### Step 2: 运行 repository 测试确认红灯

```bash
flutter test test/features/favorites/data/sqlite_favorites_repository_test.dart --reporter compact > fltest-phase12-favorites-data.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-favorites-data.log
```

Expected: `EXIT≠0`，编译错误指向 `loadById` 不存在（`FavoritesRepository` 接口与 `SqliteFavoritesRepository` 均未定义）。

### Step 3: 写 application 红灯测试（favoriteByIdProvider）

在 `test/features/favorites/application/favorites_controller_test.dart` 的 `FavoritesFilterNotifier` group 之后新增 group：

```dart
group('favoriteByIdProvider', () {
  test('filter 选中 collection A 时仍能读取 collection B 的收藏', () {
    container.read(favoritesProvider.notifier).add(
      userMessageContent: 'B 的问题',
      assistantContent: 'B 的回复',
      collectionId: 'col-b',
    );
    container.read(favoritesProvider.notifier).add(
      userMessageContent: 'A 的问题',
      assistantContent: 'A 的回复',
      collectionId: 'col-a',
    );
    final bId = container
        .read(favoritesProvider)
        .firstWhere((f) => f.collectionId == 'col-b')
        .id;

    container.read(favoritesFilterProvider.notifier).setFilter('col-a');
    final favorite = container.read(favoriteByIdProvider(bId));

    expect(favorite, isNotNull);
    expect(favorite!.userMessageContent, 'B 的问题');
    expect(favorite.collectionId, 'col-b');
  });

  test('rename 后 by-ID 标题立即更新', () {
    final id = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '问题', assistantContent: '回复');

    container.read(favoritesProvider.notifier).rename(id, '新标题');

    expect(container.read(favoriteByIdProvider(id))!.title, '新标题');
  });

  test('move 后 by-ID collectionId 立即更新', () {
    final id = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '问题', assistantContent: '回复');

    container.read(favoritesProvider.notifier).moveTo(id, 'col-x');

    expect(container.read(favoriteByIdProvider(id))!.collectionId, 'col-x');
  });

  test('remove 后 by-ID 为 null', () {
    final id = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '问题', assistantContent: '回复');

    container.read(favoritesProvider.notifier).remove(id);

    expect(container.read(favoriteByIdProvider(id)), isNull);
  });
});
```

### Step 4: 运行 application 测试确认红灯

```bash
flutter test test/features/favorites/application/favorites_controller_test.dart --reporter compact > fltest-phase12-favorites-app.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-favorites-app.log
```

Expected: `EXIT≠0`，`favoriteByIdProvider` 未定义。

### Step 5: 实现 loadById 与 by-ID read model

**5a.** `lib/features/favorites/application/ports/favorites_repository.dart`，在 `loadAll` 之后插入：

```dart
  /// 按 ID 读取单条收藏；记录不存在时返回 null。
  Favorite? loadById(String favoriteId);
```

**5b.** `lib/features/favorites/data/sqlite_favorites_repository.dart`，在 `loadAll` 之后插入（复用 `_rowToFavorite`）：

```dart
  @override
  Favorite? loadById(String favoriteId) {
    final rows = _database.connection.select(
      'SELECT * FROM favorites WHERE id = ? LIMIT 1;',
      [favoriteId],
    );
    if (rows.isEmpty) return null;
    return _rowToFavorite(rows.first);
  }
```

**5c.** `lib/features/favorites/application/favorites_controller.dart`，在文件底部（`FavoritesController` 类之后、imports 区不变）新增：

```dart
/// 按 ID 读取单条收藏。
///
/// 与 filtered 列表解耦：详情页不依赖当前筛选是否包含该 ID。
/// [favoritesProvider] 仅作为 add/remove/move/rename 的失效信号，
/// 真实数据始终来自 repository 精确查询。
final favoriteByIdProvider = Provider.family<Favorite?, String>((ref, id) {
  ref.watch(favoritesProvider);
  return ref.watch(favoritesRepositoryProvider).loadById(id);
});
```

**5d.** 确认没有其他 `FavoritesRepository` 实现需要同步：

```bash
rg -n "implements FavoritesRepository" lib test
```

Expected: 仅命中 `lib/features/favorites/data/sqlite_favorites_repository.dart` 一行。

### Step 6: 运行 Task 1 数据层测试确认绿灯

```bash
flutter test test/features/favorites/data/sqlite_favorites_repository_test.dart test/features/favorites/application/favorites_controller_test.dart --reporter compact > fltest-phase12-favorites-data.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-favorites-data.log
```

Expected: `EXIT=0`。

### Step 7: 写 app router 红灯测试（direct URL / fresh rebuild / invalid / deleted / push-back）

新增 `test/app/router/app_router_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

import '../../features/favorites/favorites_screen_test_helpers.dart';
import '../../helpers/test_harness.dart';

Future<SharedPreferences> _testPrefs(AppDatabase db) async {
  return createEmptyPreferences(db);
}

void main() {
  testWidgets('favorite detail direct URL 不依赖 extra 恢复完整内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-direct',
      userMessageContent: '直接打开的用户消息',
      assistantContent: '直接打开的助手回复',
      assistantModelDisplayName: 'DeepSeek V4 Flash',
    );
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: '/favorites/fav-direct');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('直接打开的用户消息'), findsOneWidget);
    expect(find.text('直接打开的助手回复'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
  });

  testWidgets('fresh router rebuild 后同一 URL 仍恢复详情', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-rebuild',
      userMessageContent: '重建后的用户消息',
      assistantContent: '重建后的助手回复',
    );
    final prefs = await _testPrefs(db);

    final scope1 = await pumpTestAppScope(
      tester,
      preferences: prefs,
      database: db,
      router: createAppRouter(initialLocation: '/favorites/fav-rebuild'),
    );
    await tester.pump();
    expect(find.text('重建后的用户消息'), findsOneWidget);

    // 卸载旧树、销毁旧 scope 与 router，证明重建不依赖任何内存对象。
    await tester.pumpWidget(const SizedBox.shrink());
    scope1.dispose();

    final scope2 = await pumpTestAppScope(
      tester,
      preferences: prefs,
      database: db,
      router: createAppRouter(initialLocation: '/favorites/fav-rebuild'),
    );
    await tester.pumpWidget(scope2);
    await tester.pump();

    expect(find.text('重建后的用户消息'), findsOneWidget);
    expect(find.text('重建后的助手回复'), findsOneWidget);
  });

  testWidgets('invalid ID 显示收藏链接无效并可返回列表', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: '/favorites/%20');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏链接无效'), findsOneWidget);

    await tester.tap(find.text('返回收藏列表'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
  });

  testWidgets('deleted 收藏直接打开旧 URL 显示收藏不存在', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-deleted',
      userMessageContent: '将被删除的问题',
      assistantContent: '将被删除的回复',
    );
    final prefs = await _testPrefs(db);
    // 通过 repository API 删除，模拟记录已被移除。
    SqliteFavoritesRepository(db).delete('fav-deleted');

    final router = createAppRouter(initialLocation: '/favorites/fav-deleted');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从收藏列表点击 item 进入详情，返回回到列表', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-push',
      userMessageContent: '列表进入的问题',
      assistantContent: '列表进入的回复',
    );
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: AppDestination.favorites.path);
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    await tester.tap(find.text('列表进入的问题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/favorites/fav-push',
    );
    expect(find.text('列表进入的回复'), findsOneWidget);

    // AppBar 自动 leading 是 BackButton（tooltip 随 locale 变化，用类型 finder）。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
    expect(find.text('列表进入的问题'), findsOneWidget);
  });
}
```

注意：`seedFavorite` 来自 `favorites_screen_test_helpers.dart`（该文件 export 了 `SqliteFavoritesRepository` 的用法）；删除操作直接构造 `SqliteFavoritesRepository(db)`（import 已在文件头列出）。

### Step 8: 运行 router 测试确认红灯

```bash
flutter test test/app/router/app_router_test.dart --reporter compact > fltest-phase12-router.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-router.log
```

Expected: `EXIT≠0`，`createAppRouter` 未定义 / `FavoriteDetailScreen(favoriteId:)` 构造失败 / 恢复文案缺失。

### Step 9: 增加 route 常量（仅 favorite 部分）

`lib/app/navigation/app_destination.dart`，在 enum 之后追加：

```dart
/// 非顶层路由的稳定名称与参数键，供 route builder、导航发起方与测试共享。
///
/// 详情/媒体页面是顶层页面的子页面，不进入 [AppDestination.values]，
/// 否则会错误出现在 NavigationRail/NavigationBar。
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

（`mediaImage`/`mediaVideo`/`mediaPath` 本步一并加入以保持常量聚合一处；Task 2 才消费它们，本提交内无人引用这些常量不会报 lint——`unused` 只针对局部变量/字段，`static const` 不触发。）

### Step 10: 改写 FavoriteDetailScreen（ID 构造 + 恢复状态，删本地镜像）

整体重写 `lib/features/favorites/presentation/favorite_detail_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import '../application/collections_controller.dart';
import '../application/favorite_source_conversation_command.dart';
import '../application/favorites_controller.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite.dart';
import 'package:oh_my_llm/core/widgets/app_confirm_dialog.dart';
import 'widgets/favorite_card.dart';

/// 单条收藏的详情页，展示完整对话内容。
///
/// 只接收 [favoriteId]（可能为 null/空），实体经 [favoriteByIdProvider]
/// 按 ID 读取；链接无效或收藏已删除时展示可返回的恢复状态。
/// 不保存任何 route 传入的 [Favorite] 镜像，避免陈旧数据。
class FavoriteDetailScreen extends ConsumerStatefulWidget {
  const FavoriteDetailScreen({required this.favoriteId, super.key});

  final String? favoriteId;

  @override
  ConsumerState<FavoriteDetailScreen> createState() =>
      _FavoriteDetailScreenState();
}

class _FavoriteDetailScreenState extends ConsumerState<FavoriteDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final rawId = widget.favoriteId?.trim() ?? '';
    final favorite = rawId.isEmpty
        ? null
        : ref.watch(favoriteByIdProvider(rawId));

    if (favorite == null) {
      final invalid = rawId.isEmpty;
      return _FavoriteDetailRecoveryPage(
        title: invalid ? '收藏链接无效' : '收藏不存在',
        description: invalid ? '链接中缺少有效的收藏 ID。' : '这条收藏可能已被删除。',
      );
    }

    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = favorite.collectionId != null
        ? collectionById[favorite.collectionId]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(favorite.title ?? '收藏详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: '重命名',
            onPressed: () => _showRenameDialog(context, favorite),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除收藏',
            onPressed: () => _confirmDelete(context, favorite),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: FavoriteCard(
          favorite: favorite,
          collectionName: collection?.name,
          onDeletePressed: () => _confirmDelete(context, favorite),
          onMoveToCollection: () =>
              _showMoveDialog(context, favorite, collections),
          onGoToConversation: favorite.sourceConversationId != null
              ? () => _goToConversation(context, favorite)
              : null,
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    Favorite favorite,
  ) async {
    final controller = TextEditingController(text: favorite.title ?? '');
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名收藏'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '自定义标题',
              hintText: '留空则使用消息摘要',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确认'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (result == null) return;
    final trimmed = result.trim();
    // 变更后由 favoriteByIdProvider 重读，页面无需本地同步。
    ref
        .read(favoritesProvider.notifier)
        .rename(favorite.id, trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _showMoveDialog(
    BuildContext context,
    Favorite favorite,
    List<FavoriteCollection> collections,
  ) async {
    String? selectedCollectionId = favorite.collectionId;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('移动到收藏夹'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoveCollectionTile(
                  label: '未分类',
                  icon: Icons.folder_off_outlined,
                  selected: selectedCollectionId == null,
                  onTap: () => setState(() => selectedCollectionId = null),
                ),
                if (collections.isNotEmpty) ...[
                  const Divider(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: collections.length,
                      itemBuilder: (context, index) {
                        final collection = collections[index];
                        return _MoveCollectionTile(
                          label: collection.name,
                          icon: Icons.folder_outlined,
                          selected: selectedCollectionId == collection.id,
                          onTap: () => setState(
                            () => selectedCollectionId = collection.id,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedCollectionId != favorite.collectionId
                  ? () => Navigator.of(context).pop(selectedCollectionId ?? '')
                  : null,
              child: const Text('移动'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    ref
        .read(favoritesProvider.notifier)
        .moveTo(favorite.id, result.isEmpty ? null : result);
  }

  Future<void> _confirmDelete(BuildContext context, Favorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const AppConfirmDialog(
        title: '删除收藏',
        message: '确定要删除这条收藏记录吗？',
        confirmLabel: '删除',
      ),
    );

    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).remove(favorite.id);
      if (context.mounted) context.pop();
    }
  }

  void _goToConversation(BuildContext context, Favorite favorite) {
    ref
        .read(favoriteSourceConversationCommandProvider)
        .selectSourceConversation(
          conversationId: favorite.sourceConversationId!,
          assistantMessageId: favorite.sourceAssistantMessageId,
        );
    context.go(AppDestination.chat.path);
  }
}

/// 收藏详情恢复页：参数无效或收藏不存在时的可返回页面级状态。
class _FavoriteDetailRecoveryPage extends StatelessWidget {
  const _FavoriteDetailRecoveryPage({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏详情')),
      body: AppEmptyState(
        icon: Icons.bookmark_remove_rounded,
        title: title,
        description: description,
        action: FilledButton(
          onPressed: () {
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(AppDestination.favorites.path);
            }
          },
          child: const Text('返回收藏列表'),
        ),
      ),
    );
  }
}

/// 移动收藏夹对话框中的选项行。
class _MoveCollectionTile extends StatelessWidget {
  // 原实现（原文件第 219–278 行）整体保留，一字不改。
}
```

要点（对照原文件）：
- 删除 `late Favorite _favorite`、`_refreshFavorite()`、构造器 `favorite` 参数；四个方法均新增 `Favorite favorite` 参数并在 build 中传当前 provider 值。
- `_showMoveDialog` 内 `selectedCollectionId != favorite.collectionId` 判断与 pop 结果处理原样保留。
- 原文件底部第 219–278 行的 `_MoveCollectionTile`（`StatelessWidget`，含 `label`/`icon`/`selected`/`onTap` 四字段与 build 实现）整体保留，一字不改——上面重写代码中的 `_MoveCollectionTile` 引用即指它。

### Step 11: 提取 createAppRouter 工厂并接入 favorites 子路由

重写 `lib/app/router/app_router.dart` 的路由部分（顶部 import 删除 `package:oh_my_llm/features/favorites/domain/models/favorite.dart`）。**本步只接 favorites 子路由**——media 子路由与 `media_route_pages.dart` import 在 Task 2 Step 9a 才加入（此时 `MediaImageRoutePage` 还不存在，引用了会编译失败）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_detail_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorites_screen.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import '../composition/sync_workspace_screen.dart';
import '../navigation/app_destination.dart';

/// 应用顶层路由配置。
///
/// 以 GoRouter 管理顶层页面与子页面跳转。顶层保持平铺 GoRoute；
/// 收藏详情是 favorites 的 child，经 pushNamed 进入、pop 回到列表。
/// 初始落地页为聊天页。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

/// 创建应用 GoRouter，可传入 [initialLocation] 供测试直接打开深链。
GoRouter createAppRouter({
  String initialLocation = AppDestination.chat.path,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppDestination.chat.path,
        name: AppDestination.chat.name,
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: AppDestination.history.path,
        name: AppDestination.history.name,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        name: AppDestination.settings.name,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppDestination.favorites.path,
        name: AppDestination.favorites.name,
        builder: (context, state) => const FavoritesScreen(),
        routes: [
          GoRoute(
            path: ':favoriteId',
            name: AppRouteName.favoriteDetail,
            builder: (context, state) => FavoriteDetailScreen(
              favoriteId: state
                  .pathParameters[AppRouteParameter.favoriteId],
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppDestination.sync.path,
        name: AppDestination.sync.name,
        builder: (context, state) => const SyncWorkspaceScreen(),
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(body: Center(child: Text('未找到页面：${state.uri}')));
    },
  );
}
```

注意：Task 2 Step 9a 会在此文件新增 `import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';`，并在 `/sync` route 下追加 `media/image`、`media/video` 两个子 route。

### Step 12: 替换 FavoritesScreen 导航发起方

`lib/features/favorites/presentation/favorites_screen.dart`：

```dart
        return FavoriteListItem(
          favorite: favorite,
          collectionName: collection?.name,
          onTap: () => context.pushNamed(
            AppRouteName.favoriteDetail,
            pathParameters: {
              AppRouteParameter.favoriteId: favorite.id,
            },
          ),
        );
```

不传 `extra`、不手工 encode、不捕获整个 `Favorite`。

### Step 13: 更新 favorites 测试 helper（test route 改 ID contract）

`test/features/favorites/favorites_screen_test_helpers.dart`，`pumpFavoritesScreen`：

- 签名增加 `String initialLocation = AppDestination.favorites.path`。
- `GoRouter(initialLocation: initialLocation, ...)`。
- favorites route 加 `name: AppDestination.favorites.name`（`pushNamed` 依赖 name）。
- `/favorites/detail` route 替换为：

```dart
      GoRoute(
        path: '/favorites/:favoriteId',
        name: AppRouteName.favoriteDetail,
        builder: (context, state) => FavoriteDetailScreen(
          favoriteId: state.pathParameters[AppRouteParameter.favoriteId],
        ),
      ),
```

- 删除 `import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';`（test router 不再 cast extra）。
- 文件顶部新增 `import 'package:oh_my_llm/app/navigation/app_destination.dart';` 已存在（第 6 行），确认 `AppRouteName`/`AppRouteParameter` 来自同一文件无需新 import。

### Step 14: 运行 favorites 全量测试（含既有 detail/basics cases）

```bash
flutter test test/features/favorites/favorites_screen_test.dart test/app/router/app_router_test.dart test/features/favorites/data/sqlite_favorites_repository_test.dart test/features/favorites/application/favorites_controller_test.dart --reporter compact > fltest-phase12-favorites-all.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-favorites-all.log
```

Expected: `EXIT=0`。既有 detail cases（tap 后 `pumpAndSettle` 断言详情、删除后回列表、来源跳转、窄屏不溢出）与新 router cases 全部通过。若 `favorites_screen_basics_cases.dart` 的 'tapping item navigates to detail' 失败，检查 test router 的 favorites route 是否已命名。

### Step 15: Task 1 范围审计

```bash
rg -n "state\.extra|extra:\s*favorite|FavoriteDetailScreen\(favorite:" lib/app lib/features/favorites test/features/favorites test/app
rg -n "'/favorites/detail'|\"/favorites/detail\"" lib test
```

Expected: 两命令在 Phase 12 相关路径内零命中（test helper 中的旧 route 已替换）。

### Step 16: 格式化与提交

```bash
git diff --name-only -- '*.dart'
dart format lib/app/navigation/app_destination.dart lib/app/router/app_router.dart lib/features/favorites/application/ports/favorites_repository.dart lib/features/favorites/application/favorites_controller.dart lib/features/favorites/data/sqlite_favorites_repository.dart lib/features/favorites/presentation/favorites_screen.dart lib/features/favorites/presentation/favorite_detail_screen.dart test/app/router/app_router_test.dart test/features/favorites/application/favorites_controller_test.dart test/features/favorites/data/sqlite_favorites_repository_test.dart test/features/favorites/favorites_screen_test_helpers.dart
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
        test/features/favorites/favorites_screen_test_helpers.dart
git status --short
git diff --cached --name-only
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git commit -m "refactor(favorites): 以 ID 恢复收藏详情路由"
```

- 提交只包含 Task 1 文件与 hook 自动产生的 `pubspec.yaml` 版本变化；不得包含 `.opencode/plans` 删除或 media 改动。
- `dart format --output=none --set-exit-if-changed` 非零退出时不得提交，先修复再提交。
- 若 `favorites_screen_basics_cases.dart` 在 Step 14 有实际 diff（预期没有，因为行为未变），从 `git add` 列表补入。

---

## Task 2：媒体 viewer/player 纳入 GoRouter 子路由

**目标：** 所有媒体页面入口共享 `/sync/media/*` route matrix，只携带 relative path，并在 session/参数缺失时恢复。

**Files:**
- Modify: `lib/features/media/utils/path_utils.dart`
- Create: `lib/features/media/presentation/pages/media_route_pages.dart`
- Modify: `lib/app/router/app_router.dart`（media 子路由 + import）
- Modify: `lib/features/media/presentation/media_browser_tab.dart`
- Modify: `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`
- Modify: `lib/features/media/application/shuffle_playback_controller.dart`（仅内部复用 URL helper）
- Modify: `test/features/media/presentation/image_viewer_page_test.dart`（只改过时注释）
- Modify: `test/features/media/presentation/video_player_page_test.dart`（删文件内 fake，import shared）
- Modify: `test/features/media/helpers/media_test_helpers.dart`（加 FakeMediaBrowserController）
- Create: `test/features/media/helpers/fake_video_player_controller.dart`
- Create: `test/features/media/utils/path_utils_test.dart`（已有，扩展）
- Create: `test/features/media/presentation/media_route_pages_test.dart`
- Create: `test/features/media/presentation/media_browser_navigation_test.dart`
- Create: `test/features/media/presentation/shuffle_appbar_actions_test.dart`
- Modify: `test/app/router/app_router_test.dart`（media 部分）

**Interfaces:**
- Consumes: `encodeMediaPath`、`isImageFile`/`isVideoFile`、`MediaServerInfo`、`MediaBrowserState`/`mediaBrowserControllerProvider`、`ImageViewerPage`、`VideoPlayerPage`（含 `controllerFactory`）、`ShufflePlaybackActive.currentVideo`、`AppRouteName`/`AppRouteParameter`（Task 1 已加）、`AppEmptyState`。
- Produces:
  - `String? normalizeMediaRoutePath(String? rawPath)`（path_utils.dart）
  - `String buildMediaResourceUrl(MediaServerInfo server, String type, String relativePath)`（path_utils.dart）
  - `MediaImageRoutePage({required String? relativePath})`、`MediaVideoRoutePage({required String? relativePath, VideoPlayerController Function(Uri)? controllerFactory})`（media_route_pages.dart，均为 ConsumerWidget）
  - `FakeMediaBrowserController extends MediaBrowserController`（media_test_helpers.dart，`build()` 返回注入的初始 state）
  - `FakeVideoPlayerController` 从 `video_player_page_test.dart` 原样移至 `test/features/media/helpers/fake_video_player_controller.dart`

### Step 1: 写 path helper 红灯测试

在 `test/features/media/utils/path_utils_test.dart` 追加两个 group：

```dart
group('normalizeMediaRoutePath', () {
  test('null / 空 / 仅空白返回 null', () {
    expect(normalizeMediaRoutePath(null), isNull);
    expect(normalizeMediaRoutePath(''), isNull);
    expect(normalizeMediaRoutePath('   '), isNull);
  });

  test('不以 / 开头返回 null', () {
    expect(normalizeMediaRoutePath('photo.jpg'), isNull);
  });

  test('去掉首尾分隔后无文件段返回 null', () {
    expect(normalizeMediaRoutePath('/'), isNull);
    expect(normalizeMediaRoutePath('///'), isNull);
  });

  test('任一路径段为 . 或 .. 返回 null', () {
    expect(normalizeMediaRoutePath('/a/../b.jpg'), isNull);
    expect(normalizeMediaRoutePath('/./b.jpg'), isNull);
    expect(normalizeMediaRoutePath('/..'), isNull);
  });

  test('合法路径保留中文、空格与 .. 文件名子串', () {
    expect(normalizeMediaRoutePath('/相册/我的 猫.jpg'), '/相册/我的 猫.jpg');
    expect(normalizeMediaRoutePath('/a/photo..jpg'), '/a/photo..jpg');
  });

  test('规范化首尾多余分隔符', () {
    expect(normalizeMediaRoutePath('/a/b//c.jpg'), '/a/b/c.jpg');
    expect(normalizeMediaRoutePath('/a/b.jpg/'), '/a/b.jpg');
  });
});

group('buildMediaResourceUrl', () {
  test('使用可信 server 与相对路径构建 URL，中文每段只编码一次', () {
    final url = buildMediaResourceUrl(
      testServer,
      'image',
      '/相册/我的 猫.jpg',
    );

    expect(
      url,
      'http://192.168.1.5:8080/api/media/image/%E7%9B%B8%E5%86%8C/%E6%88%91%E7%9A%84%20%E7%8C%AB.jpg',
    );
  });

  test('视频类型构建 video 端点', () {
    expect(
      buildMediaResourceUrl(testServer, 'video', '/视频/demo.mp4'),
      startsWith('http://192.168.1.5:8080/api/media/video/'),
    );
  });
});
```

`testServer` 来自 `test/features/media/helpers/media_test_helpers.dart`——`path_utils_test.dart` 需要新增该 import；若不想跨 helpers，直接写 `MediaServerInfo(ip: '192.168.1.5', httpPort: 8080)` 亦可，二选一保持一致。

### Step 2: 运行确认红灯

```bash
flutter test test/features/media/utils/path_utils_test.dart --reporter compact > fltest-phase12-path-utils.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-path-utils.log
```

Expected: `EXIT≠0`，`normalizeMediaRoutePath`/`buildMediaResourceUrl` 未定义。

### Step 3: 提取共享 FakeVideoPlayerController 并先恢复原测试全绿

**3a.** 新建 `test/features/media/helpers/fake_video_player_controller.dart`，内容为 `video_player_page_test.dart` 第 15–114 行的 `FakeVideoPlayerController` 类**原样**（含 doc 注释），仅补充文件头 import：

```dart
import 'package:video_player/video_player.dart';

/// 用于测试的 Fake VideoPlayerController。
///
/// 不依赖平台原生播放器，所有方法通过覆写实现。
/// 提供可追踪的 [seekToCalls] 和 [setPlaybackSpeedCalls] 列表，
/// 以及可设置的 [fakePosition]、[fakeDuration] 等状态字段。
class FakeVideoPlayerController extends VideoPlayerController {
  // ...原样复制 video_player_page_test.dart 中的整个类体...
}
```

**3b.** `test/features/media/presentation/video_player_page_test.dart`：
- 删除文件内 `FakeVideoPlayerController` 类定义（含 `// ── FakeVideoPlayerController ───` 注释块）。
- 新增 `import '../helpers/fake_video_player_controller.dart';`（`test/` 内互引用用相对路径，`presentation/` 与 `helpers/` 同属 `test/features/media/` 下）。
- `import 'package:video_player/video_player.dart';` 保留（`VideoPlayerValue`/`DurationRange` 等仍在测试 body 使用）。

**3c.** 运行验证（原行为零变化，应全绿）：

```bash
flutter test test/features/media/presentation/video_player_page_test.dart --reporter compact > fltest-phase12-video-leaf.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-video-leaf.log
```

Expected: `EXIT=0`。

### Step 4: 写 media route pages 红灯测试

**4a.** `test/features/media/helpers/media_test_helpers.dart` 追加（供 route/navigation/shuffle 测试共享）：

```dart
/// 测试用 MediaBrowserController：不发起网络请求，直接返回注入的初始状态。
class FakeMediaBrowserController extends MediaBrowserController {
  FakeMediaBrowserController(this.initialState);

  final MediaBrowserState initialState;

  @override
  MediaBrowserState build() => initialState;
}
```

**4b.** 新建 `test/features/media/presentation/media_route_pages_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/presentation/pages/image_viewer_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';

import '../../../helpers/test_harness.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

FileItem _image(String path) => FileItem(
      name: path.split('/').last,
      isDirectory: false,
      sizeBytes: 1,
      relativePath: path,
    );

/// 恢复页依赖 GoRouter.of，必须由 GoRouter 承载才能渲染。
GoRouter _recoveryRouter(Widget page) {
  return GoRouter(
    initialLocation: '/media',
    routes: [
      GoRoute(path: '/media', builder: (context, state) => page),
    ],
  );
}

void main() {
  testWidgets('当前目录两张图片，target 为第二张时画廊从 2 / 2 开始', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [
                _image('/相册/第一张.jpg'),
                _image('/相册/第二张.jpg'),
              ],
            ),
          ),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/第二张.jpg'),
    );

    // 计数器直接显示（无网络图片加载阻塞 build）
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });

  testWidgets('target 不在当前 items 时降级单图且不崩溃', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer, items: const []),
          ),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/不存在.jpg'),
    );

    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer),
          ),
        ),
      ],
      router: _recoveryRouter(const MediaImageRoutePage(relativePath: null)),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('图片扩展名不匹配显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: _recoveryRouter(
        const MediaImageRoutePage(relativePath: '/a/readme.txt'),
      ),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('server 缺失显示媒体会话已失效', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(const MediaBrowserState()),
        ),
      ],
      router: _recoveryRouter(
        const MediaImageRoutePage(relativePath: '/相册/猫.jpg'),
      ),
    );

    expect(find.text('媒体会话已失效'), findsOneWidget);
  });

  testWidgets('视频 path 合法时通过共享 fake 初始化并显示文件名', (tester) async {
    final fake = FakeVideoPlayerController();
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer),
          ),
        ),
      ],
      child: MediaVideoRoutePage(
        relativePath: '/视频/demo.mp4',
        controllerFactory: (uri) => fake,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.playCallCount, greaterThanOrEqualTo(1));
    expect(find.text('demo.mp4'), findsOneWidget);
    expect(find.byType(VideoPlayerPage), findsOneWidget);
  });

  testWidgets('视频 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer),
          ),
        ),
      ],
      router: _recoveryRouter(const MediaVideoRoutePage(relativePath: null)),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('视频扩展名不匹配显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: _recoveryRouter(
        const MediaVideoRoutePage(relativePath: '/a/readme.txt'),
      ),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('恢复页按钮 pop 或 go 回 /sync', (tester) async {
    final prefs = await _testPrefs();
    final router = GoRouter(
      initialLocation: '/sync/media/image',
      routes: [
        GoRoute(
          path: '/sync',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('同步落点')),
          ),
          routes: [
            GoRoute(
              path: 'media/image',
              builder: (context, state) => const MediaImageRoutePage(
                relativePath: null,
              ),
            ),
          ],
        ),
      ],
    );
    await pumpTestApp(tester, preferences: prefs, router: router);

    expect(find.text('返回局域网同步'), findsOneWidget);

    // 无父 route 可 pop（deep link 直达）→ 点击后 go 回 /sync。
    await tester.tap(find.text('返回局域网同步'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('同步落点'), findsOneWidget);
  });
}
```

`pumpTestApp` 的 `child` 模式已注入 `appCompositionOverrides`，`mediaBrowserControllerProvider` 未被生产绑定，override 直接生效。`ImageViewerPage` 内 `Image.network` 在测试中加载失败走 `errorBuilder`（不抛异常），与现有 `image_viewer_page_test.dart` 的依赖行为一致，不影响计数器断言。

### Step 5: 运行确认红灯

```bash
flutter test test/features/media/presentation/media_route_pages_test.dart --reporter compact > fltest-phase12-media-routes.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-routes.log
```

Expected: `EXIT≠0`，`media_route_pages.dart` 不存在。

### Step 6: 实现 path helper

`lib/features/media/utils/path_utils.dart` 追加（保留原 `encodeMediaPath`；文件头新增相对路径 import，同 feature 内部不用 package: 根路径）：

```dart
import '../domain/models/media_server_info.dart';

/// 验证并规范化媒体路由的 path 参数。
///
/// 返回 null 表示参数缺失或非法；否则返回以 `/` 开头的规范化路径。
/// 只验证 route contract，不做文件系统访问。
String? normalizeMediaRoutePath(String? rawPath) {
  final trimmed = rawPath?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('/')) return null;
  final segments = trimmed
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return null;
  if (segments.any((s) => s == '.' || s == '..')) return null;
  return '/${segments.join('/')}';
}

/// 使用可信 server 与相对路径构建媒体资源 URL。
///
/// 路径段只编码一次；调用方必须传入已校验的 relativePath。
String buildMediaResourceUrl(
  MediaServerInfo server,
  String type,
  String relativePath,
) {
  return 'http://${server.ip}:${server.httpPort}/api/media/$type/${encodeMediaPath(relativePath)}';
}
```

### Step 7: 实现 media_route_pages.dart

新建 `lib/features/media/presentation/pages/media_route_pages.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import '../../application/media_browser_controller.dart';
import '../../domain/media_file_classification.dart';
import '../../utils/path_utils.dart';
import 'image_viewer_page.dart';
import 'video_player_page.dart';

/// 图片查看的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，结合当前可信媒体会话重建
/// [ImageViewerPage]；参数缺失/非法或会话失效时展示恢复页。
/// 不读取 route 中的 host/port，网络 authority 只来自已连接会话。
class MediaImageRoutePage extends ConsumerWidget {
  const MediaImageRoutePage({required this.relativePath, super.key});

  final String? relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = normalizeMediaRoutePath(relativePath);
    if (normalized == null || !isImageFile(_fileNameOf(normalized))) {
      return const MediaRouteRecoveryPage(
        routeTitle: '图片查看',
        reason: '媒体链接无效',
      );
    }

    final browser = ref.watch(mediaBrowserControllerProvider);
    final server = browser.server;
    if (server == null) {
      return const MediaRouteRecoveryPage(
        routeTitle: '图片查看',
        reason: '媒体会话已失效',
      );
    }

    final imageItems = browser.items
        .where((i) => isImageFile(i.name))
        .toList(growable: false);
    final targetIndex = imageItems.indexWhere(
      (i) => i.relativePath == normalized,
    );

    if (targetIndex >= 0) {
      // 目标在当前目录图片列表中：按当前 items 顺序恢复画廊。
      return ImageViewerPage(
        imageUrls: [
          for (final item in imageItems)
            buildMediaResourceUrl(server, 'image', item.relativePath),
        ],
        initialIndex: targetIndex,
      );
    }

    // 目标不在当前列表（direct link/rebuild 时列表未恢复）：单图查看，
    // 资源已删除时由 leaf page 的 broken-image 状态呈现，仍可返回。
    return ImageViewerPage(
      imageUrls: [buildMediaResourceUrl(server, 'image', normalized)],
    );
  }
}

/// 视频播放的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，结合可信 server 重建 [VideoPlayerPage]；
/// [controllerFactory] 仅作测试注入的播放器平台替换，不进入 route state。
class MediaVideoRoutePage extends ConsumerWidget {
  const MediaVideoRoutePage({
    required this.relativePath,
    this.controllerFactory,
    super.key,
  });

  final String? relativePath;
  final VideoPlayerController Function(Uri)? controllerFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = normalizeMediaRoutePath(relativePath);
    if (normalized == null || !isVideoFile(_fileNameOf(normalized))) {
      return const MediaRouteRecoveryPage(
        routeTitle: '视频播放',
        reason: '媒体链接无效',
      );
    }

    final server = ref.watch(mediaBrowserControllerProvider).server;
    if (server == null) {
      return const MediaRouteRecoveryPage(
        routeTitle: '视频播放',
        reason: '媒体会话已失效',
      );
    }

    // 随机播放列表来自递归接口，当前目录 items 不一定包含目标，
    // 因此不要求用 state.items 验证视频存在。
    return VideoPlayerPage(
      videoUrl: buildMediaResourceUrl(server, 'video', normalized),
      fileName: _fileNameOf(normalized),
      controllerFactory: controllerFactory,
    );
  }
}

/// 媒体路由恢复页：参数或会话失效时的可返回页面级状态。
///
/// 不自动 redirect：让用户看到失效原因，同时支持 push 后的 pop
/// 与 deep link 直达时的 go 回退。
class MediaRouteRecoveryPage extends StatelessWidget {
  const MediaRouteRecoveryPage({
    required this.routeTitle,
    required this.reason,
    super.key,
  });

  final String routeTitle;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(routeTitle)),
      body: AppEmptyState(
        icon: Icons.link_off_rounded,
        title: reason,
        description: '媒体链接或会话已失效，请返回局域网同步重新连接。',
        action: FilledButton(
          onPressed: () {
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(AppDestination.sync.path);
            }
          },
          child: const Text('返回局域网同步'),
        ),
      ),
    );
  }
}

/// 取路径最后一个段作为文件名。
String _fileNameOf(String normalizedPath) {
  return normalizedPath.split('/').last;
}
```

### Step 8: 运行 route pages 测试确认绿灯

```bash
flutter test test/features/media/presentation/media_route_pages_test.dart test/features/media/utils/path_utils_test.dart --reporter compact > fltest-phase12-media-routes.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-routes.log
```

Expected: `EXIT=0`。

### Step 9: 加入 media 子路由并补 router 测试

**9a.** `lib/app/router/app_router.dart`：在 Step 11 的版本上追加 media 子路由——文件顶部新增 `import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';`，并把 `/sync` route 改为：

```dart
      GoRoute(
        path: AppDestination.sync.path,
        name: AppDestination.sync.name,
        builder: (context, state) => const SyncWorkspaceScreen(),
        routes: [
          GoRoute(
            path: 'media/image',
            name: AppRouteName.mediaImage,
            builder: (context, state) => MediaImageRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
        ],
      ),
```

**9b.** `test/app/router/app_router_test.dart` 追加三个测试（无需新增 import——`AppRouteName`/`AppRouteParameter` 已由 `app_destination.dart` 提供；断言的是恢复页而非 seeded 媒体会话，因此不需要 media 类型）：

```dart
  testWidgets('pushNamed(mediaImage) 后 URI 携带 path，pop 回 /sync', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: AppDestination.sync.path);
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    router.pushNamed(
      AppRouteName.mediaImage,
      queryParameters: {AppRouteParameter.mediaPath: '/相册/猫.jpg'},
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/sync/media/image',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['path'],
      '/相册/猫.jpg',
    );
    // 未 seed 会话 → 恢复页而非抛异常
    expect(find.text('媒体会话已失效'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
  });

  testWidgets('pushNamed(mediaVideo) 同理', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: AppDestination.sync.path);
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    router.pushNamed(
      AppRouteName.mediaVideo,
      queryParameters: {AppRouteParameter.mediaPath: '/视频/demo.mp4'},
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/sync/media/video',
    );
    expect(find.text('媒体会话已失效'), findsOneWidget);
  });

  testWidgets('media route 缺 query 仍匹配并显示恢复页，不抛异常', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '/sync/media/image',
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('媒体链接无效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

### Step 10: 写 MediaBrowserTab 导航红灯测试

新建 `test/features/media/presentation/media_browser_navigation_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';

import '../../../helpers/test_harness.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

FileItem _file(String path) => FileItem(
      name: path.split('/').last,
      isDirectory: false,
      sizeBytes: 1,
      relativePath: path,
    );

FileItem _dir(String path) => FileItem(
      name: path.split('/').last,
      isDirectory: true,
      sizeBytes: 0,
      relativePath: path,
    );

/// 最小 GoRouter 宿主：/sync 渲染 MediaBrowserTab，media 子路由走生产 routed pages。
GoRouter _mediaRouter() {
  return GoRouter(
    initialLocation: AppDestination.sync.path,
    routes: [
      GoRoute(
        path: AppDestination.sync.path,
        builder: (context, state) => Scaffold(
          body: MediaBrowserTab(onExitMediaBrowser: () {}),
        ),
        routes: [
          GoRoute(
            path: 'media/image',
            name: AppRouteName.mediaImage,
            builder: (context, state) => MediaImageRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
              controllerFactory: (uri) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('点击图片文件名进入 media/image 子路由，back 回浏览列表', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_file('/相册/猫.jpg'), _file('/相册/狗.jpg')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('猫.jpg'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/sync/media/image',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['path'],
      '/相册/猫.jpg',
    );
    expect(find.byType(MediaImageRoutePage), findsOneWidget);

    // viewer 的返回按钮是 IconButton(Icons.arrow_back)，无 tooltip。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('狗.jpg'), findsOneWidget);
  });

  testWidgets('点击视频文件名进入 media/video 子路由，back 回浏览页', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_file('/视频/demo.mp4'), _file('/视频/other.mp4')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('demo.mp4'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/sync/media/video',
    );
    // push 后父浏览页仍在树中：列表 tile 与播放器标题各渲染一次文件名。
    expect(find.text('demo.mp4'), findsWidgets);

    // VideoTopBar 的返回按钮也是 IconButton(Icons.arrow_back)，无 tooltip。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('other.mp4'), findsOneWidget);
  });

  testWidgets('点击目录只改变浏览路径，不产生媒体子路由', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_dir('/相册'), _file('/相册/猫.jpg')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('相册'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 目录点击不 push 子路由
    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
  });

  testWidgets('server 缺失时点击媒体文件不导航', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(items: [_file('/相册/猫.jpg')]),
          ),
        ),
      ],
    );

    await tester.tap(find.text('猫.jpg'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.byType(MediaImageRoutePage), findsNothing);
  });
}
```

### Step 11: 运行确认红灯

```bash
flutter test test/features/media/presentation/media_browser_navigation_test.dart --reporter compact > fltest-phase12-media-nav.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-nav.log
```

Expected: `EXIT≠0`——MediaBrowserTab 仍走 `Navigator.push`，URI 不变化。

### Step 12: 迁移 MediaBrowserTab

`lib/features/media/presentation/media_browser_tab.dart`：

- import 变化：删除 `pages/image_viewer_page.dart`、`pages/video_player_page.dart`、`../utils/path_utils.dart`（后者的 `encodeMediaPath` 只被 `_buildMediaUrl` 使用）；新增 `package:go_router/go_router.dart`、`package:oh_my_llm/app/navigation/app_destination.dart`。`../domain/media_file_classification.dart` 保留（`isImageFile`/`isVideoFile` 仍用于点击分支）。
- `onItemTap` 的图片/视频分支替换为：

```dart
              onItemTap: (item) {
                if (item.isDirectory) {
                  controller.navigateTo(item.relativePath);
                } else if (isImageFile(item.name)) {
                  // server 缺失时不导航，保持原有防御行为；
                  // 图片/视频 URL 由 routed page 从可信会话重建。
                  if (state.server == null) return;
                  context.pushNamed(
                    AppRouteName.mediaImage,
                    queryParameters: {
                      AppRouteParameter.mediaPath: item.relativePath,
                    },
                  );
                } else if (isVideoFile(item.name)) {
                  if (state.server == null) return;
                  context.pushNamed(
                    AppRouteName.mediaVideo,
                    queryParameters: {
                      AppRouteParameter.mediaPath: item.relativePath,
                    },
                  );
                }
                // 其他类型文件：无操作
              },
```

- 删除整个 `_buildMediaUrl` 方法。
- `thumbnailBase` 计算保留（缩略图仍用 `http://{ip}:{httpPort}`）。

### Step 13: 运行 navigation 测试确认绿灯

```bash
flutter test test/features/media/presentation/media_browser_navigation_test.dart --reporter compact > fltest-phase12-media-nav.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-nav.log
```

Expected: `EXIT=0`。

### Step 14: 写 ShuffleAppBarActions 红灯测试

新建 `test/features/media/presentation/shuffle_appbar_actions_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/shuffle_appbar_actions.dart';

import '../../../helpers/test_harness.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

/// 记录 onPlayerExited 调用次数的随机播放控制器替身。
class RecordingShuffleController extends ShufflePlaybackController {
  RecordingShuffleController(this.initialState);

  final ShufflePlaybackState initialState;
  int onPlayerExitedCallCount = 0;

  @override
  ShufflePlaybackState build() => initialState;

  @override
  void onPlayerExited() {
    onPlayerExitedCallCount++;
  }
}

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

GoRouter _shuffleRouter(RecordingShuffleController shuffleController) {
  return GoRouter(
    initialLocation: AppDestination.sync.path,
    routes: [
      GoRoute(
        path: AppDestination.sync.path,
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            actions: [
              ShuffleAppBarActions(currentDirectoryPath: '/视频'),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
        routes: [
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
              controllerFactory: (uri) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('下一个按钮以 currentVideo.relativePath 打开 mediaVideo 路由', (
    tester,
  ) async {
    final prefs = await _testPrefs();
    final shuffleController = RecordingShuffleController(
      ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: '第一个.mp4', relativePath: '/视频/第一个.mp4'),
          VideoItem(name: '第二个.mp4', relativePath: '/视频/第二个.mp4'),
        ],
        currentIndex: 0,
        directoryPath: '/视频',
      ),
    );
    final router = _shuffleRouter(shuffleController);
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        shufflePlaybackControllerProvider.overrideWith(
          () => shuffleController,
        ),
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer),
          ),
        ),
      ],
    );

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/sync/media/video',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['path'],
      '/视频/第二个.mp4',
    );
    expect(find.text('第二个.mp4'), findsOneWidget);
  });

  testWidgets('pop 播放器后 onPlayerExited 恰好调用一次', (tester) async {
    final prefs = await _testPrefs();
    final shuffleController = RecordingShuffleController(
      ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: '第一个.mp4', relativePath: '/视频/第一个.mp4'),
          VideoItem(name: '第二个.mp4', relativePath: '/视频/第二个.mp4'),
        ],
        currentIndex: 0,
        directoryPath: '/视频',
      ),
    );
    final router = _shuffleRouter(shuffleController);
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        shufflePlaybackControllerProvider.overrideWith(
          () => shuffleController,
        ),
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer),
          ),
        ),
      ],
    );

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 点击播放器返回按钮（IconButton(Icons.arrow_back)，无 tooltip），
    // pop 完成后应触发一次 onPlayerExited。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(shuffleController.onPlayerExitedCallCount, 1);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
  });
}
```

### Step 15: 运行确认红灯

```bash
flutter test test/features/media/presentation/shuffle_appbar_actions_test.dart --reporter compact > fltest-phase12-shuffle.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-shuffle.log
```

Expected: `EXIT≠0`——`_navigateToPlayer` 仍走 `Navigator.push`，URI 不变化。

### Step 16: 迁移 ShuffleAppBarActions（+ shuffle controller 复用 helper）

**16a.** `lib/features/media/presentation/widgets/shuffle_appbar_actions.dart`：

- import 变化：删除 `../pages/video_player_page.dart`；新增 `package:go_router/go_router.dart`、`package:oh_my_llm/app/navigation/app_destination.dart`。
- `_onShufflePressed`：`videoUrl != null && state is ShufflePlaybackActive` 判定不变，但导航参数改为 `state.currentVideo.relativePath`（state 在 `if` 内已经类型收窄）：

```dart
    final videoUrl = await controller.startShuffle(currentDirectoryPath);

    if (!context.mounted) return;

    final state = ref.read(shufflePlaybackControllerProvider);
    if (videoUrl != null && state is ShufflePlaybackActive) {
      _navigateToPlayer(context, state.currentVideo.relativePath, controller);
    } else {
      context.showWarningBubble('当前目录下未找到视频文件');
    }
```

- `_onNextPressed` / `_onPrevPressed`：URL 返回值仅作成功/null 判定，导航用 `state.currentVideo.relativePath`：

```dart
  Future<void> _onNextPressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = controller.playNext();
    if (videoUrl == null) return;
    final state = ref.read(shufflePlaybackControllerProvider);
    if (state is ShufflePlaybackActive) {
      _navigateToPlayer(context, state.currentVideo.relativePath, controller);
    }
  }
```

（`_onPrevPressed` 同理：`playPrevious()` 判定后同样调用 `_navigateToPlayer(context, state.currentVideo.relativePath, controller)`。）

- `_navigateToPlayer` 改为 GoRouter 子路由 + 保留 exit contract：

```dart
  Future<void> _navigateToPlayer(
    BuildContext context,
    String relativePath,
    ShufflePlaybackController controller,
  ) async {
    await context.pushNamed(
      AppRouteName.mediaVideo,
      queryParameters: {AppRouteParameter.mediaPath: relativePath},
    );
    if (context.mounted) {
      controller.onPlayerExited();
    }
  }
```

（`fileName` 参数已删除——`MediaVideoRoutePage` 由 URL path 推导文件名；三个调用处均不再传 `state.currentVideo.name`。`_onPrevPressed` 与 `_onNextPressed` 结构相同。）

**16b.** `lib/features/media/application/shuffle_playback_controller.dart` 的 `buildVideoUrl` 内部复用 helper（public contract 不变）：

```dart
  /// 构建视频播放 URL。
  String? buildVideoUrl(String relativePath) {
    final server = ref.read(mediaBrowserControllerProvider).server;
    if (server == null) return null;
    return buildMediaResourceUrl(server, 'video', relativePath);
  }
```

（顶部 `import '../utils/path_utils.dart';` 已存在。）

### Step 17: 更新过时注释与 leaf 测试回归

`test/features/media/presentation/image_viewer_page_test.dart` 第 234 行附近，把：

```dart
      // ImageViewerPage 通过 Navigator.push 进入，pop 后应返回上一个路由
      // 在测试中，由于只有这一层页面，pop 后会显示空或前一个路由。
      // 直接验证返回到 pumpTestApp 的初始路由（即不再有 ImageViewerPage 的内容）
```

改为：

```dart
      // ImageViewerPage 是路由承载的页面，pop 后应返回父页面。
      // 在测试中作为唯一页面，pop 后不再有 ImageViewerPage 的内容。
```

（只更新描述，不改变断言。）

### Step 18: 运行 media 定向回归（三组命令）

```bash
flutter test test/features/media/utils/path_utils_test.dart test/features/media/presentation/media_route_pages_test.dart test/features/media/presentation/media_browser_navigation_test.dart test/features/media/presentation/shuffle_appbar_actions_test.dart --reporter compact > fltest-phase12-media-routes.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-routes.log
```

```bash
flutter test test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/application/shuffle_playback_controller_behavior_test.dart test/features/media/application/shuffle_playback_controller_test.dart --reporter compact > fltest-phase12-media-leaf.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-media-leaf.log
```

```bash
flutter test test/features/sync/sync_screen_test.dart --reporter compact > fltest-phase12-sync-workspace.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-sync-workspace.log
```

每条预期 `EXIT=0`。若 sync workspace 测试依赖 Android media tab 与真实 controller（而非 fake），需确认其 seed 方式仍兼容（它已有 Android media session init/reset 覆盖，未受影响）。

### Step 19: 静态审计与提交

```bash
rg -n "Navigator\.push|MaterialPageRoute|state\.extra|extra:" lib/features/media/presentation lib/app/router
rg -n "MediaServerInfo|host|httpPort|imageUrls|videoUrl" lib/app/router lib/app/navigation
```

判读：
- 第一条在 media production navigation source（`media_browser_tab.dart`/`shuffle_appbar_actions.dart`/`app_router.dart`）中不得再命中 push/MaterialPageRoute/extra；`showDialog` 与 dialog/leaf 内部 pop 不在检查对象内。
- 第二条不得显示 route contract 携带 server authority、URL list 或 absolute media URL；route builder 只传 relative path。`VideoPlayerPage(videoUrl: ...)` 在 `media_route_pages.dart` 内允许命中（URL 解析后的 leaf contract）。

```bash
git diff --name-only -- '*.dart'
dart format lib/app/navigation/app_destination.dart lib/app/router/app_router.dart lib/features/media/application/shuffle_playback_controller.dart lib/features/media/presentation/media_browser_tab.dart lib/features/media/presentation/pages/media_route_pages.dart lib/features/media/presentation/widgets/shuffle_appbar_actions.dart lib/features/media/utils/path_utils.dart test/app/router/app_router_test.dart test/features/media/helpers/fake_video_player_controller.dart test/features/media/helpers/media_test_helpers.dart test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/media_browser_navigation_test.dart test/features/media/presentation/media_route_pages_test.dart test/features/media/presentation/shuffle_appbar_actions_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/utils/path_utils_test.dart
git add lib/app/navigation/app_destination.dart \
        lib/app/router/app_router.dart \
        lib/features/media/application/shuffle_playback_controller.dart \
        lib/features/media/presentation/media_browser_tab.dart \
        lib/features/media/presentation/pages/media_route_pages.dart \
        lib/features/media/presentation/widgets/shuffle_appbar_actions.dart \
        lib/features/media/utils/path_utils.dart \
        test/app/router/app_router_test.dart \
        test/features/media/helpers/fake_video_player_controller.dart \
        test/features/media/helpers/media_test_helpers.dart \
        test/features/media/presentation/image_viewer_page_test.dart \
        test/features/media/presentation/media_browser_navigation_test.dart \
        test/features/media/presentation/media_route_pages_test.dart \
        test/features/media/presentation/shuffle_appbar_actions_test.dart \
        test/features/media/presentation/video_player_page_test.dart \
        test/features/media/utils/path_utils_test.dart
git status --short
git diff --cached --name-only
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git commit -m "refactor(media): 统一媒体查看与播放路由"
```

- 如果某文件最终没有实际 diff（例如 `shuffle_playback_controller.dart` 未改动），先从 `git add` 删除该路径，禁止制造空改动。
- 提交只包含 Task 2 与 hook version bump，不夹带 `.opencode/plans` 删除。

---

## Task 3：验证 shell 条件未触发并完成全量门禁

**目标：** 以已有 ownership tests 证明 flat top-level routes 仍满足当前 UX；不创建无证据的 shell diff。

**Files:** 无生产改动；只运行验证。

### Step 1: 运行 Chat 卸载/重挂恢复证据（两条定向用例）

```bash
flutter test test/features/chat/chat_screen_test.dart --plain-name "ChatScreen 卸载后在同 scope 重挂，body 草稿恢复" --reporter compact > fltest-phase12-chat-remount.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-chat-remount.log
```

```bash
flutter test test/features/chat/chat_screen_test.dart --plain-name "编辑后卸载重挂丢弃编辑模式，草稿恢复为会话级值" --reporter compact > fltest-phase12-chat-edit-remount.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-chat-edit-remount.log
```

两条均 `EXIT=0` 即为「不触发 StatefulShellRoute」的当前行为证据。不要新增「切页后滚动 controller 必须是同一实例」之类实现细节测试。

### Step 2: route matrix 集成回归

```bash
flutter test test/app/router/app_router_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/favorites/favorites_screen_test.dart --reporter compact > fltest-phase12-navigation.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-navigation.log
```

`EXIT=0`。必须覆盖并通过：
- favorite direct/rebuild/invalid/deleted/push/back；
- media image/video push/back/missing path/session；
- desktop rail 与 compact navigation bar 仍切换顶层 destination；
- favorite 来源对话仍 go chat。

### Step 3: 生产代码范围审计

```bash
rg -n "state\.extra\s+as\s+Favorite|extra:\s*favorite|/favorites/detail" lib test
rg -n "Navigator\.push|MaterialPageRoute" lib/features/media/presentation
rg -n "StatefulShellRoute|StatefulNavigationShell" lib/app
rg -n "features/.*/data|core/persistence" lib/features/favorites/presentation lib/features/media/presentation
```

预期：
1. 旧 favorite extra contract 零命中；
2. media feature 不再有页面 push/MaterialPageRoute（`showDialog` 内 pop、viewer/player 自身 pop 除外）；
3. `lib/app` 仍无 StatefulShellRoute（这是明确判定结果，不是遗漏）；
4. favorites/media 的 presentation 层不穿透 data/persistence（`media_route_pages.dart` 只依赖 application/domain/utils）。

### Step 4: 格式化与暂存后复检

```bash
git diff --name-only -- '*.dart'
dart format <上一步列出的本 Phase Dart 文件>
git diff --check
git status --short
git diff --cached --name-only
dart format --output=none --set-exit-if-changed <全部 staged Dart 文件>
```

确认 `.opencode/plans/*.md` 删除不在 staged set；`--set-exit-if-changed` 非零退出不得提交。

### Step 5: 架构门禁与 analyze

```bash
flutter test test/architecture/import_boundary_checker_test.dart --reporter compact > fltest-phase12-architecture.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest-phase12-architecture.log
flutter analyze > flanalyze-phase12.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 flanalyze-phase12.log
```

预期均 `EXIT=0`，analyze 输出 `No issues found!`。

### Step 6: 强制格式全量测试

```bash
flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

- `EXIT=0`：通过；
- `EXIT≠0`：`grep -nE " -[1-9]" fltest.log` 定位失败，只修复本 Phase 引入的回归；
- 禁止直接运行不重定向的全量 `flutter test`。

### Step 7: 最终提交策略

正常情况下 Task 1、Task 2 已分别形成完整提交，Task 3 不产生生产代码。若最终门禁发现本 Phase 自身回归，用最小独立提交：

```bash
git commit -m "fix(navigation): 修复可恢复路由回归"
```

不得把 shell migration、UI redesign、媒体播放增强或 unrelated lint cleanup 放入该提交。

---

## 自检清单（对应契约完成定义）

- [ ] `/favorites/:favoriteId` 是唯一收藏详情 production route；旧 `/favorites/detail` 与 Favorite extra contract 已删除（Task 1 审计）。
- [ ] `FavoritesRepository.loadById`、SQLite 实现、`favoriteByIdProvider` 与 tests 完整（Task 1 Step 5–6）。
- [ ] 详情 direct URL、fresh router rebuild、invalid ID、missing/deleted ID、正常 push/back 均有行为测试（Task 1 Step 7）。
- [ ] FavoriteDetailScreen 不保存 route 传入 Favorite 镜像；rename/move/delete 后读取结果一致（Task 1 Step 10）。
- [ ] 图片与视频分别位于 `/sync/media/image`、`/sync/media/video` 子路由，URL 只携带 relative path query（Task 2 Step 9）。
- [ ] MediaBrowserTab 与 ShuffleAppBarActions 不再调用 `Navigator.push(MaterialPageRoute)`（Task 2 Step 12/16/19 审计）。
- [ ] media path 缺失/非法、server/session 缺失都有页面级恢复 UI 和返回操作（Task 2 Step 7）。
- [ ] 图片正常画廊、single fallback、视频播放/错误、shuffle exit lifecycle 保持现有产品行为（Task 2 Step 18 回归）。
- [ ] `AppDestination.values` 未增加详情/media；NavigationRail/NavigationBar 仍只显示五个顶层入口。
- [ ] StatefulShellRoute 触发条件已明确判定为未触发；未产生 shell migration diff（Task 3 Step 1/3）。
- [ ] 新 routed pages 通过 import boundary checker（Task 3 Step 5）。
- [ ] 所有改动 Dart 文件已 format，staged 后格式复检通过（Task 3 Step 4）。
- [ ] `flutter analyze` 为 `EXIT=0`（Task 3 Step 5）。
- [ ] 全量测试按重定向规范执行并得到 `EXIT=0`（Task 3 Step 6）。
- [ ] commits 按 Favorites/Media 两个 vertical slice 分开，未包含 `.opencode/plans` 删除等 unrelated 改动。

## 停止条件（遇到必须停下报告，不得自行扩大）

1. 为恢复 media route 需要持久化 peer IP/port/pairing credential 或整个媒体列表；
2. 必须改变 `ImageViewerPage` 缩放/PageView 或 `VideoPlayerPage` playback/gesture/orientation 才能接路由；
3. 出现真实顶层状态丢失 UX，且现有 Chat/Sync ownership 无法恢复——先提交失败行为测试与影响矩阵，再决定是否迁移 shell；
4. 需要修改 Favorite schema/domain/business rules 才能 `loadById`；
5. 需要让 feature presentation import data/core persistence——修正边界设计，而不是加入 architecture allowlist。
