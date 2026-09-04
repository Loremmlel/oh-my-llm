# Token 用量与服务商设置轻量实施计划

**状态：** PR 1 已合入，PR 2 实施中；已按 Ponytail 原则收缩。

**目标：**

- 服务商 API Key 输入框允许直接查看、复制和粘贴。
- 从 API 拉取模型时，可逐模型标记“支持深度思考”。
- 助手消息显示服务商返回的 Token 用量，输入区显示当前会话缓存命中率。

**当前基线：** 以实施时最新 `master` 为准。仓库已经有三协议
`ChatGenerationUsage` 解析、generation lifecycle、会话全量保存事务和后台
writer；本计划只补齐缺失数据，不重建这些机制。

## 1. Ponytail 取舍

原计划用独立 settlement 表保存已删除消息的历史统计，由此又需要专用
repository 接口、冲突异常、后台 command/ACK、load join、summary 投影和大量
幂等测试。这些复杂度只为一个尚无计费或审计要求的 UI 指标服务，不值得。

本计划改为：

- 两个 PR，而不是三个：两个很小的 Settings 表单改动放在同一个 PR；带 schema
  迁移的 Chat 改动单独审查。
- Token 用量直接属于生成它的 assistant message，以一个 nullable JSON 列持久化。
- 会话命中率从现存 `messageNodes` 即时求和，不保存第二份 summary。
- 删除消息或分支后，相关用量随消息删除，命中率随之重算；删除会话自然删除全部
  用量。这符合“会话当前保留内容的统计”直觉。
- 复用现有 `saveConversationDurable()`、SQLite 会话事务和后台 writer，不增加
  `UsageRepository`、settlement API、worker command、receipt 索引或冲突类型。
- 复用现有 `ChatGenerationUsage`，不为相同数据再造 `ChatTokenUsage`。
- 数字格式化留在两个使用它的 widget 内，不创建只有一两个函数的 formatter module。
- 测试补在现有 owner 的测试文件中；不建立协议 × lifecycle × UI 的重复矩阵。
- 本文件只记录行为、最小改动和验证，不复制逐次 `git add`、commit、PR body、
  Sourcery 和 RED/GREEN 命令脚手架；这些统一遵循 `AGENTS.md`。

只有出现以下真实需求时才重新设计独立 usage ledger：删除消息后仍需审计、费用结算、
按模型/服务商分析，或需要记录自动重试的每个 attempt。届时它应作为独立功能，而不是
这次 UI 展示的预留扩展点。

## 2. 产品契约

### 2.1 API Key

- 只修改新增/编辑服务商对话框中的 API Key 字段。
- 明文显示，使用系统原生选择、复制和粘贴。
- 使用 `TextInputType.visiblePassword`，并设置 `autocorrect: false`、
  `enableSuggestions: false`。
- 不增加显隐按钮。
- 服务商列表继续掩码；存储、导入导出、Sync、自定义 Header 和日志脱敏不变。

### 2.2 拉取模型时设置深度思考能力

- 每个拉取结果行维护自己的 `supportsReasoning`，默认 `false`。
- 只有新模型被选中时复选框可操作；取消选择不清空先前值。
- 已存在模型的选择框、显示名称和能力复选框全部禁用，且不参与提交。
- 手工/拉取模式切换继续通过现有 `Visibility(maintainState: true)` 保留状态。
- `ModelBatchFormData` 携带 `supportsReasoning`，Settings 保存时原样写入
  `LlmProviderModelConfig`；不按模型名、host 或接口响应猜测能力，也不更新已有模型。

### 2.3 消息 Token 行

- 仅在非 streaming 的 assistant message 有任一会展示的用量字段时显示；只有
  `reasoningTokens` 时不生成空白行。
- 位于 `finishReason` 后、消息版本切换器前，使用可换行的轻量文本：
  `输入 4,000 · 缓存命中 1,500 · 缓存写入 800 · 输出 900`。
