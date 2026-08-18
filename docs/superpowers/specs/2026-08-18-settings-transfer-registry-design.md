# 统一设置传输 Registry 架构设计

**日期：** 2026-08-18
**状态：** 已批准，待实施计划
**适用范围：** Settings 剪贴板导入导出、单项设置分享与 Sync 设置同步

## 1. 背景

当前应用已经有一条部分统一的设置传输链路：设置页按 Tab 导出到剪贴板、从剪贴板导入、复制单条预设 Prompt，以及设备间 Sync，均以 `SettingsExportData` / `SettingsExportCodec` 为主要交换边界；导入还复用了 `SettingsImportDeduplicator` 与 `SettingsImportExecutor`。

现状并非完全“各自为战”，但统一只停留在交换包和部分执行器层面。每增加一种可传输设置，仍可能需要分别修改：

- `SettingsExportData` 字段、`hasContent` 与构造调用；
- `SettingsExportCodec` 编码、解码和格式校验；
- `SettingsTransferWorkflow` 的读取依赖、Tab 导出和 Tab 匹配；
- `SettingsImportDeduplicator` 的本地读取和冲突策略；
- `SettingsImportExecutor` 的写入目标与执行分支；
- `RiverpodSettingsSyncFacade` 的选择、导出与去重映射；
- Sync 分类、敏感等级和请求 payload；
- 剪贴板及 Sync 确认对话框中的摘要行。

这些枚举已经出现可观察的漂移风险。例如输出处理设置已经进入交换包与导入执行链，却没有同步进入所有确认摘要；剪贴板确认对话框也只完整描述部分列表型数据。当前设置页还依赖 Tab index 与 `SettingsTransferTab.values` 顺序一致，Sync 则维护另一套四分类布尔选择和敏感性 switch。

本设计把“什么可以传输、如何传输、如何合并、是否敏感、如何摘要”收敛为 Settings feature 内的单一 catalog。剪贴板和 Sync 只作为传输适配器消费同一套设置传输能力。

## 2. 核心决策

> **所有设置默认仅本地。只有显式注册 `SettingsTransferParticipant<T>` 的设置才可传输；注册后，当前分类导出、全局剪贴板导入、标准摘要、安全确认和设备 Sync 自动消费同一份声明。**

由此得到以下规则：

1. 不扫描全部 Provider、SharedPreferences key 或 SQLite 表来猜测可传输设置。
2. Settings feature 拥有 transfer catalog、participant 语义和 canonical document；Clipboard 与 Sync 不维护具体设置字段清单。
3. participant 必须显式声明稳定 key、所属分组、敏感等级、codec、读取、冲突处理、摘要和写入。
4. 新增普通设置不会自动传输；新增并注册 participant 后，不再修改剪贴板入口、Sync 页面、Sync facade 字段映射或确认对话框字段列表。
5. 合并、替换或清空语义由 participant 明确决定，统一框架不根据 Dart 类型猜测。
6. 交换格式与 Sync 协议继续采用严格版本边界；schema 改变必须显式提升版本。
7. 不为所有设置建立统一模型或 Controller 上帝基类；复用集中在窄持久化基类与 transfer participant 策略。

## 3. 目标

- 建立 Settings transfer 的单一事实来源。
- 让新增可传输设置只需实现并注册 participant，不再手工接线到所有入口。
- 让剪贴板和 Sync 共享相同的编码、解码、领域校验、冲突处理、摘要及执行语义。
- 将剪贴板导入从当前 Tab 解耦，自动识别 document 中的全部已注册 section。
- 保留稳定分组，新增 participant 只声明所属分组，不扩张 Sync 页面或协议分类。
- 对 API Key、自定义 Header 等敏感内容统一执行剪贴板与 Sync 确认规则。
- 严格区分“没有传输该设置”和“传输了有效空值”，允许替换型设置表达清空。
- 在混合 SQLite / SharedPreferences 存储下提供诚实、可恢复的执行结果，不伪装成不存在的全局事务。
- 用 catalog 契约测试直接证明“新增 participant 不修改入口”的自动适配能力。

## 4. 非目标

本设计不实现：

- 运行时反射、Provider 自动扫描或 SharedPreferences 全量导出；
- build_runner / 注解代码生成；
- 实时双向同步、云端同步或后台持续同步；
- 集合删除传播、整库镜像或三方冲突解决 UI；
- 对所有设置 Controller、Repository 或 domain model 的统一继承树；
- 自动把设备本地偏好变为可传输设置；
- 历史设置交换格式的永久兼容链；
- SQLite schema 或现有本地设置持久化格式迁移；
- 对无关 feature 的状态管理重构。

