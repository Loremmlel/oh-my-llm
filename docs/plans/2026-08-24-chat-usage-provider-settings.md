# Token 用量与服务商设置改进总实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用三个可独立审查和回滚的 PR，展示助手消息 Token 用量与会话缓存命中率、把 API Key 改为可靠的明文凭据输入，并在从 API 拉取模型时逐模型配置深度思考能力。

**Architecture:** Token 用量使用“最终 generation 结算回执”作为唯一持久化事实源：协议 adapter 归一 usage，generation lifecycle 只保留最终 attempt 的快照，`ChatConversationRepository` 在一个事务内保存终态消息并幂等插入回执，消息用量和会话命中率均从回执投影。API Key 和模型能力是两个独立的 Settings presentation 变更，不依赖 Token schema，也不与 Token PR 叠加分支。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` / Riverpod 3 / sqlite3 / 原始 `package:http` / PowerShell 7。

**Spec:** 本文件第 1～4 节是已批准产品与架构契约；用户明确要求跳过独立 spec 与逐节审批，直接生成本总实施计划。

## Global Constraints

- 计划基线是 `4776ee8483586e84add776bf41d4250c51e939fb`；计划 PR 合入后，三个实现分支都从最新 `master` 新建，不互相堆叠 commit。
- 总计划位于 `docs/plans/`；不得恢复已移除的 `docs/superpowers/plans/`。
- 三个实现 PR 必须保持独立：不得为了减少 PR 数把 Settings 小改动合入 Token schema PR。
- 所有新增测试名称、production 注释和测试注释使用简体中文；代码中不留下任务号、审查轮次或临时 Phase 编号。
- 跨 feature/core/app import 使用 `package:oh_my_llm/...`；同一 feature 内使用相对 import；不得新增 `part` / `part of`。
- 每次提交前格式化本次修改的全部 Dart 文件；暂存后再次运行 `dart format --output=none --set-exit-if-changed`。
- 单文件测试的工具级 timeout 必须设为 60,000ms；全量测试设为 240,000ms。测试、analyze、构建与诊断日志全部写入 ignored 的 `logs/`。
- 测试进程超时后先运行 `.\scripts\kill-stale-test-processes.ps1`，再诊断；不得直接重跑。
- 静态门禁和测试串行执行，不并行启动 `flutter analyze`、import boundary 或 Flutter tests。
- 每个实现 PR 在提交前运行定向测试、`dart run tool/check_import_boundaries.dart`、`flutter analyze`、全量测试、format 和 diff/scope audit。
- post-commit hook 会依据中文 conventional commit 前缀更新 `pubspec.yaml` 并 amend；每次提交后重新读取最终 HEAD 和版本，不引用 hook 前 SHA。
- PR 标题和正文使用简体中文；正文保留 `变更摘要 / 变更原因 / 实现说明 / 验证 / 风险与影响 / 审查重点` 六个二级标题。
- 不修改 API Key 的 SharedPreferences 格式、Settings transfer 注册、剪贴板敏感确认、Sync 敏感确认、列表掩码或日志脱敏。
- 不按模型名、host 或服务商猜测深度思考能力；远程模型目录不被视为 capability 权威来源。
- Token 数据是 best-effort：只使用 SSE 实际返回的 usage，不使用 tokenizer 本地估算，不承诺与服务商 Dashboard 或账单完全一致。

---

## 1. 分支与 PR 拆分

计划 PR 合入后，三个实现 agent 可以并行工作：

| PR | 分支 | 标题 | 允许范围 |
|---|---|---|---|
| A | `fix/settings-api-key-plain-text` | `fix(settings): API Key 输入框支持明文复制粘贴` | 唯一 API Key 表单及其 widget test |
| B | `feat/settings-model-fetch-reasoning` | `feat(settings): 拉取模型时配置深度思考能力` | 模型拉取结果行、批量表单数据、Settings 保存接线及其测试 |
| C | `feat/chat-token-usage` | `feat(chat): 展示消息 Token 用量与会话缓存命中率` | Chat usage domain/application/data/presentation、SQLite v15、相关测试 |

固定执行规则：

1. 每个 agent 先执行 `git switch master`、`git pull --ff-only`，确认计划 PR 已在 `master`。
2. PR A 执行 `git switch -c fix/settings-api-key-plain-text`；PR B 执行 `git switch -c feat/settings-model-fetch-reasoning`；PR C 执行 `git switch -c feat/chat-token-usage`。
3. 只读取本文件的全局限制、已批准契约和自己的 PR 章节；不得提前实现其他 PR。
4. PR A/B/C 没有代码依赖，可以独立合入；若 GitHub 同时审查，以各自 base/head diff 为准。
5. 任一 PR 发现必须修改另一 PR 的允许文件时停止，先报告冲突；不得跨分支顺手修复。

## 2. 已批准产品契约

### 2.1 助手消息 Token 行

- 只在 assistant 消息终态且至少一个 usage 字段已知时显示。
- 位置固定在 `finishReason` 之后、消息版本切换器之前；现有顶部字数统计不移动、不合并。
- 使用一条可自动换行的轻量文本：`输入 4,000 · 缓存命中 1,500 · 缓存写入 800 · 输出 900`。
- 数量显示精确整数和千位分隔，不使用 K/M 缩写。
- 字段为 `null` 时整项不生成；服务商明确返回 `0` 时显示 `0`。
- `输入` 是协议归一后的输入总计；`缓存命中` 是 cache read；`缓存写入` 是 cache creation/write；`输出` 是服务商返回的总输出，允许包含隐藏 reasoning 消耗。
- 不新增 reasoning token 独立 UI，不新增 usage 展开面板或 Chip。

### 2.2 会话缓存命中率

- 公式固定为：`Σ cacheReadInputTokens / Σ inputTotalTokens × 100%`。
- 只纳入同一结算回执中 `inputTotalTokens` 与 `cacheReadInputTokens` 都非 null、且 `inputTotalTokens > 0` 的 generation；缺失 cache read 不按 0 处理。
- 所有用户可感知 generation 都进入会话历史：普通发送、手动重试、编辑消息后重新生成。
- 自动重试的前序 attempt 属于同一 generation 的恢复过程，不结算；只结算最终 attempt。
- 最终 attempt 无论正常完成、用户停止、异常 finish reason、最终空回复或错误，只要实际收到至少一个 usage 字段，就可写回消息；命中率仍按完整 pair 过滤。
- TLS/SSL、429、连接建立失败、连接重置或收到正文但没收到 usage 的 attempt 不估算、不结算 usage。
- 会话累计单调：删除消息、删除分支、切换版本不删除结算回执；删除整个会话时才级联删除回执。
- 会话内切换模型或服务商不分组，所有已结算 generation 一起统计。
- 输入区只显示 `当前会话缓存命中率：37.5%`；不显示分子/分母或覆盖率。
- 无可统计 pair 时固定显示 `当前会话缓存命中率：暂无数据`。
- 命中率保留一位小数；该行在展开 composer 中固定占位，折叠后隐藏。
- 指标位于服务商/模型行之后、紧凑/桌面操作行之前；不得塞入紧凑操作按钮横排。

### 2.3 API Key 明文输入

- 只改变新增/编辑服务商对话框中的唯一 API Key 输入框。
- 字符明文可见，支持系统原生选择、复制和粘贴。
- 使用 `TextInputType.visiblePassword`，`autocorrect: false`、`enableSuggestions: false`。
- 不增加失去意义的眼睛按钮。
- 服务商卡片继续掩码；自定义 Header 不改；导出/导入/Sync/日志安全边界不改。

### 2.4 从 API 拉取模型时配置深度思考

- 能力仍是每个模型自己的 `bool supportsReasoning`，不是服务商级字段。
- 每个可新增模型行提供“支持深度思考”复选框；默认 `false`。
- 只有模型被选中时能力复选框可操作；暂时取消模型选择后保留该行先前能力值。
- 手工/拉取模式切换继续通过 `Visibility(maintainState: true)` 保留拉取状态。
- 已存在模型整行禁用：模型选择、显示名称和能力复选框均不可操作，保留“已存在”标签。
- 已存在模型不参与 submit-ready 判断和批量提交；批量新增仍不更新已有模型。
- `ModelBatchFormData` 显式携带 `supportsReasoning`；Settings 保存接线不得再硬编码 `false`。

## 3. Token usage 深 module 与 interface

### 3.1 唯一事实源

新增 `conversation_usage_settlements` 表，一条记录代表一个 assistant message 对应 generation 的最终 usage 结算。它不是完整 attempt ledger：自动重试前序 attempt、无 usage 的请求、供应商原始 JSON 均不写入。

```sql
CREATE TABLE conversation_usage_settlements (
  conversation_id TEXT NOT NULL,
  assistant_message_id TEXT NOT NULL,
  input_total_tokens INTEGER CHECK (input_total_tokens >= 0),
  cache_read_input_tokens INTEGER CHECK (cache_read_input_tokens >= 0),
  cache_write_input_tokens INTEGER CHECK (cache_write_input_tokens >= 0),
  output_tokens INTEGER CHECK (output_tokens >= 0),
  settled_at TEXT NOT NULL,
  PRIMARY KEY (conversation_id, assistant_message_id),
  FOREIGN KEY (conversation_id)
    REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_usage_settlements_conversation
ON conversation_usage_settlements(conversation_id);
```

`assistant_message_id` 故意不引用 `messages(id)`：删除消息时回执必须保留。`conversation_id` 必须引用 conversation，以便删除会话时清理。

### 3.2 Domain 投影

创建 `lib/features/chat/domain/models/chat_token_usage.dart`：

```dart
final class ChatTokenUsage extends Equatable {
  const ChatTokenUsage({
    this.inputTotalTokens,
    this.cacheReadInputTokens,
    this.cacheWriteInputTokens,
    this.outputTokens,
  });

  final int? inputTotalTokens;
  final int? cacheReadInputTokens;
  final int? cacheWriteInputTokens;
  final int? outputTokens;

  bool get hasAnyValue;
  ChatTokenUsage mergeSnapshot(ChatTokenUsage newer);
  Map<String, dynamic> toJson();
  factory ChatTokenUsage.fromJson(Map<String, dynamic> json);
}

final class ChatTokenUsageSummary extends Equatable {
  const ChatTokenUsageSummary({
    this.eligibleInputTokens,
    this.cacheReadInputTokens,
  });

  final int? eligibleInputTokens;
  final int? cacheReadInputTokens;
  double? get cacheHitRate;
}
```

不变量：

- 四个 Token 字段只允许 null 或非负 int。
- `mergeSnapshot` 使用 newer 的非 null 值覆盖旧值，显式 0 同样覆盖；不得相加 SSE snapshot。
- `cacheHitRate` 在任一累计值为 null、分母小于等于 0 时返回 null，否则返回 0～1 的 double。
- `ChatMessage.tokenUsage` 与 `ChatConversation.tokenUsageSummary` 是 repository-owned 只读投影，必须进入 `copyWith` 与 `Equatable.props`。
- 两个投影不得写入 `ChatMessage.toJson` / `ChatConversation.toJson`，避免普通 whole-conversation save 成为第二事实源；后台结算命令单独携带 usage。
- 普通 load 由 repository 查询回执并注入投影；删除消息后 summary 仍由所有回执聚合，但已不存在的 message 不再有气泡投影。

### 3.3 Repository seam

深化现有 `ChatConversationRepository`，不新增 `UsageRepository`：

```dart
Future<ChatConversation> settleFinalGeneration({
  required ChatConversation conversation,
  required String assistantMessageId,
  required ChatTokenUsage? usage,
});
```

interface 契约：

- `conversation` 已包含终态 assistant 内容/错误/停止结果。
- `usage == null` 时只保存终态 conversation，不插入回执；仍返回从数据库重新加载的 canonical conversation。
- 非 null usage 必须 `hasAnyValue == true`，assistant ID 必须属于该 conversation 且 role 为 assistant。
- 首次结算在一个 `BEGIN IMMEDIATE` 事务内保存 conversation 与插入回执。
- 相同 `(conversationId, assistantMessageId)` + 相同 usage 重放是幂等成功；不同 usage 抛 `ChatUsageSettlementConflict` 并回滚。
- 返回值必须包含该消息的 usage 投影和整个会话的 summary 投影。
- `saveConversation` / `saveConversations` 不创建、修改或删除回执。

### 3.4 Protocol adapter 归一化

- Chat Completions：`prompt_tokens -> inputTotalTokens`，`prompt_tokens_details.cached_tokens -> cacheReadInputTokens`，若 details 自然带 `cache_write_tokens` 则读取为 cache write，`completion_tokens -> outputTokens`。
- Chat Completions request 固定发送 `stream_options: {'include_usage': true}`；parser 必须在检查 `choices` 前解析顶层 usage，接受官方形状 `choices: []` 的 usage-only chunk。
- Responses：`input_tokens -> inputTotalTokens`，`input_tokens_details.cached_tokens/cache_write_tokens` 映射缓存字段，`output_tokens -> outputTokens`。
- Anthropic：保留 raw `input_tokens`、`cache_read_input_tokens`、`cache_creation_input_tokens` 的 null/0；`inputTotalTokens = input + (cacheRead ?? 0) + (cacheWrite ?? 0)`，cache read/write 投影仍保持原始 null/0，`output_tokens -> outputTokens`。
- 从现有 application port 删除未使用的 `reasoningTokens` 独立字段；`outputTokens` 保持服务商总输出。

## 4. 数据流与终态顺序

```text
protocol SSE adapter
  -> ChatGenerationChunk.usage: ChatTokenUsage?
  -> ChatGenerationRun._attemptUsage.mergeSnapshot()
  -> host.completeAttempt(ChatAttemptSnapshot.usage)
     -> 若可自动重试：普通 intermediate save，丢弃 usage，reset attempt
     -> 若 final：repository.settleFinalGeneration(...)
        -> SQLite transaction 保存消息 + 幂等插入回执
        -> reload/join 消息 usage + aggregate 会话 summary
        -> controller 用 canonical conversation 更新 state
  -> ChatMessageBubble 显示 final message usage
  -> Composer 显示 conversation summary 的 cacheHitRate
```

固定时序：

1. `ChatGenerationRun` 仅在当前 attempt 内 merge usage。
2. `ChatAttemptRetry` 决策返回后立刻把 `_attemptUsage` 清为 null，再进入 retry waiting；停止于 retry waiting 时不能结算已被丢弃的 usage。
3. `FinishSuccess`、`FinishOutputRuleError`、重试耗尽、stop 都调用同一个 repository 终态结算 interface。
4. preparing 阶段停止时 usage 为 null，只保存终态消息。
5. settlement durable ACK 成功后才能把 canonical projection 写入 Riverpod state 并完成 terminal decision。
6. background writer 的 settlement command 不走 80ms debounce；它必须先等待既有 pending batch/ACK，再发送直接 typed command，ACK 后由主 isolate `_inner.loadConversation(id)` 读取 canonical projection。
7. writer 不可达时使用同一 `SqliteChatConversationRepository.settleFinalGeneration` 降级，不复制 SQL 规则。

---

## 5. PR A：API Key 明文凭据输入

### Task A1：锁定并实现明文凭据输入语义

**Files:**

- Modify: `test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart`
- Modify: `lib/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog.dart`

**Interfaces:**

- Consumes: 现有 `ValueKey('model-provider-api-key-field')` 与编辑态完整 Key controller。
- Produces: 明文、可复制粘贴且禁用自然语言建议的唯一 API Key `TextFormField`。

- [ ] **Step 1: 写失败的 widget contract test**

在现有 group 中新增中文用例，按 key 读取字段并断言：

```dart
testWidgets('API Key 字段明文显示并关闭输入建议', (tester) async {
  await pumpDialog(
    tester,
    initialValue: const LlmProviderConfig(
      id: 'provider-1',
      name: '测试服务商',
      apiUrl: 'https://api.example.com/v1/chat/completions',
      apiKey: 'sk-visible-copy-paste-key',
      apiProtocol: LlmApiProtocol.chatCompletions,
      models: [],
    ),
    onSubmit: (_) async {},
  );

  final field = tester.widget<TextFormField>(
    find.byKey(const ValueKey('model-provider-api-key-field')),
  );
  expect(field.obscureText, isFalse);
  expect(field.keyboardType, TextInputType.visiblePassword);
  expect(field.autocorrect, isFalse);
  expect(field.enableSuggestions, isFalse);
  expect(find.text('sk-visible-copy-paste-key'), findsOneWidget);
});
```

- [ ] **Step 2: 运行 RED**

工具级 timeout 60,000ms：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart --plain-name "API Key 字段明文显示并关闭输入建议" --reporter compact 2>&1 | Out-File -Encoding utf8 logs/api-key-plain-text-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/api-key-plain-text-red.log
```

预期：`EXIT` 非 0，至少因 `obscureText` 仍为 true 失败；若测试因 Finder/fixture 无效而失败，先修正测试直到正向对照能读到字段，不能把编译失败当有效 RED。

- [ ] **Step 3: 最小实现**

把 API Key 字段改为：

```dart
TextFormField(
  key: const ValueKey('model-provider-api-key-field'),
  controller: _apiKeyController,
  decoration: const InputDecoration(labelText: 'API Key'),
  keyboardType: TextInputType.visiblePassword,
  autocorrect: false,
  enableSuggestions: false,
  validator: validateRequired,
)
```

不得修改 provider card 掩码、自定义 Header、transfer/Sync 或 storage。

- [ ] **Step 4: 运行 GREEN 与整文件回归**

```powershell
flutter test test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/api-key-plain-text-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/api-key-plain-text-green.log
```

预期：`EXIT=0`；新增、编辑、协议选择和保存中关闭保护全部继续通过。

- [ ] **Step 5: 格式化、暂存并提交**

```powershell
dart format lib/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog.dart test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart
git add lib/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog.dart test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "fix(settings): API Key 输入框支持明文复制粘贴"
```

提交后读取 hook amend 后最终 HEAD，并确认除上述 Dart 文件与 `pubspec.yaml` 外无文件进入提交。

### Task A2：PR A 完整验证与 scope audit

- [ ] **Step 1: 串行执行静态与全量门禁**

使用第 8 节统一命令，日志前缀改为 `api-key-plain-text-*`；全部 `EXIT=0`。

- [ ] **Step 2: 人工行为 smoke**

在 Windows debug 中打开“设置 → 服务商 → 新增/编辑”，确认完整 Key 可见，可使用 Ctrl+A/C/V，卡片仍掩码。Android 只需 widget contract；本 PR 不要求真实设备键盘验证。

- [ ] **Step 3: scope audit**

```powershell
git diff --name-only master...HEAD
git diff --check master...HEAD
git status --short
```

允许文件只有 Task A1 的两个 Dart 文件与 hook 生成的 `pubspec.yaml`。出现其他文件立即停止。

---

## 6. PR B：拉取模型时配置深度思考

### Task B1：禁用已存在模型的假交互

**Files:**

- Modify: `test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart`
- Modify: `lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart`
- Modify: `lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart`

**Interfaces:**

- Consumes: `ModelSelectionEntry.alreadyExists` 与现有“只新增、同 modelName 跳过”的 controller 契约。
- Produces: 已存在条目不可选、不可编辑、不可提交；新条目行为不变。

- [ ] **Step 1: 扩展已有“已存在”测试形成有效 RED**

在 `shows already-exists chip...` 用例后断言：

```dart
final checkbox = tester.widget<Checkbox>(modelCheckbox('gpt-4o'));
expect(checkbox.onChanged, isNull);

final displayName = tester.widget<TextFormField>(
  find.byKey(const ValueKey('model-fetch-display-name-gpt-4o')),
);
expect(displayName.enabled, isFalse);
expect(
  tester.widget<FilledButton>(find.widgetWithText(FilledButton, '添加所选模型')).onPressed,
  isNull,
);
```

- [ ] **Step 2: 运行 RED**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart --plain-name "shows already-exists chip for existing models" --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-existing-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/model-fetch-existing-red.log
```

预期：Checkbox `onChanged` 当前非 null，测试断言失败。

- [ ] **Step 3: 实现禁用规则**

- 已存在条目的模型 Checkbox 使用 `onChanged: null`。
- 显示名称 `enabled: entry.selected && !entry.alreadyExists`。
- `_isBatchSubmitReady` 和 `_handleSubmit` 显式过滤 `e.selected && !e.alreadyExists`，不要只依赖当前初始状态。
- 保留“已存在”标签，不改变 modelName 精确、区分大小写的去重语义。

- [ ] **Step 4: 运行 GREEN**

```powershell
flutter test test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-existing-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/model-fetch-existing-green.log
```

预期：`EXIT=0`，普通拉取、提交所选和模式切换既有行为保持。

- [ ] **Step 5: 提交独立修复**

```powershell
dart format lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart
git add lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "fix(settings): 禁用拉取列表中的已有模型交互"
```

### Task B2：逐模型选择并持久化深度思考能力

**Files:**

- Modify: `lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart`
- Modify: `lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart`
- Modify: `test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart`

**Interfaces:**

- Produces: `ModelSelectionEntry.supportsReasoning` 与 `ModelBatchFormData.supportsReasoning`。
- Consumes: `LlmProviderModelConfig.supportsReasoning` 与现有 `upsertModels()` 去重保存。

- [ ] **Step 1: 写表单级 RED**

拉取两个新模型，选择两者，仅为第二个打开能力复选框，然后提交：

```dart
expect(captured, hasLength(2));
expect(captured![0].supportsReasoning, isFalse);
expect(captured![1].supportsReasoning, isTrue);
```

再在模式保持用例中为 `gpt-4o` 勾选能力，执行“取消模型选择 → 重新选择”和“手工输入 → 从 API 拉取”，两次都断言能力仍为 true。Finder 固定使用：

```dart
find.byKey(const ValueKey('model-fetch-reasoning-gpt-4o'))
```

- [ ] **Step 2: 运行表单 RED**

```powershell
flutter test test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-reasoning-form-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/model-fetch-reasoning-form-red.log
```

预期：`ModelBatchFormData.supportsReasoning` 或新 Finder 尚不存在导致失败；补测试辅助时要保证旧提交所选用例仍是正向对照。

- [ ] **Step 3: 实现行状态与提交数据**

`ModelSelectionEntry` 增加：

```dart
bool supportsReasoning = false;
```

每个可新增模型显示紧凑 `CheckboxListTile`：

```dart
CheckboxListTile(
  key: ValueKey('model-fetch-reasoning-${entry.remoteModel.id}'),
  contentPadding: EdgeInsets.zero,
  dense: true,
  value: entry.supportsReasoning,
  title: const Text('支持深度思考'),
  onChanged: entry.selected && !entry.alreadyExists
      ? (value) {
          setState(() => entry.supportsReasoning = value ?? false);
          widget.onSelectionChanged?.call();
        }
      : null,
)
```

取消模型选择时不得重置 `supportsReasoning`。

`ModelBatchFormData` 增加 required bool，并在 `_handleSubmit` 映射：

```dart
ModelBatchFormData(
  displayName: e.controller.text.trim(),
  modelName: e.remoteModel.id,
  supportsReasoning: e.supportsReasoning,
)
```

- [ ] **Step 4: 运行表单 GREEN**

```powershell
flutter test test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-reasoning-form-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/model-fetch-reasoning-form-green.log
```

- [ ] **Step 5: 写 Settings 保存接线 RED**

在 Settings screen case 中：

1. seed 一个无模型 provider；
2. 用 `modelCatalogWorkflowProvider.overrideWithValue(...)` 返回普通模型和推理模型；
3. 打开新增模型对话框、切到拉取、选择两行，仅勾选推理模型能力；
4. 提交后从 `llmModelConfigRepositoryProvider` 的 typed repository 读取两个模型；
5. 断言能力分别 false/true。

核心断言：

```dart
final container = ProviderScope.containerOf(
  tester.element(find.byType(SettingsScreen)),
);
final models = container.read(llmModelConfigRepositoryProvider).loadAll();
expect(models.singleWhere((m) => m.modelName == 'plain-model').supportsReasoning, isFalse);
expect(models.singleWhere((m) => m.modelName == 'reasoning-model').supportsReasoning, isTrue);
```

沿用同文件现有的 `ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)))` 取 container；不得为此修改 test helper，也不得读取 raw SharedPreferences JSON。

- [ ] **Step 6: 运行接线 RED**

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart --plain-name "从 API 拉取模型时分别保存深度思考能力" --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-reasoning-screen-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/model-fetch-reasoning-screen-red.log
```

