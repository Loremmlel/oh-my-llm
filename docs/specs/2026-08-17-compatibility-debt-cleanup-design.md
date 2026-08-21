# 历史兼容债务清理设计

**日期：** 2026-08-17  
**状态：** 已批准  
**适用范围：** Oh My LLM 当前 Windows + Android 自用部署

## 1. 背景

Oh My LLM 是自用应用，当前只有两个实际部署终端（Windows 与 Android）。两个终端均已升级到当前最新版本并完成当前版本启动流程，因此“任意历史版本都可以直接升级到最新版”不再是产品需求。

仓库过去已经多次主动移除过期兼容层，但当前仍保留若干已经完成使命的历史兼容代码：内部状态的 additive compatibility projection、旧 SharedPreferences JSON 形状回退、SQLite 多版本迁移链、设置导入旧格式迁移链等。这些代码会持续增加状态不变量、分支数量、测试矩阵和后续 schema 演进成本。

本设计将兼容策略从“尽量保留历史升级路径”调整为“当前格式即基线”。历史兼容只有在它仍是明确产品需求时才能长期存在。

## 2. 核心决策

> **仓库默认只支持当前持久化格式与当前交换格式。除非向后兼容本身是明确产品需求，否则已经完成迁移的历史私有部署不构成长期兼容要求。**

由此得到以下规则：

1. **当前格式是唯一 canonical representation。** 内部状态、持久化对象和导入导出格式不得长期维护两个等价表示。
2. **内部兼容层优先删除。** presentation/application 之间为了过渡而存在的重复字段、投影字段、别名字段在消费者迁移后立即移除。
3. **历史迁移是临时代码。** 当所有受控终端都确认升级并完成迁移后，对应旧版本迁移代码应在下一次技术债清理中删除。
4. **兼容只允许停留在明确边界。** 当前第三方 API 协议差异、操作系统差异、真实 runtime 行为差异属于现役能力，不因本设计被删除。
5. **旧格式必须显式失败，而不是静默猜测。** 当历史格式退出支持范围后，解析器应返回明确的不支持/格式错误，而不是继续 fallback。
6. **懒兼容不能被“最新版已运行”自动判定为可删除。** 如果旧数据只有在读取时通过 `fromJson`/fallback 被兼容，而读取后并不会写回 canonical 格式，那么必须先证明旧形状已不存在，或先执行一次有界 canonicalization，再删除 fallback。
7. **新增 compatibility shim 必须有退出条件。** 新增代码必须同时说明：为什么需要、位于哪个边界、何时可以删除、由哪些测试保护。

## 3. 什么算兼容债，什么不算

### 3.1 应清理的历史兼容债

- 已有 canonical state 后仍保留的 additive/duplicated state 字段。
- 已有带版本 envelope 后仍接受的历史裸 JSON 形状。
- 只服务于已升级终端的旧 SQLite schema migration。
- 只服务于旧备份格式的 settings import migrator、旧字段别名。
- 已无消费者的 deprecated alias、transitional DTO、旧字段名、旧默认迁移分支。
- 仅为了“也许有人从很老版本升级”而保留、但当前自用部署不再需要的代码与测试 fixture。

### 3.2 不属于本次清理的现役兼容能力

以下内容即使代码中存在分支，也不能仅因为出现“compatibility/fallback”概念就删除：

- OpenAI-compatible provider 的 endpoint/path/payload 差异。
- Chat Completions、Responses、Anthropic 等当前支持的 API 协议。
- Windows 与 Android 平台差异。
- 外部进程、HTTP、SSE、文件系统等真实 runtime 返回类型或行为差异。
- 当前 Sync 协议及其现役跨端契约；除非另行审计并明确确认其旧版本分支已经退出支持。
- 当前格式中“字段可选”本身的业务语义。

判断标准不是“代码有没有分支”，而是这个分支服务的是**当前环境多样性**还是**已经退役的历史数据/历史客户端**。

## 4. 当前清理清单