代码生成可以在 participant 数量显著增长、手工注册成为可测量维护成本后另行设计；它不是本次 registry 的前置条件。

## 5. 总体架构

```text
各设置 Controller / Repository
          ↑↓
SettingsTransferParticipant<T>
          ↓
 SettingsTransferCatalog
          ↓
SettingsTransferCoordinator
     ┌──────────┬─────────────┐
     ↓          ↓             ↓
当前分组导出   单项值导出   自动识别并准备导入
     ↓          ↓             ↑
      Clipboard presentation adapter
                              ↑
                       SettingsSyncFacade
                              ↑↓
                          Sync 协议
```

核心组件：

1. `SettingsTransferParticipant<T>`：一种设置的类型化传输声明。
2. `SettingsTransferCatalog`：已注册 participant 与稳定分组的不可变集合。
3. `SettingsTransferCoordinator`：统一导出、解码、准备、重校验和执行。
4. `SettingsTransferDocument`：纯数据、版本化的 canonical 交换包。
5. `SettingsImportBatch`：所有 section 已完成类型化准备后的待确认批次。
6. `SettingsTransferSummaryItem`：participant 生成的安全摘要。
7. Clipboard adapter：只负责系统剪贴板调用和 presentation 交互。
8. `SettingsSyncFacade`：Sync application 对 Settings transfer 能力的唯一聚合边界。

职责约束：

- participant 不导入 Flutter UI、Clipboard 或 Sync 协议类型。
- domain document 不读取 Provider，也不执行持久化。
- presentation 不解析 section payload，不按具体设置类型分支。
- Sync 不读取 Settings controller，不重新声明设置字段或合并规则。
- participant 的读取函数在操作发生时读取最新状态，catalog 创建时不缓存设置快照。
- 当前 Tab 只决定导出的 group；导入不再依赖当前 Tab。

## 6. 稳定分组

Catalog 定义六个稳定分组：

| ID | 显示名 | 顺序 | 当前典型内容 |
| --- | --- | ---: | --- |
| `providers` | 服务商 | 0 | 服务商、模型、API Key |
| `presets` | 预设 | 1 | 预设 Prompt |
| `prompts` | 提示词 | 2 | 记忆、模板、固定顺序提示词 |
| `network` | 网络 | 3 | 自定义 Header |
| `outputProcessing` | 输出处理 | 4 | 输出处理规则 |
| `other` | 其它 | 5 | 字号、自动重试等 |

分组是稳定交换与 Sync 选择概念。participant 必须引用现有分组，不能自行创建任意字符串分组。增加新 participant 不改变协议；增加第七个分组属于显式协议和交换格式变更。

设置页 Tab 应通过 descriptor 关联 transfer group，不再依赖 Tab index 与 enum values 顺序偶合。Tab descriptor 可以继续由 Settings presentation 持有，但其 transfer group 必须是稳定 ID。

分组敏感性不手写。`SettingsTransferGroupDescriptor.containsSensitive` 由组内 participant 的最高敏感等级聚合：

- 服务商 participant 含 API Key，因此 `providers` 自动是敏感分组；
- Header participant 含 token 风险，因此 `network` 自动是敏感分组；
- `other` 不再因为历史上与 Header 共用 Sync 分类而被整体标记敏感；
- 将来在任意分组注册敏感 participant，该组的所有标准入口自动升级为敏感流程。

## 7. Participant 契约

### 7.1 类型化接口

概念接口如下；最终命名可在实施计划中根据 Dart 类型约束微调，但职责不得合并或缺失：

```dart
abstract interface class SettingsTransferParticipant<T> {
  SettingsTransferKey get key;
  SettingsTransferGroup get group;
  String get label;
  int get order;
  TransferSensitivity get sensitivity;

  T readLocal();
  Object encode(T value);
  T decode(Object payload);

  bool shouldExport(T value);

  SettingsTransferChange<T>? prepareImport({
    required T local,
    required T incoming,
  });

  Future<void> applyImport(T value);
}
```

字段语义：

- `key`：section 的稳定 wire key；不得因类重命名而变化。
- `group`：六个稳定分组之一。
- `label` / `order`：安全摘要的稳定显示与顺序。
- `sensitivity`：至少区分 `standard` 和 `credentialBearing`。
- `readLocal`：读取操作发生时的最新本地值。
- `encode` / `decode`：只处理该 participant 的 section payload。
- `shouldExport`：明确当前值是否形成 section；框架不统一猜空值。
- `prepareImport`：完成领域校验、去重、合并或替换，返回实际 change；没有变化返回 `null`。
- `applyImport`：调用所属 Controller / Repository 并等待真实持久化 Future。

