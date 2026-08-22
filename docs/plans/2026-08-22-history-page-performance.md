# 历史页打开与搜索性能诊断实施计划

**Goal:** 用可复现 profile 解释历史页打开卡顿的真实归因，并且只在证据成立后选择一条最小修复路径；保持历史搜索、分页、路由、错误与选择行为不变。

**Architecture:** 当前 History 在首帧后由 `HistoryPaginationController` 同步执行 `COUNT -> page SELECT -> row mapping`。本计划先把 repository、controller、route/layout 的时间分开记录，再以硬门禁选择 SQL/query、历史专用 read adapter 或 UI/layout 三条路径之一。测量前不扩大全局 Chat repository，不把现有 writer isolate 兼作 reader，也不添加无执行计划证据的索引。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` / Riverpod 3 / sqlite3 FFI / Dart Timeline / Flutter DevTools Performance / PowerShell 7。

**Branch:** `perf/history-page-performance`

**Planning baseline:** `cfbb5299d8293196d1df9d37d11d115470c4ee51`。计划阶段完成了只读调用链审计和方向性内存 SQLite 合成基准，但没有在真实 Windows profile build 中录制 UI frame，没有修改生产代码，也不能把方向性数字写成修复验收结果。

**诊断执行状态（2026-08-22）:** Task 0/1/2 已完成；测量证据与唯一路径选择见「Task 2：测量结果」。Candidate B 已深化为可直接实施的 Task 3–8；本轮仍只修改计划文档，等待用户明确授权 production 实现。

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
- 用户明确授权 Task 3–8 前，禁止修改 production 代码 → 当前已完成计划深化，仍等待 production 授权。
- 未选择 `STOP`；全部临时 instrumentation 已删除。Task 2 提交时工作树与 HEAD 一致；当前只存在本轮实施计划深化的文档差异，证据继续保留在 ignored `logs/`。

## 7. Candidate A：SQL/query 路径（已按测量排除）

进入条件未成立：实测两个候选索引（`conversations(updated_at DESC, id DESC)`、`messages(conversation_id, role, node_index)`）都不改变执行计划与耗时；COUNT+page 重复扫描即便合并也只把 833.57ms 降到约 540ms 量级；把 `%keyword%` 搜索降到帧预算内需要 FTS 或滚动 schema 迁移，命中本路径显式停止条件。证据见 6.3 与 `logs/history-perf-seed-*.log`。本路径不实施。

## 8. Candidate B：历史专用 read adapter（唯一实施路径，已深化）

**进入条件已由测量证实**：搜索态 SQLite 同步执行占用 UI isolate 128–834ms（远超帧预算）；Candidate A 无法在 bounded scope 内消除阻塞；目标是消除 UI isolate 冻结，不承诺查询 wall-clock 延迟消失。实施完成后 10 万消息级搜索仍可能需要 500–800ms，但期间必须持续有帧、loading 动画可运行、搜索输入可继续编辑。

### 8.1 Task 3：锁定深 module 的外部 interface

**Files:**

- Create: `lib/features/chat/application/ports/history_page_query.dart`
- Modify: `lib/features/chat/application/history/history_pagination_controller.dart`

`HistoryPageQuery` 是 History controller 与 SQLite/Isolate 之间唯一新增 seam。controller 只学习“提交一个窗口请求并异步得到一个完整窗口”，不学习 SendPort、命令 ID、数据库路径、COUNT/page 两条 SQL 或 worker 生命周期。

接口固定为：

```dart
final class HistoryPageRequest extends Equatable {
  HistoryPageRequest({
    required String keyword,
    required this.requestedPage,
    required this.pageSize,
  }) : keyword = keyword.trim() {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', '必须大于 0');
    }
  }

  final String keyword;
  final int requestedPage;
  final int pageSize;

  @override
  List<Object?> get props => [keyword, requestedPage, pageSize];
}

final class HistoryPageResult extends Equatable {
  HistoryPageResult({
    required List<ChatConversationSummary> items,
    required this.totalItems,
    required this.committedPage,
  }) : items = List.unmodifiable(items) {
    if (totalItems < 0) {
      throw ArgumentError.value(totalItems, 'totalItems', '不得小于 0');
    }
    if (committedPage < 1) {
      throw ArgumentError.value(committedPage, 'committedPage', '必须至少为 1');
    }
  }

  final List<ChatConversationSummary> items;
  final int totalItems;
  final int committedPage;

  @override
  List<Object?> get props => [items, totalItems, committedPage];
}

final class HistoryPageQueryException implements Exception {
  const HistoryPageQueryException(this.message);
  final String message;

  @override
  String toString() => 'HistoryPageQueryException: $message';
}

abstract interface class HistoryPageQuery {
  Future<HistoryPageResult> load(HistoryPageRequest request);
  Future<void> dispose();
}

