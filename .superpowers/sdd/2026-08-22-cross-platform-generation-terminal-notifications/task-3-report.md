# Task 3 实施报告：coordinator 接入与前台服务端口瘦身

## 状态

DONE

## 提交

- Commit：`ccd70c2d5884502735997feab28708fa045743c7`
- Message：`refactor(app): 原子迁移生成通知协调与前台端口`（计划第 13 节固定文案）
- post-commit hook 自动 bump 版本并 amend 并回本次提交（refactor → patch+1，3.76.19 → 3.76.20）。
- 变更范围：11 个文件（与 brief 文件清单完全一致），+1069 / -793。

## 改动内容

### coordinator（lib/app/composition/chat_generation_notification_coordinator.dart）

- 构造函数新增必填 `notificationSessionId` 与 `ChatGenerationTerminalNotifications terminalNotifications`；provider 读取 Task 2 的 `chatGenerationNotificationSessionIdProvider` 与 `chatGenerationTerminalNotificationsProvider`，未现场生成第二个 session。
- 散落的 per-token 字段收进私有 `_NotificationGenerationContext`（token、conversationId、lastDelivered*、lastCounts、pendingTimer/Projection、tokenUnavailable、timedOut、terminalEnqueued、stopInFlight）。新 token 只替换 `_currentContext`；旧 context 由已入队 closure 持有直到 FIFO 完成。
- `onStateChanged` 按 6.2 固定顺序：
  - 入口 token 校验；更小 token 迟到快照拒绝；更大 token 创建新 context 并只作废旧 context 的未触发尾缘定时器（不取消已入队 operation）。
  - `phase.isTerminal` 时先用 `projectChatGenerationTerminalReceipt(sessionId, snapshot, context.lastCounts)` 得 nullable 收据，terminal 每 context 只入队一次，总是取消 pending timer；closure 捕获 context/receipt/conversationId/skipRemove，执行时不比较 `_currentContext`。
  - `skipRemove=false` 先 `_port.remove`（沿用三次 ACK 重试 [0/200ms/800ms]，重试只受 dispose 取消）；成功或耗尽后都 report；cancellation receipt 为 null 只 cleanup；timeout 已清理时 cancelled 为完全 no-op、真正终态跳过 remove 直接 report；report 契约外抛错兜底为 `terminal_report_failed` 固定诊断。
  - 非终态才调用 projector；`timedOut/tokenUnavailable/terminalEnqueued` 抑制尚未入队的 start/update。
  - 尾缘定时器回调先校验「捕获 context 仍 current 且未终态」再入队；operation 一旦入队不再做 current-token 校验，ACK 只写回捕获 context。
- timeout action（6.3）：仅当前 token 且未终态时受理；置 `timedOut`、取消挂起更新、**不调 remove**（避免 MethodChannel 内 Kotlin 重入）、不 stop/cancel/retry/finalize；用同 session + `context.lastCounts` 构造 `foregroundProtectionTimedOut` 收据并把 report 加入同一 async tail；重复 timeout 幂等。
- 7 秒上界写入 `_terminalOp` 注释：3 × 2s channel timeout + 200ms + 800ms = 7s，并注明 tail 前置在途命令需另加等待；测试以 fake 时间锁定该值。

### ongoing projector（chat_generation_notification.dart）

- 删除 `ChatGenerationNotificationTerminalBehavior`、projection 的 `terminalBehavior` 字段、`summarizeChatGenerationNotificationError()`、`_errorTextFor`、`_errorPublicCopy` 及只为错误摘要存在的 `dart:async`/`dart:io`/`chat_error_messages.dart`/`chat_generation_client.dart` imports。
- 只接受 preparing/streaming/retryWaiting/stopping/finalizing；对 idle 和全部 terminal phase 抛 `ArgumentError`（coordinator 保证不调用）。
- 新增必填 `notificationSessionId`；`ChatGenerationForegroundPayload` 增加 `timeoutActivationPayload`（由共享 `ChatGenerationNotificationPayloadCodec` 按 `v1:<session>:<token>:foregroundProtectionTimedOut` 预编码的三键 v1 JSON）。字数、截断、ongoing 文案、action 全部保持不变。

### 前台端口瘦身

- `ChatGenerationForegroundServicePort` 删除 `fail()`；保留 ensureNotificationPermission/start/update/remove/takePendingOpenConversation/actions/dispose；`ChatGenerationOpenConversationRequested` doc 明确仅供 Android ongoing 点击，不得用于新终态通知。
- `AndroidChatGenerationForegroundService` / `NoopChatGenerationForegroundService` 同步删除 `fail()` 实现（Android 的 `failForegroundGeneration` 方法编码随之移除；Kotlin 侧按计划留给 Task 5 一并删除）。
- 无 deprecated shim；`rg TerminalBehavior|summarizeChatGenerationNotificationError|failForegroundGeneration lib test` 零残留。