`encode` 必须返回非 null、JSON-safe 的 section payload。`decode` 必须对当前格式执行严格校验。旧字段别名、缺失默认和历史迁移只有在它们仍是当前格式的明确业务语义时才能存在，不能作为永久 fallback。

`readLocal` 是同步契约：它必须立即返回已经加载到内存或可同步读取存储中的当前状态，不能在内部启动异步首载。当前九类数据满足此前提：SQLite 设置实体在 controller build 时同步全量加载，版本化 JSON 与服务商配置也使用同步 getter。未来若某个候选 participant 只能异步首载，必须先在 bootstrap / controller 生命周期中完成加载并暴露同步快照，或另行把 coordinator 与 facade 的 prepare 契约整体演进为 `Future`；不能只让单个 participant 偷渡异步行为。

### 7.2 Change 与摘要

`SettingsTransferChange<T>` 至少保存：

- participant key；
- prepare 时观察到的本地值或可比较指纹；
- 准备好的最终写入值；
- `SettingsTransferSummaryItem`；
- 用于执行的类型安全 participant 引用。

执行时由 coordinator 使用该 participant 对准备好的最终值调用 `applyImport`。change 不内嵌任意可执行闭包，也不设计为可序列化对象；它只是一次导入会话中的短生命周期、类型化执行描述。

摘要不能只有一个全局 `count` 假设。participant 根据 change 返回安全摘要，至少支持：

- `merge`：例如“预设 Prompt：新增 2 项”；
- `replace`：例如“字号设置：替换”；
- `clear`：例如“自定义请求头：清空”。

摘要只包含 label、数量和动作，不包含 API Key、Header value、Prompt 全文或其他敏感 payload。

### 7.3 受控类型擦除

Catalog 需要统一遍历不同 `T`，因此 transfer 基础设施内部提供非泛型适配接口，例如 `AnySettingsTransferParticipant`。类型擦除只能存在于 participant adapter / catalog / coordinator 内部：

```text
SettingsTransferParticipant<List<PresetPrompt>>
                         ↓ 受控适配
AnySettingsTransferParticipant
                         ↓
SettingsTransferCatalog
```

业务 Controller、Settings presentation、Sync facade 与 Sync presentation 不直接执行 `dynamic` cast。所有 payload 类型转换必须由注册时已经绑定的 participant 完成。

### 7.4 通用策略基类

不要求所有设置模型或 Controller 继承统一基类。transfer 层提供两个主要复用策略：

```dart
abstract class ReplacingValueParticipant<T>
    implements SettingsTransferParticipant<T> { /* ... */ }

abstract class MergingCollectionParticipant<T>
    implements SettingsTransferParticipant<List<T>> { /* ... */ }
```

- `ReplacingValueParticipant<T>`：本地与传入值一致时 no-op，不同时整体替换；有效空值可以清空。
- `MergingCollectionParticipant<T>`：根据子类提供的等价/合并函数生成新增或更新集合；空集合默认 no-op。
- 服务商配置使用专用 participant，保留 ID 优先、等价键回退、模型名去重的既有规则。
- 模板提示词 participant 在生成 change 前继续执行模板编译校验。

这些基类减少 participant 样板代码，但不把存储类型、传输分组、安全等级和业务冲突策略塞进所有设置的公共父类。

### 7.5 Controller 基类评估

当前仓库已经有适用于 SQLite “全量加载 + 全量写入”实体的 `SettingsEntityController<T>`。自动重试、字号、Header 和输出处理等版本化 JSON 标量也存在相似 `build/save` 模式，未来可以独立评估一个窄的 `VersionedJsonSettingsController<T>`。

该持久化基类不是本设计的前置条件，也不应与 transfer 元数据耦合：

- transfer registry 必须能通过 reader/writer 闭包适配现有任意 Controller；
- 服务商等专用 Controller 继续独立；
- 设置页 Tab 偏好等非 Notifier、本地 UI 状态不被迫进入统一继承树；
- 本次实施若无明确必要，不顺带重构全部标量 Controller。

## 8. Catalog

`SettingsTransferCatalog` 是已注册 participant 的不可变集合，提供：

- 按 key 查找 participant；
- 按 group 取得有序 participant；
- 生成有内容的有序 group descriptors；
- 聚合 group / document 敏感等级；
- 生成确定顺序的 participant key 清单；
- 验证选中的 group ID；
- 为 Clipboard 与 Sync 生成相同摘要投影。

Catalog 创建时立即验证：