final historyPageQueryProvider = Provider<HistoryPageQuery>((ref) {
  throw StateError('HistoryPageQuery 尚未由应用组合层绑定');
});
```

接口不增加 `count`、`loadPage`、`cancel`、`isWorkerReady`、`databasePath` 等方法。COUNT、页码夹取、page SELECT、row mapping、读取事务、worker readiness 与异常映射都属于 adapter implementation。删除这个 module 后这些复杂度会重新散落到 controller、screen 和测试，因此该 seam 有实际 depth；生产 SQLite adapter 与测试 controllable adapter 是两个真实 adapter，不是为单一实现制造的假 seam。

固定不变量：

- `HistoryPageRequest.keyword` 在构造时 trim；搜索大小写、LIKE 转义和匹配字段仍由现有 SQLite repository 定义。
- `requestedPage` 可越界；adapter 根据同一查询快照的 `totalItems` 夹取，空结果固定提交 page 1。
- `pageSize` 必须大于 0；10/20/50 的产品合法性仍由 controller 校验，data 层不 import UI page-size options。
- `HistoryPageResult.items` 返回不可修改列表；`totalItems >= 0`、`committedPage >= 1`。
- `load` 的数据库/worker/协议错误统一抛 `HistoryPageQueryException`；controller 不把内部错误文本展示给用户，只落现有 `historyLoadErrorMessage`。
- `dispose` 幂等；dispose 开始后新的 `load` 立即以 `HistoryPageQueryException` 失败。
- `ChatConversationRepository` 保持原样；History 迁出其读取调用方，但 ChatSessions、写入、Sync 等既有调用者不迁移。

### 8.2 Task 4：先用红灯锁定异步调度和 committed-window 契约

**Files:**

- Create: `test/helpers/chat/controllable_history_page_query.dart`
- Modify: `test/features/chat/application/history/history_pagination_controller_test.dart`
- Modify: `test/helpers/chat/flaky_chat_conversation_repository.dart`
- Delete after migration: `test/helpers/chat/fake_history_repository.dart`

`ControllableHistoryPageQuery` 必须：

- 实现 `HistoryPageQuery`；
- 每次 `load` 记录 immutable request；
- 为每个真正收到的 request 暴露独立 `Completer<HistoryPageResult>`；
- 支持完成成功、完成 `HistoryPageQueryException`、检查尚未完成的请求数；
- `dispose` 后完成所有未决 completer 为错误，且后续 `load` 失败；
- 不使用 timer、固定延迟或真实 SQLite。

先创建 port 与 controllable adapter，使测试可以编译；此时 controller 仍使用同步 repository，以下新测试必须 RED：

1. `初次查询未完成时进入 loading 且没有伪造空态提交`。
2. `已初始化窗口重载期间保留旧列表并显示 busy`。
3. `活动请求期间连续提交三个目标时只执行首个和最后一个`：A 正在执行，B 成为 pending，C 替换 B；B 的公开 Future 立即返回 `ignored`，A 完成后 query 只收到 C，不收到 B。
4. `旧成功完成时不覆盖新的 pending 目标`。
5. `旧失败完成时不覆盖新的 pending 目标`。
6. `最新失败保留已提交窗口并落 inline 错误状态`。
7. `搜索请求未完成时清空关键词仍会提交空关键词目标`：不能因为 committed keyword 仍为空而误判 no-op。
8. `失败后的 retry 重新提交失败目标`：失败目标不能永久留在“已请求”缓存中，也不能退回 committed window。
9. `dispose 后活动结果迟到不会写 state 且公开 Future 返回 ignored`。
10. `搜索态 rename/delete 强制刷新且不会被旧查询复活`。
11. 现有 26 个同步测试迁移为 await 公开 Future 或显式完成 controllable query；原有页码、偏好、hasAny、错误、rename/delete 行为断言全部保留。

red 命令（工具级 timeout 60,000ms）：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/history/history_pagination_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-controller-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-controller-red.log
```

RED 证据必须来自上述异步行为断言失败，不接受 import/语法/未实现方法导致的编译失败作为有效 red。先添加最小 port/fake 让测试编译，再记录行为红灯；red 测试与 green 实现最终进入同一个行为提交，不留下失败 commit。

删除旧 fake 后，把 `flaky_chat_conversation_repository.dart` 中“与 `FakeHistoryRepository` 不同”的陈旧 doc 改为直接说明其为什么委托真实 SQLite repository；不改变 generation 故障注入行为。

### 8.3 Task 5：实现 controller 的有界 latest-wins 调度

**File:** `lib/features/chat/application/history/history_pagination_controller.dart`

controller 的 `HistoryPaginationState` 始终表示**最后成功提交的窗口**；pending keyword/page/pageSize 不提前写入这些 committed 字段。唯一允许提前变化的现有字段是 `isLoading=true`，使 UI 显示 loading/busy 并保留 stale content。

新增私有状态：

```dart
int _nextGeneration = 0;
bool _disposed = false;
_HistoryLoadOperation? _activeLoad;
_HistoryLoadOperation? _pendingLatest;
HistoryPageRequest? _latestRequestedWindow;
HistoryPageRequest? _failedRequest;
```

controller 文件公开以下三态 outcome，presentation 用它区分成功、最新失败与不拥有提交权的调用：

