# 全仓 Ponytail Audit 记录

**审计日期：** 2026-08-25  
**审计基线：** `master` / `1e4663c88bad1e54e9399ca45bad8302599bd990`  
**审计范围：** 全仓生产代码、测试代码、测试辅助代码、直接依赖，以及已合入 `master` 的 PR #1–#10 历史

**执行状态（2026-08-25 更新）：** 首批低风险清理（候选 1/2/3/6 + 依赖）已通过 PR #18/#19/#22/#23/#24 全部合入 master；候选 4/7/8 经调查确认收益大幅低于初估或另有取舍，不纳入实施；候选 5/9/10 留作第二批，需先走计划流程。详见文末「执行记录与审计修正」。

## 结论

当前仓库约有：

- 生产 Dart：392 个文件、46,967 行。
- 测试 Dart：260 个文件、54,153 行。

第一轮静态审计已经能看到不少单 caller 薄层、重复测试和 test-only seam；第二轮回看 PR #1–#10 后，又确认了一个更重要的问题：同一个 AI PR 有时会同时创建 abstraction、caller、fake、helper 和 tests，导致这些结构今天看起来像已经成熟的 subsystem，实际上可能只是一次开发过程共同产生的 accidental complexity。

因此本文件只保留最终 cleanup backlog 和必要证据，不再记录完整审计过程。目标是降低长期维护成本，而不是为了 LOC 删除代码，也不是追求更高 coverage 或更完整的架构形式。

预计全部候选实施后可净减约：

| 类别 | 预计净减（修订后） |
|---|---:|
| production | 900–1,300 行 |
| test / fake / helper | 2,100–2,600 行 |
| docs / process artifacts | 3,600–3,750 行 |
| **合计** | **6,600–7,700 行** |

> 修订说明（2026-08-25 调查复核）：原审计初估的 8,700–11,400 行含 docs 类别重复计算（候选 1 的 348 行与候选 2 重叠），且候选 4/8/7/9 收益被高估，已全部按实测修订（各候选区间与第一批实际净减见文末「执行记录与审计修正」）。第一批已实际净减约 **4,100 行**（docs 3,398 / test 约 610 / production 约 130）。

此外可移除 2 个当前源码未直接引用的 direct dependency：`cupertino_icons`、`meta`。依赖清理应单独实施并重新确认。

## 明确保留的高价值复杂度

以下内容默认不因 LOC 较多而清理：

- 已发布 SQLite migration、合法旧库 fixture、数据保留与真实野库回归。
- Sync 加密、typed protocol、nonce replay、配对授权和敏感字段确认。
- Settings Transfer 的稳定 document codec、显式传输白名单、敏感导入导出确认、prepare 零写入、stale revalidation、串行写入和 partial-failure 行为。
- Chat Completions、Responses、Anthropic 三协议编码、SSE 解析和错误边界。
- generation race、durable stop、持久化终态以及通知 token / ACK 竞态。
- History read isolate 的启动、退出、dispose 和 SQLite 文件锁生命周期。
- UDP socket、scheduler、multicast lock 等真实并发或平台 seam。
- Windows pointer / key 到 BackButtonDispatcher 的真实输入适配，以及不同页面 Back / Escape 的真实差异。
- 已知真实历史 bug、可访问性、数据安全和平台生命周期回归。

## 前 10 个 Cleanup 候选

以下按“高置信度、低风险、可删除净 LOC、适合作为独立 PR”综合排序。LOC 是保守估算，不是实施配额。

### 1. ✅ 已实施 · 收缩 Windows Back 的重复测试与已完成计划

**标签：** `delete` / `shrink`  
**风险：** 低  
**预计净减：** production 0–10 行、test 420–520 行、docs 340–350 行

PR #10 只新增约 73 行 production：一个约 56 行的 `WindowsNavigationInputAdapter` 加根节点挂载；同时新增约 718 行测试和 430 行 plan / smoke。production adapter 本身已经接近最小实现，主要问题在重复证明。

保留：pointer back；`browserBack` down / repeat / up 阶段；TextField 聚焦；一条真实 Windows root wiring；一条非 Windows gate；Favorites generic Back 与 video Back / Escape 的页面差异回归。

删除或合并：多个只证明放行分支的负向测试、integration 中已由 AppShell / router / dialog / page tests 拥有的返回优先级矩阵，以及已完成的 implementation plan。硬件 smoke 证据已在 Git history 中保留。

这是推荐的第一个 cleanup PR：几乎不碰 production 行为，最适合验证“删重复证明、保真实行为”的方法。

### 2. ✅ 已实施 · 退役已完成或已经失效的 AI implementation plans

