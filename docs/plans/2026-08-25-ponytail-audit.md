# 全仓 Ponytail Audit 记录

**审计日期：** 2026-08-25

**审计基线：** `master` / `1e4663c88bad1e54e9399ca45bad8302599bd990`

**审计范围：** 全仓生产代码、测试代码、测试辅助代码、直接依赖，以及已合入 `master` 的 PR #1–#10 历史

**审计目标：** 降低总代码量和维护复杂度，优先寻找可直接 delete、inline、reuse 或 simplify 的内容，而不是追求 coverage 或架构形式上的完美。

本文只记录候选和建议顺序，不授权批量实施。每个 cleanup PR 都应重新核对当前调用图、已有行为测试和实际 diff，不得把估算 LOC 当作交付指标。

## 基线概况

- 生产 Dart：约 392 个文件、46,967 行。
- 测试 Dart：约 260 个文件、54,153 行。
- 审计时 `master` 与 `origin/master` 一致，工作区干净。
- 测试代码多本身不构成问题；本次关注薄层催生的装配、同一行为跨层重复验证、只证明抽象可扩展的测试，以及只有一个生产 caller/implementation 的名义边界。

## 第二轮方法：PR Archaeology

第一轮只看当前静态结构，容易把「同一个 AI PR 同时创建 abstraction、caller、fake、helper 和 tests」误认成已经独立演化成熟的 subsystem。第二轮逐个读取 PR #1–#10 的描述及原始 `base...head` 完整 diff，并执行以下检查：

1. 按路径统计 production、test、docs 的新增与删除；`lib/` 计 production，`test/` 计 test，`docs/` 与根目录 Markdown 计 docs，`pubspec.yaml` 和 `.gitignore` 不计入三类。
2. 盘点 PR 新建的 interface、port、adapter、facade、coordinator、workflow、DTO、state、fake、helper 和 integration suite。
3. 在当前 `master` 搜索每个抽象的真实生产 caller、implementation 和实例数量。
4. 区分配套是否在同一个 PR 中一起出现，而不是用今天的测试数量或引用数量反推抽象合理性。
5. 反事实比较「从当时已有代码出发的最小实现」，并分别标记 necessary、accidental、test-induced 和 documentation/process complexity。

LOC 统计为原 PR diff 的行统计，不等于当前文件长度。重命名按 Git rename 处理；估算净减按当前 `master` 重新计算。

## PR #1–#10 逐项结论

| PR | 原始 diff：production | 原始 diff：test | 原始 diff：docs | 结论 | 原因 |
|---|---:|---:|---:|---|---|
| #1 `docs: 制定历史兼容债务激进清理方案` | `+0/-0` | `+0/-0` | `+535/-0` | **minor cleanup** | 只新增 design + implementation plan，没有 runtime 抽象；但 rolling migration floor 已被当前「已发布迁移长期保留」规则和 #8 的真实野库事故否定，现存两份文档会给出相反指导。 |
| #2 `fix(chat): 统一前台通知字数统计规则` | `+10/-6` | `+5/-5` | `+0/-0` | **no action** | 直接复用已有 `countChatWords()`，只修改一个已有测试；这是本轮希望看到的最小修复，没有新 seam 或测试层。 |
| #3 `feat(settings): 建立设置传输 v9 注册表并迁移 Sync v4 协议` | `+2700/-1632` | `+4633/-3101` | `+0/-0` | **second-pass candidate** | 同一 PR 同时创建 participant 层级、type erasure/box、catalog/provider、coordinator、结果对象、fake participant 和扩展性测试；今天仍只有一个 catalog 实例。协议和敏感边界必要，注册表机制明显可压平。 |
| #4 `test(sync): 端口关闭断言改用原生 TCP 探测` | `+0/-0` | `+5/-2` | `+0/-0` | **protected** | 用原生 `Socket.connect` 替代会读取代理环境变量的 HTTP 探针，直接保护真实端口生命周期；无生产抽象、无 fake 膨胀。 |
| #5 `docs: 记录 master 受保护与分支命名规范` | `+0/-0` | `+0/-0` | `+9/-0` | **no action** | 九行稳定仓库规则，信息密度高，没有重复机制。 |
| #6 `docs: 规范 Pull Request 描述与 Sourcery 审查流程` | `+0/-0` | `+0/-0` | `+107/-0` | **minor cleanup** | 六段式契约和诚实验证规则有价值；完整示例与模板逐段重复，可在不削弱规则的前提下压缩约 45–70 行。 |
| #7 `feat(favorites): 收藏夹分页浏览器与统一的历史分页体验` | `+4226/-1539` | `+5152/-1111` | `+1042/-17` | **second-pass candidate** | 133 文件中有 41 个 docs rename，但仍实质触及 52 个 production、37 个 test 文件；migration/repository 行为必要，route/browser/pagination/preferences/bindings/test subsystem 可重新压平。 |
| #8 `fix(persistence): v13→v14 迁移补齐 favorites.title` | `+13/-0` | `+57/-0` | `+0/-0` | **protected** | 真实用户库、真实启动失败、真实数据副本验证；单事务窄自愈和数据保留回归属于高价值 migration archaeology，不能为 LOC 删除。 |
| #9 `fix(ui): 收藏与历史页返回、菜单锚定与布局修正` | `+211/-178` | `+82/-0` | `+0/-0` | **no action** | 四个具体用户可见缺陷，production 净增仅 33 行；新增测试直接断言返回目标、视觉顺序与菜单位置，没有新通用框架。 |
| #10 `feat(windows): 鼠标侧键与 browserBack 键接入全局返回导航` | `+73/-1` | `+718/-0` | `+430/-0` | **second-pass candidate** | 生产 adapter 本身窄且合理；12 条 adapter test、9 条 integration test、2 条页面回归和 430 行 plan/smoke 同时出现，大量重复证明既有返回链而不是新输入映射。 |