## 测试（全部简体中文标题）

新增/改写 coordinator 测试（33 例全绿），覆盖 brief 全部 13 个 RED 契约：

| brief RED 测试 | 对应实现 |
| --- | --- |
| 成功先清理 ongoing 再报告终态 | sharedLog 断言 `['remove','report:succeeded:1']` 顺序 |
| 三次 cleanup channel timeout 与退避使 report 最晚在 7 秒执行 | fake 时间记账：3×2s+200ms+800ms 恰为 7s，report 在耗尽后才执行，未真实等待 |
| 空回复失败和持久化失败都清理 ongoing | 参数化两 token |
| 取消只清理不报告 | remove 一次、receipts 空 |
| 中间重试不清理也不报告 | retryWaiting 零清理零报告 |
| 成功终态使用完整 outcome 计数而 timeout 使用最后安全计数 | success 重算 5/2 vs timeout fallback 3/1 |
| 保护超时只报告且不调用 remove 或停止生成 | receipts 单条 foregroundProtectionTimedOut、零 remove、零 stop |
| 保护超时后真正终态仍报告且不重复清理 | succeeded 双报告零 remove；cancelled 完全 no-op |
| terminal report 失败不毒化 coordinator | 抛错 fake → `terminal_report_failed`，下一 token 正常 |
| 尚未入队的旧 token terminal 和 timeout 被拒绝 | 入口拒绝 + stale_native_action |
| token1 terminal 入队后 token2 启动仍按 FIFO 完成 | sharedLog `['start:1','remove','report:succeeded:1','start:2']` |
| token1 ACK 迟到只修改 token1 context 不毒化 token2 | 迟到失败后 token2 start/update 照常 |
| ongoing warm 与 pending 点击仍转发到现有 openConversation 回调 | warm 流 + 冷启动 pending 双路径回归 |

projector 测试重写：5 个 ongoing 阶段映射表、idle+5 终态阶段显式拒绝（参数化）、预编码 timeout payload 精确 JSON 断言、不同 session 不同 event key、字数统计与长度上限保留。集成测试改为断言 remove + 终态收据（注入 FakeTerminalNotifications 经真实 Riverpod wiring 观测），bindings/platform/noop 测试同步移除 fail。

## 验证证据（logs/）

| 日志 | 结果 |
| --- | --- |
| `logs/terminal-coordinator-red.log` | EXIT=1（编译失败证明新契约尚不存在，RED 证据） |
| `logs/terminal-coordinator-green.log` | EXIT=0，33 例全过 |
| `logs/terminal-projector-green.log` | EXIT=0，17 例 |
| `logs/terminal-platform-adapters-green.log` | EXIT=0，18 例 |
| `logs/terminal-bindings-green.log` | EXIT=0，8 例 |
| `logs/terminal-integration-green.log` | EXIT=0，10 例 |
| `logs/fltest.log` | EXIT=0，全量 2207 例通过 |
| `logs/analyze-terminal-notifications.log` | No issues found |
| `logs/import-boundaries-terminal-notifications.log` | 403 文件，0 违规 |
| `logs/terminal-postformat-check.log` | 格式化后复跑核心两文件 EXIT=0 |

提交前已完成 `dart format` + `dart format --output=none --set-exit-if-changed`（EXIT=0）与 `git diff --cached --check`（干净）。

## 设计取舍说明

- **执行期不做 current-token 校验**：入队后的 start/update/remove/report 一律 FIFO 执行到底；唯一保留的执行期抑制是 `tokenUnavailable`（同 token 前序命令把通道判死后不再向死通道重试），这是通道级 fail-open 经济性，不属于被新 token 取消的语义。
- **`timeoutActivationPayload` 设为可空 String?**：共享 codec 编码失败时（session/conversationId 违反 invariant 的防御路径）返回 null，原生侧按协议不符拒绝即可 fail-open；正常路径 session 为合法 hex、conversationId 合法，恒非空。Task 4 再把它加入 Android wire 编码。
- **projector import 共享 codec**：`features/chat/application` 引用 `package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart`。import boundaries 工具无此方向禁令（0 违规），且计划 6.4 明确 projector 必填 sessionId、payload 由共享 Dart codec 预编码——单一 codec 是 Kotlin 不复刻 JSON/FNV/session 规则的前提。
- **重复 timeout 幂等**：同一 context 第二次 timeout 动作静默忽略（收据只会入队一次），即使默认深模块的 eventKey 去重也能兜底。

## Concerns

- 无阻塞性 concern。Task 4 需记得把 `timeoutActivationPayload` 加入 Android adapter 的 start/update wire 编码（本任务按计划未传，Kotlin runtime 未消费该键）。