1. participant key 全局唯一且符合稳定 key 规则；
2. participant order 在分组内稳定且无冲突；
3. participant 只引用已定义分组；
4. label 非空；
5. sensitivity 已显式声明；
6. codec、reader、prepare 与 writer 均存在。

注册 participant 就是 opt-in。注册后不能单独关闭某个标准入口：当前分组导出、全局剪贴板导入和 Sync 都必须消费它。单项分享是额外调用方式，是否在业务 UI 提供按钮由具体 feature 决定。

生产 catalog 与 formatVersion schema 快照的一致性不属于运行时 constructor 校验；它由第 9.4 节和第 16.1 节的生产 catalog 契约测试负责。这样测试专用 catalog 可以注册 fake participant，同时仍执行 key 唯一、分组、顺序和声明完整性等运行时结构校验。

## 9. Canonical 交换格式

### 9.1 Document 结构

新格式使用统一 sections map：

```json
{
  "identifier": "shikiyuzu-oh-my-llm",
  "formatVersion": 9,
  "sections": {
    "autoRetrySettings": {
      "enabled": true
    },
    "customHeaders": {
      "headers": []
    }
  }
}
```

示例故意不包含空的合并型集合。服务商、预设和提示词没有可导出内容时，对应 section 必须缺失；`customHeaders.headers` 的空列表则是替换型 participant 的有效清空值。

`SettingsTransferDocument` 位于 Settings domain transfer 区域，是纯数据对象。它保存深度不可变、JSON-safe 的 section payload；只有统一 codec 和 coordinator 可以把原始 section 转成类型化 change。原始 map 不向 presentation 或具体 Controller 扩散。

顶层 codec 只负责：

- identifier；
- formatVersion；
- sections 容器结构；
- JSON-safe 值与确定性 key 顺序。

participant 负责自己的 section schema。group、label、order、sensitivity、摘要和冲突策略不写入 document，本机 catalog 是这些元数据的权威来源，避免远端伪造“普通数据”标签绕过敏感确认。

### 9.2 缺失、空值与 null

严格区分：

- section 不存在：本次没有传输该设置，绝不影响本地值。
- section 存在且 payload 为空：传输了一个有效空值，由 participant 策略解释。
- 未声明可空的 section 出现 `null`：整个 document 无效。
- 真正需要表达 nullable domain value 时，participant 使用明确对象结构，例如 `{ "value": null }`，不把顶层 section null 当作通用语义。

默认 presence 规则：

- 合并型集合只在有可导出内容时形成 section；空集合导入为 no-op。
- 替换型设置在所属 group 被选择时形成 section，包括默认值和有效空值。
- 自定义 Header、输出处理规则虽然内部含列表，但当前持久化行为是整体保存，因此按替换型聚合设置处理；空列表可以清空本地配置。
- 服务商、预设和提示词为空时不删除本地集合。

### 9.3 严格解码

一次导入按以下顺序完成，任一步失败都不执行写入：

1. identifier 匹配；
2. formatVersion 等于当前唯一支持版本；
3. sections 是合法对象；
4. 每个 section key 都能在 catalog 中找到；
5. 每个 payload 通过 participant decode 与领域校验；
6. 所有 participant 完成 `prepareImport`；
7. coordinator 生成不可变 `SettingsImportBatch`。

未知 key、非法 payload、重复/非法结构或任一领域校验失败都拒绝整个 document。不静默跳过未知设置，也不把部分解码成功描述为完整导入。

Sync 路径在上述第 4 步之后增加一项 transport-specific 校验：每个已知 section 必须属于本次请求 group，验证通过后才进入 participant decode。Clipboard 路径没有 requested groups 约束，但仍执行完整的通用解码和敏感确认。

### 9.4 版本门禁

迁移到 sections 结构时，Settings transfer format 从 v8 提升到 v9。v9 是新的唯一 canonical 版本；v8 和未来版本均明确返回 unsupported，不保留 v8/v9 双解码生产链。

Catalog 契约测试固定：

```text
formatVersion + 排序后的 participant key 集合 + canonical encode fixtures
```

每个 participant 必须有 canonical encode fixture，固定当前 section JSON 形状。增加/删除注册项或改变 canonical fixture 时，测试会要求显式更新生产 schema 快照；仓库规则要求该变化同时提升顶层 formatVersion。测试的作用是让 schema 漂移变成可见、可审查的改动，不能代替 code review 对“不得覆写同一版本快照”的检查。运行时入口不维护另一份字段 switch。

本设计不引入 participant 级 `schemaRevision`。当前兼容策略是任何 section schema 变化都可能使旧应用误读整个 document，因此统一提升顶层 formatVersion 并整体拒绝旧格式；再增加一个必须同步 bump、又不进入 wire 的版本号没有独立价值。将来若产品需要各 section 独立演进，必须另行设计带 section revision 的 wire envelope、支持范围和错误语义，不能在本设计中预埋半套版本机制。