- `null` 字段不显示，服务商明确返回的 `0` 显示为 `0`。
- 数量使用精确整数和千位分隔，不使用 K/M 缩写。
- 不显示独立 reasoning token，不增加展开面板、Chip 或交互。

### 2.4 当前会话缓存命中率

- 对现存 `messageNodes` 中的 assistant usage 求和，不只扫描当前选中分支，因此手动
  重试和编辑产生的仍保留分支都会计入。
- 只纳入 `inputTokens != null`、`cachedInputTokens != null`、
  `inputTokens > 0` 且 `cachedInputTokens <= inputTokens` 的消息；不可能的 pair
  按未知值忽略，不把异常比例截断成 100%。
- 公式为 `Σ cachedInputTokens / Σ inputTokens × 100%`，不是逐消息百分比平均。
- 展开输入区在服务商/模型行后显示
  `当前会话缓存命中率：37.5%`；没有有效 pair 时显示
  `当前会话缓存命中率：暂无数据`；折叠后隐藏。
- 命中率保留一位小数。消息或分支被删除后立即按剩余消息重算。

### 2.5 用量来源与 attempt 语义

- 只使用三协议实际返回的 usage；不做 tokenizer 或字符数估算，也不承诺与账单一致。
- 同一 attempt 的分散 usage snapshot 以“新事件的非 null 值覆盖旧值”合并，显式
  `0` 不得丢失。
- 自动重试时丢弃前序 attempt 的 usage，只把最终 attempt 的 usage 写到 assistant
  message。
- 正常完成、空回复、异常 finish reason、最终错误或用户停止，只要最终 attempt
  收到 usage，就随终态消息保存。
- Responses `response.failed` envelope 携带的 usage 先合并到当前 attempt，
  再进入失败终态。
- preparing 或 retry waiting 阶段停止时没有当前 attempt usage，不写用量。

## 3. 最小数据设计

### 3.1 复用并下移 `ChatGenerationUsage`

把现有 `ChatGenerationUsage` 从 application port 移到 chat domain（名称不变），供
协议 parser、generation run 和 `ChatMessage` 共用。保留现有字段与 `merge()`：

```dart
final int? inputTokens;
final int? outputTokens;
final int? reasoningTokens;
final int? cachedInputTokens;
final int? cacheWriteInputTokens;
```

只新增当前缺失的 `cacheWriteInputTokens`、`hasAnyValue`、`toJson/fromJson`。
`reasoningTokens` 继续保留现有协议信息，但本次不展示。外部协议和持久化 JSON 中的
负数或非 int 字段按未知值处理；全字段未知时 usage 为 `null`。

`ChatMessage` 增加：

```dart
final ChatGenerationUsage? tokenUsage;
```

它进入 constructor、`copyWith`、`Equatable.props` 和 JSON 编解码。因为
`ChatConversation.toJson()` 已经是后台 writer 的传输格式，所以无需新增 writer 协议。

### 3.2 SQLite v15

在 `messages` 表增加一个 nullable 列：

```sql
token_usage_json TEXT
```

- fresh schema 直接包含该列。
- v14→v15 只执行 `ALTER TABLE messages ADD COLUMN token_usage_json TEXT` 并更新
  `user_version`，不建新表或索引。
- v13 仍必须先执行已发布的 v13→v14 收藏迁移，再继续到 v15；不得删除现有迁移、
  fixture 或数据保留测试。
- `chat_sql_codec.dart` 在现有 message row 编解码中读写 JSON；
  `SqliteChatConversationRepository` 的既有全量保存事务保持唯一写入路径。

### 3.3 派生命中率

在 `ChatConversation` 提供只读 getter（名称可按现有风格调整）：

```dart
double? get cacheHitRate;
```

getter 扫描 `messageNodes`，过滤第 2.4 节定义的有效 pair 后求加权比例。没有有效
pair 时返回 `null`。不增加 `ChatTokenUsageSummary`，不把累计值写入 JSON 或 SQLite。

## 4. 数据流