```dart
enum HistoryWindowLoadOutcome {
  committed,
  failed,
  ignored,
}
```

`_HistoryLoadOperation` 只在 controller 文件内部存在，持有 `generation`、`request` 与 `Completer<HistoryWindowLoadOutcome>`。公开调用统一经过 `_scheduleLoad(request)`，语义固定为：

1. controller 已 dispose：返回 `Future.value(HistoryWindowLoadOutcome.ignored)`。
2. 自增 generation，把 request 设为 `_latestRequestedWindow`，写 `isLoading=true`。
3. 若已有 pending，先把旧 pending 的 completer 完成为 `ignored`，再用新 operation 替换；任意时刻最多“1 个 active + 1 个 latest pending”。
4. 若没有 active，`unawaited(_drainLoads())`；`_drainLoads` 一次只调用一个 `query.load`。
5. active 成功/失败后，只有 `generation == _nextGeneration` 且 controller 未 dispose 才能提交 state；旧成功、旧失败都只把自己的 Future 完成为 `ignored`。
6. 最新成功：一次性提交 items/total/page/keyword/pageSize/hasAny/isInitialized、清 error、`isLoading=false`，清空 `_failedRequest`，对应 Future 返回 `committed`。
7. 最新失败：保留 committed window，把本次 request 保存到 `_failedRequest`，写 `isInitialized=true`、`errorMessage=historyLoadErrorMessage`、`isLoading=false`，对应 Future 返回 `failed`。
8. active 结束后若有 pending，立即执行 pending；没有 pending 时清空 `_latestRequestedWindow`。失败后也必须清空，使同一目标可以重试。
9. `ref.onDispose` 设置 `_disposed=true`，把 pending completer 完成 `ignored`；active 的迟到完成只返回 `ignored`，不写 state。query 的生命周期由其 provider 拥有，controller 不调用 `query.dispose`。

所有会触发查询的公开方法返回 `Future<HistoryWindowLoadOutcome>`。no-op、busy guard、被 supersede 和 dispose 返回 `ignored`；只有最新数据库失败返回 `failed`：

```dart
Future<HistoryWindowLoadOutcome> loadRoute({
  int? page,
  int? pageSize,
  String? keyword,
});
Future<HistoryWindowLoadOutcome> goToPage(int page);
Future<HistoryWindowLoadOutcome> prev();
Future<HistoryWindowLoadOutcome> next();
Future<HistoryWindowLoadOutcome> first();
Future<HistoryWindowLoadOutcome> last();
Future<HistoryWindowLoadOutcome> setPageSize(int size);
Future<HistoryWindowLoadOutcome> setKeyword(String keyword);
Future<HistoryWindowLoadOutcome> retry();
Future<HistoryWindowLoadOutcome> afterRename(
  String conversationId,
  String newTitle,
);
Future<HistoryWindowLoadOutcome> afterDelete(Set<String> deletedIds);
```

细节：

- `goToPage` 的 `isLoading` busy 守卫保持；pagination UI 不允许在途翻页。
- `setKeyword` 在查询期间仍可调用。no-op 比较对象是 `_latestRequestedWindow ?? committedWindow`，因此“在途非空搜索后清空”会生成新请求。
- `retry` 优先重新 schedule `_failedRequest`，没有失败目标时才使用 committed window；任何新的非 retry 目标都会清空旧 `_failedRequest`。这保证搜索、深链或翻页失败后的按钮重试原请求，而不是悄悄重查旧窗口。
- `setPageSize` 不提前修改 committed `state.pageSize`；合法显式值仍立即异步保存偏好，查询失败时可见窗口和 URL 保持旧值。
- 非搜索态 `afterRename` 继续本地改标题并返回 `committed`，不查询、不改变 route；搜索态强制 schedule 当前窗口。
- `afterDelete` 对非空 ID 集合强制 schedule 当前窗口；空集合返回 `ignored`。
- `_calcHasAny` 和 `historyLoadErrorMessage` 保持。
- 删除“底层 SQLite 同步所以使用 Notifier”的旧 doc；保留 `Notifier` 是因为状态需要 committed-window + stale-content 语义，而不是因为查询同步。

green 命令复用 8.2 的单文件命令，输出改为 `logs/history-perf-controller-green.log`，必须 `EXIT=0`。

### 8.4 Task 6：实现 SQLite read adapter、feature-owned protocol 与独立 worker

**Files:**

- Modify: `lib/core/persistence/app_database.dart`
- Create: `lib/features/chat/data/persistence/history_reader_protocol.dart`
- Create: `lib/features/chat/data/persistence/history_reader_entry_point.dart`
- Create: `lib/features/chat/data/persistence/history_page_query_adapter.dart`
- Create: `test/features/chat/data/persistence/history_page_query_adapter_test.dart`

#### 8.4.1 为什么 adapter 接收 AppDatabase

生产构造固定为：

```dart
SqliteHistoryPageQueryAdapter(AppDatabase database)
```

不能只接收 path：