## 10. 首批 Participant

首批注册当前已经参与设置传输的九类数据：

| Participant key | 分组 | 导入策略 | 敏感性 |
| --- | --- | --- | --- |
| `modelProviders` | 服务商 | 专用 ID / 等价键 / 模型合并 | 含凭据 |
| `presetPrompts` | 预设 | 内容去重合并 | 普通 |
| `memoryPrompts` | 提示词 | 内容去重合并 | 普通 |
| `templatePrompts` | 提示词 | 编译校验后内容去重合并 | 普通 |
| `fixedPromptSequences` | 提示词 | 内容去重合并 | 普通 |
| `customHeaders` | 网络 | 整体替换，可清空 | 含凭据 |
| `outputProcessing` | 输出处理 | 整体替换，可清空 | 普通 |
| `fontSizeSettings` | 其它 | 整体替换 | 普通 |
| `autoRetrySettings` | 其它 | 整体替换 | 普通 |

明确保持本地、不注册：

- `ChatDefaults`：最近模型和预设选择，含设备本地实体 ID 引用；
- 设置页当前 Tab；
- 媒体根目录；
- 媒体网格密度等设备布局偏好；
- 模型目录等可重新计算派生状态；
- 其他未经过显式产品决策的 Provider、SharedPreferences key 或 SQLite 数据。

## 11. 四条数据流

### 11.1 导出当前分组到剪贴板

```text
当前 Tab descriptor
  → transfer group
  → catalog 取得组内 participants
  → participant 读取最新本地值
  → shouldExport
  → encode
  → SettingsTransferDocument
  → 敏感导出确认
  → Clipboard
```

coordinator 先生成不可变 export batch，其中包含 document、摘要和聚合敏感等级。presentation 不读取 payload；若 batch 敏感，先展示“系统剪贴板可能被其他应用读取”的确认。presentation 必须把确认结果传回 export batch / coordinator，只有 application 边界接受确认后才返回可写入剪贴板的序列化文本；未确认时不得执行 `Clipboard.setData`。

没有任何 section 时提示当前分组没有可导出数据。Clipboard 平台调用留在 Settings presentation；coordinator 不导入 `package:flutter/services.dart`。

### 11.2 从剪贴板全局导入

```text
Clipboard text
  → 顶层格式解码
  → catalog 按 section key 路由
  → participant decode
  → 读取本地值
  → prepareImport
  → SettingsImportBatch
  → 通用摘要与敏感确认
  → revalidate
  → execute
```

当前 Tab 不参与解码或匹配。确认对话框遍历 `batch.summaryItems`，不按具体设置字段写 `if`。batch 含敏感 change 时显示统一警告和确认，但不显示具体 secret。

用户确认后执行已经准备好的 batch，不重新读取剪贴板，从而避免确认内容与实际导入内容不一致。

### 11.3 分享单条预设

coordinator 提供类型化单值导出入口：

```dart
exportValue<T>(
  SettingsTransferParticipant<T> participant,
  T value,
)
```

预设 UI 把单条 `PresetPrompt` 包装为只含该预设的列表，交给预设 participant 编码。它与整个预设分组使用相同 key、codec、formatVersion、安全规则和导入路径，不保留专门拼装 `SettingsExportData` 的旁路。

未来其他集合型设置需要单项分享时可以复用该入口，但 registry 不自动为所有 participant 生成单项分享按钮。

### 11.4 设备 Sync

```text
Settings catalog group projection
  → Sync 页面自动生成选择项
  → 加密请求稳定 group IDs
  → 服务端再次验证分组与敏感确认
  → coordinator.exportGroups
  → 结构化 SettingsTransferDocument
  → 加密响应
  → coordinator.prepareIncoming(requestedGroups)
  → SettingsImportBatch
  → 通用摘要确认
  → execute
```

Sync snapshot 直接嵌入 document 的结构化 map，不二次编码为 JSON 字符串。客户端敏感确认不是唯一安全门；服务端根据自己的 catalog 投影重新验证所选 group，未知 group 或缺失敏感确认时拒绝请求。

客户端收到响应后，coordinator 验证所有 section 都属于请求过的 groups。远端不能在普通分组请求中夹带服务商或 Header 等未确认数据。

## 12. Sync Facade 与协议

### 12.1 Facade 投影

`SettingsSyncFacade` 继续作为 Sync application 所有的 consumer port，由 Settings application 提供 Riverpod 实现。其职责改为投影 catalog，而不是重新枚举 Settings controller：

