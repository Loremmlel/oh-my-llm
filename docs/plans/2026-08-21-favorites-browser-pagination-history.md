# 收藏浏览器、通用分页与历史页体验 Implementation Plan

> **交给 agentic worker：** 一次只执行一个 Task。每个 Task 必须先保存 red 证据，再完成实现、保存 green 证据、格式化并提交。不要预做后续 Task，也不要把计划中的非目标顺手纳入。

**Goal:** 将收藏从顶部 FilterChip + 全量列表重构为“收藏夹动态网格 → 收藏项真实分页列表 → 收藏项详情”的两级浏览器，同时抽取受控分页 module，并让历史页采用相同的固定底部分页与当前页选择体验。

**Architecture:** Core pagination module 只拥有页码算法、受控分页栏和固定底部分页列表外壳；Favorites 独占收藏查询、迁移、选择、移动和删除语义；History 仍是 Chat 的 read model，保留时间分组与标题/用户消息搜索。SQLite v14 将“未分类”升级为固定、不可删除的系统收藏夹，所有收藏归属非空。页面浏览状态由可序列化 route query 驱动，本地只保留选择与滚动等瞬态状态。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` · Riverpod 3 `NotifierProvider` · 原始 `sqlite3` · SharedPreferences · `go_router` · Material 3。

---

## 1. 这份计划属于什么

- 前置 `grilling` 已完成 **to-spec**：产品决策、边界和异常路径已确认。
- 本文是 **to-tickets / implementation plan**：把规格拆成小模型可逐项执行的代码任务。
- 若实现中发现规格缺口，停止对应 Task 并回报，不得自行扩展产品行为。

## 2. 已确认的产品契约

### 收藏

- 只有两级：收藏夹总览 → 收藏项分页列表；不支持嵌套。
- 收藏夹总览使用 `AppAdaptiveGrid`，卡片显示名称、数量、最近收录时间。
- 收藏项使用分页列表；固定按 `created_at DESC, id DESC` 排序，不提供搜索或排序控件。
- 分页容量为 `10 / 20 / 50`，默认 20；收藏功能独立持久化最近容量。
- 分页栏固定在页面底部，列表独立滚动；翻页后回到列表顶部。
- 多选只在当前页有效；翻页、修改容量和重新查询时清除。
- 单项和批量删除都要确认；批量操作只包含移动和删除。
- 收藏详情保留 Markdown/推理展示，整理标题、归属、模型、时间与操作层级。
- 从详情返回时恢复收藏夹、页码、页容量、滚动位置；不恢复多选。
- 成功添加/移动收藏后记住最近使用的收藏夹；目标失效时回退系统“未分类”。

### 系统“未分类”收藏夹

- 使用固定保留 ID，作为真实 SQLite 行存在。
- 始终存在、始终显示、固定置顶；空时显示 0 项。
- 不可重命名、不可删除；普通收藏夹禁止创建/改名为“未分类”。
- `favorites.collection_id` 必填；所有旧 null/空归属迁入系统收藏夹。
- `collection_assigned_at` 记录加入当前收藏夹的时间；移动时更新。
- 删除普通收藏夹默认把内容原子移动到“未分类”，也可选择其他目标；危险次级选项为连同其中收藏一起删除。

### 历史

- 使用同一个分页 module 和固定底部分页布局。
- 保留时间分组与现有搜索契约：只匹配标题和用户消息，不匹配 assistant。
- 搜索增加清空与无结果恢复入口；窄屏不得溢出。
- 选择只在当前页有效；交互与收藏对齐。
- 打开会话使用可返回导航，返回时恢复搜索、页码、页容量和滚动位置。
- 历史拥有独立的 page-size 偏好；不与收藏共用。
- 修复删除后 OFFSET 漏项、搜索态重命名结果不一致和隐藏跨页选择。

## 3. 严格非目标

- 嵌套收藏夹、标签、手动拖拽排序。
- 收藏搜索 UI/SQL、收藏排序选择器、收藏项网格模式。
- 跨页选择、“选择全部搜索结果”。
- 删除撤销、软删除、收藏内容编辑器。
- 收藏导入导出、Settings transfer、LAN Sync 协议变更。
- Chat 侧栏全量 conversation summary 的架构改造。
- 新依赖、平台标签式布局分支、`state.extra` 传实体。

## 4. Deep-module 决策

### 真实 seam

1. `AppPaginationBar`：受控 interface；隐藏页码折叠、紧凑布局、页码跳转校验和 disabled 语义。
2. `AppPaginatedListShell`：受控 interface；隐藏 header/body/footer 排布、固定底栏、首次加载/旧内容错误状态和翻页回顶。
3. `FavoritesRepository` / `CollectionsRepository`：application port；SQLite adapter 隐藏 count + page 查询、批量 mutation 和删夹事务。

### 不得制造的浅抽象

- 不泛型化 Favorites/History Controller。
- 通用分页 module 不 import Riverpod、Favorites、History 或 Chat。
- 不把搜索防抖、收藏移动、历史 rename/delete reconciliation 放进 core。
- 选择行 wrapper 只有在收藏与历史最终产生完全相同的两个真实 adapter 后才可抽；否则保留各 feature 行 widget。

## 5. 执行与 Git 规则

- 实现分支使用 `feat/favorites-browser-pagination`；不得在 `master` 提交。
- 当前工作区已有无关未跟踪文件 `devtools_options.yaml`，任何 Task 都不得修改或暂存它。
- 所有 PowerShell 日志写入 `logs/`。
- 单文件/单目录测试的工具级硬超时设为 `60000`ms；全量测试设为 `240000`ms。
- 测试进程若超时，先运行 `./scripts/kill-stale-test-processes.ps1`，再诊断。
- 所有新增测试名称和注释使用简体中文。
- 每次提交前格式化本次改动的全部 Dart 文件；暂存后再次执行 `dart format --output=none --set-exit-if-changed`。
- commit subject/body 使用简体中文，保留英文 conventional 前缀。

## 6. 任务图与审查里程碑

| Task | 目标 | 依赖 | 推荐 commit |
|---|---|---|---|
| 1 | 抽取 core 受控分页 module | 无 | `feat(core): 抽取受控分页列表模块` |
| 2 | 修正 History 分页 application 契约 | 1 | `fix(history): 修正分页窗口与浏览状态` |
| 3 | History UI 采用共享分页和当前页选择 | 1, 2 | `refactor(history): 对齐分页列表交互` |
| 4 | History route 恢复与可返回 Chat 导航 | 2, 3 | `feat(history): 恢复分页浏览上下文` |
| 5 | 里程碑 A 门禁 | 1–4 | 仅有直接回归时提交 |
| 6 | SQLite v14 与系统收藏夹不变量 | 5 | `feat(favorites): 建立系统未分类收藏夹` |
| 7 | Favorites repository 真分页与事务 | 6 | `feat(favorites): 实现收藏分页查询与批量事务` |
| 8 | Favorites application 所有权与 Chat facade | 7 | `refactor(favorites): 分离浏览窗口与全局收藏身份` |
| 9 | 收藏夹动态网格与新 routes | 8 | `feat(favorites): 建立收藏夹浏览器` |
| 10 | 收藏项分页、多选、移动和删除 | 9 | `feat(favorites): 实现分页收藏项管理` |
| 11 | 详情页与添加/移动体验收口 | 8–10 | `refactor(favorites): 优化收藏详情与归类流程` |
| 12 | 集成、无障碍与全量门禁 | 6–11 | 仅有直接回归时提交 |

**推荐 PR seam：** Task 1–5 作为“通用分页 + 历史体验”PR；合入后 Task 6–12 作为“收藏浏览器 + v14”PR。若只使用一个 PR，也必须保留 Task 5 的中间 green checkpoint。

---

## Task 1：抽取 core 受控分页 module

**Files:**

- Create: `lib/core/widgets/pagination/app_pagination_state.dart`
- Create: `lib/core/widgets/pagination/app_pagination_bar.dart`
- Create: `lib/core/widgets/pagination/app_paginated_list_shell.dart`
- Create: `lib/core/widgets/pagination/pagination.dart`
- Create: `test/core/widgets/pagination/app_pagination_state_test.dart`
- Create: `test/core/widgets/pagination/app_pagination_bar_test.dart`
- Create: `test/core/widgets/pagination/app_paginated_list_shell_test.dart`
- Reference only: `lib/features/history/presentation/widgets/history_pagination_bar.dart`

**Interface:**

- `AppPaginationState(currentPage, pageSize, totalItems, isBusy)`，派生 `totalPages/hasPrevious/hasNext`。
- `AppPaginationBar(state, pageSizeOptions, onPageChanged, onPageSizeChanged)`。
- `AppPaginatedListShell(header, bodyBuilder, paginationState, ...callbacks, pageIdentity, initialLoading, error, onRetry)`。
- `bodyBuilder` 获得 shell 所有的 `ScrollController`；caller 只构建 feature-owned 列表内容。

**Invariants:**

- 页码从 1 开始；总数为 0 时 currentPage 仍安全归一为 1，分页栏可隐藏。
- 页码折叠规则保持既有 History 行为：不超过 7 页全显，否则首 2、尾 2、当前 ±1，中间省略。
- compact 模式提供上一页、`X/Y`、下一页和容量；宽模式显示页码与跳转。
- busy 时禁止所有 page mutation，但不清空已有 body。
- `pageIdentity` 变化后回到列表顶部；详情 push/pop 未改变 identity 时保持滚动。
- module 内不得出现 Provider/ref、业务文案或 feature import。

- [ ] **Step 1：先写纯状态与页码算法失败测试**

覆盖：0/1/7/8/100 页、越界 currentPage 夹取、前后页、相同页不回调、非法跳转文本不回调。

- [ ] **Step 2：写分页栏失败 widget tests**

覆盖宽/窄父约束、busy disabled、容量选择、页码跳转、Semantics label、48px 命中区域。测试必须用父级 `SizedBox(width: ...)`，不得改整窗平台标签。

- [ ] **Step 3：写列表外壳失败 widget tests**

覆盖固定 footer、body 独立滚动、初始 loading、旧内容 + inline error、retry、pageIdentity 改变回顶、push/pop 等价重建时滚动不被错误清空。

- [ ] **Step 4：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/widgets/pagination --reporter compact 2>&1 | Out-File -Encoding utf8 logs/pagination-core-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/pagination-core-red.log
```