预期：当前 `settings_screen.dart` 把所有批量模型硬编码成 false，推理模型断言失败。

- [ ] **Step 7: 修复 Settings 接线并运行 GREEN**

把唯一硬编码替换为：

```dart
supportsReasoning: item.supportsReasoning,
```

然后运行：

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/model-fetch-reasoning-screen-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/model-fetch-reasoning-screen-green.log
```

- [ ] **Step 8: 格式化、暂存并提交**

```powershell
$DartFiles = @(
  'lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart',
  'lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart',
  'lib/features/settings/presentation/settings_screen.dart',
  'test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart',
  'test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart'
)
dart format $DartFiles
git add $DartFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "feat(settings): 拉取模型时配置深度思考能力"
```

### Task B3：PR B 完整验证与 scope audit

- [ ] 运行第 8 节统一门禁，日志前缀 `model-fetch-reasoning-*`，全部 `EXIT=0`。
- [ ] 在 430px widget viewport 验证每行可以换行/纵向扩展，无横向 overflow；不增加按设备名分支。
- [ ] `git diff --name-only master...HEAD` 只允许 Task B1/B2 列出的五个 Dart 文件和 hook 自动修改的 `pubspec.yaml`。
- [ ] 自审 `master...HEAD`：不存在模型名推断、已有模型更新、服务商级能力字段或协议响应 capability 扩展。

---

## 7. PR C：Token 用量与会话缓存命中率

### Task C1：领域 usage 与三协议归一化

**Files:**

- Create: `lib/features/chat/domain/models/chat_token_usage.dart`
- Create: `test/features/chat/domain/models/chat_token_usage_test.dart`
- Modify: `lib/features/chat/application/ports/chat_generation_client.dart`
- Modify: `test/features/chat/application/ports/chat_generation_client_contract_test.dart`
- Modify: `lib/features/chat/data/generation/chat_completions/chat_completions_client.dart`
- Modify: `lib/features/chat/data/generation/chat_completions/chat_completions_parser.dart`
- Modify: `test/features/chat/data/generation/chat_completions/chat_completions_client_test.dart`
- Modify: `test/features/chat/data/generation/chat_completions/chat_completions_parser_test.dart`
- Modify: `lib/features/chat/data/generation/responses/responses_parser.dart`
- Modify: `test/features/chat/data/generation/responses/responses_parser_test.dart`
- Modify: `lib/features/chat/data/generation/anthropic/anthropic_parser.dart`
- Modify: `test/features/chat/data/generation/anthropic/anthropic_parser_test.dart`
- Modify: `test/features/chat/data/generation/responses/responses_client_test.dart`
- Modify: `test/features/chat/data/generation/anthropic/anthropic_messages_client_test.dart`

**Interfaces:**

- Produces: `ChatTokenUsage`，供 `ChatGenerationChunk`、run snapshot、repository settlement 共用。
- Removes: application port 内旧 `ChatGenerationUsage` 与独立 `reasoningTokens` 字段。

- [ ] **Step 1: 写领域 RED**

覆盖：四字段 equality、null/0、`hasAnyValue`、newer 非 null 覆盖、newer null 保留、负数拒绝、JSON round-trip。

```dart
test('mergeSnapshot 保留 null 并让显式零覆盖旧值', () {
  const old = ChatTokenUsage(
    inputTotalTokens: 100,
    cacheReadInputTokens: 40,
    outputTokens: 20,
  );
  const newer = ChatTokenUsage(
    cacheReadInputTokens: 0,
    cacheWriteInputTokens: 8,
  );
  expect(
    old.mergeSnapshot(newer),
    const ChatTokenUsage(
      inputTotalTokens: 100,
      cacheReadInputTokens: 0,
      cacheWriteInputTokens: 8,
      outputTokens: 20,
    ),
  );
});
```

- [ ] **Step 2: 运行领域 RED**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/domain/models/chat_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-domain-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/token-usage-domain-red.log
```

