# 历史页打开与搜索性能诊断实施计划

**Goal:** 用可复现 profile 解释历史页打开卡顿的真实归因，并且只在证据成立后选择一条最小修复路径；保持历史搜索、分页、路由、错误与选择行为不变。

**Architecture:** 当前 History 在首帧后由 `HistoryPaginationController` 同步执行 `COUNT -> page SELECT -> row mapping`。本计划先把 repository、controller、route/layout 的时间分开记录，再以硬门禁选择 SQL/query、历史专用 read adapter 或 UI/layout 三条路径之一。测量前不扩大全局 Chat repository，不把现有 writer isolate 兼作 reader，也不添加无执行计划证据的索引。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` / Riverpod 3 / sqlite3 FFI / Dart Timeline / Flutter DevTools Performance / PowerShell 7。

**Branch:** `perf/history-page-performance`

**Planning baseline:** `cfbb5299d8293196d1df9d37d11d115470c4ee51`。计划阶段完成了只读调用链审计和方向性内存 SQLite 合成基准，但没有在真实 Windows profile build 中录制 UI frame，没有修改生产代码，也不能把方向性数字写成修复验收结果。

**诊断执行状态（2026-08-22）:** Task 0/1/2 已完成；测量证据与唯一路径选择见「Task 2：测量结果」。本修订只含计划文档改动，等待用户批准修订后的 Candidate B 实施方案后才允许修改 production。

## 1. 已确认事实

### 1.1 历史页打开调用链

```text
AppShell context.go('/history')
  -> GoRouter 构造 HistoryScreen
  -> initState post-frame _syncFromRoute()
  -> HistoryPaginationController.loadRoute()
  -> countHistorySummaries(keyword)
  -> clamp requested page
  -> loadHistorySummaries(keyword, limit, offset)
  -> SQLite Row -> ChatConversationSummary mapping
  -> Riverpod state commit
  -> HistoryScreen/ListView.builder render current page