### 分类补充

- PR #3 的 `docs +0/-0` 只表示文档不在该 PR diff 中。其实现依据已在 base 中存在：当前 `settings-transfer-registry` implementation plan 1,491 行、design spec 714 行，共 2,205 行，仍属于该 subsystem 的当前维护成本。
- PR #7 的 docs 统计中约 41 个文件是目录重命名；真正新增的 implementation plan 为 1,025 行。重命名解释了部分「133 文件」数字，但不能解释 production/test 的净增。
- PR #10 当时新增 348 行 plan 与 82 行 smoke；smoke 后来已被删除，当前仍保留 349 行已完成 plan。
- PR #3 删除了旧 settings transfer workflow/deduplicator/executor/codec 等代码，但最终 production 仍净增 1,068 行、test 净增 1,532 行。它是「替换旧复杂度后又建立更大的通用机制」，不是单纯新增业务能力导致的必然增长。

## 重点复核：PR #3 Settings Transfer

### 同一个 PR 创建的 subsystem

PR #3 一次性创建了以下生产结构：

- `SettingsTransferParticipant<T>`。
- `ReplacingValueParticipant<T>` / `MergingCollectionParticipant<T>` 两个策略基类。
- `ErasedSettingsTransferParticipant` / `SettingsTransferParticipantBox<T>` 类型擦除层。
- `SettingsTransferCatalog` / `SettingsTransferGroupDescriptor`。
- `settingsTransferCatalogProvider` / `settingsTransferCoordinatorProvider`。
- 九个 concrete participant，以及两个私有 JSON participant 基类。
- `SettingsTransferCoordinator`、`SettingsImportBatch` 和十四种 export/import sealed result。
- Settings → Sync 的 `SettingsSyncFacade`、`SettingsSyncPreparedImport`、第二套 summary/sensitivity/result DTO 和唯一 adapter 实现。

同一 PR 又新增约 1,952 行 catalog contract、catalog、coordinator、participant 专用测试；测试内同时创建多套 `_FakeIntParticipant`、`_FakeCollectionParticipant`、`_TestOnlyStringParticipant` 和 retry participant。

### 当前真实使用图

- 当前 production 只有 **一个** `SettingsTransferCatalog` 实例，由 `settingsTransferCatalogProvider` 固定构造九项；没有 runtime plugin、用户注册或第二套 catalog。
- 九个 concrete participant 全部只在这一个 provider 中实例化，全部与 interface 在同一 PR 出生。
- `SettingsTransferParticipantBox.erase` 的生产用途只有把这九项装入同一个 catalog；`ErasedSettingsTransferParticipant` 只服务 catalog/coordinator。
- `catalog.participant<T>(key)` 只有一个真实 caller：设置页复制单条预设，且通过硬编码 `presetPrompts` key 取回刚注册的 participant。
- `SettingsTransferCoordinator` 有两个真实入口：Settings UI 与唯一 `RiverpodSettingsSyncFacade`；它不是多实现 extension point。
- `SettingsSyncFacade` 和 `SettingsSyncPreparedImport` 各只有一个 production implementation。跨 feature port 有依赖边界价值，但两套几乎同构的 summary/sensitivity/execution result 形成机械翻译层。