预期：新领域类型不存在而失败。

- [ ] **Step 3: 最小实现领域类型并迁移 client contract**

- 创建第 3.2 节精确类型；constructor 使用 assert 或显式 `ArgumentError` 拒绝负数，测试与选择保持一致。
- `ChatGenerationChunk.usage`、`ChatGenerationResult.usage`、`complete()` fold 改用 `ChatTokenUsage` 和 `mergeSnapshot`。
- 删除旧 `ChatGenerationUsage`，更新 contract test 的字段名；不保留 compatibility alias。

- [ ] **Step 4: 运行领域与 client contract GREEN**

```powershell
flutter test test/features/chat/domain/models/chat_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-domain-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/token-usage-domain-green.log
flutter test test/features/chat/application/ports/chat_generation_client_contract_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-client-contract-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/token-usage-client-contract-green.log
```

- [ ] **Step 5: 写三协议 RED**

必须包含：

1. Chat request body 精确包含 `"stream_options":{"include_usage":true}`。
2. Chat parser 对 `{"choices":[],"usage":...}` 产生仅含 usage 的 chunk。
3. Chat/Responses 的显式 `cache_write_tokens: 0` 保留为 0，缺失保持 null。
4. Anthropic fixture `input=10, cache_creation=4, cache_read=3` 归一为 `inputTotal=17, cacheWrite=4, cacheRead=3`；后续 output event merge 后 output=20。
5. 三协议全字段缺失/非 int 时 usage 为 null。