**标签：** `delete`  
**风险：** 极低  
**预计净减：** docs 约 3,300–3,400 行

重点包括 PR #1 compatibility plan、Settings Transfer implementation plan、PR #7 pagination / favorites plan、PR #10 Windows Back plan。

其中 PR #1 的 rolling migration floor 已被后续真实野库事故和当前“已发布 migration 长期保留”规则否定。稳定、仍有效的产品边界应压缩到短 spec 或 AGENTS；逐任务 red / green、命令记录和阶段路标属于执行脚手架，可由 Git history 恢复。

### 3. ✅ 已实施 · 内联收藏 intent 薄编排

**标签：** `yagni`  
**风险：** 低  
**预计净减：** production 70–100 行、test 220–270 行

`ChatFavoriteIntentCommand` 只有 `ChatScreen` 一个 production caller。`restore`、`addToCollection`、`createCollection` 大多只是转发 `ChatFavoritesFacade`，sealed result 又让页面重新 pattern-match 刚包装的结果。

建议删除 command、result 类型及 Provider，让 `ChatScreen` 直接调用仍保留的 `ChatFavoritesFacade`。最近 user message 解析若仍值得单独验证，只保留一个私有纯函数和最小参数化测试。

`ChatFavoritesFacade` 不应删除：它仍承担 Chat 与 Favorites 的真实跨 feature 边界。

### 4. ⏸ 暂缓 · 收缩生成通知的重复测试矩阵

**标签：** `delete` / `shrink`  
**风险：** 低  
**预计净减：** test 400–550 行

平台选择绑定本身很薄，但对应测试和 integration 又按多个 LLM 协议重复验证相同的 `start / update / remove / fail` 投递。协议客户端、notification projector 和 coordinator 已分别拥有自己的契约测试。

保留 coordinator 的 token、定时器、串行 tail、ACK retry、dispose、stale action、durable stop 和持久化终态等竞态；integration 只保留能证明真实 wiring 的少量成功、停止和 fail-open 链路，不再做协议 × 通知交叉矩阵。

### 5. 📋 第二批（计划） · 压缩服务商配置控制器测试

**标签：** `shrink`  
**风险：** 低  
**预计净减：** test 280–300 行（修订后）

`LlmProviderConfigsController` production 约 153 行，但测试约 821 行。普通 CRUD、unknown provider、empty input 和排序分支反复创建完整 ProviderContainer / fixture，很多用例只是逐方法锁定显然的列表操作。

建议把机械 CRUD / no-op 合并为参数化测试，复用最小持久化断言；保留导入等价键、协议隔离、重复模型、同批输入去重和持久化失败不发布状态等真实边界。

### 6. ✅ 已实施 · 清理 PR #7 的外围薄层和 test-only seam

**标签：** `delete` / `inline`  
**风险：** 低至中  
**预计净减：** production 120–200 行、test 300–500 行

PR #7 实质触及约 52 个 production、37 个 test 文件。migration、repository 和真实两级收藏浏览必须保留，但外围有一批成本高于价值的结构：History `prev / next / first / last` convenience API、preference writer Provider、`bindFavoritesRepositories` test-only flag、`FavoriteCollectionGridSpec`、部分 route DTO / wrapper，以及与共享分页纯函数重复的 controller 测试。

这一轮只清 perimeter，不改 schema、repository、History async race，也不重写 Favorites browser ownership。

### 7. ❌ 建议搁置 · 内联单 caller 的 Model Catalog workflow

**标签：** `yagni`  
**风险：** 低  
**预计净减：** production 60–80 行、test 100–130 行

`ModelCatalogWorkflow`、`ModelCatalogRequest`、`ModelCatalogFailure` 只有 Settings 页面一个 caller。该层主要重新命名字段后转发给 `ModelListClient`，再把 `ModelListException` 映射成另一种异常。

建议把 endpoint override / parsing 和稳定错误文案放回 `ModelListClient` 或 Settings 调用边界，删除 workflow Provider、专用 DTO 和异常层。

### 8. ⏸ 暂缓 · 去重视频交互测试矩阵

**标签：** `delete` / `shrink`  
**风险：** 低  
**预计净减：** test 250–400 行

M / F / 方向键 / Escape / 长按 / 滚轮等输入在 desktop controller、desktop page 和 accessibility 三层重复验证。

controller 保留完整输入状态机；page 层只验证必要 wiring；accessibility 只验证 semantics、焦点顺序、keyboard equivalent 和 live region。失焦、销毁后 Future、全屏恢复失败、控制栏焦点等真实生命周期或历史 regression 应保留。