### 复杂度分类

**Genuinely necessary complexity**

- `SettingsTransferDocument` 的稳定 identifier/version/sections codec 和 malformed/old/future version 显式拒绝。
- 九项显式白名单；不得扫描 Provider、SharedPreferences key 或 SQLite 自动暴露设置。
- credential-bearing 元数据、导出暴露前确认、导入执行前再次确认和安全摘要。
- prepare 零写入、执行前 stale revalidation、写入串行化、一次性 batch、partial failure 安全摘要。
- Sync v4 typed protocol、请求分组校验、未请求 section 拒绝以及 Settings ↔ Sync 边界。

**Accidental complexity**

- 固定九项数据被表达成 public generic interface → 两个策略基类 → 两个私有 JSON 基类 → 九个类 → erased view → box → catalog → provider 的长链。
- catalog 的 key 正则、重复 key、重复 order、排序和 runtime typed lookup 主要防御「未来动态注册」；production 列表是源码中唯一、固定、可 review 的实例。
- 单条预设导出为复用 catalog 而做 `participant<T>(magicKey)` round-trip，反而制造了 type-erasure 后再恢复类型的循环。
- Settings 与 Sync 各维护一套几乎一一映射的 group descriptor、sensitivity、summary 和 execution result。

**Test-induced complexity**

- `新增 fake participant 无需 coordinator 分支`、`test-only participant 可注册`、`生产 catalog 固定九项顺序`、`错误泛型在执行前失败` 等测试主要证明注册框架本身。
- fake participant、box runtime 类型检查和 catalog 构造失败矩阵让同一个 PR 创建的 extension point 看起来拥有多个实现；它们不是独立 production 需求。
- catalog contract 逐项 typed fixture、participant 专用测试、coordinator fake 测试、settings facade 测试和 Sync integration 对同一路径重复覆盖。

**Documentation/process overhead**

- PR diff 本身没有 docs，但当前相关 plan/spec 共 2,205 行；其中 1,491 行 implementation plan 已完成，属于可由 Git history 取回的执行脚手架。

### 反事实最小实现

从 PR #3 的真实需求重新实现，仍应保留 strict document codec、显式九项白名单、敏感确认、prepare/revalidate/serial execution 和 Sync port；不需要保留可动态扩展的 participant object model。

更小的形态可以是：

1. 一个 application-private、非继承式的 `SettingsTransferSection` 描述值，保存 key/group/label/sensitivity 与已经擦除好的 read/encode/decode/prepare/apply closures。
2. 一个固定、有序的九项 list；generic factory 只在构造 closure 时提供编译期类型检查，不公开 `participantAs<T>`。
3. coordinator 直接迭代该 list；单预设分享直接调用预设 section 的 encoder 或一个私有纯函数。
4. 保留一个窄 Settings → Sync port，但合并纯机械的 descriptor/summary/result 投影，避免两套 sealed hierarchy 逐项翻译。
5. 行为测试集中在 codec、安全确认、零写入/stale/串行/部分失败与一条真实 Sync round-trip；删除动态扩展性证明。

**估计净减：** production 550–850 行、test 950–1,350 行；另可删除完成的 implementation plan，并把 design spec 压缩为稳定边界说明，docs 约 1,900–2,000 行可退役或压缩。为避免与全仓 completed-plan cleanup 重复计数，最终总表只把 spec 的额外 400–500 行压缩计入本项。

## 重点复核：PR #7 Favorites / Pagination

### 原 PR 的真实规模

- production 净增 2,687 行。
- test 净增 4,041 行。
- docs 净增 1,025 行。
- 41 个 docs rename 抬高了 133-file 数字，但排除它们后仍有约 92 个非纯重命名文件，绝不是一个单一分页 widget PR。

### 同一个 PR 创建的 subsystem