- [ ] **Step 6: 运行协议 RED**

逐文件运行并分别写：

```powershell
flutter test test/features/chat/data/generation/chat_completions/chat_completions_client_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-chat-client-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-chat-client-red.log
flutter test test/features/chat/data/generation/chat_completions/chat_completions_parser_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-chat-parser-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-chat-parser-red.log
flutter test test/features/chat/data/generation/responses/responses_parser_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-responses-parser-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-responses-parser-red.log
flutter test test/features/chat/data/generation/anthropic/anthropic_parser_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-anthropic-parser-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-anthropic-parser-red.log
```

每个 RED 必须失败在对应行为断言；旧字段重命名造成的编译失败只用于迁移提示，不算 parser 行为 RED。

- [ ] **Step 7: 实现 adapter 归一并运行 GREEN**

严格按第 3.4 节映射。Chat parser 先提取 usage，再决定是否读取 choice；usage-only chunk 的 `isEmpty` 可以仍为 true，但不得返回 null。逐文件重跑 Step 6 命令，日志后缀改为 `-green.log`，全部 `EXIT=0`。

- [ ] **Step 8: 格式化并提交**

```powershell
$DartFiles = @(git diff --name-only -- '*.dart')
dart format $DartFiles
git add lib/features/chat/domain/models/chat_token_usage.dart test/features/chat/domain/models/chat_token_usage_test.dart lib/features/chat/application/ports/chat_generation_client.dart test/features/chat/application/ports/chat_generation_client_contract_test.dart lib/features/chat/data/generation test/features/chat/data/generation
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "refactor(chat): 归一化流式 Token 用量契约"
```