```

关键位置：

- `lib/app/shell/app_shell_scaffold.dart`：顶层导航 `context.go`。
- `lib/app/router/app_router.dart`：History route。
- `lib/features/history/presentation/history_screen.dart`：post-frame route 同步、300ms 搜索防抖、成功后 URL replace。
- `lib/features/chat/application/history/history_pagination_controller.dart`：同步 `count -> clamp -> load -> commit`。
- `lib/features/chat/data/persistence/background_chat_repository.dart`：只把写入放到 worker；历史读取仍直接委托主 isolate SQLite repository。
- `lib/features/chat/data/persistence/sqlite_chat_conversation_repository.dart`：SQL、子查询与 row mapping。
- `lib/features/chat/domain/history_pagination_state.dart`：当前页、loading、stale content 与 inline error 状态。

### 1.2 普通进入不等于全量加载

- 页容量固定为 `10/20/50`，默认 20；ListView 使用 builder，不一次 build 全部历史行。
- 空搜索首次进入只执行满足条件的 `COUNT` 和当前页查询。
- page query 每行用相关子查询读取首条/末条用户消息预览。
- `historyPaginationProvider` 不是 auto-dispose；再次进入完全相同窗口时可能命中幂等检查而不重查。
- 因此“代码是同步的”只能证明主 isolate 存在阻塞风险，不能单独证明用户看到的卡顿由这两条 SQL 导致。

### 1.3 高风险候选

1. 非空搜索使用 `LOWER(...) LIKE '%keyword%'`，匹配标题和所有用户消息；前导 `%` 不能被普通 B-tree 消除，并且当前先 COUNT 再 page query，最坏情况重复扫描。
2. 根部生成通知 coordinator eager watch `chatSessionsProvider`，冷启动会无 limit 加载全部会话摘要，再完整加载最近会话。
3. 选择未加载的超长会话时同步加载全部消息、分支和检查点，并逐消息 JSON 解码。
4. 从 Chat 路由离开、History 首帧 layout/raster 或 route transition 也可能是热点；若 repository span 很短，必须沿 UI 路径继续查。

本 PR 只允许修复 History 页面和其必要的共享查询设施。冷启动无界摘要与超长会话完整加载只记录为后续问题，不在本 PR 实施。

### 1.4 方向性合成基准（不是验收证据）

同 schema/SQL 的 warm、内存 SQLite 方向性结果：

| 数据量 | 空搜索 COUNT | 空搜索 page 20 | 无界摘要 | 不命中搜索 COUNT + page |
|---|---:|---:|---:|---:|
| 1,000 会话 x 10 消息 | 0.32ms | 0.16ms | 3.77ms | 10.83ms |
| 10,000 会话 x 10 消息 | 3.57ms | 0.14ms | 41.40ms | 101.45ms |
| 1,000 会话 x 100 消息 | 0.37ms | 0.12ms | 4.58ms | 67.77ms |

这些数字只说明增长趋势：普通第一页不一定是主因，搜索和无界摘要更容易越过一帧。真实 Windows 文件数据库、FFI、对象映射、build 和 raster 必须重新测。

## 2. 固定用户可见契约

- 搜索继续匹配会话标题和所有用户消息，不匹配 assistant 回复。
- 搜索继续大小写不敏感，并按字面转义 `%`、`_`；不改变中文、Unicode 或跨分支消息语义。
- 搜索防抖保持 300ms；清空关键词立即执行。
- 页容量保持 10/20/50、默认 20，合法显式容量继续写偏好。
- 排序、稳定 tie-break、时间分组、标题/预览、rename/delete 后刷新语义不变。
- route 继续是已提交窗口的序列化 owner；成功后才 replace URL，失败保留上一个已提交 URL/window。
- 首次加载 UI 保持流畅并显示可动画 loading，数据到达后渲染。
- 已初始化后的搜索/翻页保留旧列表；分页控件忙碌时禁用，搜索输入仍可使用。
- 并发查询使用 latest-wins：旧成功和旧失败都不得覆盖最新请求。
- 查询失败保留 stale content，显示 inline “加载历史记录失败”与重试；不用 SnackBar/Dialog。
- 搜索、分页、容量变化前清除选择的现有语义不变，即使查询失败也不恢复旧选择。
- 不通过最小关键词长度、减少搜索字段、取消总数、缩短预览或降低页容量制造性能提升。

## 3. 全局限制与停止条件

- 不能用 debug build 判断性能；UI 证据必须来自 `flutter run --profile -d windows`。
- 不能把 wall-clock 毫秒阈值写进普通 CI 测试；CI 只保护行为和查询形态。
- 不能把 sqlite3 connection 跨 isolate 发送；后台读取必须拥有自己的文件连接。
- 不能把长读取塞进现有 `chat_writer_entry_point.dart`：其串行 command loop 必须优先保证 durable write。
- 测量前不把 `ChatConversationRepository` 整体异步化，不波及 `ChatSessionsController.build/selectConversation`。
- 没有 `EXPLAIN QUERY PLAN` 变化和 profile 证据时不添加索引。
- `%keyword%` 扫描若需要 FTS、schema 大迁移或改变搜索语义，停止本 PR，另立设计。
- 若 repository span 低于帧预算安全余量而 UI 仍掉帧，停止 DB 路径并转向 History UI/layout。
- 若热点位于 ChatScreen teardown、App Shell/router 或冷启动全局加载，记录证据并停止本 PR，不偷改全局架构。
- 若所有规定场景均无法稳定复现，不提交象征性 production 改动。

## 4. Task 0：锁定当前行为基线

**Files:** 不修改 production；只运行现有测试。

- [x] 清理异常残留测试进程：`./scripts/kill-stale-test-processes.ps1`（pwsh 7 执行，未发现残留）。
- [x] 四组定向基线全部 `EXIT=0`，日志 `logs/history-perf-{repository,controller,screen,router}-baseline.log`：
  - `sqlite_chat_conversation_repository_test.dart`：15 例通过。
  - `history_pagination_controller_test.dart`：26 例通过。
  - `history_screen_test.dart`：31 例通过。
  - `app_router_test.dart`：23 例通过。
- [x] 无既有失败；本 PR 未顺手修复任何基线问题。
- [x] 测试数、HEAD、Flutter/Dart 版本已记录到「Task 2：测量结果」章节末尾的环境记录。

## 5. Task 1：建立可复现 profile 证据

### 5.1 数据集

必须至少覆盖：

- 1,000 会话 x 10 消息；
- 10,000 会话 x 10 消息；
- 1,000 会话 x 100 消息；
- 空搜索；
- 不命中搜索；
- 命中标题搜索；
- 命中用户消息搜索；
- 首次进入、相同 route 第二次进入；
- 页面离开再返回；
- 当前实际数据库（仅在合成数据无法解释体感时）。

合成数据必须通过 repository/schema helper 写入临时文件数据库，不覆盖 AppData 生产库。普通有效模型用 typed fixture/repository，不手写漂移 JSON。

若使用实际数据库，只采集：会话数、消息总数、单会话消息数 p50/p95/max、当前会话消息数、数据库文件大小、搜索是否命中和执行计划；不得输出标题或消息正文到日志。

### 5.2 临时 instrumentation

只在性能 worktree 临时增加 `dart:developer` `TimelineTask`，至少分开标记：

- `history.route.sync`
- `history.controller.reload`
- `history.repository.count.sql`
- `history.repository.page.sql`
- `history.repository.row_mapping`
- `history.widget.build`
- `chat.sessions.initial_summaries`（仅用于排除冷启动混入）
- `chat.sessions.load_conversation`（仅用于记录后续风险）

要求：

- instrumentation 不读取/记录 keyword 或内容，只记录数量、limit/offset 和固定事件名；
- SQL 执行和 row mapping 分开 span；
- instrumentation 在最终 production diff 前全部删除；
- 不提交临时脚本、DevTools 导出或用户数据；证据放 ignored `logs/`。

### 5.3 Profile 场景

使用：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter run --profile -d windows 2>&1 | Out-File -Encoding utf8 logs/history-perf-profile-run.log
```