### 9. 📋 第二批（深度简化，计划） · 压平 Settings Transfer 的固定注册表架构

**标签：** `yagni` / `shrink`  
**风险：** 中高  
**预计净减：** production 400–600 行、test 600–850 行，另可压缩稳定 spec 约 200–350 行（修订后）

PR #3 一次性创建 participant hierarchy、type erasure / box、catalog / provider、coordinator、结果对象、fake participant 和大量扩展性测试。今天 production 仍只有一个固定 catalog，九个 participant 只由这个 provider 构造，没有 runtime plugin、用户注册或第二套 catalog。

当前链路大致是：

`generic participant -> replacing/merging base -> JSON base -> concrete participant -> erased view -> box -> catalog -> provider`

真正需要的是固定九项白名单、strict codec、安全确认、prepare / stale / serial / partial-failure 和 Sync 边界，而不是动态扩展 object model。

更小的方向应是 application-private 的固定 section descriptor 列表，以 closure 保存 read / encode / decode / prepare / apply；coordinator 直接遍历固定列表。跨 feature 的窄 Sync port 可以保留，但应减少两套几乎同构的 descriptor / summary / result 机械翻译。

这是深度 simplification，不与低风险 cleanup 混在同一个 PR 中。

### 10. 📋 第二批（深度简化，计划） · 压平 PR #7 的 Favorites / shared pagination core

**标签：** `shrink`  
**风险：** 中高  
**预计净减：** production 350–440 行、test 350–450 行（修订后）

PR #7 的 migration / repository 很有价值，但 UI 状态层存在重复 owner：Favorites repository 本身是同步查询，route 已持有 page / pageSize 等可序列化状态，又额外通过 browser controller / state 缓存同一窗口，形成 URL、controller state、screen echo 三方同步成本。

同时，共享 pagination 从 PR 前约 270 行的 History bar 扩展成约 515 行 core state / bar / shell / constants，并配套约 592 行 core tests；两个 caller 的共享价值存在，但当前抽象面偏大。

建议让 Favorites 以 route tuple + library revision 直接查询当前页；History 保留真正需要的 async query controller 与竞态语义；shared pagination 只保留两个页面真正共享的页码算法和 visual bar；selection 继续由页面本地拥有，不再创建新的 selection framework。

这一项必须单独设计和实施，不得触碰 migration、数据保留和 History isolate 生命周期。

## 其他暂缓候选

以下仍有 cleanup 价值，但证据或收益暂不足以进入前十，后续在上述 PR 完成后重新评估：Chat workspace 的 read-model / view-state / bindings 数据搬运层；PR #7 之外的 preference writer fake seams；单方法 nominal ports；PR #6 中重复的 PR 模板完整示例。

`cupertino_icons` / `meta` 依赖已于 2026-08-25 移除（PR #24），不再属于暂缓项。另有两个本次调查新增的后续项：收藏按来源元数据匹配（既有缺陷：同内容多条收藏时按内容取最新可能删错，Sourcery review 提出）与 `docs/plans/2026-08-22-history-page-performance.md` 状态过期（功能已实现但文档仍标"等待授权"）。

不要为了“顺手”把这些内容塞入前十候选的实施 PR。

## PR #1–#10 Archaeology 摘要

第二轮历史审计只用于校正上面的前十候选，不再作为第二套 roadmap。

| PR | production diff | test diff | docs diff | 最终判断 |
|---|---:|---:|---:|---|
| #1 compatibility cleanup plan | `+0/-0` | `+0/-0` | `+535/-0` | **cleanup**：失效 / 已完成计划退役 |
| #2 notification word count | `+10/-6` | `+5/-5` | `+0/-0` | **no action**：理想的小修复 |
| #3 Settings Transfer v9 | `+2700/-1632` | `+4633/-3101` | `+0/-0` | **deep simplification**：固定注册表被包装成可扩展 subsystem |
| #4 native TCP probe test | `+0/-0` | `+5/-2` | `+0/-0` | **protected**：真实端口生命周期 |
| #5 branch rules | `+0/-0` | `+0/-0` | `+9/-0` | **no action** |
| #6 PR / Sourcery rules | `+0/-0` | `+0/-0` | `+107/-0` | **minor cleanup**：示例可压缩，规则保留 |
| #7 Favorites / Pagination | `+4226/-1539` | `+5152/-1111` | `+1042/-17` | **cleanup + deep simplification**：先外围，再 core |
| #8 v13 -> v14 migration fix | `+13/-0` | `+57/-0` | `+0/-0` | **protected**：真实用户库与数据保留 |
| #9 UI fixes | `+211/-178` | `+82/-0` | `+0/-0` | **no action**：具体用户可见缺陷 |
| #10 Windows Back | `+73/-1` | `+718/-0` | `+430/-0` | **cleanup**：production 合理，测试 / 执行文档过量 |

