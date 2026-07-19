# 设计文档：同步去重修复 + 收藏页增强

> 日期：2026-07-14
> 状态：已批准

---

## 一、问题概述

### Bug：同步时标量型设置不去重

同步功能在去重阶段对 `autoRetrySettings`、`customHeadersConfig`、`fontSizeSettings` 三个标量型配置直接透传，不做相等性比较。只要同步时选了"其它"分类，即使两端配置完全一致，也会被当作"有新数据"，导致每次同步都弹出导入确认对话框。

### 新功能：收藏页增强

1. **收藏项重命名**：当前 `Favorite` 模型没有 title 字段，列表中用 `userMessageContent` 前 10 字符作为标题替代。需要支持自定义标题。
2. **移动收藏项**：当前 `moveToCollection` / `moveTo` 方法已存在但 UI 上无入口。需要在收藏详情页提供"移动到收藏夹"的操作。

---

## 二、Bug 修复：同步去重

### 根因

`SettingsImportDeduplicator.deduplicate()`（`settings_import_deduplicator.dart:210-212`）对三个标量型配置直接透传：

```dart
autoRetrySettings: data.autoRetrySettings,      // 不比较
customHeadersConfig: data.customHeadersConfig,   // 不比较
fontSizeSettings: data.fontSizeSettings,          // 不比较
```

`hasContent`（`settings_export_data.dart:184`）只检查 `!= null`，因此只要服务端返回了这些配置就永远视为"有新数据"。

### 修复方案

在 `deduplicate()` 方法中增加本地配置的传入参数，使用 `Equatable` 的 `props` 进行相等性比较。如果远端值与本地值一致则置为 `null`（表示无新数据），不一致则保留远端值。

#### 改动文件

1. **`settings_import_deduplicator.dart`**
   - `deduplicate()` 新增 3 个可选参数：`existingAutoRetrySettings`、`existingCustomHeadersConfig`、`existingFontSizeSettings`
   - 返回 `SettingsExportData` 时对每个标量配置做相等性检查：
     - 如果 `existingXxx == data.xxx` 则置 `null`
     - 否则保留 `data.xxx`

2. **`sync_client_controller.dart`**
   - `_deduplicate()` 传入本地当前的 `autoRetrySettingsProvider`、`customHeadersProvider`、`fontSizeSettingsProvider` 值

3. **`sync_server_controller.dart`**
   - `_buildExportData()` 补充 `fontSizeSettings` 的导出（当前缺失）

4. **`sync_import_confirm_dialog.dart`**
   - 补充 `customHeadersConfig` 和 `fontSizeSettings` 的展示行（当前缺失）

### 测试要点

- 两端 `autoRetrySettings` 完全一致时，去重后 `autoRetrySettings` 为 `null`
- 两端 `autoRetrySettings` 不同时，去重后保留远端值
- `customHeadersConfig` 同理（含空 headers 列表的情况）
- `fontSizeSettings` 同理
- 混合场景：部分一致部分不一致
- 全部一致时 `hasContent == false`，进入 `SyncPhase.noNewData`

---

## 三、新功能：收藏项重命名

### 数据层变更

#### `Favorite` 模型（`favorite.dart`）

新增 `String? title` 字段：

```dart
class Favorite extends Equatable {
  const Favorite({
    // ...existing fields...
    this.title,
  });

  final String? title;  // 自定义标题，null 时用 userMessageContent 前缀显示

  /// 列表展示用标题：有自定义标题则用，否则取 userMessageContent 前缀。
  String get displayTitle => title ?? userMessageContent;

  // copyWith 加入 title 参数
  // props 列表加入 title
}
```

#### 数据库迁移（`app_database.dart`）

- V10 迁移：`ALTER TABLE favorites ADD COLUMN title TEXT;`
- 全新安装在 `_createSchema()` 中直接包含 `title TEXT` 列
- 迁移逻辑：
  ```
  if (currentVersion < 10) {
    _migrateV10();
  }
  ```
  `_migrateV10()` 对已有数据库执行 `ALTER TABLE`；对新数据库在 `_createSchema()` 中包含列。

#### Repository 层

**`FavoritesRepository` 接口**新增：
```dart
void updateTitle(String favoriteId, String? title);
```

**`SqliteFavoritesRepository`**：
- `save()` SQL 加入 `title` 列
- `_rowToFavorite()` 读取 `title` 列
- 新增 `updateTitle()` 实现：`UPDATE favorites SET title = ? WHERE id = ?;`

#### Controller 层

**`FavoritesController`**新增：
```dart
void rename(String favoriteId, String? title) {
  _repo.updateTitle(favoriteId, title);
  _refresh();
}
```

### UI 变更