从点击 History 前开始录制，每个数据规模独立记录：

1. 冷启动到首帧；
2. 已在 Chat 时第一次进入空搜索 History；
3. 第二次进入相同 route；
4. 输入不存在关键词并等待 300ms；
5. 输入标题命中和消息命中关键词；
6. 翻到下一页和改变 page size；
7. 查询期间继续输入，让旧/新请求重叠（仅当已试验异步 candidate 时）。

每个场景记录：

- UI frame 是否超过 16.7ms；
- build/layout/raster/UI thread 的热点名称；
- count SQL、page SQL、mapping、controller 总 span；
- query 次数；
- 第二次进入是否仍执行 SQL；
- 数据基数和 `EXPLAIN QUERY PLAN`；
- 卡顿是否与 repository span 重合。

**执行记录（2026-08-22）**：场景未使用手动 DevTools 录制，改为可复现的自动化等价物——临时 in-app 驱动（已删除）按上述场景序列导航/输入，等价调用真实入口（`router.go` 与 app shell 相同路径、搜索框 `TextField.onChanged` 回调、工具栏 `onSearchCleared`、`goToPage`/`setPageSize` 与分页按钮相同 controller 入口），每步以 `TimelineTask` 标记窗口；采集脚本通过 Dart VM Service（WebSocket）设置 `Dart`/`Embedder`/`GC` timeline 流并在场景完成后拉取 `getVMTimeline`。偏差声明：物理键盘/鼠标事件派发未经过（非测量对象），bootstrap 曾注入 3s 启动延迟以保证冷启动 span 进入录制窗口（不改变场景内测量）。全部场景按数据规模独立成 run（共 6 个 profile 进程），逐场景结果见 6.2；场景 7（查询重叠）按计划留待 B 实施后验证。

### 5.4 SQL 执行计划

对实际 `countHistorySummaries` 与 `loadHistorySummaries` 的空/非空 keyword 版本执行 `EXPLAIN QUERY PLAN`，确认：

- `conversations(updated_at DESC)` 是否使用；
- 第二排序键是否创建临时 B-tree；
- `messages(conversation_id, node_index)` 如何参与相关子查询；
- 搜索是否重复扫描 messages；
- 候选 `(updated_at DESC, id DESC)` 或 `(conversation_id, role, node_index)` 是否真实改变计划。

不得仅看到 “SCAN” 就判定必须建索引；必须结合时间和数据规模。

## 6. Task 2：测量结果与硬门禁（已完成）

以下数字全部来自真实 Windows profile build（`flutter run --profile -d windows`）+ Dart VM Service timeline（`Dart`/`Embedder`/`GC` 流），不是合成基准。采集方法、原始 JSON 与逐场景摘要见 ignored 的 `logs/history-perf-timeline-*.json` 与 `logs/history-perf-summary-*.txt`；合成数据集与执行计划日志见 `logs/history-perf-seed-*.log`。

### 6.1 数据集与环境

| 数据集 | 会话 | 消息 | 库文件大小 |
|---|---:|---:|---:|
| 1000x10 | 1,000 | 10,000 | 18.0MB |
| 10000x10 | 10,000 | 100,000 | 181.9MB |
| 1000x100 | 1,000 | 100,000 | 179.1MB |

环境记录：HEAD `ca5b6276fd0f9c9cfc3b00ef49128b76a2ae46`（本计划文档已在其上提交）；Flutter 3.44.8 stable；Dart 3.11.x；基线测试数 15/26/31/23（见 Task 0）。

### 6.2 测量表（每场景取 profile 实测最大 span，单位 ms）