| 区域 | 当前兼容行为 | 复杂度成本 | 目标状态 | 删除门槛 |
|---|---|---|---|---|
| Chat generation state | `generation` 已存在，同时维护 `isStreaming` / `isAutoRetryWaiting` / `autoRetryCount` 等兼容投影 | 双状态源、同步不变量、presentation 依赖扩散 | `generation` 为唯一事实来源；UI 只消费 snapshot 或派生 selector/getter | 所有消费者迁移并通过现有 generation/controller 测试 |
| `VersionedJsonStorage` | `decodeObject` 在缺少 `value` 时继续接受历史裸对象 | 当前 envelope 与历史裸对象形成两套输入语义，object/list 行为不对称 | object/list 都只接受当前 versioned envelope | 审计所有 `decodeObject` 消费者；若存在懒兼容残留，先 canonicalize |
| SQLite | `AppDatabase` 保留 V9→V13 迁移链及旧 system prompt 合并逻辑 | 启动分支、旧 schema 知识、fixture 与测试矩阵持续增长 | v13 成为当前 baseline；新库直接创建 v13；低于 baseline 的库明确 unsupported | 两个实际终端确认已处于 v13；合并前再做备份与版本断言 |
| Settings export/import | v5→v6→v7→v8 migrator，且接受旧 `version` 字段别名 | 每次格式升级都会把迁移链继续向后拖长 | 当前仅接受 `formatVersion: 8`；v5/v6/v7 与 `version` alias 退出支持 | 需要保留的旧备份先在当前版重导出为 v8，或明确接受其不可再导入 |
| 其他 JSON alias/default | 部分模型可能通过缺字段默认值兼容旧持久化形状 | 容易让旧形状永久潜伏 | 逐项分类；只删除纯历史 fallback | 必须区分“当前可选语义”和“历史形状兼容” |

## 5. SQLite 的滚动基线规则

SQLite 是最容易形成永久 archaeology 的区域。本项目采用**滚动 migration floor**，不保留无限迁移链。

当前清理完成后：

- `schemaVersion = 13`。
- 新数据库直接创建完整 v13 schema，并设置 `PRAGMA user_version = 13`。
- v13 数据库正常打开。
- `< 13` 数据库不再承诺自动升级，应明确报“legacy database unsupported”一类错误，而不是继续部分执行旧 schema 上的当前查询。
- V9/V10/V11/V12/V13 的历史逐级迁移实现，以及只保护这些迁移的 fixture/test，可以随之退役。当前 schema 建表定义本身继续保留。

未来假设引入 v14：

1. 发布时临时保留 **v13 → v14** 一步迁移。
2. Windows 与 Android 都升级并确认成功运行 v14。
3. 下一次 compatibility cleanup 把当前 baseline 提升到 v14。
4. 删除 v13 → v14 migration，并让新安装直接创建 v14。

因此长期目标不是“设计更漂亮的 migration framework”，而是让历史迁移链通常保持在 **0～1 步**。

## 6. JSON 持久化的额外安全规则

SQLite 使用显式 `user_version`，终端完成迁移后可以较强地证明旧 schema 已退出；JSON 不一定如此。

对于 JSON fallback，删除前必须回答：

1. 当前写入是否总是写 canonical versioned envelope？
2. 旧裸对象是否可能一直躺在 SharedPreferences 中，从未被读取？
3. 读取旧对象后是否会自动写回当前格式？
4. 如果不会，是否可以在当前两个终端上手动触发保存，或用一次性 bounded canonicalization 重写？

只有在答案能证明旧形状不再存在时，才直接删除 fallback。否则先加入一次性 canonicalization，确认两端执行后，再删除 canonicalization 与 fallback。**一次性迁移代码本身也必须有删除计划，不能变成新的永久层。**

## 7. Settings 导入导出的断代策略

设置交换格式不是跨公众用户的长期公开兼容承诺，本项目按当前自用需求处理：