Expected: `EXIT≠0`，类型尚不存在。

- [ ] **Step 5：实现最小受控 interface**

从 `HistoryPaginationBar` 搬移纯页码算法与视觉行为，不复制 Riverpod 读取。不要删除旧 History widget；Task 3 才切 consumer。

- [ ] **Step 6：保存 green 证据**

```powershell
flutter test test/core/widgets/pagination --reporter compact 2>&1 | Out-File -Encoding utf8 logs/pagination-core-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/pagination-core-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7：格式化、暂存检查并提交**

```powershell
$Files = @(
  'lib/core/widgets/pagination/app_pagination_state.dart',
  'lib/core/widgets/pagination/app_pagination_bar.dart',
  'lib/core/widgets/pagination/app_paginated_list_shell.dart',
  'lib/core/widgets/pagination/pagination.dart',
  'test/core/widgets/pagination/app_pagination_state_test.dart',
  'test/core/widgets/pagination/app_pagination_bar_test.dart',
  'test/core/widgets/pagination/app_paginated_list_shell_test.dart'
)
dart format $Files
git add -- $Files
dart format --output=none --set-exit-if-changed $Files
git commit -m "feat(core): 抽取受控分页列表模块"
```

---

## Task 2：修正 History 分页 application 契约

**Files:**

- Modify: `lib/features/chat/domain/history_pagination_state.dart`
- Modify: `lib/features/chat/application/history/history_pagination_controller.dart`
- Create: `lib/features/chat/application/history/history_browse_preferences_controller.dart`
- Modify: `test/features/chat/application/history/history_pagination_controller_test.dart`
- Create: `test/features/chat/application/history/history_browse_preferences_controller_test.dart`

**Interface changes:**

- state 增加显式 `isInitialized`、可空 `errorMessage`，并保留旧页数据支持 stale-content error。
- controller 增加单一 `loadRoute({page, pageSize, keyword})`/等价入口；所有 route 输入在一处 trim、校验和夹取。
- page size 偏好 key 固定为 `app.feature.history.page_size`，仅接受 10/20/50。
- `afterDelete` 与搜索态 `afterRename` 必须重新查询，不允许只修本地列表造成 OFFSET/匹配错误。

- [ ] **Step 1：改写失败测试，先锁定两个现存 bug**

1. 40 条、每页 20、当前第 1 页删除 1 条后，当前页仍为 20 条，原第 2 页首项被补入，下一页不漏项。
2. 搜索关键词命中标题，rename 后不再命中时，该项从当前结果消失、总数修正；反向进入匹配也按 repository 查询结果决定。

删除锁定“仅本地移除后留下 19 项”的旧断言；这是错误行为，不保留兼容。

- [ ] **Step 2：补 route load、error 和偏好失败测试**

覆盖非法 page/pageSize、页码越界、查询抛错时保留旧内容、retry 成功、SharedPreferences revive、非法偏好回退 20、History/Favorites key 不共用。

- [ ] **Step 3：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/history --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-pagination-application-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/history-pagination-application-red.log
```