| 场景 | 数据规模 | UI 最慢帧 | count SQL | page SQL | mapping | build/layout/raster | 查询次数 | 归因 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 首次空搜索 | 1000x10 | 16.75（1 帧超预算） | 1.44 | 0.76 | 0.78 | build 0.08 / raster 7.74 | 1+1 | reload 3.08ms，帧余量充足 |
| 首次空搜索 | 10000x10 | 22.29（1 帧超预算） | 14.73 | 0.76 | 0.65 | build 0.08 / raster 8.89 | 1+1 | count 扫全会话成为主项，reload 16.22ms 贴帧预算 |
| 首次空搜索 | 1000x100 | 15.50（0 帧超预算） | 5.27 | 0.96 | 0.74 | build 0.09 / raster 8.17 | 1+1 | reload 7.06ms，余量充足 |
| 第二次相同 route | 三组全部 | 6.22–9.95（0 帧超预算） | — | — | — | — | 0 | `sameAsCurrent` 幂等跳过，route.sync 0.01–0.02ms，无 SQL |
| 不命中搜索 | 1000x10 | 5.41 | 92.27 | 35.55 | 0.01 | build 0.01 | 1+1 | reload 127.95ms 单次 UI 同步冻结 |
| 不命中搜索 | 10000x10 | 4.67 | 541.56 | 291.89 | 0.00 | build 0.01 | 1+1 | reload 833.57ms，UI 冻结近 1 秒 |
| 不命中搜索 | 1000x100 | 4.96 | 482.22 | 256.89 | 0.00 | build 0.01 | 1+1 | reload 739.21ms，随消息总量线性 |
| 标题命中搜索 | 1000x10 | 6.44 | 33.65 | 33.35 | 0.77 | build 0.02 | 1+1 | reload 67.32ms |
| 标题命中搜索 | 10000x10 | 6.66 | 291.78 | 301.78 | 0.75 | build 0.02 | 1+1 | reload 593.88ms |
| 标题命中搜索 | 1000x100 | 7.33 | 270.02 | 284.48 | 0.74 | build 0.03 | 1+1 | reload 554.77ms |
| 消息命中搜索 | 1000x10 | 7.74 | 29.46 | 33.62 | 0.86 | build 0.01 | 1+1 | reload 63.40ms |
| 消息命中搜索 | 10000x10 | 8.08 | 293.44 | 293.38 | 0.61 | build 0.01 | 1+1 | reload 587.05ms |
| 消息命中搜索 | 1000x100 | 7.48 | 259.59 | 257.60 | 0.43 | build 0.02 | 1+1 | reload 517.50ms |
| 清空/翻页/改容量（空搜索） | 1000x10 | 8.96 | 0.85–1.44 | 0.60–0.98 | 0.59–1.21 | — | 1+1 | reload 2.46–3.08ms |
| 清空/翻页/改容量（空搜索） | 10000x10 | 7.80 | 13.60–15.44 | 0.62–1.63 | 0.45–1.27 | — | 1+1 | reload 16.17–16.52ms，临界一帧 |
| 清空/翻页/改容量（空搜索） | 1000x100 | 6.38 | 3.40–4.54 | 1.52–1.83 | 0.48–1.14 | — | 1+1 | reload 4.72–7.59ms |

补充观察：

- **搜索态卡顿的帧形态是「无帧」而非「慢帧」**：同步 SQL 阻塞 UI isolate 期间引擎无法调度新帧，因此上表搜索行的「UI 最慢帧」都不超预算，但 reload span 内列表完全无响应（1000x10 约 128ms；10 万消息级 517–834ms）。超帧归因必须看 span 而不是只看帧长。
- `history.widget.build` 全场景 <0.1ms；当前页 row mapping ≤1.3ms；raster 峰值 8.89ms —— History build/layout/raster 不构成热点。
- 1000x100 的 enter.2/enter.4（离开进入 Chat 页窗口）出现 25.03/20.45ms 超帧，且与任何 History span 不重合 —— 热点在 route transition / Chat 侧，记录为独立现象，不在本 PR 范围。
- 每次搜索态 reload 内 COUNT 与 page SELECT 各自独立全量扫描（重复扫描确认）；单次 reload 的 count 与 page 耗时同量级。
- 冷启动（场景窗口外，`chat.sessions.initial_summaries`，尾项 10.1）：1000x10 = 51.01ms 与 420.22ms 两次运行；10000x10 = 2286.70ms（其中无界 page SELECT 冷读 2002ms、row mapping 284ms）与 488.61ms；1000x100 = 325.55ms。冷启动阻塞随会话数线性放大且远超帧预算，是独立于本 PR 的后续问题。