- core：`AppPaginationState`、`AppPaginationBar`、`AppPaginatedListShell`、页码算法、page-size 常量和 barrel。
- History：`HistoryBrowseRouteQuery`、page-size preference controller/writer、扩展后的 route echo/load API 与选择状态矩阵。
- Favorites：`FavoriteBrowserState` / `FavoriteBrowserController`、两个 preference controller、revision 型 `FavoritesLibraryController`、`CollectionsSummariesController`。
- DTO/helper：`FavoritePage`、`FavoriteCollectionSummary`、`CollectionDeleteRequest` hierarchy、`FavoriteCollectionGridSpec`、selection toolbar。
- test seam：`HistoryPageSizeWriter`、`FavoritesPreferenceWriter`、`bindFavoritesRepositories` composition flag、多个 `_FlakyFavoritesRepository` / `_FlakyCollectionsRepository`。
- tests：三套 core pagination test、browser/controller/preferences tests，以及 favorites/history route/pagination/selection/widget matrices。

### 当前真实使用图

- `AppPaginatedListShell` 有两个 production caller：HistoryScreen 与 FavoriteCollectionItemsScreen。
- `AppPaginationBar` 只有 `AppPaginatedListShell` 一个 production caller。
- `FavoriteBrowserController` 只有 FavoriteCollectionItemsScreen 一个 caller；`FavoriteBrowserState` 只被该 controller 自己引用。
- Favorites repository 是同步 SQLite 查询，但 route 的 `collectionId/page/pageSize` 又复制进 browser state，再由 screen 处理 route replace 回声。
- `HistoryBrowseRouteQuery` 只有 router 构造与 HistoryScreen 消费；Favorites 路由已经直接传递 `collectionId/page/pageSize`，证明不需要为每页建立 route DTO class。
- `HistoryBrowsePreferencesController`、`FavoritesBrowsePageSizeController` 都只有各自 pagination controller 一个真实 consumer；writer Provider 只供测试模拟失败。
- `FavoriteCollectionGridSpec` 只在收藏网格这一条 UI 树中搬运六个布局常量，另有 58 行专用测试。
- `HistoryPaginationController.prev/next/first/last` 当前没有任何 production caller，只有测试调用。

### 必须保护的复杂度

- v13→v14 SQLite migration、系统未分类收藏夹、非空归属、RESTRICT 外键、事务回滚和所有数据保留测试。
- repository 的 `LIMIT/OFFSET + COUNT`、稳定排序、删除/移动原子事务、页码越界后按真实总数补页。
- History read isolate 的 active/latest pending、旧成功/旧失败不得覆盖新请求、dispose 与文件锁生命周期。
- route query 的可序列化 deep-link/back-forward 行为本身。
- 收藏夹/详情/选择等真实用户功能和可访问性行为。

### 可重新压平的 subsystem

**Accidental complexity**

- PR 前已有 270 行 `HistoryPaginationBar`；PR 没有只抽出最小共享视觉，而是删除它并新增约 515 行 core pagination state/bar/shell/constants，再新增 592 行 core tests。共享有价值，但抽象面大于两个 caller 的需要。
- Favorites 的 repository 是同步的；用 236 行 browser controller + state 再缓存 route-owned window，制造 URL、controller state 和 screen echo 三方一致性问题。
- `HistoryBrowseRouteQuery`、`FavoriteCollectionGridSpec`、`CollectionsSummariesController`、`FavoritePage` 等对象中，前两项和 controller wrapper 可直接 record/inline/provider 化；后两项只应在确实提高查询表达时保留。

**Test-induced complexity**

- 两个 preference writer Provider、`bindFavoritesRepositories` flag 和重复 flaky repository 都由失败注入测试催生。
- core state/bar/shell、History controller、History widget、Favorites browser、Favorites widget 多层反复验证相同的 page clamp、next/previous、page size、busy/error 和 route restore。
- 当前 900+ 行 History controller tests 中，`prev/next/first/last`、`hasPrevious/hasNext`、非法容量、同页 no-op 等机械分支与共享分页纯函数重复；应保留竞态、mutation invalidation、retry、dispose 和错误保留旧窗口。
- History/Favorites 的 Ctrl/Shift/Ctrl+A/翻页清选择矩阵在同一 PR 中扩张；本地 `Set + anchor` ownership 正确，但输入组合可共享一个小纯函数或减少跨 feature 重复验收，不需要再建 selection framework。

**Documentation/process overhead**

- 1,025 行已完成 implementation plan 记录逐任务 red/green、命令和阶段路标；稳定产品契约已存在于代码、AGENTS 和行为测试，执行脚手架可以从 Git history 恢复。

### 反事实最小实现

从 PR 前代码出发，最小路线应是：

