# Favorites 路由独占分页查询实施记录

**候选**：全仓 ponytail audit #10

**分支**：`refactor/favorites-route-pagination`

**状态**：已实施，待 PR 合入

## 目标

删除 Favorites 对 route 分页状态的第二份 controller/state 所有权，让收藏夹路径与 query 参数直接决定同步分页查询，同时保留现有 SQLite schema、路由格式、分页视觉组件、History 异步查询控制器、选择行为和错误恢复语义。

不在范围内：修改共享 `AppPaginationBar`、`AppPaginatedListShell`、`AppPaginationState`，调整 History 分页，改变 Favorites repository、数据库迁移、收藏排序或本地容量偏好格式。

## 实施前基线

记录时间：2026-09-04，基于 `master` `84a5ca4`。

- `FavoriteBrowserController`、`FavoriteBrowserState` 与页面共同维护 collection/page/pageSize/items/error，route 变化需要页面 post-frame 回显到 controller。
- controller 生产文件 237 行；收藏夹内容页 420 行，相关生产路径合计 657 行。
- controller 契约测试 254 行，另有 Favorites 整页分页、选择、详情返回、删除收藏夹和故障恢复测试。
- Favorites 定向基线 59 tests 通过，约 24 秒；shared pagination 与 History 各自已有独立测试所有权。

## 最终设计

- `FavoritePageQuery` 是 route-owned 的 `collectionId/page/pageSize` record；`FavoritePageWindow` 返回有效收藏夹、规范页码、容量与 `FavoritePage`。
- `favoritePageWindowProvider` 是同步 `Provider.family<AsyncValue<FavoritePageWindow>, FavoritePageQuery>`，watch 收藏库 revision 后直接查询 repository。
- provider 统一处理首页下界、非法容量、失效收藏夹回退、越界末页重查和固定安全错误，不缓存第二份可变分页状态。
- 页面从 route 与持久化容量偏好构造 query；翻页和切换容量只 replace URL。成功结果与显式 route 不一致时再规范化 URL。
- 页面仅保留 `_lastSuccessfulWindow` 供失败时显示旧内容；该缓存不参与下一次查询，也不决定 URL。
- 收藏选择、键盘操作、详情 push/pop 与容量偏好仍由原有 owner 负责；共享分页 core 与 History 异步控制器未修改。

## 测试重组

- 以 `favorite_page_window_provider_test.dart` 替换旧 controller 测试，通过 route query 外部契约覆盖参数规范化、失效收藏夹、mutation 自动重查、末页消失和安全错误。
- 整页测试继续覆盖 URL 翻页、容量持久化、详情返回、失败旧内容与重试、选择清理及收藏夹删除。
- 强化末页删除和当前收藏夹删除断言：除页面内容外，还验证 URL 被规范化到真实页码或系统收藏夹。
- 故障注入测试同时绑定真实 Favorites repository，避免旧 controller 吞掉缺失测试依赖后产生的伪空态。

## 实施结果

- `lib/`：净减 **103 行**（删除 237 行 controller；新增 78 行查询 provider；页面净增 56 行；注释替换不改变行数）。
- `test/`：净减 **7 行**（旧 controller 测试替换为更窄的 provider 契约表，并强化 route 断言）。
- 最终生产路径对 `FavoriteBrowserController`、`FavoriteBrowserState`、`favoriteBrowserProvider` 的引用为零。
- route 成为 collection/page/pageSize 的唯一 writer；同步 provider 没有命令 API、可变 cache 或第二套分页状态机。
- SQLite schema、Favorites 数据格式、路由参数名、本地容量偏好格式、共享分页 core 与 History 查询均未修改。

## 验证记录

- Favorites 全域 96 tests：通过，约 11 秒，日志 `logs/favorites-route-pagination-green.log`。
- `flutter analyze`：通过，0 issue，日志 `logs/favorites-route-pagination-analyze.log`。
- `dart run tool/check_import_boundaries.dart`：通过，检查 388 个文件、0 违规，日志 `logs/favorites-route-pagination-boundaries.log`。
- 全量测试：1,719 tests 通过，约 40 秒，日志 `logs/fltest.log`。
- Dart format：所有改动 Dart 文件已格式化；staged format gate 通过，0 个文件需要修改。

## 审查重点

- route query 是否是分页参数的唯一 owner，页面缓存是否严格只服务于错误时旧内容展示。
- 收藏夹失效和末页消失后，provider 查询结果与 URL canonicalization 是否保持一致。
- mutation revision 是否让相同 family query 自动重查，同时保留错误文案脱敏和显式重试。
- shared pagination、History async race、repository 与 SQLite 边界是否确实未被扩大修改。