### 6.3 EXPLAIN QUERY PLAN 结论（详见 `logs/history-perf-seed-*.log`）

- 空搜索 page：`SCAN c USING INDEX idx_conversations_updated_at` + `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`（id tie-break）。实测空搜索 page 恒 <1ms，tie-break 临时 B-tree 不是热点（时间戳基本互异）。
- 搜索态（count 与 page 同型）：keyword EXISTS 相关子查询 `SEARCH m USING COVERING INDEX idx_messages_conversation_node_index (conversation_id=?)` 后逐行过滤 `role='user' AND LOWER(m.content) LIKE '%kw%'` —— 每会话扫全量消息，COUNT 与 page 各扫一遍。
- 候选索引实测：`conversations(updated_at DESC, id DESC)` 与 `messages(conversation_id, role, node_index)` 均不改变执行计划，warm 耗时无改善（前导 `%` LIKE 不可索引消除，role 过滤在 covering index 上同样要取行）。计划 5.4 的两个候选索引均不成立，不建索引。

### 6.4 路径选择

```text
选择的唯一路径：B（历史专用 read adapter）
排除 Candidate A 的证据：进入条件要求「便宜 query rewrite/index 足以保持现有搜索语义」。
  实测两个候选索引均不改变执行计划与耗时；消除 COUNT+page 重复扫描最多把
  833.57ms 降到单次扫描的 ~540ms 量级，仍远超帧预算；把 %keyword% 搜索降到
  帧预算内需要 FTS 或 schema 大迁移 —— 命中 A 的显式停止条件，故 A 不成立。
排除 Candidate C 的证据：进入条件要求「controller/repository span 有充分安全余量」。
  实测搜索态 reload 128–834ms 位居 UI isolate；history.widget.build <0.1ms、
  raster 峰值 8.89ms、当前页 mapping ≤1.3ms，UI/layout 没有可点名的热点，C 不成立。
涉及的精确 production 文件：见第 8 节展开的逐文件清单。
新增/修改测试文件：见第 8 节展开的逐测试清单。
red 失败原因：见第 8.4 节 red/green 证据规划。
green 可观察结果：见第 8.4 节。
commit 划分：单个行为提交 `perf(history): 历史分页查询移入后台读 isolate 消除 UI 阻塞`（含全部实现与测试，不留红灯 commit）。
```

门禁规则（原样保留，执行结果）：

- 只能选择一条路径 → 已选 B，A/C 实施步骤已从计划删除，仅保留排除证据。
- 路径确定后必须展开成逐文件、逐测试、逐 commit 的无歧义任务 → 见第 8 节修订版。
- 用户再次批准修订后的计划前，禁止修改 production 代码 → 当前等待批准，本轮未改 production。
- 未选择 `STOP`；全部临时 instrumentation 已删除，工作树与 HEAD 一致，证据保留在 ignored `logs/`。

## 7. Candidate A：SQL/query 路径（已按测量排除）

进入条件未成立：实测两个候选索引（`conversations(updated_at DESC, id DESC)`、`messages(conversation_id, role, node_index)`）都不改变执行计划与耗时；COUNT+page 重复扫描即便合并也只把 833.57ms 降到约 540ms 量级；把 `%keyword%` 搜索降到帧预算内需要 FTS 或滚动 schema 迁移，命中本路径显式停止条件。证据见 6.3 与 `logs/history-perf-seed-*.log`。本路径不实施。

## 8. Candidate B：历史专用 read adapter（唯一实施路径，待用户批准）

**进入条件已由测量证实**：搜索态 SQLite 同步执行占用 UI isolate 128–834ms（远超帧预算）；Candidate A 无法在 bounded scope 内消除阻塞；目标是消除 UI 阻塞，不承诺查询总延迟消失。