- [ ] **Step 4：实现 query reconciliation**

- 抽一个 controller 私有 `_reloadCurrentWindow()`，统一 count、夹取页码、load 当前窗口和错误处理。
- delete 后一律按数据库真实结果重拉当前窗口；不得根据 remaining 非空就跳过补页。
- keyword 非空时 rename 后重拉；keyword 为空可本地更新标题，但不得破坏 revision 语义。
- SharedPreferences 写失败只保留内存选择，不阻塞浏览。
- 不把 History Controller 泛型化，也不改 Chat repository port 的搜索契约。
- 为保证 Task 2 单独 green，可暂留 `loadInitial()` 作为只委托 `loadRoute` 的兼容入口；Task 4 route 接管初始化后必须删除该入口和全部调用。

- [ ] **Step 5：保存 green 证据并提交**

```powershell
flutter test test/features/chat/application/history --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-pagination-application-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/history-pagination-application-green.log
```

格式化本 Task Dart 文件，精确暂存后提交：

```powershell
git commit -m "fix(history): 修正分页窗口与浏览状态"
```

---

## Task 3：History UI 采用共享分页和当前页选择

**Files:**

- Modify: `lib/features/history/presentation/history_screen.dart`
- Modify: `lib/features/history/presentation/widgets/history_toolbar.dart`
- Modify: `lib/features/history/presentation/widgets/history_conversation_tile.dart`
- Delete: `lib/features/history/presentation/widgets/history_pagination_bar.dart`
- Modify: `lib/features/history/presentation/widgets/history_widgets.dart`
- Modify: `lib/features/history/presentation/widgets/empty_history_view.dart`
- Modify: `test/features/history/history_screen/history_screen_actions_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_pagination_bar_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_test_helpers.dart`
- Create: `test/features/history/history_screen/history_screen_responsive_cases.dart`
- Modify: `test/features/history/history_screen_test.dart`

**Required behaviour:**

- 保留 `GroupedConversationList` 与时间桶；它们是 History/Chat 领域实现，不进入 core。
- 分页栏固定在 Card/页面底部；列表在其上独立滚动。
- 普通态不常驻 checkbox 和 rename 图标；overflow 提供选择、重命名、删除。
- Windows：Ctrl-click、Shift-click 当前页区间、Ctrl+A 当前页、Esc 退出、Delete 弹确认、右键菜单/菜单键。
- Android：长按进入选择；overflow 是可发现的等价入口。
- 选择态点击整行切换选择；翻页、容量变化、搜索生效前清空选择。
- 工具栏 normal 模式显示搜索；selection 模式显示已选数量、选择当前页/清除、删除、退出。
- 搜索框有 clear，窄屏使用可用父宽；超宽内容使用现有 `AppContentWidths` 合理限宽。

- [ ] **Step 1：先改 widget tests 为简体中文并写 red cases**

新增：

- 分页栏位于可滚动列表之后且不随列表滚动。
- 320px 父宽搜索框不 overflow；1440px 时内容不无限拉伸。
- 翻页/容量/搜索清除选择。
- overflow 单删确认；取消不删除。
- Shift 当前页区间选择、Ctrl+A、Esc、Delete。
- normal tap 导航、selection tap 只切选择。
- 搜索无结果可以清除关键词。

- [ ] **Step 2：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-pagination-ui-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/history-pagination-ui-red.log
```

- [ ] **Step 3：迁移到 core pagination module**

- `HistoryScreen` 将 History state 映射成 core `AppPaginationState`。
- callbacks 只转发 controller/route intent；core 不读 Provider。
- `AppPaginatedListShell.bodyBuilder` 内构建时间分组列表。
- 删除旧 `HistoryPaginationBar` 及所有引用；禁止留一层 pass-through wrapper。

- [ ] **Step 4：实现选择与 responsive 交互**

选择 anchor 只在当前页内有效；清选择时同时清 anchor。所有菜单 action 必须有 tooltip/Semantics；disabled、selected 和 count 状态可被读屏识别。

- [ ] **Step 5：保存 green 证据并提交**

```powershell
flutter test test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-pagination-ui-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/history-pagination-ui-green.log
```

格式化、精确暂存后提交：

```powershell
git commit -m "refactor(history): 对齐分页列表交互"
```

---

## Task 4：History route 恢复与可返回 Chat 导航

**Files:**

- Modify: `lib/app/navigation/app_destination.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/features/history/presentation/history_screen.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/features/history/history_screen/history_screen_actions_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_pagination_bar_cases.dart`

**Route contract:**

- `/history?page=2&pageSize=20&q=关键字`。
- query 缺失时：page=1，pageSize 使用 History 偏好，q=''。
- URL pageSize 合法时优先并回写偏好；非法值回退偏好/20。
- 页面 mutation 使用 replace 更新当前 History location，避免堆叠每次按键/翻页历史记录。
- 点击会话使用 push 到 `/chat?conversationId=<id>`；pop 恢复原 History widget、route 和 scroll。
- 多选不进入 URL，也不在 push/pop 后保留。

- [ ] **Step 1：写 route parser/round-trip 失败测试**

覆盖中文 q 编解码、非法整数、负数、pageSize 非法、页码因数据变化夹取、无参数默认。

- [ ] **Step 2：写 History → Chat → Back 失败测试**

种子至少 25 条并设置搜索；打开第 2 页会话，断言 Chat 收到序列化 conversationId，pop 后仍是相同 q/page/pageSize 且列表滚动 offset 恢复。

- [ ] **Step 3：保存 red、实现、保存 green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/router/app_router_test.dart test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-route-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/history-route-red.log
```

实现后用相同命令写 `logs/history-route-green.log`，要求 `EXIT=0`。

- [ ] **Step 4：提交**

```powershell
git commit -m "feat(history): 恢复分页浏览上下文"
```

---

## Task 5：里程碑 A 门禁