### Task C2：SQLite v15 与原子结算回执

**Files:**

- Modify: `lib/core/persistence/app_database.dart`
- Modify: `test/core/persistence/app_database_migration_test.dart`
- Modify: `lib/features/chat/domain/models/chat_message.dart`
- Modify: `lib/features/chat/domain/models/chat_conversation.dart`
- Modify: `test/features/chat/domain/models/chat_message_test.dart`
- Modify: `test/features/chat/domain/models/chat_conversation_test.dart`
- Modify: `lib/features/chat/application/ports/chat_conversation_repository.dart`
- Modify: `lib/features/chat/data/persistence/chat_sql_codec.dart`
- Modify: `lib/features/chat/data/persistence/sqlite_chat_conversation_repository.dart`
- Modify: `lib/features/chat/data/persistence/background_chat_repository.dart`
- Create: `lib/features/chat/data/persistence/chat_writer_protocol.dart`
- Modify: `lib/features/chat/data/persistence/chat_writer_entry_point.dart`
- Create: `test/features/chat/data/persistence/chat_usage_settlement_test.dart`
- Modify: `test/features/chat/data/persistence/background_chat_repository_test.dart`
- Modify: `test/helpers/chat/flaky_chat_conversation_repository.dart`
- Modify: `test/helpers/chat/controllable_chat_conversation_repository.dart`
- Modify: `test/integration/chat_lifecycle_integration_test.dart`

**Interfaces:**

- Consumes: Task C1 `ChatTokenUsage`。
- Produces: `ChatConversationRepository.settleFinalGeneration(...)`、`ChatMessage.tokenUsage`、`ChatConversation.tokenUsageSummary`。

- [ ] **Step 1: 写 v15 migration RED**

更新 migration test：

- 当前 schema 期望 15；fresh DB 存在 settlement 表、5 个业务列和 conversation 索引。
- 创建合法 v14 fixture，打开后迁移到 v15，原 conversations/messages/favorites 数据保持。
- v13 现在显式拒绝；删除旧 v13→v14 收藏迁移 helper 与其专项测试，不保留两步链。
- v16 显式拒绝。
- 删除 conversation 后 settlement 级联删除；删除 message 不删除 settlement。

```dart
test('v14 数据库迁移到 v15 并保留聊天数据', () async {
  final path = createV14Database('usage-v14.db');
  final database = AppDatabase.forPath(path);
  addTearDown(database.close);
  expect(database.connection.select('PRAGMA user_version').single['user_version'], 15);
  expect(
    database.connection.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='conversation_usage_settlements'",
    ),
    isNotEmpty,
  );
});
```

- [ ] **Step 2: 运行 migration RED**

```powershell
flutter test test/core/persistence/app_database_migration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-migration-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 200 logs/token-usage-migration-red.log
```

预期：v15/table/migration 断言失败；正向 v14 fixture 必须能被独立 sqlite 打开，避免无效 fixture 造成假 RED。

- [ ] **Step 3: 实现 rolling migration**

- `currentSchemaVersion = 15`。
- `_initializeSchema` 只接受 0、15、14；14 调用 `_migrateUsageSettlementsFromV14ToV15()`。
- fresh `_createSchema()` 直接创建第 3.1 节表与索引。
- v14→v15 在单事务中创建表/索引、foreign key check、设置 user_version 15。
- 删除 `_migrateFavoritesFromV13ToV14` 与仅服务旧迁移的 `_hasColumn`；保留 fresh schema 需要的 `_favoritesTableV14Ddl` 和系统收藏夹播种。
- 更新类注释说明 v14 是唯一临时旧基线。

- [ ] **Step 4: 运行 migration GREEN**

```powershell
flutter test test/core/persistence/app_database_migration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-migration-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-migration-green.log
```

- [ ] **Step 5: 写 domain projection 与 repository RED**

新测试至少覆盖：

1. 首次 settlement 保存终态消息并返回消息 usage + summary。
2. 相同 assistant + 相同 usage 重放不重复累计。
3. 相同 assistant + 不同 usage 抛 `ChatUsageSettlementConflict`，消息和回执都回滚。
4. usage null 只保存消息，不创建回执。
5. 缺 cache read 的回执不进入 summary；显式 cache read 0 进入 0.0%。
6. 手工插入多个回执后 summary 是加权总和，不平均每轮百分比。
7. 删除消息后 summary 不变；删除 conversation 后回执为空。
8. close/reopen 后投影一致。
9. `ChatMessage.toJson` 和 `ChatConversation.toJson` 不含 usage projection 字段，fromJson 默认空投影。

核心 repository test 形状：

```dart
final canonical = await repository.settleFinalGeneration(
  conversation: terminalConversation,
  assistantMessageId: 'assistant-1',
  usage: const ChatTokenUsage(
    inputTotalTokens: 100,
    cacheReadInputTokens: 40,
    outputTokens: 20,
  ),
);
expect(canonical.messageNodes.singleWhere((m) => m.id == 'assistant-1').tokenUsage, isNotNull);
expect(canonical.tokenUsageSummary.cacheHitRate, 0.4);
```