### 8.1 production 文件清单（逐文件）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lib/features/chat/application/ports/history_page_query.dart`（新增） | `HistoryPageRequest{keyword, requestedPage, pageSize}`、`HistoryPageResult{items, totalItems, committedPage}`、`abstract interface class HistoryPageQuery { Future<HistoryPageResult> load(request); Future<void> dispose(); }`。module 隐藏 `COUNT -> clamp -> page SELECT -> mapping`，caller 原子收到一个窗口。 |
| 2 | `lib/core/persistence/app_database.dart`（修改） | `AppDatabase.forPath` 从 `@visibleForTesting` 转为生产可用工厂（doc 注明用途：后台 read/write isolate 以自己的连接打开同一文件库；schema 校验与 PRAGMA 配置与主连接一致）。 |
| 3 | `lib/features/chat/data/persistence/history_reader_entry_point.dart`（新增） | 长期 read isolate 入口：接收主 isolate 命令，**不复用** `chat_writer_entry_point.dart`（其串行 command loop 必须优先保证 durable write）。typed 命令协议：`HistoryQueryCommand{id, keyword, requestedPage, pageSize}` -> `HistoryQueryResponse{id, items(List<ChatConversationSummary>), totalItems, committedPage}` / `HistoryQueryErrorResponse{id, message}` / `CloseCommand` -> `ExitResponse`（对齐现有 `background_worker_command.dart` 的 typed 纪律；实体对象跨 isolate 直接 deep-copy 传输，不做二次 JSON 编解码）。worker 端用 `AppDatabase.forPath` 建自有连接 + `SqliteChatConversationRepository` 执行 count+clamp+load+mapping。 |
| 4 | `lib/features/chat/data/persistence/history_page_query_adapter.dart`（新增） | `IsolateHistoryPageQueryAdapter implements HistoryPageQuery`：构造时 spawn read isolate（`path == ':memory:'` 时不 spawn，降级为 `_InProcessHistoryPageQuery`——同进程 `Future.microtask` 包同步 count+load，保证测试/内存库语义正确，绝不让 worker 打开另一个空的 `:memory:`）。`load` 返回独立 Future（不排队、不取消，串行执行）；`dispose` 发送 CloseCommand 并等待 ExitResponse ACK，超时（5s）后 kill isolate，app teardown 有界完成。错误映射：worker 异常/超时 -> `HistoryPageQueryException`，由 controller 按现有错误契约落 inline 错误态。 |
| 5 | `lib/features/chat/application/history/history_pagination_controller.dart`（修改） | 依赖从 `chatConversationRepositoryProvider` 换为 `historyPageQueryProvider`；`loadRoute`/`_reloadCurrentWindow` 变 async：每次调用自增 monotonically increasing generation；`await query.load(...)` 完成后仅当 generation 仍为最新才 commit 成功或失败状态（latest-wins：旧成功与旧失败都不得覆盖最新请求）。保持现有状态字段与语义：初次 `isLoading` 驱动可动画 loading；已初始化时查询失败保留 stale content + `historyLoadErrorMessage`；页码夹取语义由 worker 端 clamp 结果带回（`committedPage`），空结果页码归一为 1 的现有行为不变。busy 守卫（`isLoading` 时 `goToPage` 直接返回）保持。controller 公开方法返回 `Future<bool>`（true=已提交）供 screen 决定 URL replace 时序。 |
| 6 | `lib/features/chat/application/providers/`（或现有 provider 绑定处，修改） | 新增 `historyPageQueryProvider = Provider<HistoryPageQuery>`，生产绑定 `IsolateHistoryPageQueryAdapter(AppDatabase.path)`；与 `chatConversationRepositoryProvider` 同层定义，保持 application 拥有 port、data 提供实现、composition 不被 presentation 引用的现状。 |
| 7 | `lib/features/history/presentation/history_screen.dart`（修改） | `_handleSearchChanged` 防抖回调、`onPageChanged`、`onPageSizeChanged`、`onRetry`、delete 后刷新改为 `await` controller 返回值，**仅最新请求成功提交后才 `_replaceRouteLocation()`**；失败保留上一个已提交 URL/window。其余 UI（loading 动画、错误卡片、分页禁用）依赖既有状态字段，无新增布局改动。 |
| 8 | `lib/features/chat/application/sessions/chat_sessions_controller.dart`（不动） | 冷启动无界摘要与本 PR 无关（尾项 10.1）；`ChatSessionsController.build/selectConversation` 不异步化。 |

### 8.2 测试文件清单（逐测试）