补充：PR #3 虽自身 docs diff 为 0，但其 base 已有 1,491 行 implementation plan 和 714 行 design spec；PR #7 的 133 个 changed files 中约 41 个是 docs rename，但 production / test 净增仍很大；PR #10 的 smoke 后来已删除，当前仍保留约 349 行已完成 implementation plan。

## 执行原则

- 一次只实施一个候选，不做全仓“大删测试”PR。
- cleanup 不使用 Superpowers / TDD 流程；现有测试首先作为 characterization / regression baseline。
- 删除 abstraction 时同步删除只证明该 abstraction 可扩展或实现细节的 fake / contract test。
- 测试缩减的标准是删除重复或低价值装配，不是追求更低测试数量。
- 优先 `delete > inline > reuse > simplify`；不要为了“简化”再创建新的 generic framework。
- production cleanup 原则上应净负 LOC；如果必须增加新 subsystem 才能完成，应停止重新评估。
- 不顺手改变 schema、已发布 migration、wire format、敏感确认、持久化兼容或竞态语义。
- 每个 cleanup PR 正文记录 production / test / docs 实际净变化、保留的行为契约和实际运行过的验证；未运行的测试不得写成已通过。

---

## 执行记录与审计修正（2026-08-25）

### 第一批（已合入 master）

| 候选 | PR | 内容 | 实际净减 |
|---|---|---:|---:|
| 2（退役 plans） | #18 | 删除 5 份已合入功能的 plan/design | docs -3,398 |
| 1（Windows Back 测试） | #19 | 收缩重复测试 + 补 browserBack 根部用例 | test -339 |
| 3（收藏 intent） | #22 | 内联薄编排（原 #20 因需人工审阅回滚后重提，经独立审阅 + 补撤销回归测试） | prod -75 / test -122 |
| 6（PR #7 外围） | #23 | 死 API / 死 seam / GridSpec 内联 | 约 -205（含 test） |
| 依赖 | #24 | 移除 `cupertino_icons` / `meta` | 0 |

实际合计约 **4,100 行**（docs 3,398 / test 约 610 / production 约 130）。

### 调查修正（相对原始审计）

- **docs 类别重复计算**：候选 1 的 348 行（windows-back plan）与候选 2 重叠，两候选都实施时只删一次；原合计 8,700-11,400 行应下调至约 6,600-7,700。
- **候选 4**：声称 400-550 行实为约 40-55 行（把应保留的契约/竞态测试计入了可减）。
- **候选 8**：声称 250-400 实为约 68 行，且 accessibility 层被误判为第三层重复。
- **候选 7**：因架构门禁（presentation 不得直触 data 层）净减仅约 25-40 行且必须保留 application seam，性价比最低。
- **候选 9**：收益偏高 30-40%（prod 实约 400-600、test 约 600-850、spec 约 200-350）。
- **候选 3**："最近 user message 解析"因禁 `part of` 只能提为 public 纯函数（约 +20 行），否则无法参数化测试。
- **候选 5**：必须先补 `sortProviderConfigs` 单元测试再收缩（现有排序覆盖全在待删测试里）。
- **新增撤销路径回归测试**（候选 3）：独立审阅发现内联后"撤销恢复收藏"契约失去测试保护，补用例后全量 2136 用例通过。

### 第二批（未开始，需先走计划流程）

- **候选 5**：压缩服务商配置控制器测试（test 约 280-300）。
- **候选 9**：压平 Settings Transfer 固定注册表（prod 400-600 / test 600-850 / spec 200-350；深度简化，计划必含往返/边界/安全/快照验证）。
- **候选 10**：压平 Favorites / shared pagination core（prod 350-440 / test 350-450；先外围后 core，须单独设计）。

### 不做或暂缓

- 候选 4：不做（6 个协议×通知用例是"多协议真实路由→通知"的唯一端到端证据）。
- 候选 8：暂缓（收益约 68 行，且删后留 wiring 盲区）。
- 候选 7：建议搁置（撞架构门禁，性价比最低）。

### 后续改进项

- 收藏按来源元数据匹配（`sourceAssistantMessageId` / `sourceConversationId` 优先，历史条目 fallback 内容匹配）——既有缺陷，待安排独立 PR。
- `docs/plans/2026-08-22-history-page-performance.md` 状态过期（868 行）——可单独清理。
