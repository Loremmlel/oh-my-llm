# 历史页打开与搜索性能诊断实施计划

**Goal:** 用可复现 profile 解释历史页打开卡顿的真实归因，并且只在证据成立后选择一条最小修复路径；保持历史搜索、分页、路由、错误与选择行为不变。

**Architecture:** 当前 History 在首帧后由 `HistoryPaginationController` 同步执行 `COUNT -> page SELECT -> row mapping`。本计划先把 repository、controller、route/layout 的时间分开记录，再以硬门禁选择 SQL/query、历史专用 read adapter 或 UI/layout 三条路径之一。测量前不扩大全局 Chat repository，不把现有 writer isolate 兼作 reader，也不添加无执行计划证据的索引。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` / Riverpod 3 / sqlite3 FFI / Dart Timeline / Flutter DevTools Performance / PowerShell 7。

**Branch:** `perf/history-page-performance`

**Planning baseline:** `cfbb5299d8293196d1df9d37d11d115470c4ee51`。计划阶段完成了只读调用链审计和方向性内存 SQLite 合成基准，但没有在真实 Windows profile build 中录制 UI frame，没有修改生产代码，也不能把方向性数字写成修复验收结果。

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

- [ ] 清理异常残留测试进程：

```powershell
./scripts/kill-stale-test-processes.ps1
```

- [ ] 运行 repository、controller、History screen 和 router 定向基线，每条命令工具级 timeout `60000`ms：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-repository-baseline.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/history-perf-repository-baseline.log
flutter test test/features/chat/application/history/history_pagination_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-controller-baseline.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/history-perf-controller-baseline.log
flutter test test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-screen-baseline.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/history-perf-screen-baseline.log
flutter test test/app/router/app_router_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/history-perf-router-baseline.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/history-perf-router-baseline.log
```

- [ ] 所有 baseline 必须 `EXIT=0`。已有失败先诊断并区分基线问题，不得把本性能 PR 当作顺手修复入口。
- [ ] 记录测试数、HEAD、Flutter/Dart 版本到本计划“测量结果”章节。

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

### 5.4 SQL 执行计划

对实际 `countHistorySummaries` 与 `loadHistorySummaries` 的空/非空 keyword 版本执行 `EXPLAIN QUERY PLAN`，确认：

- `conversations(updated_at DESC)` 是否使用；
- 第二排序键是否创建临时 B-tree；
- `messages(conversation_id, node_index)` 如何参与相关子查询；
- 搜索是否重复扫描 messages；
- 候选 `(updated_at DESC, id DESC)` 或 `(conversation_id, role, node_index)` 是否真实改变计划。

不得仅看到 “SCAN” 就判定必须建索引；必须结合时间和数据规模。

## 6. Task 2：填写测量结果并通过硬门禁

Task 1 完成后，把下表真实填写回本计划；`TBD` 未清零前不得修改 production：

| 场景 | 数据规模 | UI 最慢帧 | count SQL | page SQL | mapping | build/layout/raster | 查询次数 | 归因 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 首次空搜索 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 第二次相同 route | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 不命中搜索 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 标题命中搜索 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 消息命中搜索 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

同时填写：

```text
选择的唯一路径：TBD（A SQL/query / B history read adapter / C UI/layout / STOP）
排除另两条路径的证据：TBD
涉及的精确 production 文件：TBD
新增/修改测试文件：TBD
red 失败原因：TBD
green 可观察结果：TBD
commit 划分：TBD
```

门禁规则：

- 只能选择一条路径；不得同时做 SQL + isolate + UI “保险优化”。
- 路径确定后必须把 7/8/9 中对应分支展开成逐文件、逐测试、逐 commit 的无歧义任务，删除另外两个候选实施步骤。
- 用户再次批准修订后的计划前，禁止修改 production 代码。
- 若选择 `STOP`，删除所有临时 instrumentation，保留 ignored 证据并报告；不创建空 commit。

## 7. Candidate A：SQL/query 路径（测量后才能展开）

### 进入条件

- UI 超帧与 `countHistorySummaries` 或 `loadHistorySummaries` span 重合；
- 真实执行计划显示可消除的重复扫描、临时排序或相关子查询热点；
- 便宜 query rewrite/index 足以保持现有搜索语义；
- 不需要 FTS、schema 大迁移或修改页面契约。

### 允许的最小方向

按顺序评估，前一项有效则停止：

1. 在不改 schema 的前提下减少搜索态 `COUNT + page` 重复扫描；
2. 只有执行计划证明排序热点时评估 `conversations(updated_at DESC, id DESC)`；
3. 只有 role/node lookup 热点成立时评估 `messages(conversation_id, role, node_index)`；
4. 把 total + 当前页原子返回给 controller，但不得改变无结果页码夹取语义。

### 必须补的 red/green contract

- repository page 与 count 结果完全等价；
- 同 updatedAt 下 ID tie-break 稳定；
- 标题/用户消息搜索、assistant 排除、LIKE wildcard escaping 不变；
- 空结果、越界页、rename/delete reconciliation 不变；
- `EXPLAIN QUERY PLAN` 和 query 次数确实改善；
- timing 只记录为 profile 证据，不写进 test expectation。

### 停止条件

- 添加索引不改变真实执行计划；
- query 已有安全余量而 UI 仍掉帧；
- 需要 FTS 或滚动 schema migration 才能改善 `%keyword%`；
- 原子 total/page 需要破坏空页夹取或错误语义。

## 8. Candidate B：历史专用 read adapter（测量后才能展开）

### 进入条件

- SQLite/FFI/mapping 持续占用 UI isolate 超过帧预算；
- Candidate A 不能在 bounded scope 内消除阻塞；
- 目标是消除 UI 阻塞，而不是宣称查询总延迟消失。