- [ ] **Step 6: 运行 repository RED**

```powershell
flutter test test/features/chat/data/persistence/chat_usage_settlement_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-settlement-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-settlement-red.log
```

预期：settlement interface/type/table projection 尚不存在。

- [ ] **Step 7: 实现 domain 投影与 SQLite adapter**

- `ChatMessage` 增加 nullable `tokenUsage`；`ChatConversation` 增加默认 `const ChatTokenUsageSummary()`。
- 投影进入 constructor/copyWith/props，不进入 JSON。
- `chat_sql_codec.dart` 把“事务包装”和“保存 conversation rows”拆开，确保 normal save 和 settlement transaction 复用同一 row implementation，禁止嵌套事务。
- settlement transaction 先验证 assistant，再保存终态 conversation，再 insert/幂等校验 receipt。
- loadAll/loadConversation 一次查询回执，构建 `usageByAssistantId` 与 `summaryByConversationId`，注入仍存在的 assistant 和 conversation。
- SQL `SUM` 只针对 input/cache pair 均已知且 input>0 的行；没有 eligible row 时 summary 两项为 null。

- [ ] **Step 8: 实现后台 typed command**

`chat_writer_protocol.dart` 定义：

```dart
final class SettleFinalGenerationCommand extends WorkerCommand {
  SettleFinalGenerationCommand({
    required this.id,
    required this.conversationJson,
    required this.assistantMessageId,
    required this.usageJson,
  });

  final int id;
  final Map<String, dynamic> conversationJson;
  final String assistantMessageId;
  final Map<String, dynamic>? usageJson;
}
```

- worker 收到命令后调用 feature codec 的同一 settlement 实现并回 ACK/ERROR。
- background repository 的 direct settlement 不参加 debounce；发送前 `await flush()`，用独立 completer 等 ACK，成功后 `_inner.loadConversation(id)` 返回 canonical。
- `:memory:` 直接调用 inner adapter。
- worker 不可达时直接 inner settlement；不得先 ACK 再降级。
- close 必须等待 direct settlement ACK；timeout 后走现有可终止/降级规则，不能留下 DLL 锁进程。

- [ ] **Step 9: 运行 repository/background GREEN**

```powershell
flutter test test/features/chat/data/persistence/chat_usage_settlement_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-settlement-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 240 logs/token-usage-settlement-green.log
flutter test test/features/chat/data/persistence/background_chat_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-background-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-background-green.log
flutter test test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-repository-regression.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-repository-regression.log
```

- [ ] **Step 10: 格式化并提交**

```powershell
$DartFiles = @(git diff --name-only -- '*.dart')
dart format $DartFiles
git add lib/core/persistence/app_database.dart test/core/persistence/app_database_migration_test.dart lib/features/chat/domain/models lib/features/chat/application/ports/chat_conversation_repository.dart lib/features/chat/data/persistence test/features/chat/domain/models test/features/chat/data/persistence
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "refactor(chat): 建立最终生成用量结算回执"
```

### Task C3：generation lifecycle 只结算最终 attempt

**Files:**

- Modify: `lib/features/chat/application/generation/chat_generation_contract.dart`
- Modify: `lib/features/chat/application/generation/chat_generation_run.dart`
- Modify: `lib/features/chat/application/sessions/chat_sessions_controller.dart`
- Modify: `lib/features/chat/application/sessions/chat_sessions_controller_support.dart`
- Modify: `test/features/chat/application/generation/chat_generation_run_test.dart`
- Modify: `test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_generation_cases.dart`
- Modify: `test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_retry_cases.dart`
- Modify: `test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_stop_cases.dart`
- Modify: `test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_branching_cases.dart`

**Interfaces:**

- Consumes: Task C1 `ChatTokenUsage` 与 Task C2 settlement interface。
- Produces: `ChatAttemptSnapshot.usage`、`ChatPartialSnapshot.usage`，以及 success/error/stop 统一 durable settlement。

- [ ] **Step 1: 写 run-level RED**

新增中文用例：

- 同一 attempt 分散 usage snapshot 合并后传给 host。
- host 返回 `ChatAttemptRetry` 后旧 usage 被丢弃，第二 attempt 最终 snapshot 只含第二次值。
- streaming stop 把当前 attempt 已知 usage 放入 partial。
- preparing stop 与没有 usage 的连接错误传 null。
- 显式 0 不被 merge 丢失。

```dart
expect(
  host.attempts.single.usage,
  const ChatTokenUsage(
    inputTotalTokens: 100,
    cacheReadInputTokens: 25,
    outputTokens: 30,
  ),
);
```

- [ ] **Step 2: 运行 run RED**

```powershell
flutter test test/features/chat/application/generation/chat_generation_run_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-run-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-run-red.log
```

- [ ] **Step 3: 实现 per-attempt accumulator**

- `_startStream` 在处理 content/reasoning/finishReason 同时 merge `chunk.usage`。
- snapshot 增加 nullable usage。
- 收到 `ChatAttemptRetry` 决策时立刻 `_attemptUsage = null`；`_startNextAttempt` 防御性再次清空。
- stop partial 携带当前 usage；retryWaiting 中 usage 已为空。
- 不把 usage 放进 300ms `ChatStreamingReply`，消息级 UI 只在终态更新。

- [ ] **Step 4: 运行 run GREEN**

```powershell
flutter test test/features/chat/application/generation/chat_generation_run_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-run-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 240 logs/token-usage-run-green.log
```

- [ ] **Step 5: 写 controller RED**

覆盖以下可观察结果：

1. success 收到 usage 后 repository reload 的 assistant 有 usage，summary 更新。
2. 自动重试第一 attempt 带 usage、第二 attempt 带另一 usage：只结算第二次。
3. 手动重试和编辑各产生新 assistant，summary 单调增加两次。
4. retry 耗尽的最终 attempt 若有 usage 仍结算；前序自动 attempt 不结算。
5. output rule 清空正文仍结算服务商已返回 usage。
6. streaming stop 有 usage 时结算；preparing/retryWaiting stop 无回执。
7. TLS/429/连接错误、正文后断流但无 usage 不产生回执。
8. 删除已结算消息/全部版本后 summary 不回退。

- [ ] **Step 6: 运行 controller RED**

逐文件运行 generation/retry/stop/branching case 入口 `chat_sessions_controller_test.dart` 的 plain-name，或整入口一次运行：

```powershell
flutter test test/features/chat/application/sessions/chat_sessions_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-controller-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 260 logs/token-usage-controller-red.log
```

预期：当前 controller 仍走 `saveConversationDurable`，没有 settlement 投影。

- [ ] **Step 7: 把终态保存 funnel 到 settlement**

- 在 support 中增加一个调用 repository settlement 的 durable helper；错误转换为现有 persistenceFailed，不新增 SnackBar/Dialog。
- `FinishSuccess`、`FinishOutputRuleError`：调用 settlement，canonical conversation 写回 state，再返回 decision。
- `FinishRetry`：先判断 `_canRetry`；可重试时只做既有 intermediate save 并返回 Retry；不可重试时对最终 attempt 调 settlement，再返回 GiveUp。
- stop：构造 stopped conversation 后调用相同 settlement interface；usage null 时只保存不插 receipt。
- settlement 后更新 `conversationSummaries` 与 `historyRevision` 的语义保持现有终态行为，不因只增加 usage 重复增加历史项。
- 不用 `generationId` 做 durable key；它是进程内递增值。幂等键固定为 assistant message ID。