#### `FavoriteDetailScreen`（详情页）

- AppBar 标题从固定的 `'收藏详情'` 改为 `favorite.title ?? '收藏详情'`
- AppBar actions 新增编辑按钮（`Icons.edit_note_rounded`），tooltip 为"重命名"
- 点击后弹出 `AlertDialog`，包含一个 `TextField`，初始值为 `favorite.title ?? ''`
  - 输入框 placeholder 为"自定义标题（留空则使用消息摘要）"
  - 确认时调用 `favoritesProvider.notifier.rename(id, title.isEmpty ? null : title)`
  - `FavoriteDetailScreen` 从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，内部维护 `_favorite` state
  - 初始化时从 GoRouter extra 接收 `Favorite` 对象存入 state
  - 重命名后通过 `ref.read(favoritesProvider).firstWhere(...)` 获取更新后的 `Favorite`，刷新 state（不 pop）
  - 移动收藏夹后同理刷新 state

#### `FavoriteListItem`（列表项）

- 第一行标题从 `_snippet(favorite.userMessageContent)` 改为：
  - `favorite.title != null` 时显示 `favorite.title`
  - 否则 fallback 到 `_snippet(favorite.userMessageContent)`

### 测试要点

- 新建收藏默认 `title == null`，列表显示消息摘要前缀
- 设置自定义标题后，列表项和详情页 AppBar 显示自定义标题
- 清除自定义标题（设为空字符串）后，fallback 回消息摘要前缀
- 数据库迁移：旧数据 `title` 列为 `NULL`，不影响现有展示

---

## 四、新功能：移动收藏项到其它收藏夹

### 数据层

已有 `moveToCollection` / `moveTo` 方法，无需改动。

### UI 变更

#### `FavoriteDetailScreen`（详情页）

在 `FavoriteCard` 的元信息行中，收藏夹名称旁边新增"移动到收藏夹"按钮：

- 图标：`Icons.drive_file_move_outline`
- 点击后弹出选择器对话框，复用 `AddToFavoritesDialog` 的模式：
  - 列出"未分类"选项 + 所有收藏夹
  - 支持新建收藏夹
  - 选中后调用 `favoritesProvider.notifier.moveTo(favorite.id, selectedCollectionId)`
- 移动后 UI 通过 `ref.watch` 自动刷新

#### `FavoriteCard` 变更

- 新增 `onMoveToCollection` 回调参数（`VoidCallback?`）
- 在元信息行中，收藏夹名称后添加移动按钮

### 测试要点

- 从"未分类"移动到某收藏夹后，详情页元信息行显示新收藏夹名称
- 从某收藏夹移动到"未分类"后，收藏夹标签消失
- 移动后列表筛选视图正确刷新

---

## 五、影响范围

| 文件 | 变更类型 |
|------|---------|
| `lib/features/settings/application/settings_import_deduplicator.dart` | 修改 - 增加标量配置去重 |
| `lib/features/sync/application/sync_client_controller.dart` | 修改 - 传入本地标量配置 |
| `lib/features/sync/application/sync_server_controller.dart` | 修改 - 补充 fontSizeSettings 导出 |
| `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart` | 修改 - 补充展示行 |
| `lib/features/favorites/domain/models/favorite.dart` | 修改 - 新增 title 字段 |
| `lib/core/persistence/app_database.dart` | 修改 - V10 迁移 |
| `lib/features/favorites/data/favorites_repository.dart` | 修改 - 新增 updateTitle 接口 |
| `lib/features/favorites/data/sqlite_favorites_repository.dart` | 修改 - SQL 更新 |
| `lib/features/favorites/application/favorites_controller.dart` | 修改 - 新增 rename 方法 |
| `lib/features/favorites/presentation/favorite_detail_screen.dart` | 修改 - 重命名 + 移动 UI |
| `lib/features/favorites/presentation/widgets/favorite_list_item.dart` | 修改 - title 展示 |
| `lib/features/favorites/presentation/widgets/favorite_card.dart` | 修改 - 移动按钮 |

### 测试文件

| 文件 | 变更类型 |
|------|---------|
| `test/features/settings/settings_import_deduplicator_test.dart` | 新增/修改 - 标量配置去重测试 |
| `test/features/favorites/domain/favorite_test.dart` | 修改 - title 字段测试 |
| `test/features/favorites/data/sqlite_favorites_repository_test.dart` | 修改 - updateTitle 测试 |
| `test/features/favorites/application/favorites_controller_test.dart` | 修改 - rename 测试 |
| `test/features/favorites/favorites_screen_test.dart` | 修改 - title 展示测试 |
| `test/core/persistence/app_database_test.dart` | 修改 - V10 迁移测试 |