| # | 文件 | 内容 |
|---|---|---|
| 1 | `test/features/chat/application/history/history_pagination_controller_test.dart`（迁移+新增） | 现有 26 例的行为契约保留，注入物从同步 repository fake 换为 controllable `FakeHistoryPageQuery`（`Completer` 精确编排每次 load 的完成时序与结果）。新增异步契约红灯用例（见 8.3）。 |
| 2 | `test/features/chat/data/persistence/history_page_query_adapter_test.dart`（新增） | file-backed integration：真实文件库 + 真实 worker isolate —— (a) worker 用自有连接读到主 isolate 写入的数据；(b) count+clamp+page 结果与主 isolate `SqliteChatConversationRepository` 直接调用完全等价（含空结果页码归一、越界页夹取、keyword LIKE 转义语义）；(c) SQLite 错误映射为 `HistoryPageQueryException`；(d) `dispose` 收到 ExitResponse ACK 后 worker 连接关闭、进程不残留；(e) `:memory:` 路径不 spawn isolate 且结果等价。 |
| 3 | `test/features/history/history_screen_test.dart`（迁移+新增） | 既有 31 例经 `pumpTestApp` 注入 in-process async adapter（同进程内存库）。新增/补强：(a) busy 时分页控件禁用、搜索输入仍可输入；(b) 搜索成功后 URL 才 replace、失败保留旧 URL；(c) dispose 后迟到结果不抛 zone error、不改可见状态；(d) rename/delete invalidation 不被旧查询复活。 |
| 4 | `test/app/router/app_router_test.dart`（迁移） | History 深链恢复用例改走 async adapter 注入，断言 post-frame + 完成信号后的窗口恢复（等待可观察完成条件，不盲 pump 固定延迟）。 |
| 5 | `test/helpers/chat/`（新增 shared fake） | `ControllableHistoryPageQuery`：enqueue 完成/失败/延迟，记录 requestHistory，供 1/3 复用（case-file decomposition 约定不变）。 |

### 8.3 必须先写的红灯测试（对应计划原第 8 节契约）

1. Future 未完成时 `isLoading=true` 且旧列表保留（初次 loading / 已初始化 stale content 两种）。
2. 两请求逆序完成时 latest-wins：旧成功不覆盖新窗口。
3. 旧失败不覆盖新成功。
4. 最新失败保留已提交窗口（stale content + inline 错误）。
5. URL（screen 层）成功后才更新，失败保留。
6. controller/provider dispose 后迟到结果安全（无 zone error、无状态写入）。
7. busy 时分页禁用、搜索仍可输入。
8. rename/delete 后 invalidation 不被在途旧查询覆盖。
9. adapter 生命周期：worker close、异常映射与 teardown 有界（8.2#2）。

### 8.4 red/green 证据规划

- **red**：先提交只含 8.3 全部红灯测试与 controllable fake 的测试改动，在当前同步实现（HEAD）上运行——同步实现下请求互相即时覆盖、无 generation 概念、busy/dispose/迟到结果语义不存在，latest-wins 逆序完成、迟到结果安全、URL 失败保留等用例必然失败；`logs/history-perf-adapter-red.log` 记录失败输出。
- **green**：实现 8.1 全部文件后同批测试通过（`logs/history-perf-application-green.log` / `logs/history-perf-widget-green.log`）；可观察结果 = 搜索/翻页期间 UI 不再被同步 SQL 阻塞（实施后按 5.3 场景 7 重跑 profile：查询重叠时输入仍响应、旧结果不覆盖新请求），行为契约（第 2 节）逐条不变。
- red 测试与实现合并为**同一个行为提交**，不留下永远失败的中间 commit。

### 8.5 已知取舍与边界

- 单 worker 只消除 UI 阻塞，不真正取消 SQLite：慢搜索在 worker 内照常跑完（540–830ms 量级），期间新请求排队串行执行；这与第 2 节 latest-wins 契约一致（旧结果被丢弃，用户看到最新）。若未来需要查询级取消，回到 query complexity 问题另行设计，不做无限排队。
- read worker 与 writer isolate 各持独立文件连接：SQLite WAL/busy 语义下并发读写安全性与主 isolate 现状一致；adapter 测试覆盖 busy 场景。
- `AppDatabase.forPath` 转正不改变其 schema 校验行为：版本不匹配依旧显式拒绝。
- 若实施中发现必须异步化 `ChatSessionsController` 或让 History presentation 直接 import data/persistence —— 命中停止条件，停下来重新评审。

## 9. Candidate C：History UI/layout 路径（已按测量排除）

进入条件未成立：实测 `history.controller.reload` 搜索态 128–834ms 位居 UI isolate，无安全余量；`history.widget.build` <0.1ms、raster 峰值 8.89ms、当前页 mapping ≤1.3ms，frame chart 无法点名 History 子树热点（唯一的非搜索超帧出现在离开 History 后的 Chat/route transition 窗口，与 History span 不重合）。本路径不实施。

## 10. 后续聊天存储架构尾项（不实施）

以下问题必须保留在本计划末尾，但不得提前实现：

### 10.1 冷启动无界摘要