1. 完整保留 schema migration、repositories、两级收藏路由和真实页面。
2. 从既有 History pagination bar 只抽出两个页面真正共享的视觉和页码纯函数，不同时创建 state object、shell、bar、barrel 和独立三层测试契约。
3. Favorites 直接以 route tuple + revision 查询当前页；同步 repository 不需要独立 async browser state machine。
4. History 继续保留异步 query controller，但删除无 caller convenience API，把 route parsing 用 record/参数表达。
5. page-size preference 直接复用已注入的 SharedPreferences；删除 writer Provider 与只验证 fake 失败的测试。
6. selection 留在页面本地；只提取能实际净减 LOC 的 range-selection 纯函数，不建立新的 controller/interface。

**估计净减：** production 400–650 行、test 850–1,300 行、docs 约 1,000 行。该估算明确排除 migration/repository 数据安全测试。

## 重点复核：PR #10 Windows Back Navigation

### 事实与当前调用图

- PR 新增 production `+73/-1`：56 行 adapter 文件和 `app.dart` 中 17 行平台挂载。
- 同时新增 test `+718`：277 行 adapter tests、407 行 integration suite、34 行页面差异回归。
- 同时新增 docs `+430`：348 行 implementation plan、82 行 hardware smoke。
- 当前 `WindowsNavigationInputAdapter` 只有 `OhMyLlmApp` 一个 production caller；`WindowsBackRequest` typedef 只在 adapter 自己和测试中出现。
- adapter 没有 route state、factory 或多实现 port；生产设计本身已经接近最小可行实现。

### 真正需要保留的行为保护

- pointer back 触发一次 dispatcher request。
- 首次 `browserBack` key down 被消费；repeat/up 不重复返回。
- 非 Windows host 不挂 adapter。
- 至少一条真实 `OhMyLlmApp` wiring 证明输入进入 `BackButtonDispatcher`。
- TextField 聚焦时 browserBack 仍能冒泡，是 Focus 树上的真实风险，可保留一条。
- Favorites selection generic Back 与 video fullscreen generic Back/Escape 的两条页面差异回归保护真实行为，应保留。
- 真实鼠标 smoke 的「无双退」结论有平台价值；当前 smoke 文件虽已删除，Git history 仍保留证据。

### 重复或实现细节测试

- primary、secondary、browserForward、Escape、Left、Alt+Left 分成六条负向用例，只是在逐个证明 `_handleKeyEvent` 的 `if` 分支；可参数化为一条代表性放行测试。
- callback 返回 false、adapter 卸载后无响应主要证明 StatelessWidget/Flutter 生命周期，不是产品行为。
- integration suite 中 Dialog、Drawer、本地返回目标、非 Chat 顶层和 Chat 根已经由 `app_shell_scaffold_test.dart` 覆盖。
- busy PopScope 已由 Sync/Chat dialog tests 覆盖；pushed 子路由已由 app router tests 覆盖。
- 用 adapter 再跑完整返回优先级没有证明新的 adapter 行为，因为 adapter 只调用同一个 dispatcher；一条 wiring smoke 足以防止误改成 `router.pop()`/`go('/chat')`。

### 反事实最小实现

保留现有 50 行左右 adapter 和根挂载；测试收敛为约 4–6 条：pointer、browserBack phase、代表性放行、TextField、Windows wiring、非 Windows gate。既有 AppShell/router/page tests 继续拥有返回链语义。

已完成 plan 可以删除；长期 smoke 若要保留，应只保留硬件/驱动环境、pointer/key 两条路径和无双退三项，不重复自动化矩阵与执行日志。

**估计净减：** production 0–10 行、test 420–520 行、当前 docs 340–350 行。

## 明确保留的高价值复杂度

以下区域具有真实的数据、安全、并发或平台边界，不应因为 LOC 较多就直接删除：

- 已发布 SQLite migration 链、合法旧库 fixture 与数据保留测试，包括 #7/#8 的 v13→v14 收藏迁移与野库自愈。
- Sync 加密、typed protocol、nonce replay、配对授权和敏感字段确认。
- Settings transfer strict codec、显式传输白名单、敏感导入导出确认、stale/serial/partial-failure 行为；候选只挑战其表达层数。
- Chat Completions、Responses、Anthropic 三协议编码、SSE 解析和错误边界。
- generation race、durable stop、持久化终态和通知 token/ACK 竞态。
- history read isolate 的启动、退出、dispose 和 SQLite 文件锁生命周期。
- UDP socket、scheduler、multicast lock 等需要确定性驱动并发/平台行为的 seam。
- Windows pointer/key 到 dispatcher 的真实输入适配、真实硬件差异和页面级 Back/Escape 差异。
- 已知真实历史 bug、可访问性、数据安全和平台生命周期回归。