- [ ] 运行 core pagination、History application、History widget、router 定向测试。
- [ ] 运行 `dart run tool/check_import_boundaries.dart`，输出写 `logs/history-pagination-boundaries.log`。
- [ ] 运行 `flutter analyze`，输出写 `logs/history-pagination-analyze.log`。
- [ ] 运行强制重定向的全量测试，输出写 `logs/fltest.log`，工具超时 240000ms。
- [ ] 运行以下审计：

```powershell
rg -n "historyPaginationProvider|features/history|features/favorites" lib/core/widgets/pagination
rg -n "HistoryPaginationBar" lib test
rg -n "state\.extra|MaterialPageRoute" lib/features/history lib/app/router
git diff --check master...HEAD
git status --short
```

Expected:

- core pagination 无 feature/Riverpod import。
- `HistoryPaginationBar` 零引用且文件已删除。
- History 保留时间分组和搜索语义。
- `devtools_options.yaml` 仍未暂存、未修改。
- 没有门禁修复则不创建空提交。

---

## Task 6：SQLite v14 与系统“未分类”不变量

**Files:**

- Create: `lib/core/constants/app_reserved_entities.dart`
- Modify: `lib/core/persistence/app_database.dart`
- Modify: `lib/features/favorites/domain/models/collection.dart`
- Modify: `lib/features/favorites/domain/models/favorite.dart`
- Modify: `lib/features/favorites/application/favorites_controller.dart`
- Modify: `lib/features/favorites/application/collections_controller.dart`
- Modify: `lib/features/favorites/application/ports/favorites_repository.dart`
- Modify: `lib/features/favorites/application/ports/collections_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_favorites_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_collections_repository.dart`
- Modify: `lib/features/favorites/presentation/favorites_screen.dart`
- Modify: `lib/features/favorites/presentation/widgets/dialogs/manage_collections_dialog.dart`
- Modify: `test/core/persistence/app_database_migration_test.dart`
- Modify: `test/helpers/fixtures.dart`
- Modify: `test/features/favorites/favorites_screen_test_helpers.dart`
- Modify: affected Favorites/Chat test fixtures that construct `Favorite`/`ChatFavoriteDraft`

**Canonical constants:**

- 单一固定 ID，例如 `AppReservedEntities.uncategorizedFavoriteCollectionId = '__uncategorized_favorites__'`。
- 固定显示名 `未分类`；普通名称校验比较 trim 后的精确中文名称。
- 不允许 core persistence import Favorites feature；Favorites 可以读取这个纯常量。

**v14 schema:**

- `favorites.collection_id TEXT NOT NULL`。
- `favorites.collection_assigned_at TEXT NOT NULL`。
- FK 改为 `ON DELETE RESTRICT`/默认 NO ACTION；不得 SET NULL/SET DEFAULT。
- 索引至少包含 `(collection_id, created_at DESC, id DESC)` 和支持 collection card 最近收录聚合的索引。
- 全新 schema 创建 collections 后立即 seed 系统收藏夹。

**v13 → v14 migration:**

1. 单事务开始。
2. `INSERT OR IGNORE` 固定系统收藏夹，不能按 name 复用普通行。
3. 重建 favorites 表；旧 null/空/孤儿 collection_id 写固定系统 ID。
4. 旧记录 `collection_assigned_at = created_at`。
5. 保留全部既有 11 列与值，重建索引。
6. 执行 `PRAGMA foreign_key_check`；有结果则回滚并失败。
7. `PRAGMA user_version = 14`；提交。
8. 仍拒绝 `<13` 与 `>14`；v13 是唯一临时支持的旧基线。

- [ ] **Step 1：构造真实 v13 文件数据库并写失败测试**

必须覆盖：

- null favorite → 系统 ID，assignedAt=createdAt。
- 普通收藏夹 favorite 保持原 ID。
- 全部文本、reasoning、source、title、model 字段逐列不丢失。
- 系统行始终存在且仅一条。
- reopen v14 幂等。
- 删除系统行/直接删除有收藏普通夹被 FK 拒绝。
- v12/v15 显式拒绝。
- migration 中途失败回滚；原 v13 数据仍可由 raw sqlite 读取。