- [ ] **Step 8: 运行 controller GREEN 与 persistence 回归**

```powershell
flutter test test/features/chat/application/sessions/chat_sessions_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-controller-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 280 logs/token-usage-controller-green.log
flutter test test/features/chat/application/sessions/chat_sessions_controller_persistence_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-controller-persistence-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-controller-persistence-green.log
```

- [ ] **Step 9: 格式化并提交**

```powershell
$DartFiles = @(git diff --name-only -- '*.dart')
dart format $DartFiles
git add lib/features/chat/application/generation lib/features/chat/application/sessions test/features/chat/application/generation test/features/chat/application/sessions
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "refactor(chat): 结算最终生成的 Token 用量"
```

### Task C4：消息气泡和输入区展示

**Files:**

- Create: `lib/features/chat/presentation/formatters/chat_token_usage_formatter.dart`
- Create: `test/features/chat/presentation/formatters/chat_token_usage_formatter_test.dart`
- Modify: `lib/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart`
- Create: `test/features/chat/presentation/widgets/messages/bubble/chat_message_bubble_token_usage_test.dart`
- Modify: `lib/features/chat/application/workspace/chat_workspace_view_state.dart`
- Modify: `test/features/chat/application/workspace/chat_workspace_view_state_test.dart`
- Modify: `lib/features/chat/presentation/widgets/composer/chat_composer_card.dart`
- Create: `test/features/chat/presentation/widgets/composer/chat_composer_card_token_usage_test.dart`
- Modify: `test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart`

**Interfaces:**

- Consumes: `ChatMessage.tokenUsage` 与 `ChatConversation.tokenUsageSummary.cacheHitRate`。
- Produces: exact number formatting、message bottom Wrap、expanded composer fixed status row。

- [ ] **Step 1: 写 formatter RED**

固定用例：

```dart
test('Token 数使用千位分隔且命中率保留一位小数', () {
  expect(formatTokenCount(0), '0');
  expect(formatTokenCount(1234), '1,234');
  expect(formatCacheHitRate(null), '当前会话缓存命中率：暂无数据');
  expect(formatCacheHitRate(0), '当前会话缓存命中率：0.0%');
  expect(formatCacheHitRate(0.375), '当前会话缓存命中率：37.5%');
});
```

不得新增 `intl` 依赖；用纯 Dart formatter。

- [ ] **Step 2: 写 bubble RED**

覆盖：assistant 四项顺序、null 静默隐藏、显式 0 显示、user 不显示、streaming 不显示、stats 在 finish chip 后且 version navigator 前、窄宽自然 Wrap 无 overflow。

- [ ] **Step 3: 写 composer/read-model RED**

覆盖：

- read model 从 conversation summary 投影 rate，而非扫描 messageNodes。
- 展开 composer 无数据时固定显示暂无数据。
- 37.5% 与 0.0% 精确文案。
- 折叠 composer 不显示该行。
- 679/680px 两侧都只有一条状态行，操作行分支不变。

- [ ] **Step 4: 运行 UI RED**

```powershell
flutter test test/features/chat/presentation/formatters/chat_token_usage_formatter_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-formatter-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-formatter-red.log
flutter test test/features/chat/presentation/widgets/messages/bubble/chat_message_bubble_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-bubble-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-bubble-red.log
flutter test test/features/chat/presentation/widgets/composer/chat_composer_card_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-composer-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-composer-red.log
```

- [ ] **Step 5: 实现 formatter 与 bubble 行**

- `formatTokenCount` 对非负 int 从右向左每三位插入逗号。
- bubble 构造已知字段列表，再用 `Wrap(spacing: 8, runSpacing: 4)` 渲染 `bodySmall/onSurfaceVariant` 文本。
- 使用固定文案 `输入 / 缓存命中 / 缓存写入 / 输出`；不重复写“Token”。
- 在源码顺序上放到 finish chip 之后、version navigator 之前。

- [ ] **Step 6: 实现 composer summary 投影**

- `ChatWorkspaceComposerReadModel/State` 增加 required `double? cacheHitRate`，factory/props 全部透传。
- provider 构造 read model 时使用 `conversation.tokenUsageSummary.cacheHitRate`，不扫描 active path 或全部 nodes。
- composer 在 `ComposerProviderModelRow` 后加 6px 间距和一条固定 `bodySmall/onSurfaceVariant` Text，再进入 action row。
- 文案仅调用 formatter；不显示 ratio/coverage，不加交互行为或 Tooltip。

- [ ] **Step 7: 运行 UI GREEN 与现有响应式回归**

```powershell
flutter test test/features/chat/presentation/formatters/chat_token_usage_formatter_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-formatter-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 160 logs/token-usage-formatter-green.log
flutter test test/features/chat/presentation/widgets/messages/bubble/chat_message_bubble_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-bubble-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-bubble-green.log
flutter test test/features/chat/presentation/widgets/composer/chat_composer_card_token_usage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-composer-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-composer-green.log
flutter test test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-composer-responsive-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-composer-responsive-green.log
flutter test test/features/chat/application/workspace/chat_workspace_view_state_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-workspace-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 180 logs/token-usage-workspace-green.log
```

- [ ] **Step 8: 格式化并提交**

```powershell
$DartFiles = @(git diff --name-only -- '*.dart')
dart format $DartFiles
git add lib/features/chat/presentation lib/features/chat/application/workspace test/features/chat/presentation test/features/chat/application/workspace
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git commit -m "feat(chat): 展示 Token 用量与会话缓存命中率"
```

### Task C5：端到端回归、兼容审计与最终验证

**Files:**

- Modify: `test/integration/multi_protocol_chat_generation_integration_test.dart`
- Modify: `test/features/chat/application/sessions/chat_sessions_controller_persistence_test.dart`
- 本 Task 不修改 production；若 required gate 暴露 Tasks C1–C4 的缺陷，回到对应 Task 修复并重跑其 RED/GREEN。

- [ ] **Step 1: 多协议正向闭环**

`multi_protocol_chat_generation_integration_test.dart` 的三个协议成功链路分别提供原生 usage 事件，并断言归一化四字段已经挂到 terminal assistant；`chat_sessions_controller_persistence_test.dart` 再用一个 fake stream 验证 generation terminal → repository close/reopen → assistant message 仍有四字段投影 → conversation rate 正确。三协议 parser 已分别单测，不复制三套完整 UI 流程。

- [ ] **Step 2: 运行 Token 定向套件**

按顺序运行 C1～C4 的全部 GREEN 文件，以及：

```powershell
flutter test test/integration/multi_protocol_chat_generation_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-integration-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-integration-green.log
flutter test test/features/chat/application/sessions/chat_sessions_controller_persistence_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/token-usage-persistence-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 220 logs/token-usage-persistence-green.log
```

- [ ] **Step 3: 重复结算与删除语义审计**

直接查询测试数据库证明：

- 同 assistant 恰好一条 receipt；
- 自动重试前序 usage 没有 receipt；
- manual retry/edit 各有新 assistant receipt；
- message delete 后 receipt 存在；
- conversation delete 后 receipt 为 0。

不得用只检查 domain state 的测试替代 SQLite 断言。

- [ ] **Step 4: rolling baseline 审计**

```powershell
rg -n "v13|V13|13→14|_migrateFavoritesFromV13ToV14" lib/core/persistence/app_database.dart test/core/persistence/app_database_migration_test.dart
```