- 文件库：adapter 只把 `database.path` 传给 worker，worker 用 `AppDatabase.forPath` 建自己的连接；
- `:memory:`：必须复用传入 `AppDatabase` 的同一连接，由私有 `_InProcessHistoryPageQuery` 执行；用 path 打开会得到另一个空库；
- controller 和 presentation 不接触 `AppDatabase`，该依赖只存在于 data adapter/composition。

`AppDatabase.forPath` 移除 `@visibleForTesting`，doc 改为“后台读写 isolate 以独立连接打开同一文件库”；`_configure`、schema 校验和版本拒绝语义不变。

#### 8.4.2 feature-owned typed protocol

不得扩展 `core/persistence/background_worker_command.dart` 的 `sealed WorkerCommand`；它属于 writer 协议且 sealed subtype 不能散落到另一个 library。`history_reader_protocol.dart` 独立定义：

- `HistoryReaderBootstrap{responsePort, databasePath}`；
- `HistoryReaderReady{commandPort}`；
- `HistoryReaderStartupError{message}`；
- sealed `HistoryReaderCommand`；
- `HistoryReaderQuery{id, request}`；
- `HistoryReaderClose`；
- sealed `HistoryReaderResponse`；
- `HistoryReaderSuccess{id, result}`；
- `HistoryReaderFailure{id, message}`；
- `HistoryReaderExit`。

消息只携带 SendPort、String、int 和可发送的 immutable Dart value objects；`ChatConversationSummary` / `HistoryPageResult` 由同代码 isolate 直接 deep-copy，不做 JSON 二次编解码。协议类型只供 data implementation 使用，不暴露到 application port。

#### 8.4.3 worker 查询与一致性

`historyReaderEntryPoint` 使用 `@pragma('vm:entry-point')`：

1. 收到 bootstrap 后先 `AppDatabase.forPath(databasePath)`；成功才创建/公布 commandPort 并回 `HistoryReaderReady`。
2. 打开失败回 `HistoryReaderStartupError`，关闭 ReceivePort 并退出。
3. 每个 query 在 worker 自有连接上执行：
   - `BEGIN DEFERRED`；
   - `countHistorySummaries(keyword)`；
   - 根据 total 和 pageSize 夹取 committed page（空结果 page 1）；
   - `loadHistorySummaries(keyword, limit, offset)`；
   - 把 items 包为不可修改列表；
   - `COMMIT` 后回 success；
   - 任一步失败先 `ROLLBACK`，再回 failure。
4. 同一 query 的 COUNT 与 page SELECT 因此来自同一 WAL read snapshot；writer isolate 可以继续提交写入。
5. worker 一次只处理一条 query；controller 的有界调度保证主路径不会把任意数量旧请求送入 worker。
6. 收到 close 时，事件循环会先完成当前同步 query，再关闭 AppDatabase、回 Exit 并关闭 commandPort。

不添加索引、FTS、schema 变更或查询语义改写。

#### 8.4.4 adapter 生命周期

文件库 adapter 持有 main response、error、exit 三个 ReceivePort，以及 command id -> completer 映射：

- 首次 `load` 等待同一个 readiness Future；spawn/open 超过 5 秒视为 startup failure，kill isolate 并把 load 映射为 `HistoryPageQueryException`。
- `Isolate.spawn` 使用 fatal error + error/exit listener；未收到 `HistoryReaderExit` 的异常退出必须使 readiness 和全部 query completer 失败，不能永久 loading。
- query 本身不设置任意短 wall-clock timeout：大库全扫描可能合法超过 5 秒；SQLite 锁等待已有 `busy_timeout=5000`。若未来需要查询取消/硬超时，另立设计。
- 正常 `dispose` 发送 close，等待 Exit 最多 5 秒；超时 kill。无论正常/kill 都取消 subscriptions、关闭 ReceivePorts、完成所有未决 completer，并可重复调用。
- `:memory:` adapter 不 spawn；`Future.sync` 调用同连接 repository，并保持相同 result/error/dispose interface。它只用于测试或显式内存数据库，不声称消除 UI isolate 阻塞。

#### 8.4.5 adapter 测试

全部测试通过 `HistoryPageQuery` 可观察结果，不断言私有字段：

1. `文件库 worker 能读取主连接已提交的数据`。
2. `文件库结果与直接 repository 的 count clamp page 完全等价`：覆盖空结果、越界页、排序和 10/20/50 limit。
3. `关键词保持标题和用户消息匹配且按字面转义百分号与下划线`。
4. `主连接提交新增或删除后下一次 worker 查询可见`，证明独立连接不会缓存旧窗口。
5. `缺表等 SQLite 失败映射为 HistoryPageQueryException`，不泄漏为 controller 未处理异常。
6. `无效数据库路径导致 startup failure 且 load 立即失败`。
7. `dispose 后 load 失败且第二次 dispose 正常完成`。
8. `dispose 完成后关闭主连接并可删除 sqlite wal shm 文件`，用 Windows 文件删除结果证明 worker 不残留句柄。
9. `内存库读取同一 AppDatabase 的种子数据并与文件 adapter 语义等价`；不要断言“spawn 次数”这种实现细节。

