# 测试精简实施方案

第一批删减已经实施，结果与测量口径见 [first-batch-results.md](first-batch-results.md)。Chat generation / protocol 第二批结果见 [second-batch-results.md](second-batch-results.md)，媒体视频第三批结果见 [third-batch-results.md](third-batch-results.md)，Data / controller / infrastructure 第四批结果见 [fourth-batch-results.md](fourth-batch-results.md)。

## 结论

这套测试不是“普遍无价值”，而是覆盖所有权失控：同一规则常在 domain/data、application/controller、page/widget、app composition、integration 五层重复证明。建议保留最低层的完整边界矩阵，并让上层只证明自己的接线与用户可见结果。

按四份审计的保守估算，可从 60,975 个物理行中净删约 9,963 行，剩余约 51,012 行，测试代码体积下降约 16.3%；无需增删依赖。覆盖率可以下降，但数据库迁移、安全、协议、并发终态和关键用户流不得失守。

现有 `logs/fltest.log` 提供的同机基线为 2,131 个测试、1 分 46 秒。删行数不等于运行时间收益：纯函数表格很便宜，真正应优先削减的是 `chat_screen_test.dart`、Favorites/History/Settings 整页 Widget、视频页面、app router 与 Sync workspace 这些重复 pump 完整应用的场景。

## 审计汇总

| 审计块 | 物理行 | 显式测试声明 | 预计净删 | 比例 | 详细报告 |
| --- | ---: | ---: | ---: | ---: | --- |
| Chat | 20,025 | 671 | 3,065 | 15.3% | [chat.md](chat.md) |
| Media / Settings | 18,869 | 639 | 3,522 | 18.7% | [media-settings.md](media-settings.md) |
| Sync / Favorites / History | 7,721 | 252 | 976 | 12.6% | [sync-favorites-history.md](sync-favorites-history.md) |
| Core / App / Integration / Helpers | 14,360 | 398 | 2,400 | 16.7% | [core-app-integration.md](core-app-integration.md) |
| **合计** | **60,975** | **1,960** | **9,963** | **16.3%** | 参数化循环使实际运行数高于显式声明数 |

## 测试覆盖所有权

| 契约类型 | 完整覆盖的唯一 owner | 上层最多保留 |
| --- | --- | --- |
| 纯函数、parser、格式编解码 | domain/data 的表驱动测试 | 一个接线 smoke；不重跑非法输入矩阵 |
| SQLite schema 与迁移 | migration/repository 测试 | controller 只测状态发布与失败不污染内存 |
| 异步状态机、retry、latest-wins | application/run/controller 测试 | Widget 只测一次交互、loading/error 与最终可见结果 |
| HTTP/SSE 传输 | core transport/decoder | 每个协议 client 只测专属请求编码和一条成功/错误映射 |
| 平台 MethodChannel/输入 | platform adapter | composition/integration 只测一次真实 binding |
| GoRouter 编解码 | router/query codec | feature screen 只测一个深链恢复和一个用户导航 |
| 响应式布局 | shared primitive + feature 的极端 viewport | 不按设备名穷举同一布局模式，不以“不抛异常”为唯一断言 |
| Semantics/键盘 | 自绘或自定义交互控件 | 原生 Material 控件不逐个重测 Enter/Space/Tab |
| 端到端 | 每个子系统一条成功脊柱 + 一条关键失败 | 不逐协议、逐终态、逐字段复制底层矩阵 |

## 绝对保留项

- 所有已发布 SQLite schema 的迁移实现、合法旧版 fixture、数据保留、事务回滚、未来版/过旧版/malformed 拒绝。
- Sync typed protocol、AES-GCM/AAD、secure store、匿名拒绝、本地 catalog 敏感性重算、session token 与 nonce replay；审计按当前源码 `SyncProtocolVersionPolicy.current == 4` 判断，`AGENTS.md` 中仍写 v3 的说明应另行校正，不能据此删错版本测试。
- LLM 与 peer HTTP client 的信任域隔离、敏感 Header/正文日志默认关闭与统一脱敏。
- SSE 任意 byte/UTF-8 切分、`data:` 才重置 idle timeout、非 2xx、连接中断和取消订阅。
- 消息树 append/replace/delete/selected branch，编辑用户消息产生 sibling、仅最新 assistant 可重试，以及 SQLite 分支往返。
- reasoning/content 在模型、SQLite、三个协议 parser 和 UI 的分离。
- generation prepare/stream/stop/retry/finalize/outcome、durable save、旧 token 隔离、dispose/迟到事件竞态和持久化失败终态。
- Prompt 的五段拼接顺序、过滤、检查点 tail 与模板语法的核心 parser/evaluator 边界。
- inline error/empty reply、历史搜索只匹配标题与 user、收藏事务/外键、路由可序列化 ID、关键自绘组件的键盘与 Semantics。

## 实施切片

### 低风险删除

建议分支：`test/remove-low-value-tests`。

- 整文件删除恒真/镜像测试：根级模板 smoke、布局 token、`AppAdaptiveActions`、`AppConstrainedContent`、noop foreground service、NotificationBubble 主题内部结构、`Favorite` getter/copyWith。
- 删除概率性 `List.shuffle` 顺序变化测试、把 `RenderFlex overflow` 当成功条件的响应式测试、CI 已排除且依赖 OS socket 的真实 UDP smoke。
- 删除只断言 `takeException() == null`、精确 popup 坐标、精确 revision `+1`、Flutter 原生控件 Enter/Space/Tab 的重复用例。
- 每次删除前在审计文档中确认已有 surviving owner；不要为了“补回覆盖率”新增等价 mock 测试。