```dart
abstract interface class SettingsSyncFacade {
  List<SettingsSyncGroupDescriptor> get availableGroups;

  SettingsTransferDocument exportGroups(
    Set<SettingsSyncGroupId> groups,
  );

  SettingsSyncPreparedImport prepareIncoming(
    SettingsTransferDocument document, {
    required Set<SettingsSyncGroupId> requestedGroups,
  });
}
```

`SettingsSyncGroupDescriptor` 是 Sync port DTO，只包含稳定 ID、显示名称、顺序和聚合敏感性。Settings 实现按 group wire key 做机械投影，不维护字段 switch。

`SettingsSyncPreparedImport` 是只读、短生命周期的 port 抽象，暴露安全摘要、是否敏感和执行命令；Sync presentation 不读取具体 Settings participant 或原始 payload。

`prepareIncoming` 有意保持同步：它只消费已经解密并解码出的 document，以及 participant 通过同步 `readLocal` 暴露的已加载状态，不执行文件、数据库或网络异步首载。若该前提未来不再成立，必须把 coordinator、Clipboard preparation 与 Sync facade 的 prepare 链路一起改为异步，不能只修改 facade 的一个签名。

它应直接包装一次性的 Settings import batch，并通过 port-owned DTO 返回执行结果：

```dart
abstract interface class SettingsSyncPreparedImport {
  List<SettingsSyncSummaryItem> get summaries;
  bool get containsSensitive;

  Future<SettingsSyncImportExecutionResult> execute({
    required bool confirmedSensitive,
  });
}
```

Sync 不保存不透明字符串 token，也不通过全局可变缓存回查 batch。敏感 batch 在 `confirmedSensitive == false` 时必须于 Settings application 边界拒绝且零写入，不能只依赖 Sync 按钮状态。`execute()` 只能成功发起一次；重复调用返回明确的 already-consumed 结果。Settings 实现负责把内部 `SettingsImportExecutionResult` 投影为 Sync port 结果，Sync presentation 不依赖 Settings application 内部类型。

### 12.2 选择与 wire 表达

当前四布尔 `SettingsSyncSelection` 与 `SyncCategory` enum 由稳定 group ID 集合替代。Sync UI 遍历 `availableGroups` 生成复选框、全选和敏感提示。新增 participant 进入现有 group 时不改变 wire 请求。

Sync 协议从 v3 提升到 v4，原因是：

- 分类从当前四类语义调整为六个稳定分组；
- 请求选择改为稳定 group IDs；
- snapshot 使用新的 Settings transfer v9 document。

旧 Sync 版本和未来版本都明确拒绝并提示升级，不新增匿名或降级兼容入口。

## 13. 导入一致性与并发

导入分为：

```text
Decode → Prepare → Confirm → Revalidate → Execute
```

### 13.1 Prepare

- 全部 section 解码、领域校验和冲突计算完成后才产生 batch。
- prepare 阶段不调用写入 Controller / Repository。
- 无实际 change 时返回 `noChanges`，不弹空确认框。
- batch 保存确认所需的安全摘要和 revalidate 所需的本地比较信息。

### 13.2 Revalidate

用户确认后，coordinator 重新读取 batch 涉及的本地值：

- 本地未变化：执行原 batch；
- 本地变化但重新 prepare 后的最终 change 与摘要完全一致：允许继续；
- 本地变化导致 change、动作或摘要变化：返回 `stalePreview`，不写入，重新生成确认内容。

coordinator 对导入执行使用单实例串行锁，避免剪贴板和 Sync 两个批次交错写入。batch 是一次性、短生命周期对象，不持久化到 SQLite 或 SharedPreferences。

Clipboard 使用的内部 batch 执行入口同样必须接收 `confirmedSensitive`。敏感 batch 未确认时在 application 边界返回安全失败并保持零写入；普通 batch 可以传入 `false` 并正常执行。

### 13.3 存储边界与部分失败

SQLite 与 SharedPreferences 无法共享原子事务，本设计不宣称跨 participant 全局原子：

- SQLite participant 在自己的数据库事务或 repository 原子边界内完成一次写入；
- SharedPreferences participant 保存完整版本化对象并等待真实 Future ACK；
- 单 participant 失败时不得更新其 Riverpod state 为成功状态；
- executor 按 catalog 的确定性顺序串行执行；
- 不实现无法保证成功的通用补偿回滚。

若现有 Controller 的导入方法在持久化 Future 完成前更新 state，实施时必须为该 participant 增加“持久化成功后再发布 state”的窄写入路径，或对该导入方法做同语义的顺序修正。该要求尤其需要覆盖服务商合并写入，但不授权借机重构整个 Controller 体系。

