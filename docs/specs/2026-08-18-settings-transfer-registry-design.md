# Settings Transfer v9 稳定规范

**状态**：已实施

**适用范围**：剪贴板导入导出、单条预设分享、Sync v4 设置同步

**兼容边界**：本规范不改变 SQLite schema、本地 SharedPreferences 格式或 Sync v4 envelope

## 1. 所有权与边界

Settings feature 独占设置传输语义：可传输白名单、section codec、冲突策略、敏感性、安全摘要和写入闭包都在固定 section 注册点定义。剪贴板与 Sync 只消费 `SettingsTransferCoordinator`，不得再维护字段清单或第二套 codec。

生产路径由三个构件组成：

- `SettingsTransferSection`：用 `replacing<T>`、`merging<T>` 或 `custom<T>` 在构造时绑定 typed reader、codec、prepare 和 writer。
- `SettingsTransferCoordinator`：校验和排序 section，执行导出、解码、准备、重校验与串行写入。
- `RiverpodSettingsSyncFacade`：把 Coordinator 的稳定 group 投影为 Sync-owned port 与结果 DTO；它不读取具体 Settings controller。

section 是固定应用能力，不是 runtime plugin。生产中只有九项注册，不提供动态注册、反射、代码生成、catalog、participant hierarchy 或第二套版本系统。新增或删除生产 section 是显式 wire-format 变更，必须评估并更新顶层 format version。

## 2. 固定分组与 section

Coordinator 使用 `group.order → section.order → key` 排序；key 全局唯一且匹配 `[a-z][A-Za-z0-9]*`。label 不得为空。远端不能覆盖 group、label、order 或 sensitivity。

| 顺序 | Group / wire ID | Section key | Label | 策略 | 敏感性 |
|---:|---|---|---|---|---|
| 1 | `providers` | `modelProviders` | 服务商 | 专用合并 | 凭据 |
| 2 | `presets` | `presetPrompts` | 预设提示词 | 内容去重追加 | 普通 |
| 3 | `prompts` | `memoryPrompts` | 记忆提示词 | 内容去重追加 | 普通 |
| 4 | `prompts` | `templatePrompts` | 模板提示词 | 内容去重追加 + 编译校验 | 普通 |
| 5 | `prompts` | `fixedPromptSequences` | 固定提示词序列 | 内容去重追加 | 普通 |
| 6 | `network` | `customHeaders` | 自定义请求头 | 整体替换/清空 | 凭据 |
| 7 | `outputProcessing` | `outputProcessing` | 输出处理 | 整体替换/清空 | 普通 |
| 8 | `other` | `fontSizeSettings` | 正文字号设置 | 整体替换 | 普通 |
| 9 | `other` | `autoRetrySettings` | 自动重试设置 | 整体替换 | 普通 |

六个 group 顺序固定为 `providers`、`presets`、`prompts`、`network`、`outputProcessing`、`other`。group 敏感性由其中 section 的最高敏感等级聚合，因此 `providers` 和 `network` 当前为凭据分组。

下列本地设置不进入传输文档：

- 聊天默认值与最近选择；
- Settings 最近标签页；
- 媒体根目录与媒体网格密度；
- 旧的扁平模型配置键；
- 其他未列入上表的本地偏好。

## 3. Wire document

顶层 JSON 固定为：

```json
{
  "identifier": "oh-my-llm.settings-transfer",
  "formatVersion": 9,
  "sections": {
    "presetPrompts": []
  }
}
```

规则：

- 只接受 identifier 完全匹配、整数 `formatVersion == 9`、JSON object `sections`，且无未知顶层字段的文档。
- v8、未来版本和 malformed payload 必须显式失败，不做静默 fallback。
- codec 只校验通用 JSON 结构；Coordinator 再拒绝未知 section、未请求 Sync group 和领域 payload 错误。
- map key 必须是字符串，值必须是 JSON-safe；文档构造和 `toJson` 均保持防御性不可变。
- section 缺失表示未传输；存在的空集合或空对象是有效 payload，由该 section 解释为 no-op、替换或清空。
- 合并型空集合在导出时省略；`customHeaders` 与 `outputProcessing` 的空对象仍导出，以保留显式清空语义。
- canonical v9 JSON 形状由生产 fixture snapshot 锁定。字段或 canonical encoding 变化不得在仍声明 v9 时静默落地。

## 4. 领域冲突规则

### 4.1 服务商

服务商继续使用现有专用 merger：优先保留本地稳定 ID，按凭据等价键回退匹配，并按模型名去重合并。payload 必须显式包含合法 `apiProtocol`；缺失协议不得猜测默认值。

### 4.2 提示词集合

四类提示词只写入远端新增内容：