允许结果只包含“v13 被拒绝”的当前范围测试说明；不得残留 v13→v14 迁移实现、fixture 或两步迁移链。

- [ ] **Step 5: 运行第 8 节统一门禁与 scope audit**

全部通过后才能创建 PR C。若 full suite 超时，按全局规则先清理残留进程。

---

## 8. 每个实现 PR 的统一验证命令

在各自分支仓库根目录串行执行。先运行以下分支到日志前缀的固定映射；未知分支直接停止：

```powershell
$VerificationPrefix = switch (git branch --show-current) {
  'fix/settings-api-key-plain-text' { 'api-key-plain-text' }
  'feat/settings-model-fetch-reasoning' { 'model-fetch-reasoning' }
  'feat/chat-token-usage' { 'token-usage' }
  default { throw '当前分支不属于本计划的三个实现分支' }
}
```

### 8.1 format

```powershell
$DartFiles = @(git diff --name-only master...HEAD -- '*.dart')
if ($DartFiles.Count -gt 0) { dart format $DartFiles }
git add $DartFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
if ($StagedDartFiles.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $StagedDartFiles
}
```

若最后一次 format 改文件，重新运行对应定向 GREEN，不能只重新暂存。

### 8.2 import boundary

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 "logs/$VerificationPrefix-boundaries.log"; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 140 "logs/$VerificationPrefix-boundaries.log"
```

必须 `EXIT=0`。PR C 特别确认 presentation 没有 import data/persistence，application port 不 import presentation。

### 8.3 analyze

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 "logs/$VerificationPrefix-analyze.log"; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 180 "logs/$VerificationPrefix-analyze.log"
```

必须 `EXIT=0`。

### 8.4 全量测试

工具级 timeout 240,000ms：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

必须 `EXIT=0`。输出被截断时只从 `logs/fltest.log` 查询，不直接重跑：

```powershell
Select-String -Pattern " -[1-9]" -Path logs/fltest.log
```

### 8.5 diff/scope

```powershell
git diff --check master...HEAD
git diff --stat master...HEAD
git diff --name-only master...HEAD
git status --short
git log --oneline master..HEAD
```

检查：无 logs、数据库、用户数据、临时调试、英文新增测试名、review 编号注释、跨 PR 文件。

## 9. PR 正文事实要求

每个 PR 使用 UTF-8 body file 创建，并在创建后用 `gh pr view --json title,body,baseRefName,headRefName,isDraft,url` 回读。

### PR A

- `变更摘要`：只描述 API Key 表单明文、复制粘贴和输入建议设置；明确列表仍掩码。
- `验证`：列出 dialog widget test、analyze、boundary、full suite 的实际结果；Windows smoke 只有实际执行后才能写通过。
- `风险与影响`：屏幕旁观暴露风险增加，但未改变存储/传输/日志；回滚该 commit 恢复密码显示。
- `审查重点`：字段是否仍完整预填/提交；其他秘密边界是否零 diff。

### PR B

- `变更摘要`：逐模型能力选择、已存在行禁用、能力持久化；明确不自动推断、不更新已有模型。
- `验证`：form row 独立选择、状态保持、Settings 持久化、窄屏、静态与全量实际结果。
- `风险与影响`：旧模型 JSON 默认 false 不变，无迁移；回滚后 API 拉取恢复全部 false。
- `审查重点`：`ModelBatchFormData -> SettingsScreen -> LlmProviderModelConfig` 是否无硬编码丢值；已有行是否全禁用。

### PR C

- `变更摘要`：消息四项 usage、会话命中率、final-generation receipt；明确 best-effort 与自动重试前序不计。
- `验证`：三协议、run retry reset、settlement 幂等/删除、migration、UI、integration、static/full suite 的实际结果。
- `风险与影响`：SQLite v15 只支持 v14→v15；v13 被拒绝；新增 receipt 随会话增长；删除消息不回退统计是产品契约。
- `审查重点`：receipt 是否唯一事实源、终态事务/后台 ACK、Chat usage-only chunk、Anthropic input 归一、null/0、删除语义。

## 10. 停止条件

### PR A

- 发现还有第二个 production API Key 输入入口时停止并报告，不能擅自扩大所有 secret 字段。
- 需要修改 provider storage/transfer 才能实现复制粘贴时停止；当前事实表明不需要。

### PR B

- 远程响应没有统一 capability 字段时不得添加 host/model-name 推断。
- 若需求转为更新已有模型，停止并另写批量更新设计；本 PR 只新增。
- 若窄屏行无法容纳，允许纵向布局/Wrap，不允许按 Windows/Android 标签分支。

### PR C

- 任何方案需要同时保留 v13→v14 与 v14→v15 时停止；违反 rolling baseline。
- 任何方案把 usage 同时写入 message columns、conversation totals 和 receipt 三处时停止；违反单一事实源。
- background settlement 无法保证 conversation+receipt 同事务时停止；不能用两个独立 ACK 假装原子。
- 需要完整记录自动重试前序 attempt、供应商原始 usage JSON、费用或模型分组时停止；这些超出批准范围。
- 需要 presentation import data/persistence 或新建只有一个 adapter 的 `UsageRepository` 时停止并重审 seam。
- 服务商不返回 usage 时不得用本地 tokenizer 或按字符估算补齐。
- migration、全量测试或 import boundary 失败时不得以“现有问题”跳过，必须提供 base 对照或修复本 PR 引入的问题。

## 11. 完成定义

### 总计划 PR

- 本文件是唯一功能变更；允许 post-commit hook 同提交更新 `pubspec.yaml`。
- `git diff --check` 通过，Markdown 标题/代码块/路径人工自审通过。
- 未执行 Flutter tests：计划 PR 不修改 Dart、schema 或运行时行为。
- PR 正文使用六章节并回读 base/head/title/body/url。

### PR A

- API Key 字段明文、可复制粘贴、关闭建议；列表与安全边界不变。
- 定向、static、全量与 scope audit 通过；实际验证状态如实记录。

### PR B

- 拉取行能力值逐模型独立、默认 false、状态保持；已有模型全禁用。
- 批量保存后 typed model 的 `supportsReasoning` 与行选择一致。
- 不存在推断、已有模型更新或额外 protocol 字段。

### PR C

- 三协议提供统一四字段 usage，Chat 能接收 usage-only tail chunk。
- 自动重试前序 usage 丢弃；最终 attempt 的 usage 通过单一 settlement interface 落盘。
- receipt 幂等、冲突回滚、消息删除不回退、会话删除 cascade、重开可恢复。
- 消息底部和 composer 文案、顺序、null/0、格式、折叠/响应式全部符合第 2 节。
- v15 fresh/migration/reject 语义、static、全量、scope audit 全部通过。

## 12. 执行顺序与交接

1. 先合入本计划 PR。
2. 后续 orchestrator 同时派发 PR A/B/C 三个 agent，每个 agent 独占自己的分支和允许文件。
3. 每个 PR 按任务顺序执行 RED → GREEN → commit → static/full gates → diff audit → PR。
4. Sourcery 反馈逐条用代码与测试证据判断；成立则在本 PR 修复，不成立则说明证据，跨范围建议另记。
5. 三个 PR 的完成、commit、push、PR、Sourcery、CI 与手工 smoke 状态分别报告，不把“计划已写”表述成“功能已实现”。