执行结果使用 sealed 类型：

```dart
sealed class SettingsImportExecutionResult {}

final class SettingsImportSuccess ...
final class SettingsImportStalePreview ...
final class SettingsImportFailure ...
final class SettingsImportPartialFailure ...
```

`SettingsImportPartialFailure` 明确包含：

- 已成功 participant 的安全摘要；
- 失败 participant 的 label；
- 尚未执行的 participant；
- 可安全显示的错误原因。

UI 必须提示“部分配置已导入”，不能笼统显示“导入失败”。各 participant 的 merge / replace 操作应保持幂等；用户重试时，已成功部分在下一次 prepare 中变成 no-op，只剩未完成变更。

## 14. 安全规则

1. `credentialBearing` 由 participant 声明，group / document 敏感性由 catalog 聚合。
2. 服务商 API Key 与自定义 Header value 永远不进入摘要或错误消息。
3. 敏感分组导出到剪贴板前必须确认，并明确系统剪贴板可能被其他应用读取。
4. 从剪贴板导入敏感 document 时必须确认。
5. Sync 客户端请求敏感 group 前必须确认；服务端必须独立复核该确认。
6. Sync response 不能包含未请求 group。
7. 日志不得记录完整 document、Clipboard 原文、API Key、Header value 或解码后的 secret。
8. 未知 section 不能通过“忽略即可”绕过敏感策略；当前格式整包拒绝。
9. participant label、group 和 sensitivity 以本机 catalog 为准，不信任远端元数据。
10. 敏感 export 的序列化文本与敏感 import 的执行命令都必须在 application 边界校验确认参数，不能只依赖 presentation 控件禁用状态。

## 15. 错误分类与 UI

准备阶段至少区分：

- 非本应用数据；
- 不支持的 Settings transfer 版本；
- 顶层结构损坏；
- 未知 section；
- participant payload 无效；
- 领域校验失败；
- Sync group 未知；
- Sync response 包含未请求 section；
- 敏感确认缺失；
- 没有实际变化；
- stale preview。

Clipboard 与 Sync 可以使用不同标题和上下文说明，但摘要列表必须复用同一个 presentation 组件，数据来自 `SettingsTransferSummaryItem`。通用组件根据 summary action 渲染“新增 N 项 / 替换 / 清空”，不读取具体 domain 类型。

错误文案不展示 payload 原文。执行失败与部分失败必须保留确认对话框或显示可继续处理的 inline / bubble 状态，不把错误误报为成功。

## 16. 测试策略

所有新增测试名称使用简体中文。实现阶段按仓库规则建立 red / green 证据并写入 `logs/`。

### 16.1 Catalog 契约测试

- key 唯一且顺序稳定；
- group、label、order、sensitivity 完整；
- 生产 participant key 集合与 formatVersion schema 快照一致；
- participant canonical encode fixture 与当前 formatVersion 一致；
- 每个 participant 都存在 codec、reader、prepare 和 writer；
- 每个 participant 使用类型化 fixture 完成 encode/decode round-trip；
- group sensitivity 由 participant 自动聚合；
- 未注册设置不会出现在 catalog。

### 16.2 Coordinator 通用测试

- 按单 group、多 group 和单 participant 值导出；
- section 缺失与空 section 语义不同；
- 全局 Clipboard 导入不依赖当前 Tab；
- 未知 key 或任一非法 section 在写入前拒绝整包；
- 敏感等级与摘要从 participant 自动聚合；
- Sync 拒绝未请求 group 的 section；
- prepare 阶段零写入；
- stale preview 零写入并要求重新确认；
- 串行锁阻止两个导入批次交错；
- success、failure 与 partial failure 精确报告。

### 16.3 Participant 专项测试

- 服务商 ID / 等价键 / modelName 合并规则；
- 预设、记忆和固定顺序提示词的内容等价去重；
- 模板提示词变量、条件语言编译校验与内容去重；
- 字号和自动重试整体替换；
- Header 与输出规则的非空替换和空值清空；
- 相同本地值生成 no-op；
- participant 写入 Future 完成后才报告成功。

### 16.4 入口测试

- 敏感 Clipboard 导出必须确认，取消时不写剪贴板；
- 敏感 Clipboard export batch 未确认时不返回可外发文本；
- Clipboard 导入自动识别跨 group document；
- 单条预设生成标准 v9 document；
- Settings 当前 Tab 只控制导出 group；
- Sync 页面完全由 facade group descriptors 生成；
- Sync 全选使用 facade 提供的全部 group；
- 客户端与服务端都验证敏感确认；
- 敏感 Clipboard / Sync import batch 未确认时 application 边界零写入；
- Sync snapshot 使用结构化 document，不出现二次 JSON；
- Sync v3、Settings v8、未来版本、未知 group 与未请求 section 明确拒绝。