```text
三协议 parser
  -> ChatGenerationChunk.usage
  -> ChatGenerationRun 当前 attempt accumulator
  -> ChatAttemptSnapshot / ChatPartialSnapshot
  -> controller 把最终 attempt usage 写入终态 assistant message
  -> 现有 saveConversationDurable()
  -> 现有 background writer + SQLite 会话事务
  -> ChatMessageBubble 显示消息用量
  -> ChatConversation.cacheHitRate 派生会话命中率
```

实现约束：

- usage 不进入 300ms `ChatStreamingReply`，UI 只在终态更新。
- `ChatGenerationRun` 收到 retry 决策时立即清空 accumulator；下一 attempt 开始时再做
  防御性清空。
- controller 内用一个私有 helper 把 usage 写入指定 assistant node；不把它升级成
  repository interface。
- 终态消息挂好 usage 后再走现有 durable save。既有事务已经同时保存消息正文和
  `token_usage_json`，无需额外原子结算机制。

## 5. PR 1：服务商表单小改进

**分支：** `feat/settings-provider-form-ux`

**标题：** `feat(settings): 改进服务商凭据与模型拉取表单`

### 实现

1. 在 `model_provider_form_dialog.dart` 调整唯一 API Key `TextFormField` 的四个输入属性。
2. 在 `model_fetch_section.dart` 给 `ModelSelectionEntry` 增加 mutable
   `supportsReasoning = false`，在每个新模型行增加复选框，并统一禁用已有模型行。
3. 在 `model_config_form_dialog.dart`：
   - submit-ready 与提交都过滤 `selected && !alreadyExists`；
   - `ModelBatchFormData` 增加 required `supportsReasoning`；
   - 提交时透传每行能力值。
4. 在 `settings_screen.dart` 删除批量新增路径中的 `supportsReasoning: false` 硬编码，
   改用 form data。

### 最小测试

只扩展现有测试文件：

- `model_provider_form_dialog_test.dart`：按现有 key 断言明文、键盘类型和建议设置。
- `model_config_form_dialog_test.dart`：一个用例覆盖两个新模型能力值独立、取消/恢复
  选择后状态保留、已有模型行禁用且不提交。
- `settings_screen_models_and_prompts_cases.dart`：提交后从 typed repository 读取两个
  模型，断言 `supportsReasoning` 分别为 `false/true`。

不新增 test helper，不读取 raw SharedPreferences，不为每个 widget 属性拆单独用例。

## 6. PR 2：消息 Token 用量与会话命中率

**分支：** `feat/chat-token-usage`

**标题：** `feat(chat): 展示消息 Token 用量与会话缓存命中率`

### 6.1 补齐协议 usage

- 将 `ChatGenerationUsage` 下移到 domain，并更新现有引用；不创建兼容 alias。
- Chat Completions 请求增加 `stream_options: {'include_usage': true}`；parser 在检查
  `choices` 前读取顶层 usage，使 `choices: []` 的 usage-only chunk 也能产出数据。
- Chat Completions 遇到明确提及 `stream_options` / `include_usage` 不受
  支持的 400/422 时，移除该字段并仅重试一次；其他错误不降级。
- Chat Completions / Responses 读取 cache-write 字段（存在时保留显式 `0`）。
- Anthropic 读取 `cache_creation_input_tokens`，并将
  `inputTokens = input + cache read + cache creation`；cache read/write 字段仍保留原值。
- 每个 parser 只接受非负 int；全字段无效时返回 `null`。

### 6.2 随消息持久化

- 给 `ChatMessage` 增加 `tokenUsage` 并完成 JSON round-trip。
- schema 升到 v15，在 message row codec 和 repository load 中读写
  `token_usage_json`。
- 保留 v13→v14，追加 v14→v15；fresh、v13 和 v14 三条路径最终都得到 v15。
- 不修改 `ChatConversationRepository`、`BackgroundChatConversationRepository`、
  `chat_writer_entry_point.dart` 或通用 worker command。

### 6.3 只保存最终 attempt