- 当前格式 v8 是唯一支持的导入格式。
- `formatVersion` 是唯一版本字段。
- v5/v6/v7 migrator 与旧 `version` alias 可以删除。
- 对低于 v8 的文件返回明确的 unsupported version，而不是继续升级。
- 真正需要长期保存的旧备份，应在删除 migrator 前用当前版本导入后重新导出一次 v8。

以后升级到 v9 时，可以临时保留 v8→v9；等两个终端和需要保留的备份都完成迁移后，再把 v9 提升为新的唯一 baseline。

## 8. Chat generation 单一事实来源

`ChatSessionsState` 的 generation lifecycle 应只有一个 canonical representation。

目标模型：

- `ChatGenerationSnapshot? generation`（以及其 phase/metadata）是唯一事实来源。
- `isStreaming`、`isAutoRetryWaiting`、retry count 等 UI 所需信息通过 snapshot 的派生 getter/provider/select 得到。
- controller 只更新 canonical generation snapshot，不再同时写一组“兼容字段”。
- presentation 不依赖 transitional storage fields。
- 删除为了证明“两组字段始终一致”而存在的不变量；改为直接测试 lifecycle → derived presentation semantics。

该项不涉及磁盘格式，是本轮最低风险、应最先实施的清理。

## 9. 实施顺序

按“数据风险从低到高”拆成独立、可回滚的实现提交/PR：

1. **Chat generation internal state**：删除重复状态表示。
2. **Settings export/import**：把交换格式收紧到 v8-only。
3. **Versioned JSON storage**：先审计/canonicalize，再删除裸对象 fallback。
4. **SQLite baseline**：最后提升 migration floor 到 v13，删除 V9→V13 历史链。
5. **Repository policy audit**：全仓扫描 `legacy` / `compat` / `migration` / `deprecated` / `fallback`，逐项分类；更新 `AGENTS.md` 的持久化与兼容规则。

不把以上生产代码修改塞进同一个“大清理 PR”。每阶段应能独立测试、独立 review、独立 revert。

## 10. 验证要求

每个实现阶段至少满足：

- 对修改区域运行 targeted tests。
- `flutter analyze`。
- `dart run tool/check_import_boundaries.dart`。
- 按 `AGENTS.md` 要求重定向并运行全量 `flutter test --reporter compact`，以真实 exit code 为准。
- 对 SQLite/JSON/settings format 清理增加“当前格式成功、退出支持的历史格式明确失败”的测试。
- 数据层变更合并前保留当前数据备份；SQLite 清理再次验证两个终端数据库 `PRAGMA user_version` 已达到 baseline。

本设计 PR 本身只包含文档，不改变 runtime，因此不要求为了文档改动运行 Flutter 测试；实现 PR 必须执行上述验证。

## 11. 停止条件与回退

出现以下任一情况时，应停止对应兼容删除并先解决数据归一化：

- 当前终端仍存在低于目标 baseline 的 SQLite 数据库。
- 某个 JSON 历史形状无法证明已经被重写，而删除 fallback 会导致现有数据不可读。
- 仍有需要保留、但尚未重导出的 v5/v6/v7 settings backup。
- 搜索发现所谓“legacy”分支其实保护当前 provider/runtime/platform 行为。

回退原则是**恢复最后一个明确的边界兼容层**，而不是重新引入跨层重复状态或无限迁移链。

## 12. 完成标准

本轮 implementation 完成时应满足：

- Chat generation 不再维护 duplicated compatibility state。
- `VersionedJsonStorage` object/list 都只认当前 versioned envelope；若曾需要一次性 canonicalization，该代码在两端执行确认后也被移除。
- `AppDatabase` 不再携带 V9→V13 历史迁移知识；当前 baseline 明确，新库直接建立当前 schema。
- Settings import 不再包含 v5/v6/v7 migrator 与旧版本字段 alias。
- 仓库中剩余的 compatibility 分支都能被解释为当前产品/runtime 能力，或带有明确的删除条件。
- `AGENTS.md` 不再鼓励无限累积 migration，而记录本设计的 rolling baseline 规则。

这套规则的目标不是追求“零兼容代码”，而是让**历史兼容不会默认永久化**。