- [ ] **Step 2：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/persistence/app_database_migration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-v14-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/favorites-v14-red.log
```

- [ ] **Step 3：实现 migration 与全新 schema**

不要在 controller build 时懒创建系统行。SQLite 无法原地修改列/FK，必须重建表；不得漏掉 source/reasoning/finish 之外现存字段。

- [ ] **Step 4：收紧 domain**

- `Favorite.collectionId` 改为 required non-null。
- 增加 required `collectionAssignedAt`。
- 删除 `clearCollectionId`；`copyWith` 不允许重新制造 null。
- `FavoriteCollection.isSystem` 或等价纯判断只依赖固定 ID，不依赖名称。
- 所有 test fixture 显式使用普通 collection ID 或系统 ID；malformed/migration 测试才可 raw null。

为保证本 Task 独立编译并保持旧页面可用，必须同时做以下**临时兼容**：

- 旧 `FavoritesController.add/moveTo` 在 application 入口把 null/空串立即归一为系统 ID；Task 8 将 Chat/application interface 全面 non-null 后删除兼容参数。
- 旧 `loadAll(collectionId: '')` 暂时查询系统 ID，`null` 仍代表旧页面“全部”；Task 10 删除整个扁平 filter contract。
- 旧 FavoritesScreen 的 chip/管理 dialog 识别真实 system row，只显示一次“未分类”且禁用 rename/delete；Task 9 以 grid 替换。
- 当前 `CollectionsRepository.delete` 先以一个 transaction 移动到系统 ID 再删夹，使 v14 `RESTRICT` 下旧 UI 不崩；Task 7 用 typed `CollectionDeleteRequest` 替换。
- `SqliteCollectionsRepository.save` 在本 Task 就改为 UPSERT，不能等到 Task 7，避免 rename 触发 REPLACE 删除语义。

每条 shim 都有上述明确退出 Task；最终范围审计不允许残留。

- [ ] **Step 5：保存 green 证据并提交**

```powershell
flutter test test/core/persistence/app_database_migration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-v14-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/favorites-v14-green.log
```

运行受影响 Favorites/Chat domain tests，格式化、精确暂存后提交：

```powershell
git commit -m "feat(favorites): 建立系统未分类收藏夹"
```

---

## Task 7：Favorites repository 真分页、卡片投影与批量事务

**Files:**

- Create: `lib/features/favorites/domain/models/favorite_page.dart`
- Create: `lib/features/favorites/domain/models/favorite_collection_summary.dart`
- Create: `lib/features/favorites/domain/models/collection_delete_request.dart`
- Modify: `lib/features/favorites/application/ports/favorites_repository.dart`
- Modify: `lib/features/favorites/application/ports/collections_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_favorites_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_collections_repository.dart`
- Modify: `test/features/favorites/data/sqlite_favorites_repository_test.dart`
- Modify: `test/features/favorites/data/sqlite_collections_repository_test.dart`
- Modify: `test/integration/collections_cascade_integration_test.dart`

**FavoritesRepository final interface responsibilities:**

- `loadPage(collectionId, limit, offset)` 返回当前页 items + totalItems 的 `FavoritePage`；caller 不需要分别协调 count 与 query。
- `loadById`。
- `findByAssistantContent` 与 `loadMatchingAssistantContents`/等价定向查询，供 Chat 判断当前会话消息收藏身份；不得要求加载全部收藏。
- `save`、`deleteMany`、`moveMany`、`updateTitle`。
- `moveMany` 显式接收 application 提供的 `assignedAt`，同时更新 `collection_assigned_at`；repository 内不得自行读取系统时钟，批量 ID 为空时 no-op。

**CollectionsRepository final interface responsibilities:**

- `loadSummaries()`：系统夹置顶，其余按 name 稳定排序；每项包含 count 和 `COALESCE(MAX(collection_assigned_at), collection.created_at)`。
- `loadAll()`：用于选择器；排序同上。
- `save()`：使用 `INSERT ... ON CONFLICT(id) DO UPDATE`，禁止 `INSERT OR REPLACE`。
- `delete(CollectionDeleteRequest)`：同一 transaction 内移动/删除内容并删除普通收藏夹；返回受影响数量或可测试结果。

**CollectionDeleteRequest:**

- sealed/enum + value object 表达 `moveItemsTo(targetCollectionId, assignedAt)` 与 `deleteItems`。
- 不使用 nullable target 暗示模式。
- repository adapter 再次拒绝 system ID 作为被删 ID，不能只依赖 UI disabled。

- [ ] **Step 1：写分页 repository 失败测试**

覆盖：

- 0、1、21、51 条的 total/page window。
- 相同 createdAt 使用 id DESC 稳定排序，连续翻页无重复/遗漏。
- 只返回指定 collection。
- limit/offset 非法输入显式拒绝或在 port 文档约定处规范化，不能 SQL 字符串拼接。
- matching assistant contents 只返回请求集合，空集合不生成非法 `IN ()`。
- save/read 完整保留 `collectionAssignedAt`。

- [ ] **Step 2：写 collection summary 与 mutation 失败测试**

覆盖：

- 系统夹为空仍返回且置顶。
- 普通夹按名称排序；同名时 id 稳定 tie-break。
- count 正确；移动旧收藏进入夹后 recentAssignedAt 更新为移动时刻。
- rename 含收藏夹时归属不变，证明已移除 REPLACE 副作用。
- 默认移动删除、移动到指定夹、危险连同删除三条 transaction 路径。
- transaction 任一步失败全部回滚。
- 禁删系统夹、禁止目标为不存在收藏夹。

- [ ] **Step 3：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/favorites/data --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-repositories-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/favorites-repositories-red.log
```

- [ ] **Step 4：实现 SQLite adapters**

- 所有值使用参数绑定。
- page 的 count + rows 应由一个 repository method 隐藏；必要时在同一 read transaction 中取得一致快照。
- bulk ID 使用受控 placeholders；空集合直接返回。
- 不为未来搜索增加无使用者的方法。
- 临时保留旧 `loadAll(collectionId)` 只允许用于尚未迁移的旧 UI；加明确 doc：Task 10 删除。若能在本 Task 同时保持现 UI 编译且不保留它，则直接删除。

- [ ] **Step 5：保存 green 证据**

```powershell
flutter test test/features/favorites/data --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-repositories-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/favorites-repositories-green.log
flutter test test/integration/collections_cascade_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-collection-transaction-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/favorites-collection-transaction-green.log
```

- [ ] **Step 6：提交**

```powershell
git commit -m "feat(favorites): 实现收藏分页查询与批量事务"
```

---

## Task 8：Favorites application 所有权、偏好与 Chat facade

**Files:**

- Rewrite: `lib/features/favorites/application/favorites_controller.dart`
- Rewrite: `lib/features/favorites/application/collections_controller.dart`
- Create: `lib/features/favorites/application/favorite_browser_controller.dart`
- Create: `lib/features/favorites/application/favorites_browse_preferences_controller.dart`
- Create: `lib/features/favorites/application/favorites_clock_provider.dart`
- Modify: `lib/features/chat/application/favorites/chat_favorites_facade.dart`
- Modify: `lib/features/chat/application/favorites/chat_favorite_intent_command.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Modify: `test/features/favorites/application/favorites_controller_test.dart`
- Create: `test/features/favorites/application/favorite_browser_controller_test.dart`
- Create: `test/features/favorites/application/favorites_browse_preferences_controller_test.dart`
- Modify: `test/features/chat/application/favorites/chat_favorites_facade_test.dart`
- Modify: `test/features/chat/application/favorites/chat_favorite_intent_command_test.dart`
- Modify: `test/features/chat/application/workspace/chat_workspace_view_state_test.dart`

**Final ownership:**

- 一个 Favorites library mutation controller 独占 add/remove/rename/move/bulk/delete-collection/create/rename-collection，并在成功后递增 revision。
- `favoriteByIdProvider`、收藏夹 summaries、page controller 和 Chat adapter 都 watch 同一 revision；不能互相拿“当前页 items”充当全局事实。
- `FavoriteBrowserController` 只持当前 route query 的 page window、busy/error；route 仍是 page/pageSize/collectionId 的可序列化 owner。
- page size key：`app.feature.favorites.page_size`。
- 最近归类 key：`app.feature.favorites.last_collection_id`。
- 最近归类 ID 每次读取都校验存在且非待删除目标；失效回退系统 ID并修正持久化值。
- `favoritesClockProvider` 的 interface 为 `DateTime Function()`；生产 adapter 返回 `DateTime.now()`，测试 override 固定时间。新增收藏、单项/批量移动、删夹时的 move disposition 全部从该 seam 取得时间并显式传给 repository。
- route 是 collectionId/page/pageSize 的唯一 writer；`FavoriteBrowserController` 只加载并缓存传入的不可变 route query，不提供会制造第二套页码 owner 的独立 `nextPage/setCollection` 状态机。

**Chat facade final interface:**

- `ChatFavoriteDraft.collectionId` required non-null。
- `beginToggle` 的 draft 默认使用最近有效收藏夹；不再产生 null/空串 sentinel。
- 为当前 Chat messages 定向查询收藏身份；不得 watch page provider 或加载全部 Favorites catalog。
- collection options 包含系统夹一次且置顶。
- `createCollection` 只创建并返回 ID；Add dialog 自己选中新夹，用户确认后才 add。
- 成功 add/move 才更新最近归类偏好；取消 dialog 不更新。

- [ ] **Step 1：先写状态所有权失败测试**

覆盖：

- 当前浏览第 N 页时，Chat 仍能识别其他页已收藏消息。
- 切换收藏夹/page 不改变 Chat 的收藏判断。
- add/remove/move/rename/bulk/delete collection 后 detail/page/summaries/Chat 同步失效。
- 删除当前收藏夹后 browser 自动回到可用 route/由 UI Task 处理导航，application 不留下孤儿 ID。
- 操作失败不 bump revision、不写最近选择。

- [ ] **Step 2：写偏好和 non-null Chat contract 失败测试**

覆盖 SharedPreferences revive、非法 page size、最近 ID 被删除、系统回退、创建新夹只选择不自动 add、restore 使用原 non-null collectionId。

- [ ] **Step 3：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/favorites/application test/features/chat/application/favorites test/features/chat/application/workspace/chat_workspace_view_state_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-application-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/favorites-application-red.log
```