### 预期 seam

只有选择本路径后才允许创建：

```dart
final class HistoryPageRequest {
  const HistoryPageRequest({
    required this.keyword,
    required this.requestedPage,
    required this.pageSize,
  });
}

final class HistoryPageResult {
  const HistoryPageResult({
    required this.items,
    required this.totalItems,
    required this.committedPage,
  });
}

abstract interface class HistoryPageQuery {
  Future<HistoryPageResult> load(HistoryPageRequest request);
  Future<void> dispose();
}
```

module 必须隐藏 `COUNT -> clamp -> page SELECT -> mapping`，让 caller 原子收到一个窗口；不得让 UI 依次学习/调用 `count()` 和 `load()`。

### adapter 与生命周期

- 生产 `IsolateHistoryPageQueryAdapter` 使用长期 read isolate 和自己的文件数据库连接。
- Controller 单测使用 controllable in-memory adapter，精确完成/失败请求。
- Widget 测试的内存数据库必须显式 override 同进程 async adapter；不能让 worker 打开另一个空的 `:memory:` 数据库。
- file-backed integration test 验证 worker 自有连接、SQLite busy/error 映射、close ACK。
- 不复用 writer isolate；read dispose 必须等待 ACK，并在 app teardown 有界完成。

### 异步状态契约

- monotonically increasing request generation；只有最新 success/error 能提交。
- URL 只在最新成功提交后 replace；失败保留旧 URL/window。
- 初次 loading 持续动画；reload 保留 stale content。
- 搜索输入保持可用；分页控件忙碌时禁用。
- 页面离开/provider dispose 后迟到结果不得修改可见状态或抛 zone error。
- delete/rename 与在途查询竞争时，旧结果不得复活已删除/旧名数据。
- 单 worker 只保证 UI 不阻塞，不等于真正取消 SQLite；若旧慢搜索长期阻塞新请求，回到 query complexity，而非无限排队。

### 必须先写的红灯测试

- Future 未完成时 `isLoading=true` 且旧列表保留；
- 两请求逆序完成时 latest-wins；
- 旧失败不覆盖新成功；
- 最新失败保留已提交窗口；
- URL 成功后才更新；
- dispose 后迟到结果安全；
- busy 时分页禁用、搜索仍可输入；
- rename/delete invalidation 不被旧查询覆盖；
- worker close、异常与 teardown。

### 停止条件

- 查询本来低于帧预算，isolate/序列化反而更重；
- 必须异步化全部 Chat repository 才能完成；
- 无法在 bounded scope 内证明 worker 生命周期和迟到结果安全；
- 需要让 History presentation 直接 import data/persistence。

## 9. Candidate C：History UI/layout 路径（测量后才能展开）

### 进入条件

- controller/repository span 有充分安全余量；
- Flutter frame chart 把超预算明确归因于 History build/layout/raster 或 route transition；
- Profile Widget Builds/raster trace 能点名具体 History 子树。

### 允许方向

- 只修改 trace 点名的 History presentation/widget；
- 保持每页 10/20/50 和 `ListView.builder`；
- 不凭感觉增加 cache、RepaintBoundary、const 或预构建；
- 不同时修改数据库。

### 红/绿证据

- 先写能复现多余 rebuild/layout 的结构或行为测试；
- profile 前后比较同一数据集和 route；
- 搜索、分页、选择、route、响应式与 Semantics 回归全过。

### 停止条件

- 无法稳定点名某个 widget/raster hotspot；
- 热点来自 ChatScreen teardown 或 App Shell/router；
- UI 调整后 repository span仍与掉帧重合。

## 10. 后续聊天存储架构尾项（不实施）

以下问题必须保留在本计划末尾，但不得提前实现：

### 10.1 冷启动无界摘要

- 触发链：`OhMyLlmApp` eager watch notification coordinator -> `chatSessionsProvider` -> `ChatSessionsController.build()` -> 无 limit `loadHistorySummaries()` -> 最新会话完整加载。
- 风险：会话数增长时摘要 mapping 线性增长；方向性 10,000 会话已到约 41ms（仍非真实设备证据）。
- 启动独立设计的条件：profile 证明冷启动超帧主要落在无界摘要，而非插件/窗口/首屏 build。

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

1. 可独立提交本计划文档：

```powershell
git commit -m "docs(perf): 规划历史页性能诊断"
```

2. Task 1 测量只产生 ignored logs 和计划修订；临时 instrumentation 必须在提交前删除。
3. 把真实证据和唯一 candidate 展开后，使用：

```powershell
git commit -m "docs(perf): 根据测量细化历史页优化方案"
```

4. 用户再次批准后，生产修复按修订计划拆成 1 个行为提交；不要为红灯测试单独留下永远失败的 commit。
5. 没有 production 修复时不创建 `perf:` 空提交。
6. 未经授权不 push、不创建 PR。

## 13. 当前阶段完成定义

本初稿阶段只有以下条件全部满足才算“计划可进入诊断”：

1. 当前调用链、同步读事实、普通分页规模和高风险候选被准确区分；
2. 用户可见契约和范围固定，不能靠删功能优化；
3. Task 0/1 给出可复现数据、profile 场景、Timeline span、执行计划与隐私规则；
4. Task 2 是硬门禁，`TBD` 未清零前禁止 production 改动；
5. 三个 candidate 有互斥进入条件、red/green contract 和停止条件；
6. 冷启动与超长会话只记录尾项，不在本 PR 实施；
7. 当前文档不把方向性 benchmark 写成真实 Windows 验证；
8. worktree 只留下本计划文档和 ignored logs，未 commit、未 push。