不写基于毫秒的 CI 断言，不用 sleep 猜 worker readiness。

### 8.5 Task 7：完成 composition、History UI 与 route 接线

**Production files:**

- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Modify: `lib/features/history/presentation/history_screen.dart`

**Test infrastructure/files:**

- Modify: `test/helpers/test_harness.dart`
- Modify: `test/features/history/history_screen/history_screen_test_helpers.dart`
- Modify: `test/features/history/history_screen_test.dart`
- Create: `test/features/history/history_screen/history_screen_async_query_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_actions_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_pagination_bar_cases.dart`
- Modify: `test/app/router/app_router_test.dart`
- Create: `test/app/composition/history_page_query_bindings_test.dart`

composition：

- `appCompositionOverrides` 新增 `bindHistoryPageQuery = true`。
- true 时读取 `appDatabaseProvider`，构造 `SqliteHistoryPageQueryAdapter(database)`，并以 `ref.onDispose(() => unawaited(adapter.dispose()))` 释放。
- test harness 的 `pumpTestApp`、`pumpTestAppScope`、`_buildTestScope` 同步增加该开关，默认 true；需要 `historyPageQueryProvider.overrideWithValue(fake)` 的测试必须传 false，避免重复 override。
- composition 测试用 in-memory AppDatabase 读取绑定后的 port，完成一页查询；另测 `bindHistoryPageQuery:false` 后可注入 controllable adapter。只验证 wiring，不断言 concrete runtimeType。
- `history_screen_test_helpers.dart` 保留现有 helper 签名供同步语义用例使用，并新增 `pumpControllableHistoryScreen`，返回 `({AppDatabase database, GoRouter router, ControllableHistoryPageQuery query})`。该 helper 以 `bindHistoryPageQuery:false` + provider override 装配 fake，不自动完成初始 query；每个 async case 明确决定何时完成初次窗口，避免固定 pump 次数伪装业务完成。

screen：

- 所有查询调用共用 `Future<void> _awaitLoadAndSyncRoute(Future<HistoryWindowLoadOutcome> load)`：await outcome 后，`committed` 或 `failed` 且仍 mounted 时都调用 `_replaceRouteLocation()`；controller 在失败时保留 committed state，因此 failed 会恢复最后成功窗口，committed 会 canonicalize 新窗口（包括越界页夹取）；`ignored` 不做 route mutation，让更新的请求继续拥有地址。
- `_syncFromRoute` 也使用该 helper。外部 deep link/back/forward 已经先改变地址，因此不能把 failed 和 ignored 合并；初次深链失败时 committed state 是默认窗口，URL 恢复为其 canonical 形式。
- `onPageChanged`、`onPageSizeChanged`、搜索 debounce、立即清空、`retry`、搜索态 rename、delete 后刷新都 await controller 的 `Future<HistoryWindowLoadOutcome>`。
- 内部 mutation 同样按 `committed/failed -> replace、ignored -> 不动` 收尾。通常失败时 URL 本就等于 committed window；统一 replace 仍是幂等的，并覆盖“外部 route 尚未提交时用户又发起搜索”的并发情况。
- `_handleSearchCleared` 不能用 committed keyword 为空直接返回；需同时考虑 controller 的在途目标，最简单的固定行为是：文本框从非空被明确清空时总是调用 `setKeyword('')`，由 controller 判定 no-op/supersede。
- rename 成功后始终调用 `afterRename`：非搜索态由 controller 本地更新，搜索态由 controller 重查。删除当前“搜索态直接 return、未触发 afterRename”的接线。
- 查询期间 search TextField 保持 enabled；pagination 控件继续由 `isLoading` 禁用。
- 首次查询显示既有可动画 loading；后续查询保留旧列表。不得新增布局、骨架屏或 SnackBar。

`history_screen_async_query_cases.dart` 注册下列新测试；既有 search/actions/pagination cases 只迁移异步等待方式并保留原行为断言：

1. `查询未完成时 loading 动画可 pump 且搜索输入仍可编辑`。
2. `搜索成功前 URL 保持旧值，成功后才 replace`。
3. `搜索失败保留旧 URL 和旧列表并显示加载失败`。
4. `失败后点击重试会重新提交失败目标，成功后才更新 URL`。
5. `外部 deep link 查询失败时 URL 回滚到查询前 committed window`。
6. `外部越界页成功夹取后 URL canonicalize 为 committed page`。
7. `在途非空搜索后立即清空时非空结果不能回写 URL 或列表`。
8. `A active、B pending、C latest 时只有 C 最终更新可见窗口和 URL`。
9. `页面 dispose 后迟到结果无 zone error、无 route mutation`。
10. `搜索态 rename 使项目进入或退出匹配集合时等待刷新`。
11. `delete 后刷新不会被删除前在途查询复活`。
12. `busy 时分页控件禁用，搜索输入仍可用`。
13. History 深链 `q/page/pageSize` 在异步完成信号后恢复；不用固定 sleep 或通用 `pumpAndSettle`。