- 触发链：`OhMyLlmApp` eager watch notification coordinator -> `chatSessionsProvider` -> `ChatSessionsController.build()` -> 无 limit `loadHistorySummaries()` -> 最新会话完整加载。
- 风险：会话数增长时摘要 mapping 线性增长。
- 实测（profile，`chat.sessions.initial_summaries` span，两次独立运行的波动来自 OS 页缓存冷热）：1000 会话 51–420ms；10,000 会话 489–2287ms（其中无界 page SELECT 冷读最高 2002ms、全量 row mapping 284ms）；1,000x100 消息 326ms。冷启动阻塞已远超帧预算并随会话数放大。
- 启动独立设计的条件：已满足证据门槛（冷启动超帧主要落在无界摘要），但按计划范围约束仍不在本 PR 实施；B 路径的 `HistoryPageQuery` seam 不扩大到 ChatSessionsController。

### 10.2 超长会话完整反序列化

- 触发链：选择未加载会话 -> 加载全部消息/分支/检查点 -> 每消息 JSON decode。
- 风险：单会话消息数 p95/max 增长时 UI isolate 长任务。
- 启动独立设计的条件：超长会话 profile span 与卡顿重合，并且 History 专用方案不能复用而不扩大 seam。

未来存储设计必须单独讨论会话分页/树激活、repository async ownership、SQLite 连接、durable write 一致性和 UI viewport；本计划不选择方案。

## 11. 修订后实施的通用验证门禁

选定路径并获批后，修订计划必须至少包含：

### 11.1 定向测试

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart test/features/chat/application/history/history_pagination_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-application-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-application-green.log
flutter test test/features/history/history_screen_test.dart test/app/router/app_router_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-widget-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-widget-green.log
```

按仓库规则，单文件工具级 timeout `60000`ms；组合超过时拆分，不放宽为无限等待。

### 11.2 format、架构、analyze、全量

```powershell
$DartFiles = git diff --name-only master...HEAD -- '*.dart'
if ($DartFiles) { dart format $DartFiles }
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/history-perf-boundaries.log; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 120 logs/history-perf-boundaries.log
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/history-perf-analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/history-perf-analyze.log
```

全量工具级 timeout `240000`ms：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

超时先执行 `./scripts/kill-stale-test-processes.ps1`。

### 11.3 scope audit

```powershell
git diff --check master...HEAD
git diff --name-only master...HEAD
git status --short
rg -n "TimelineTask|Stopwatch|debug_history|TBD" lib tool docs/plans/2026-08-22-history-page-performance.md
```

最终 production diff 不得留下临时 instrumentation、用户数据、DevTools export、无关 Chat storage 改动或三条 candidate 的混合实现。计划中的测量结果 `TBD` 必须清零。

## 12. 提交策略

本初稿只授权诊断，不授权 production 实现。获得用户批准后：

1. [x] 可独立提交本计划文档（已提交：`docs: 落盘历史页打开与搜索性能诊断实施计划`）。
2. [x] Task 1 测量只产生 ignored logs 和计划修订；临时 instrumentation 已在提交前删除。
3. [x] 真实证据与唯一 candidate 展开完成，本次提交：

```powershell
git commit -m "docs(perf): 根据测量细化历史页优化方案"
```

4. [ ] 用户再次批准后，生产修复按第 8 节修订计划拆成 1 个行为提交；不为红灯测试单独留下永远失败的 commit。
5. 没有 production 修复时不创建 `perf:` 空提交。
6. 未经授权不 push、不创建 PR。

## 13. 阶段完成定义

初稿阶段（已完成）要求：当前调用链、同步读事实、普通分页规模和高风险候选被准确区分；用户可见契约和范围固定；Task 0/1 给出可复现数据、profile 场景、Timeline span、执行计划与隐私规则；Task 2 硬门禁已清零；三个 candidate 有互斥进入条件且 A/C 已按测量排除；冷启动与超长会话只记录尾项；方向性 benchmark 与真实 Windows 验证已明确区分。

诊断阶段（当前）额外确认：

1. 测量结果 `TBD` 已全部清零（6.2/6.3/6.4）。
2. 唯一路径 B 已展开为逐文件、逐测试、逐 commit 任务（8.1–8.5）。
3. 全部临时 instrumentation、驱动与采集脚本已删除；`rg -n "TimelineTask|Stopwatch|debug_history|HISTORY-PERF" lib tool test` 无匹配；工作树与 HEAD 一致，仅本计划文档待提交。
4. 证据（timeline JSON、逐场景摘要、seed/EQP/基线日志、数据集）保留在 ignored `logs/`；未 push、未创建 PR。
5. **下一步被阻塞于用户对第 8 节实施方案的批准；批准前不修改任何 production 代码。**