- [ ] **Step 4：实现 deep mutation module 与 query controllers**

- 避免 `FavoritesController` 和 `CollectionsController` 各自缓存一份会互相漂移的数据。
- 所有 mutation 通过一个可观察 revision 通知 query readers。
- browser refresh 根据 repository 返回 total 修正页码并补齐当前页。
- 初始/刷新/翻页错误进入 state；有旧 items 时保留旧内容。
- SharedPreferences 写失败不回滚已经成功的数据库 mutation。

- [ ] **Step 5：重写 app composition adapter**

移除 `ref.watch(favoritesProvider)` → `ChatFavoritesSnapshot(entries: 全量)` 的绑定。adapter watch revision，按 Chat interface 的当前内容查询 repository；mutation 委托 Favorites application controller。

- [ ] **Step 6：保存 green 证据并提交**

```powershell
flutter test test/features/favorites/application test/features/chat/application/favorites test/features/chat/application/workspace/chat_workspace_view_state_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-application-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/favorites-application-green.log
```

```powershell
git commit -m "refactor(favorites): 分离浏览窗口与全局收藏身份"
```

---

## Task 9：收藏夹动态网格与新 routes

**Files:**

- Create: `lib/features/favorites/presentation/favorite_collections_screen.dart`
- Create: `lib/features/favorites/presentation/widgets/favorite_collection_grid.dart`
- Create: `lib/features/favorites/presentation/widgets/favorite_collection_tile.dart`
- Create: `lib/features/favorites/presentation/models/favorite_collection_grid_spec.dart`
- Create: `lib/features/favorites/presentation/widgets/dialogs/edit_collection_dialog.dart`
- Modify/Delete after replacement: `lib/features/favorites/presentation/favorites_screen.dart`
- Delete after replacement: `lib/features/favorites/presentation/widgets/dialogs/manage_collections_dialog.dart`
- Modify: `lib/app/navigation/app_destination.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/features/favorites/favorites_screen_test.dart`
- Modify: `test/features/favorites/favorites_screen_test_helpers.dart`
- Rewrite: `test/features/favorites/favorites_screen_basics_cases.dart`
- Rewrite: `test/features/favorites/manage_collections_dialog_cases.dart` or rename to collection-grid cases and update registration
- Create: `test/features/favorites/presentation/models/favorite_collection_grid_spec_test.dart`

**Routes:**

- `/favorites` → collection grid。
- `/favorites/collections/:collectionId?page=1&pageSize=20` → Task 10 list screen。
- `/favorites/items/:favoriteId` → detail。
- `/favorites/:favoriteId` → redirect 到新 item route；旧动态 route 必须排在静态 `collections`/`items` 之后，避免抢匹配。
- collectionId/page/pageSize 全部解析、校验；不使用 `state.extra`。

**Grid behaviour:**

- `AppAdaptiveGrid` + feature-owned spec；父约束驱动列数。
- 稳定高度卡片：folder icon、名称、`N 项收藏`、最近收录时间。
- 系统夹置顶，有低调 system 标识，无 rename/delete action。
- 普通卡片 click/Enter 打开；overflow、Windows context menu/menu key、Android long press提供 rename/delete。
- 明确 AppBar/FAB 新建入口；不把“虚线新建卡”混入数据。
- 新建成功留在总览，新卡获得可见焦点；不自动打开空夹。
- 创建/重命名为 trim 后“未分类”时 dialog inline 报错；不创建、不关闭。

- [ ] **Step 1：写 route 和 grid red tests**

覆盖：

- root 深链、collection 深链、新 detail、旧 detail redirect。
- `collections`/`items` 不被 legacy `:favoriteId` 吞掉。
- 系统夹空时仍显示并置顶。
- 320/720/1200 父宽连续 grid，不卡固定设备列数。
- 卡片 count/time、长名称 ellipsis + tooltip、focus/hover/selected Semantics。
- system action 缺失；普通夹 menu 完整。
- 新建、保留名失败、rename、empty folder delete。