### 8.6 Task 8：实现后 profile 与最终验收

先运行全部定向/静态门禁（第 11 节），再用现有 ignored 数据库：

- `logs/history-perf-data-10000x10.sqlite`；
- `logs/history-perf-data-1000x100.sqlite`。

临时恢复 Task 1 的无内容 instrumentation 与 in-app 驱动，最终再次删除。至少录制：

1. 10,000x10 首次空搜索；
2. 10,000x10 不命中搜索；
3. 10,000x10 标题命中与用户消息命中；
4. 1,000x100 不命中搜索；
5. 请求重叠：A 不命中开始后，依次提交 B、C，确认 B 不进入 worker，A 结果丢弃，C 最终提交；
6. 在途非空搜索后立即清空。

验收比较不是“SQL 从 800ms 降到 16ms”，而是：

- `history.repository.count.sql/page.sql/row_mapping` 只出现在 read worker isolate，不再占用 UI isolate；
- 500–800ms 查询窗口内 UI/Raster frame 继续产生，不再出现与 query span 等长的无帧区间；
- loading 动画和搜索输入保持响应；
- query 侧 wall-clock 可与基线同量级，不因跨 isolate 往返出现数量级回退；
- controller 每轮最多发送 active + latest 两个请求，旧成功/旧失败不提交；
- 最终 committed URL/window 与最后目标一致。

结果写 `logs/history-perf-post-summary-{10000x10,1000x100}.txt`，把摘要数字追加到本计划 8.6 的“实施记录”小节；原始 timeline JSON 留在 ignored `logs/`。若 UI 仍冻结且 SQL 已确认在 worker，命中停止条件：记录新的 UI isolate 热点并停止，不引入 FTS 或 Chat storage 重构。若 UI 流畅但 500–800ms 等待体感仍不可接受，Candidate B 仍算完成，另开 FTS/schema 设计。

#### 实施记录（2026-08-22）

环境：Windows desktop profile build（`flutter run --profile -d windows`），VM Service timeline 流 `Dart/Embedder/GC`；数据集 `logs/history-perf-data-10000x10.sqlite`（193MB）与 `logs/history-perf-data-1000x100.sqlite`（190MB）。摘要：`logs/history-perf-post-summary-10000x10.txt`、`logs/history-perf-post-summary-1000x100.txt`；原始 timeline JSON 留在 ignored `logs/`。

验收逐条对照（数字取自两份摘要的 profile 实测）：

| 验收项 | 10000x10 | 1000x100 |
|---|---|---|
| `count.sql/page.sql` 所在 isolate | 全部在 worker isolate（DartWorker 线程映射的 `isolates/1858357091969963`），UI isolate 上 0 条 | 全部在 worker `isolates/401089290511115`，UI isolate 上 0 条 |
| 有交互活动的查询窗口内帧产出 | 不命中 548ms 内 29 个 UI 帧（maxFrame 6.37ms）；消息命中 351ms 内 30 帧（2.64ms）；清空在途 566ms 内 28 帧（1.61ms）；overlap 首查询 550ms 内 30 帧（5.18ms） | 不命中 639ms 内 14 个 UI 帧（8.40ms）；消息命中 260ms 内 14 帧（4.19ms）；清空在途 564ms 内 14 帧（2.38ms）；overlap 首查询 597ms 内 14 帧（7.39ms） |
| 场景内最长单帧 | 11.80ms，无任何与 query 等长的冻结区间 | 15.72ms，无任何与 query 等长的冻结区间 |
| query wall-clock 与基线同量级 | 不命中 548ms / 标题命中 568ms / 消息命中 351ms（§6.2 基线同数据集搜索态 128–834ms，无数量级回退） | 不命中 639ms / 标题命中 615ms / 消息命中 260ms |
| latest-wins 只发 active+latest | `search.overlap` 三连输入仅 2 个 worker query（A 与 C；B 从未 dispatch），controller.load n=2 | 同样仅 2 个 worker query |
| 最终 committed URL/window | route 同步 span 每场景 1–2 次、≤0.4ms；URL 断言由 13 个异步 widget 用例覆盖 | 同左 |
| 非关键词窗口 | 首次进入 19ms、翻页 17ms、pageSize=50 18ms；同路由重复进入（`enter.2.same`）零新查询 | 首次进入 11ms、翻页 8ms、pageSize=50 8ms；同路由重复进入零新查询 |

「UI 不再冻结」与「SQL 总延迟仍存在」的区分：关键词搜索的 count+page 仍在数百毫秒量级（10000x10 约 278–311ms + 267–290ms；1000x100 约 237–325ms + 313–322ms），用户可感知的等待依旧存在；但查询期间 UI/raster 帧在有输入与动画活动时持续产出、单帧峰值 ≤15.72ms，输入与 loading 不再被 SQL 阻塞。标题命中等纯静止窗口内帧数少是「无绘制请求」而非「无帧能力」——同数据集的不命中/清空在途窗口在等长查询内分别产出 28–30 帧（10000x10）与 14 帧（1000x100）。