### 16.5 自动适配证明

测试使用测试专用 catalog 注册一个生产代码中不存在的 fake participant，不修改 coordinator、Clipboard adapter、Sync facade 或摘要组件。该 catalog 不与生产 schema 快照比较；若复用 schema contract helper，则传入包含 fake key 和 canonical fixture 的测试专用快照。随后验证 fake participant 自动进入：

- 所属 group 导出；
- Clipboard 导入准备与摘要；
- group 敏感性聚合；
- Sync group export；
- 最终 import execute。

该测试是“显式注册一次，所有标准入口自动适配”的直接架构契约。

### 16.6 Composition 与架构门禁

- 使用真实 Provider composition 验证至少一个 SQLite 集合 participant 与一个 SharedPreferences 替换型 participant 的跨容器导出/导入；
- Settings domain/application 不导入 Clipboard；
- participant 不导入 Sync presentation/data；
- Sync presentation 不引用九个具体 Settings 字段；
- import-boundary gate 无新增宽泛 allowlist；
- 最终运行 targeted tests、`flutter analyze`、`dart run tool/check_import_boundaries.dart` 和按仓库规则重定向的全量测试。

## 17. 迁移策略

最终生产路径必须一次性收敛到 registry，不能长期保留两套事实源：

1. 建立 transfer domain primitives、participant、catalog、document codec 与 coordinator。
2. 使用现有 controller / repository 和比较逻辑注册九个 participant。
3. 将设置页当前分组导出与全局 Clipboard 导入切到 coordinator。
4. 将单条预设复制切到类型化单值导出。
5. 将两个确认对话框切到通用 summary projection。
6. 将 Sync facade、Sync 页面和 v4 protocol 切到 catalog group projection。
7. 删除旧字段式 workflow、deduplicator、executor、四布尔 selection 与手写摘要。
8. 删除不再使用的 `SettingsExportData` 字段聚合，保留新的 canonical document。

实施期间可以用短生命周期 adapter 保持任务可独立验证，但 adapter 必须注明退出任务和保护测试；最终完成状态不得同时存在旧字段聚合和新 registry 两条生产链。

此次迁移只改变设置交换格式和 Sync wire 协议，不改变现有 SQLite schema、SharedPreferences key 或各设置的本地 JSON schema。

## 18. 完成标准

1. 九个 participant 各自只有一次生产注册。
2. Clipboard、Sync facade 和确认摘要中不存在按九种具体字段维护的 switch / if 清单。
3. 当前分组 Clipboard 导出继续可用。
4. Clipboard 导入无需切换 Tab，可准备跨 group document。
5. 单条预设复制仍由标准导入链识别。
6. 敏感 Clipboard 导出和导入均要求确认。
7. Sync 页面展示 catalog 投影出的六个稳定 group。
8. group 敏感性由 participant 自动聚合；当前服务商与网络为敏感分组，其他分组按成员决定。
9. 输出处理等 participant 自动出现在确认摘要，不需修改对话框。
10. 未请求 Sync group、未知 section、退出支持的旧版本、未来版本和非法 payload 全部在写入前拒绝。
11. 替换型空值可以清空 Header / 输出规则，合并型空集合不删除本地实体。
12. stale preview 不写入；partial failure 明确报告已完成与未完成项。
13. fake participant 自动适配契约测试通过。
14. 不引入所有设置统一基类、运行时反射、代码生成或新的永久兼容层。
15. 不修改 SQLite schema、现有本地设置格式或无关 feature 行为。

## 19. 停止条件

实施中出现以下任一情况时，应停止当前任务并回到设计或实施计划修订：

- participant 无法在不导入 presentation / Sync 具体实现的情况下表达读写；
- 新 document 的原始 payload map 扩散到 Controller 或 presentation；
- 为了渐进迁移需要长期保留两套生产 codec / executor；
- 某 participant 的“空值、合并、替换、清空”语义无法明确；
- Sync v4 无法在服务端独立验证敏感 group；
- 混合存储失败被 UI 误报为整批回滚或整批成功；
- 新增宽泛 import-boundary allowlist 才能通过架构门禁；
- 实施范围开始包含无关 Controller、Repository 或持久化重构。

本设计已通过书面复核，下一步是编写详细实施计划；实施计划再次明确任务边界、测试证据和提交顺序后，才开始生产代码迁移。