这批适合作为第一个 PR：改动容易逐项审查，失败时也能直接恢复单个文件或 case。

### UI 与路由矩阵收口

建议分支：`test/trim-ui-contracts`。

- ChatScreen 只保留分支切换、inline error、模板发送、草稿跨会话隔离、关键快捷键/滚动；标题、模板语法、树容器形状回到底层 owner。
- SettingsScreen 每类实体不再重复完整 CRUD；保留 provider+model 主流程、每类 prompt 一个代表创建/持久化，以及排序/变量 reconcile 等独有行为。
- 视频页面每类桌面/移动输入只留一条 wiring；交互状态转换归 controller，播放/seek/lease 归 playback controller，无障碍只保留独特语义。
- History/Favorites 页面删除 controller 已覆盖的 latest-wins、分页 clamp、rename/delete refresh；保留 URL commit/rollback、inline error、危险确认与一个翻页接线。
- `AppRouter`、`AppShellScaffold`、`SyncWorkspaceScreen` 按布局模式和 feature 各留代表，不按所有 viewport/platform/destination 做笛卡尔积。

该 PR 的审查标准是“页面是否仍覆盖用户可观察结果”，而不是“每个 controller 分支是否在页面再跑一遍”。

### Chat generation 与协议分层

建议分支：`test/trim-chat-generation`。

- `ChatGenerationRun` 独占生命周期矩阵；race contract 只保留跨持久化边界的竞态；sessions controller 只保留一条 stop 落盘、一条失败和一条 dispose。
- 自动重试保留：一次可重试成功、达到上限、异常 finish reason、timeout 开关、stop 中断和终态投影；删除一次/两次失败、多个等价正常 finish reason 的排列。
- 三个 protocol client 删除共享 transport/decoder 细节；parser 的 malformed 事件改为每协议 3 至 5 个等价类表格。
- 聊天 integration 收敛为成功持久化、停止/失败、一个协议路由和一次消息版本重启恢复，不再逐协议、逐终态重跑完整容器。

这批风险最高，应按“先确认 surviving owner，再删上层重复”的顺序逐文件做，并独立于 UI 精简接受审查。

### Data、controller 与基础设施收口

建议分支：`test/trim-data-and-infrastructure`。

- LLM provider merger 是合并规则 owner；controller 只留组合 CRUD、批量去重与写失败不发布。
- Settings transfer 保留 canonical v9、版本/malformed 拒绝、敏感确认、prepare 零写入、stale/concurrency/partial failure；catalog/coordinator/facade 不重复同一 snapshot。
- Favorites/Collections repository 删除普通 CRUD、第二份完整读取、SQLite `LIMIT/OFFSET` 51 条循环和 no-op 删除；保留 round-trip、稳定排序、外键、批量事务与回滚。
- History pagination controller 保留 latest-wins/stale/dispose/rename/delete；普通 page clamp、邻接和 route 归 shared pagination/query codec。
- 日志文件 IO 合并为写入/不写正文/轮转，SSE buffer 合并为容量丢弃/并发 flush；脱敏矩阵完整保留。
- endpoint、SSE 简单语法、UDP announcement、分页、workspace resolver 和 helper 自测改为等价类表格；不要通过“一行数据一个 test 节点”美化用例数。

## 每个 PR 的验证门槛

1. 变更前记录目标入口的用例数与耗时；变更后用同一命令、同一 warm-cache 条件重跑，报告删掉的测试节点、净删行和耗时差。
2. 每个被删行为必须能指向一个 surviving owner；若只能指向生产代码或 Dart/Flutter 框架行为，说明原测试可删；若找不到 owner，则先保留。
3. 所有改动 Dart 文件执行 `dart format`，暂存后执行 `dart format --output=none --set-exit-if-changed`。
4. 单文件/入口测试按仓库要求写入 `logs/<任务>-green.log` 并设置 60 秒进程硬超时；超时先运行 `scripts/kill-stale-test-processes.ps1`，不得直接重跑。
5. 每个 PR 结束执行 `flutter analyze`、`dart run tool/check_import_boundaries.dart`，日志写入 `logs/`。
6. 全量测试继续使用 `logs/fltest.log`、240 秒进程硬超时；比较现有 2,131 tests / 1:46 基线。期望 warm run 至少下降 20%，但不能靠删除便宜的安全/迁移纯函数测试凑数。
7. 回读 coverage 时只检查上述绝对保留模块和关键分支，不设置“总体覆盖率不得下降”的伪目标；允许未触达的简单 getter、常量和 framework wiring 下降。
8. 自审 `master...HEAD`，确认没有生产行为变化、没有新 mock 框架或快照体系、没有顺手删除安全/迁移 fixture，再按仓库六节中文 PR 模板提交审查。

## 停止条件

- 达到约 9,963 行候选净删量不是硬指标；若某项找不到明确 surviving owner，就停止删除该项。
- 同机 warm full-suite 时间下降不足 20% 时，继续分析最慢 widget 入口，不再削减毫秒级的 parser/migration 纯函数测试。
- 若精简导致单个失败无法定位，可恢复必要的表格 case 名称或 `reason`，不要恢复整层重复集成装具。
- 完成后把“一个契约一个 owner、上层一个接线”的规则补进测试协作指南，避免套件重新膨胀。

net: -9963 lines, -0 deps possible.