RED/GREEN：controller 行为红灯 `logs/history-perf-controller-red.log`（38 失败，断言级而非编译级）；GREEN 证据 `logs/history-perf-{controller,adapter,screen,composition}-green.log` 全部 EXIT=0。

清理确认：Task 8 采集用的 in-app 驱动、VM Service 抓取/分析工具与全部 `HISTORY-PERF-TEMP` timeline span 已删除（`rg "HISTORY-PERF|TimelineTask|dart:developer" lib tool test` 零命中）；用户 SharedPreferences 已从 `logs/history-perf-prefs-backup/` 恢复。

### 8.7 replace-don't-layer 清单

| 旧内容 | 最终处理 |
|---|---|
| controller 直接读取 `chatConversationRepositoryProvider` | 删除，唯一读取依赖改为 `historyPageQueryProvider` |
| controller 内 `count -> clamp -> load` | 删除，移入 SQLite adapter/worker |
| controller “同步 SQLite 所以使用 Notifier”注释 | 删除并改写为 committed-window 状态理由 |
| `test/helpers/chat/fake_history_repository.dart` | controller 测试迁移后删除，不与新 controllable query fake 并存 |
| `flaky_chat_conversation_repository.dart` 对旧 fake 的 doc 引用 | 改写为自包含说明，避免删除后留下陈旧名称 |
| screen 查询后立即 `_replaceRouteLocation()` | 删除，改为 await `committed` 后 replace |
| screen 搜索态 rename 直接 return | 删除，统一调用 controller `afterRename` |
| 临时 TimelineTask、驱动与采集代码 | profile 完成后全部删除；只保留 ignored logs 和计划摘要 |

### 8.8 已知取舍与停止条件

- 当前活动 SQLite 查询不取消；controller 只保留一个最新 pending，避免无界 FIFO。最坏情况下最新查询仍需等待当前旧查询结束后再执行。
- read worker 与 writer isolate 各持独立连接；同一 History query 使用 read transaction 获取一致快照。实现不改变 durable write ACK/flush/close。
- `:memory:` fallback 不提供性能保证，只保持测试语义；生产文件库必须走 read worker。
- 不为 worker 暴露 readiness/cancel/debug 方法到 application interface。
- 若必须异步化 `ChatSessionsController`、修改 schema/FTS、让 History presentation import data/persistence、让 reader 复用 writer command loop，立即停止并重新评审。
- 若实现后 profile 证明 UI freeze 仍与 History query 无关，不继续堆数据库优化。

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

## 11. 实施验证门禁

所有命令在仓库根目录以 PowerShell 7 **串行**执行，先 `New-Item -ItemType Directory -Force logs | Out-Null`。不得并行启动 analyzer、架构门禁或 Flutter tests。

### 11.1 定向 red/green

Task 4 的有效 RED 见 8.2。全部实现完成后的 GREEN 逐文件运行，工具级 timeout 均为 60,000ms：

```powershell
flutter test test/features/chat/application/history/history_pagination_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-controller-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-controller-green.log
flutter test test/features/chat/data/persistence/history_page_query_adapter_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-adapter-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-adapter-green.log
flutter test test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-repository-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-repository-green.log
flutter test test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-screen-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-screen-green.log
flutter test test/app/router/app_router_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-router-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-router-green.log
flutter test test/app/composition/history_page_query_bindings_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-composition-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/history-perf-composition-green.log
```

每条都必须看到 `EXIT=0`。若进程级超时，先运行 `.\scripts\kill-stale-test-processes.ps1`，确认残留已清理，再从超时日志定位；不得直接重跑。

### 11.2 format、架构、analyze、全量

先格式化本分支相对 master 修改的全部 Dart 文件：

```powershell
$DartFiles = @(git diff --name-only master...HEAD -- '*.dart')
if ($DartFiles.Count -gt 0) { dart format $DartFiles }
```

然后依次运行：

```powershell
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/history-perf-boundaries.log; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 120 logs/history-perf-boundaries.log
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/history-perf-analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/history-perf-analyze.log
```

架构门禁与 analyze 必须各自 `EXIT=0`。全量测试工具级 timeout 240,000ms：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

提交前暂存后再校验 staged Dart 格式：

```powershell
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
if ($StagedDartFiles.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $StagedDartFiles
}
```

### 11.3 scope 与临时产物审计

```powershell
git diff --check master...HEAD
git diff --name-only master...HEAD
git status --short

$InstrumentationMatches = rg -n "TimelineTask|Stopwatch|debug_history|HISTORY-PERF" lib tool test
if ($LASTEXITCODE -eq 0) {
  $InstrumentationMatches
  throw '发现未删除的性能 instrumentation'
}
if ($LASTEXITCODE -gt 1) {
  throw 'instrumentation 搜索执行失败'
}

$PlaceholderPattern = 'T' + 'BD'
$PlaceholderMatches = Select-String -Pattern $PlaceholderPattern -Path 'docs/plans/2026-08-22-history-page-performance.md'
if ($PlaceholderMatches) {
  $PlaceholderMatches
  throw '计划仍有待填占位符'
}
```