- 预设按消息的 title、role、placement 和 content 序列判等；ID、名称、更新时间和 enabled 不参与内容等价。
- 记忆提示词按 content 判等。
- 模板提示词按 content 与 variables 的有序内容判等，并在 prepare 前通过模板编译校验。
- 固定序列按 steps 的 title 与 content 序列判等；ID、名称和更新时间不参与内容等价。

同一文档内重复的新内容只追加一次。集合 writer 接收需要新增的项目，不覆盖本地集合。

### 4.3 替换设置

Header、输出规则、字号与自动重试按完整值判等。非等价值生成 replace；Header 或输出规则的有效空对象生成 clear。摘要只暴露 label、动作和安全计数，绝不包含 API key、Header value、正则正文或替换正文。

## 5. 导出契约

`exportGroups` 在调用时读取最新本地状态，按固定顺序编码所选 group。没有任何可导出 section 时返回 `SettingsExportNoContent`；否则返回尚未暴露文本的 `SettingsExportBatch`。

包含凭据 section 的 batch 必须先获得明确确认，才能通过 `exposeJson` 生成可写入剪贴板或外部系统的完整 JSON。取消确认不得触碰系统剪贴板。

`exportPreset` 是单条预设分享的唯一入口。它仍使用 `presetPrompts` 的同一 codec、v9 document 与导入路径；Settings presentation 不持有 section key，也不做泛型转换。

## 6. 导入四阶段

导入严格分为四阶段：

1. **Decode**：验证顶层文档、所有 section key、allowed groups 和全部 payload。任一项失败，整个文档零写入。
2. **Prepare**：每个 section 同步读取当前本地值，计算 typed change、安全摘要和 fingerprint。prepare 不执行数据库、偏好或网络写入。
3. **Confirm**：UI 展示安全摘要。凭据 batch 在未确认时不能执行，且未确认不会消费 batch。
4. **Execute**：进入 Coordinator 的全局串行队列；写入前逐项重新 prepare。若摘要或 fingerprint 改变，返回 refreshed stale preview，当前批次零写入并要求重新确认。

`readLocal` 必须同步返回已经加载的当前状态。若未来设置只能异步首载，应整体演进 Coordinator、Clipboard 和 Sync prepare 契约，不能让单个 section 偷渡异步读取。

batch 是一次性的：成功开始执行后再次调用返回 already-consumed。两个独立 batch 的 writer 临界区不得重叠。

## 7. 写入失败语义

SQLite 与 SharedPreferences 不共享全局事务，因此不宣称跨 section 原子：

- writer 必须等待真实持久化 ACK 后才报告完成；
- 第一项失败返回 failure，后续项不执行；
- 中途失败返回 completed、failed label、not-attempted 的安全摘要；
- 原始异常文本不得进入 UI 或 Sync 响应，统一返回稳定安全原因；
- 用户重新导入同一文档时，已成功的幂等变化应成为 no-op，只执行剩余项。

## 8. Sync v4 约束

Sync payload 直接嵌入结构化 v9 `SettingsTransferDocument`，不得二次编码为 JSON 字符串。Sync 使用六个稳定 group ID，并从 `coordinator.groups` 投影 label、order 和 sensitivity。

客户端确认不是唯一安全门。接收端按本机固定 section 重新验证：

- group ID 必须已知；
- document 中每个 section 必须属于本次 requested groups；
- 未请求 section 在 decode 前拒绝；
- 两端都根据本机敏感性要求确认；
- 未知 section、非法 payload、v8 或未来版本均拒绝。

Sync port 和结果 DTO 归 Sync application 所有；Settings 提供实现。Sync presentation 不依赖 Settings section、controller 或原始 payload。

## 9. 测试所有权

- `settings_transfer_document_codec_test.dart`：v9 顶层格式、版本、malformed、JSON-safe 和防御性不可变。
- `settings_transfer_section_test.dart`：metadata 校验以及 replacing/merging 构造器的局部策略。
- `settings_transfer_coordinator_test.dart`：allowed groups、零写入、敏感确认、stale、串行执行、failure、partial failure 和一次性 batch。
- 生产契约测试：固定九 key、六 group、敏感性、全量 typed fixture 跨容器往返、secret-safe canonical snapshot、本地专属设置排除、专用冲突规则与领域校验。
- SettingsScreen 测试：当前 Tab 导出、全局导入、敏感确认、空 replacement 和单预设导出。
- Sync 测试：结构化 v9 document、稳定 group ID、双端敏感确认、未请求 section 拒绝，以及 partial failure 重试。

测试不再证明 runtime 扩展性、typed lookup、catalog 隔离或任意 participant 注册；这些不是产品契约。