- `ChatGenerationRun` 合并当前 attempt usage，并把它加入 attempt/partial snapshot。
- retry 前清空；stop 只携带当前 attempt 已收到的值。
- controller 在 success、output-rule failure、retry give-up、最终 error 和 stop 的既有
  终态路径中，把 snapshot usage 写入同一 assistant node，再调用现有 durable save。
- 自动重试的 intermediate save 不挂 usage。

### 6.4 展示

- `ChatMessageBubble` 在现有 finish reason 和 version navigator 之间生成已知字段文本，
  用 `Wrap` 防止窄宽溢出；分隔点与后一字段绑定换行，千位分隔使用文件内私有 helper。
- `ChatConversation.cacheHitRate` 直接派生比例。
- `ChatWorkspaceComposerReadModel/State` 只增加一个 `double? cacheHitRate` 并透传。
- `ChatComposerCard` 在 provider/model row 后显示一行；格式化使用文件内私有 helper，
  折叠态不渲染。

### 最小测试

优先扩展现有 owner 测试，不建立新套件：

1. generation client contract：merge 保留旧值且显式 `0` 覆盖；JSON round-trip。
2. 三协议 parser/client：各保留一条原生映射；Chat 额外验证 request flag 和
   usage-only chunk；Anthropic 验证输入总计。
3. database migration：fresh v15、v14→v15、v13→v14→v15，并确认旧聊天/收藏数据
   保留。现有非法旧版/未来版测试继续通过。
4. SQLite repository：含 usage 的 assistant save/load round-trip；保存删掉该消息后
   usage 也消失。后台 writer 只复用现有 ACK 测试，不复制一套 usage 专项生命周期测试。
5. generation run/controller：一条用例覆盖 snapshot merge 与 retry reset；一条覆盖
   final success/stop 写入。既有错误/重试行为测试继续作为回归。
6. bubble/composer：每个 widget 各一个参数化用例，覆盖顺序、null、显式 `0`、窄宽、
   暂无数据、37.5% 和折叠隐藏；不另测私有 formatter 实现。

## 7. 统一验证

所有命令按 `AGENTS.md` 使用 PowerShell 7、写入 `logs/` 并设置工具级 timeout。
每个 PR 先跑本节列出的定向文件，再串行运行完整门禁。

### PR 1 定向

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-provider-form.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/settings-provider-form.log
flutter test test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-model-fetch.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/settings-model-fetch.log
flutter test test/features/settings/presentation/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-screen.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/settings-screen.log
```

### PR 2 定向

依次运行被修改的现有 contract/parser、migration、repository、generation、bubble、
composer 和 workspace 测试入口。每个命令沿用上面的日志模式；只在失败时从日志查询
详情，不重复建立 RED/GREEN 日志矩阵。

### 每个 PR 的完整门禁

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/import-boundaries.log; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 150 logs/import-boundaries.log
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/analyze.log
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
git diff --check master...HEAD
git diff --stat master...HEAD
git status --short
```

提交前对所有改动 Dart 文件执行 `dart format`，暂存后再次用
`dart format --output=none --set-exit-if-changed` 检查。PR 标题、六段正文、版本 bump、
scope audit 和 Sourcery 处理遵循 `AGENTS.md`，不在此重复。

## 8. 完成定义

### PR 1

- API Key 明文可复制粘贴，其他秘密边界零行为变化。
- 拉取结果逐模型保存 reasoning 能力；已有模型不编辑、不提交。
- 三个现有 Settings 测试入口、静态门禁和全量测试通过。

### PR 2

- 三协议用现有统一类型提供输入、缓存命中、缓存写入和输出用量；Chat 支持
  usage-only tail chunk。
- 只有最终 attempt usage 随 assistant message 通过既有 durable save 落盘，重开可恢复。
- v13→v14→v15 和 v14→v15 均保留数据；没有新表、索引、repository API 或 worker
  protocol。
- 消息行与 composer 文案、null/0、格式、折叠和窄宽行为符合第 2 节。
- 删除消息后命中率按剩余消息重算；这是本次刻意接受的简单语义。
- 定向测试、静态门禁、全量测试和 diff audit 全部通过。