- [ ] **Step 2：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/router/app_router_test.dart test/features/favorites/favorites_screen_test.dart test/features/favorites/presentation/models/favorite_collection_grid_spec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-grid-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/favorites-grid-red.log
```

- [ ] **Step 3：实现 routes 与 collection grid**

- Grid 只消费 application summaries，不 import data/core persistence。
- 最近收录为 collectionAssignedAt 聚合；空夹显示 collection.createdAt。
- 删除非空夹的完整 dialog 在 Task 10；本 Task 只允许 empty folder delete 或先挂接 application contract，不能临时静默级联。
- 若暂留 `FavoritesScreen` 作为命名 wrapper，它必须拥有真实职责；否则 rename/delete，禁止 pass-through 壳。

- [ ] **Step 4：保存 green 证据并提交**

用 Step 2 命令写 `logs/favorites-grid-green.log`，要求 `EXIT=0`。

```powershell
git commit -m "feat(favorites): 建立收藏夹浏览器"
```

---

## Task 10：收藏项真实分页、多选、移动与删除

**Files:**

- Create: `lib/features/favorites/presentation/favorite_collection_items_screen.dart`
- Rewrite: `lib/features/favorites/presentation/widgets/favorite_list_item.dart`
- Create: `lib/features/favorites/presentation/widgets/favorite_selection_toolbar.dart`
- Create: `lib/features/favorites/presentation/widgets/dialogs/move_favorites_dialog.dart`
- Create: `lib/features/favorites/presentation/widgets/dialogs/delete_collection_dialog.dart`
- Create: `test/features/favorites/favorites_screen_pagination_cases.dart`
- Create: `test/features/favorites/favorites_screen_selection_cases.dart`
- Create: `test/features/favorites/favorites_screen_collection_delete_cases.dart`
- Modify: `test/features/favorites/favorites_screen_test.dart`
- Modify: `test/features/favorites/favorites_screen_test_helpers.dart`
- Delete: old filter-chip cases and obsolete `favoritesFilterProvider` tests
- Delete final compatibility: old `favoritesFilterProvider`, filtered `favoritesProvider`, repository `loadAll(collectionId)` if Task 7 temporarily retained it

**List layout:**

- Windows/wide：title + assistant preview 为主体，model/time 为右侧 metadata。
- Android/narrow：相同信息纵向堆叠。
- title 最多 2 行、assistant preview 最多 2 行；不得固定截前 10 字。
- 夹内不重复 collection name。
- normal row click 打开详情；overflow 包含选择、移动、删除。

**Selection:**

- Set 只允许包含当前 page IDs。
- Ctrl-click 切单项；Shift-click 使用当前页顺序选闭区间；Ctrl+A 当前页；Esc 退出；Delete 确认。
- Android 长按进入；selection mode row tap 切换。
- page/pageSize/route collection 变化前清空 selection 和 anchor。
- toolbar：`已选择 N 项`、选择当前页/清除、移动、删除、退出。

**Collection deletion dialog:**

- 显示准确 count。
- 默认 radio：移动到系统“未分类”；可选择其他普通目标。
- 次级 danger radio：删除收藏夹及其中 N 项收藏。
- 目标不得为待删除夹；新建夹后只选中，仍需最终确认。
- application transaction 完成前 dialog busy、禁止重复提交；失败 inline 显示且不关闭。

- [ ] **Step 1：写 pagination/selection/delete red tests**

至少覆盖：

- 21 条默认 20，第 1/2 页内容和 total 正确；底栏固定。
- 10/20/50 切换持久化并更新 URL。
- 返回详情恢复 page/scroll。
- 删除/移动后当前页补齐；末页空后回退；全空显示夹内空状态。
- 翻页失败保留旧 page + inline retry。
- 选择不跨页；Shift、Ctrl+A、Esc、Delete；normal/selection tap 分流。
- 单删和批删取消/确认。
- 非空删夹默认 move、指定 move、danger delete、transaction error。
- 窄/宽行 layout 无 overflow，Semantics 不重复。

- [ ] **Step 2：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/favorites/favorites_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-paged-list-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 200 logs/favorites-paged-list-red.log
```

- [ ] **Step 3：实现 page screen 与交互**

- 页面将 Favorites browser state 映射到 core `AppPaginationState`。
- page callback 更新序列化 URL/controller，禁止只改本地整数。
- 使用 `AppPaginatedListShell` 固定底栏与 scroll owner。
- 初次加载 skeleton 与实际 row 高度接近；empty/error 文案归 Favorites presentation。
- 任何成功 mutation 后调用 application refresh/revision；不得直接 patch 多份 provider state。

- [ ] **Step 4：删除旧扁平浏览路径**

以下语义必须零结果：顶部“全部/未分类/收藏夹”FilterChip、`favoritesFilterProvider`、将空串当未分类的 production path、UI 全量 `loadAll`。

```powershell
rg -n "favoritesFilterProvider|setFilter\(|collectionId\.isEmpty|collection_id IS NULL" lib/features/favorites lib/app
```

允许 `collection_id IS NULL` 只出现在 v13→v14 migration SQL/迁移测试中。

- [ ] **Step 5：保存 green 证据并提交**

```powershell
flutter test test/features/favorites/favorites_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-paged-list-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 200 logs/favorites-paged-list-green.log
```

```powershell
git commit -m "feat(favorites): 实现分页收藏项管理"
```

---

## Task 11：详情页与添加/移动体验收口

**Files:**

- Modify: `lib/features/favorites/presentation/favorite_detail_screen.dart`
- Modify: `lib/features/favorites/presentation/widgets/favorite_card.dart`
- Modify: `lib/features/chat/presentation/widgets/dialogs/add_to_favorites_dialog.dart`
- Reuse/Modify: `lib/features/favorites/presentation/widgets/dialogs/move_favorites_dialog.dart`
- Modify: `test/features/favorites/favorites_screen_detail_cases.dart`
- Modify: `test/features/chat/presentation/chat_screen/chat_screen_favorites_cases.dart`
- Modify: `test/features/chat/application/favorites/chat_favorite_intent_command_test.dart`

**Detail hierarchy:**

- header：收藏 title、所属收藏夹、model、收藏时间。
- “查看来源对话”保持可见主操作；来源缺失/对话已删除时 disabled/recovery 文案明确。
- rename/move/delete 进入 overflow；delete 必须确认。
- content 继续复用 `FavoriteCard` 的用户消息、折叠 reasoning、Markdown assistant；不重写 renderer。
- wide 使用 `AppContentWidths.readable`；narrow 占满父宽。
- move 成功留在详情页，更新 collection chip；chip 可进入新收藏夹。
- back 回原夹时原 page/scroll 保持，该项自然消失。

**Add/move dialog:**

- initial selection = 最近有效收藏夹，否则系统夹。
- collection options 不再渲染额外手写“未分类” sentinel；系统行来自真实 options。
- 从 dialog 新建夹：留在 dialog、自动选中新夹；用户再次确认才 add/move。
- 普通名禁止 trim 后“未分类”；错误 inline。
- 成功 add/move 更新最近选择；取消不更新。

- [ ] **Step 1：写 detail/add/move red tests**

覆盖完整元数据、source action、overflow、move 后留页、chip navigation、wide/narrow、system initial selection、last selection revive、创建后未自动提交、取消不 mutation。