## 修订后的高置信度 Cleanup Backlog

候选按「证据强度、风险、可删除净 LOC」综合排序。表内 production/test/docs 估算互不重复；Settings Transfer、PR #7 和 #10 已吸收第一轮中与其重叠的零散候选。

| 顺序 | 候选 | 标签 | production | test | docs | 置信度 / 风险 |
|---:|---|---|---:|---:|---:|---|
| 1 | 退役已完成或已失效的 AI implementation plans：#1 compatibility plan/spec、Settings Transfer plan、#7 plan、#10 plan；稳定设计另留短说明 | `delete` | 0 | 0 | 3,300–3,400 | 高 / 极低；#1 还与当前 migration 规则冲突 |
| 2 | 收缩 #10 Windows back adapter/integration test 矩阵，复用既有 AppShell/router/page tests | `delete` / `shrink` | 0–10 | 420–520 | 0 | 高 / 低 |
| 3 | 内联 `ChatFavoriteIntentCommand` 和 sealed result，直接调用仍保留的 `ChatFavoritesFacade` | `yagni` | 70–100 | 220–270 | 0 | 高 / 低 |
| 4 | 收缩生成通知平台绑定与三协议 integration 交叉矩阵；保留 token/ACK/race/durable stop | `delete` / `shrink` | 0 | 400–550 | 0 | 高 / 低 |
| 5 | 表驱动压缩 `LlmProviderConfigsController` 测试；保留协议隔离、去重和持久化失败 | `shrink` | 0 | 280–400 | 0 | 高 / 低 |
| 6 | #7 perimeter：删除 History `prev/next/first/last`、writer seams、test-only composition flag、grid spec、route DTO 和重复纯函数测试 | `delete` / `inline` | 120–200 | 300–500 | 0 | 高 / 低至中 |
| 7 | 内联单 caller 的 `ModelCatalogWorkflow` / request / failure 层 | `yagni` | 60–80 | 100–130 | 0 | 高 / 低 |
| 8 | 去重视频 controller/page/accessibility 的 M/F/方向键/Escape/长按/滚轮矩阵；保留生命周期和真实历史回归 | `delete` / `shrink` | 0 | 250–400 | 0 | 高 / 低 |
| 9 | 删除 PR #7 之外的 preference/persistence writer fake seams，直接使用已注入 SharedPreferences | `yagni` | 50–80 | 70–120 | 0 | 高 / 低 |
| 10 | 用函数 Provider 替代单方法名义 ports；不推广到 UDP/crypto/transport | `yagni` | 50–90 | 30–60 | 0 | 高 / 低 |
| 11 | 压平 Chat workspace 只搬运字段的 read-model/view-state/bindings；保留 resolver 和 ownership 契约 | `yagni` / `shrink` | 150–230 | 100–150 | 0 | 中高 / 中 |
| 12 | #3 Settings Transfer：固定 section descriptors 替代 participant hierarchy/catalog/type-erasure，并收缩 abstraction-proof tests | `yagni` / `shrink` | 550–850 | 950–1,350 | 400–500 | 高 / 中高；安全/协议边界必须原样保留 |
| 13 | #7 core：route 直接拥有 Favorites window，压平同步 browser state machine，缩小 pagination shell/state 与重复 selection tests | `shrink` | 280–450 | 550–800 | 0 | 中高 / 中高；History async race 不动 |
| 14 | 压缩 PR #6 的 PR 模板完整示例，保留六段式结构和验证诚实性规则 | `shrink` | 0 | 0 | 45–70 | 高 / 极低 |
| 15 | 删除源码未引用的 `cupertino_icons` 与 `meta` 两个直接依赖 | `delete` | 少量配置行 | 0 | 0 | 高 / 低 |

## 第一批低风险 Cleanup PR

### 首选第一个 PR：收缩 Windows Back 的重复证明

建议标题：

```text
test(windows): 收缩返回输入重复测试矩阵
```

建议范围：