实现前允许列表：

- `docs/plans/2026-08-22-history-page-performance.md`；
- `lib/core/persistence/app_database.dart`；
- `lib/app/composition/cross_feature_bindings.dart`；
- `lib/features/chat/application/ports/history_page_query.dart`；
- `lib/features/chat/application/history/history_pagination_controller.dart`；
- `lib/features/chat/data/persistence/history_reader_protocol.dart`；
- `lib/features/chat/data/persistence/history_reader_entry_point.dart`；
- `lib/features/chat/data/persistence/history_page_query_adapter.dart`；
- `lib/features/history/presentation/history_screen.dart`；
- 第 8.2/8.4/8.5 明列的测试、helper 和删除项。

除 post-commit hook 按规则加入的 `pubspec.yaml` 版本变更外，最终 diff 出现其他文件即停止并解释，不顺手修改。最终不得包含：

- 临时 instrumentation/in-app driver/VM Service 采集脚本；
- `logs/`、profile 数据库、timeline JSON；
- 用户 AppData 或消息内容；
- 索引、FTS、schema version 变更；
- `ChatSessionsController`、writer isolate、通知或其他 PR 的改动。

### 11.4 实现后 profile 记录

Task 8 的 profile 是 performance 修复完成条件，不由普通 CI 时间断言替代。自动化驱动、VM Service 抓取和摘要可以由实施 Agent 完成；用户无需亲自录制。若只缺主观手感，可把 Windows profile smoke 写为非阻塞人工提示，但不得用“待用户测量”替代 8.6 的自动化证据。

## 12. 提交策略

1. [x] 初稿提交 `a1cac05 docs: 落盘历史页打开与搜索性能诊断实施计划`。
2. [x] 测量与 Candidate 选择提交 `0e15b84 docs(perf): 根据测量细化历史页优化方案`。
3. [x] 本轮深 module/并发/生命周期深化仅修改计划；若用户授权提交，使用独立中文 docs commit（已提交 `79950e6`）：

```powershell
git commit -m "docs(perf): 深化历史页后台查询实施计划"
```

4. [x] production 获得明确授权后，Task 3–8 的实现、red/green 测试和最终计划实施记录进入一个可工作的行为提交，不留下编译失败或红灯中间提交：

```powershell
git commit -m "perf(history): 历史分页查询移入后台读 isolate 消除界面阻塞"
```

5. post-commit hook 可能自动 amend `pubspec.yaml`；提交后必须重新读取最终 `HEAD`、`git diff-tree --name-only -r HEAD` 与 `HEAD:pubspec.yaml`，不能引用 hook 前 SHA。
6. 没有 production 修复时不创建 `perf:` 空提交；未经授权不 commit、不 push、不创建 PR。

## 13. 阶段完成定义

### 13.1 已完成：诊断

1. 当前调用链、同步读事实、普通分页规模和高风险候选被准确区分。
2. Task 0 基线测试与 Task 1 Windows profile 已完成。
3. 测量表、执行计划和路径门禁已清零；A/C 有明确排除证据，唯一选择 B。
4. 冷启动无界摘要和超长会话完整加载只保留为后续尾项。
5. 全部诊断 instrumentation 已删除；ignored `logs/` 保留原始证据。

### 13.2 已完成：实施计划深化

1. 外部 seam 固定为 `HistoryPageQuery.load/dispose`，没有把 worker 细节泄漏给 caller。
2. `:memory:` 复用 AppDatabase、文件库独立连接的构造矛盾已消除。
3. active + latest pending、有界调度、committed/desired window、清空在途搜索、失败重试和 dispose 迟到结果均有明确算法与红灯测试。
4. feature-owned typed protocol、read transaction、startup/exit/error/close 生命周期已展开。
5. composition/test harness/UI/route 的逐文件接线和 replace-don't-layer 删除项已列出。
6. adapter 测试、controller/widget/router/composition 测试、静态门禁、全量和 post-profile 均有命令或可观察完成信号。
7. 当前仍为文档阶段；production、commit、push、PR 均未授权。

### 13.3 待完成：production 实施

只有同时满足以下条件才可宣称 performance PR 实现完成：

1. Task 4 有有效行为 RED；Task 5–7 后全部定向测试 GREEN。
2. import boundary、analyze、全量测试和 staged format 全部通过。
3. Task 8 Windows profile 证明查询移出 UI isolate，慢查询期间持续产生 frame，输入/loading 可响应。
4. latest-only 调度、URL committed-window、失败 stale content、rename/delete invalidation 与 dispose 生命周期全部通过行为测试。
5. 最终 scope audit 只含允许文件和 hook 版本变更，无 instrumentation、数据文件、FTS/schema/Chat storage 扩 scope。
6. 8.6 追加实施后 profile 摘要，准确区分“UI 不再冻结”与“SQL 总延迟仍存在”。
7. 按授权完成 commit；push、PR 和人工 smoke 的状态分别如实报告。

**下一步：等待用户明确授权 production 实施 Task 3–8；在此之前不修改 Dart production 文件。**