- [ ] **Step 2：保存 red 证据**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/favorites/favorites_screen_test.dart test/features/chat/presentation/chat_screen/chat_screen_favorites_cases.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-detail-flow-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/favorites-detail-flow-red.log
```

- [ ] **Step 3：实现并保存 green 证据**

使用相同命令输出 `logs/favorites-detail-flow-green.log`，要求 `EXIT=0`。

- [ ] **Step 4：提交**

```powershell
git commit -m "refactor(favorites): 优化收藏详情与归类流程"
```

---

## Task 12：集成、无障碍、架构与全量门禁

**Files:**

- Modify only files required to fix direct regressions from Task 6–11。
- Modify/add integration tests only when a confirmed contract lacks coverage。

- [ ] **Step 1：运行迁移与 repository integration**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/persistence/app_database_migration_test.dart test/features/favorites/data test/integration/collections_cascade_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-data-integration.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/favorites-data-integration.log
```

- [ ] **Step 2：运行 Favorites/History/Chat 定向回归**

```powershell
flutter test test/features/favorites test/features/history test/features/chat/application/favorites test/features/chat/application/history test/features/chat/presentation/chat_screen/chat_screen_favorites_cases.dart test/app/router/app_router_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/favorites-history-regression.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 200 logs/favorites-history-regression.log
```

- [ ] **Step 3：手工无障碍/键盘审计对应 widget tests**

确认：

- collection tile、favorite row、history row 的 Semantics label 唯一。
- selected/disabled/busy/error/live 状态可感知。
- hover 不是任何操作的唯一入口。
- focus ring 可见；Enter/Space/menu key/Ctrl/Shift/Esc/Delete 行为符合已确认契约。
- 所有 Material controls 命中区域满足 token；不重复包无价值 Semantics。

- [ ] **Step 4：运行架构门禁**

```powershell
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/favorites-history-boundaries.log; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 120 logs/favorites-history-boundaries.log
```

要求 `EXIT=0`。不得新增 allowlist 绕过。

- [ ] **Step 5：格式化全部本次改动 Dart 文件并检查**

```powershell
$DartFiles = git diff --name-only master...HEAD -- '*.dart'
if ($DartFiles) { dart format $DartFiles }
git add -- $DartFiles
$StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($StagedDartFiles) { dart format --output=none --set-exit-if-changed $StagedDartFiles }
```

非零不得继续。只暂存本计划文件和真实实现文件；不得暂存 `devtools_options.yaml`。

- [ ] **Step 6：运行 analyze**

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/favorites-history-analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/favorites-history-analyze.log
```

要求 `EXIT=0`、`No issues found!`。

- [ ] **Step 7：运行强制重定向全量测试**

工具级 timeout 必须设为 `240000`ms：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

要求 `EXIT=0`。失败时从 `logs/fltest.log` 查，不直接重跑无重定向测试。

- [ ] **Step 8：严格范围与废弃语义审计**

```powershell
rg -n "favoritesFilterProvider|setFilter\(|collectionId: null|clearCollectionId|collection_id IS NULL|ON DELETE SET NULL" lib test
rg -n "HistoryPaginationBar|favoritesProvider" lib/app lib/features/chat lib/features/favorites lib/features/history
rg -n "state\.extra|MaterialPageRoute" lib/features/favorites lib/features/history lib/app/router
rg -n "features/(favorites|history|chat)|flutter_riverpod" lib/core/widgets/pagination
rg -n "INSERT OR REPLACE INTO collections" lib test
git diff --check master...HEAD
git status --short
```

解释：

- `collection_id IS NULL`/nullable 构造只允许出现在 v13 migration 与 malformed migration tests。
- core pagination 不得命中 feature/Riverpod import。
- Chat 不得再由当前 page 构建全局收藏 snapshot。
- collection rename 不得使用 REPLACE。
- 无关 `devtools_options.yaml` 仍未暂存。

- [ ] **Step 9：人工响应式 smoke check**

至少检查 Windows 窗口宽 360/720/1200/1600 与 Android 常用窄屏：

- Favorites root grid 连续换列，无 overflow。
- Favorite/History row 信息层级合理。
- 固定底部分页栏不遮内容，compact 控件可用。
- dialog 在窄屏可滚动，危险删除含准确数量。
- detail wide 限宽、narrow 满宽。

- [ ] **Step 10：仅在确有直接回归时提交最小修复**

没有修复不创建空 commit。若需要：

```powershell
git commit -m "fix(favorites): 修复收藏浏览器集成回归"
```

---

## 7. 验收映射

| 验收项 | 主要证据 |
|---|---|
| v13 用户无损升级 | migration fixture、逐列断言、reopen、rollback、foreign_key_check |
| 未分类成为真实系统夹 | fresh schema + migrated schema、guard、grid empty-visible tests |
| 收藏是真分页 | repository page/total tests、无 UI `loadAll` 审计 |
| 稳定翻页无重复遗漏 | identical timestamp + id tie-break、多页遍历测试 |
| 删除/移动事务正确 | repository transaction + integration + failure rollback |
| Chat 收藏身份不受当前页影响 | targeted facade/application tests |
| 收藏夹动态 grid | geometry/spec/widget responsive tests |
| 当前页选择安全 | page/search/size clear、Ctrl/Shift/Android cases |
| 返回恢复浏览上下文 | route round-trip、push/pop、scroll tests |
| 通用分页是真实 seam | 两个 consumer、core 无 feature/Riverpod import |
| History 行为不退化 | 时间分组、搜索契约、rename/delete reconciliation tests |
| 双端功能等价 | keyboard/context menu/long press/overflow tests + smoke check |
| 架构与质量门禁 | import boundaries、format、analyze、full test |

## 8. 完成定义

只有以下条件全部满足才算完成：

1. Task 1–12 的 red/green 证据均在 ignored `logs/` 中。
2. v13→v14 是唯一临时旧基线迁移；未来版和更旧版仍显式拒绝。
3. production 不再存在 null/空串未分类语义、顶部 FilterChip 扁平浏览或 UI 全量 favorites 查询。
4. Favorites 与 History 都消费同一个 core pagination module，但查询/搜索/mutation 仍归各自领域。
5. 新 routes 可深链、旧 favorite detail route 可兼容、返回状态恢复。
6. 所有定向测试、架构门禁、格式、analyze 和全量测试通过。
7. diff 不包含严格非目标、临时调试代码、敏感信息或无关 `devtools_options.yaml`。