1. 不修改 `WindowsNavigationInputAdapter` 与 `app.dart` 生产行为。
2. adapter unit tests 保留 pointer、browserBack phase、代表性放行、TextField 四类。
3. integration 只保留一条真实 Windows root wiring 和一条非 Windows platform gate；删除重复返回链矩阵。
4. 保留 Favorites generic Back 和 video Back/Escape 两条页面差异回归。
5. 删除已完成的 Windows implementation plan；真实 smoke 证据继续由 Git history 保留。

预计净减 760–870 行，几乎全部是 test/docs；不触碰数据、协议、业务状态或平台实现，是验证本次 cleanup 原则的最佳首个 PR。

### 其余第一批

1. **docs-only：退役已完成/冲突的 agent plans**，约净减 3,000 行以上；先确认没有外部链接依赖，稳定规则保留在 AGENTS 或短 spec。
2. **Chat favorite intent inline**，约净减 290–370 行；保留 `ChatFavoritesFacade` 与 widget 行为测试。
3. **PR #7 perimeter cleanup**，先删零 caller API、writer fake、composition test flag、grid spec 和 route DTO，不动 migration/repository/browser core。
4. **测试矩阵压缩**，分别对 generation notification、provider config、video 做独立 PR，避免一个“大删测试”难以审查。
5. **Model catalog workflow inline**，单页面、单网络 client、无数据迁移，适合作为独立小 PR。

## 第二批：需要更深入 Simplification 的 PR

### A. Settings Transfer 固定注册表压平

先用保留下来的 codec、安全确认、stale/serial/partial-failure 和 Sync e2e 测试固定行为，再替换 participant hierarchy/catalog/box。不要先删安全测试，也不要把 Settings domain 类型直接泄漏进 Sync。

如一次 diff 太大，可拆为：

1. 删除 catalog extensibility/type-erasure 专用测试并把九项声明改成静态 descriptor。
2. 合并机械的 Settings ↔ Sync descriptor/summary/result 投影。
3. 最后压缩完成的 design spec，只保留格式、安全和协议边界。

### B. Favorites route-owned browser

把 Favorites 的同步 page query 直接绑定到 route tuple + library revision，删除第二份 browser window owner。保留错误展示与 mutation 后补页；不要把 History 的异步 query controller一起泛化。

### C. Shared pagination 变浅

保留两个页面真正共享的页码算法和 visual bar；评估 shell/state 是否仍比直接组合更短。删除由 `const AppPaginationState` 催生的重复 clamp 表达式和一致性测试。

### D. Chat workspace 数据搬运层

在独立 PR 中压平 read model/view state/bindings；这项不来自 PR #1–#10，但第一轮静态审计证据仍成立。必须保留编辑、模板选择与 session ownership 行为。

## 总体净减估算

以下为互不重复的 backlog 汇总，不把已被 #3/#7/#10 吸收的第一轮候选重复相加：

| 类别 | 预计净减 |
|---|---:|
| production | 1,300–2,100 行 |
| test / fake / helper | 3,700–5,300 行 |
| docs / process artifacts | 3,700–4,000 行 |
| **合计** | **8,700–11,400 行** |
| direct dependencies | **2 个** |

与第一轮 2,100–3,000 行估算相比，增量主要来自三处历史证据：

- #3 固定九项 Settings Transfer 被同一 PR 包装成可扩展 registry subsystem。
- #7 同一 PR 同时创建 route/browser/pagination/preferences/bindings/tests，并留下 1,025 行执行计划。
- #10 用 718 行测试和 430 行文档保护 73 行 production 输入适配，其中大部分返回链在此前已有 owner tests。

## 执行原则

- 一次只实施一个可独立 review 的 cleanup 目标，不做全仓“大删测试”PR。
- 先列出保留的用户行为、数据/安全/协议/竞态契约，再删除只证明实现形态的测试。
- 不以「已有很多实现类/fake/tests」证明抽象成熟；先查它们是否在同一 PR 中共同出生。
- 删除抽象时内联到已有 owner，或改成固定数据/closure 描述；不要再创建一套 generic replacement framework。
- completed implementation plan 属执行脚手架，不是永久架构文档；稳定决策压缩进短 spec/AGENTS，过程由 Git history 保存。
- 如果 cleanup 需要改变 schema、已发布 migration、Sync wire format、敏感确认、持久化兼容或竞态语义，停止并拆成独立设计。
- 每个 PR 正文记录实际 production/test/docs 净变化；未运行的测试不得写成已通过。
