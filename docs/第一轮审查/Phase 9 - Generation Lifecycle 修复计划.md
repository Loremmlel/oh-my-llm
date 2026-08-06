# Phase 9 - Generation Lifecycle 修复计划

## 一、结论

本轮不再继续围绕当前 bridge 添加局部 guard。建议对 **generation orchestration 层做一次有边界的重写**，但不重写聊天模块。

保留：

- `chatSessionsProvider` 及 presentation 使用的公开 command/provider；
- 消息树、分支编辑、Prompt 拼接、checkpoint context 等既有纯函数；
- `ChatCompletionClient`、`ChatConversationRepository` 及 Phase 4 durable persistence contract；
- inline error、empty reply、异常 `finish_reason`、输出正则和 retry 的产品语义；
- ChatScreen、SQLite schema、同步与设置模块。

替换：

- `ChatGenerationCoordinator` 与 `ChatSessionsController` 之间由 `void` observer、多个 nullable bridge 字段和异步 event handler 组成的 generation bridge；
- controller 内的 `_coordinatorCompleter`、`_pendingSaveFuture`、`_stoppedSaveFuture`、`_coordinatorGenerationId` 等并列生命周期事实源；
- `stopStreaming()` 根据 `hasActive`、nullable completer 和 state phase 猜测当前阶段的分支。

这不是全量推倒重来。实际需要重新设计的是 chat application 中“一次 generation 从 preparing 到 durable terminal”的窄边界。现有纯业务函数和外围接口应原样复用，以控制风险。

## 二、问题是否会在真实应用触发

这些问题不是只为满足测试而扣细节，但触发概率不同。

| 问题 | 用户侧触发方式 | 现实性 | 影响 |
|---|---|---:|---|
| preparing stop 后旧写入覆盖新 generation | 用户发送后立刻停止，并在后台 80ms debounce/ACK 尚未完成时快速发送下一条 | 高 | 内存显示 A+B，重启后 B 消失；属于数据丢失 |
| stopping 期间并发第二次 stop | 快速双击、键盘和按钮同时触发、多个 presentation command 同时调用 | 中 | 第一次 stop 在 durable save 前返回，可能重复保存并错误放行下一 command |
| attempt helper 与 terminal decision 间 stop | stream 刚结束时触发 stop，或状态 listener/自动化在 `isStreaming=false` 后调用 stop | 低，但可达 | success/cancelled 两条终态并发，snapshot identity 损坏并可能重复保存 |
| preparing attempt/outcome identity 不一致 | pending 或 preparing-stop 保存失败 | 中 | 当前主要影响诊断和后续消费者；会让 lifecycle contract 不可信 |

其中第一项是明确的用户数据一致性问题，不能接受。第二、三项虽然窗口较窄，但它们证明“终态只能提交一次”和“公开 Future 完成即 durable”并没有由结构保证。只要后续 Phase 10 增加新的 command consumer，这些窗口更容易暴露。

## 三、为什么越修越出现新问题

问题不是 Flutter 或 Riverpod 特有，而是当前实现存在多个并列的生命周期 owner：

1. coordinator 用 `_GenerationHandle.isActive/outcome/phase` 判断网络与 retry 生命周期；
2. controller 用 `ChatGenerationSnapshot.phase` 判断 UI busy；
3. legacy `isStreaming/isAutoRetryWaiting` 控制旧 UI；
4. `_coordinatorCompleter` 决定公开 command 是否完成；
5. `_pendingSaveFuture`、`_stoppedSaveFuture` 各自代表一部分 durable checkpoint；
6. `_handleGenerationEvent()` 是异步的，但 observer contract 是 `void`，coordinator 不会等待 controller 完成本次投影就可以继续处理 stop 或下一事件。

因此一次逻辑转换不是一个原子动作。例如 attempt success 实际分成：coordinator 先投 `AttemptCompleted`、controller helper 改 state、async continuation 再进入 `finalizing`、保存、完成 completer、最后 finalize handle。任何两个步骤之间都可能插入 stop/dispose/new command。

之前的修复大多只保护已发现的某一个 await 之后：

- 增加 dispose guard 只解决 dispose，不解决 stop 或 run replacement；
- 跳过 finalizing stop 只覆盖进入 `finalizing` 之后，不覆盖 helper 到 decision 的间隙；
- preparing stop 加 await 解决了错误可观察性，却先投 `cancelled` 解除 busy，反而允许新 run 与旧 pending write 并发；
- 测试通常复现上一条具体时序，没有验证整套状态机不变量及所有事件交叉组合。

所以不是“每修一个随机生出一个新 bug”，而是同一个结构性缺陷在不同 interleaving 下反复显现。继续添加布尔条件会把状态空间变得更大。

## 四、必须成立的不变量

新实现先以以下不变量为设计输入，任何实现选择不得破坏它们：

1. **单一 owner**：一次 generation 的 token、phase、attempt、停止意图、terminal outcome、公开完成 Future 和 checkpoint 队列只能由一个 run 对象拥有。
2. **单一终态提交**：每个 run 只能从 non-terminal 转入一个 terminal outcome；success、cancelled、failure 和 persistence failure 不能并发提交。
3. **串行事件**：同一 run 的 preparing、chunk flush、attempt completion、retry、stop 和 terminal persistence 必须经同一个串行执行通道处理。
4. **完成即 durable**：`sendMessage/edit/retry/stopStreaming` 对外 Future 完成时，该 run 要求的最后一个 durable checkpoint 已成功，或已明确进入 `persistenceFailed`。
5. **旧 run 不与新 run 写入交叉**：旧 run 未完成 terminal checkpoint 前，新 generation command 必须被 busy guard 拒绝；不能先解除 busy 再在后台补保存。
6. **stop 幂等**：第一次 stop 只记录一次停止意图；后续 stop 返回同一个 completion Future，不重复生成 stopped snapshot，不重复保存。
7. **finalizing 不可取消**：attempt 已确定终态后，stop 只等待该终态完成，不把 success/failure 改成 cancelled。
8. **token 全程稳定**：token 在进入 preparing 前分配；attempt 从 1 开始；snapshot 与 outcome 的 generation/attempt identity 必须相等。
9. **每次 await 后验证 run**：host 侧任何 state 投影都同时验证 controller 未 dispose 且 run token 仍为当前 token。
10. **兼容字段只做投影**：`isStreaming`、`isAutoRetryWaiting`、`autoRetryCount` 只能从 run snapshot 投影，不参与生命周期决策。

## 五、目标设计

### 5.1 一个 run 贯穿完整生命周期

引入 coordinator 内部的 `_ChatGenerationRun`。它从 command 被接受开始，一直存活到 terminal checkpoint 完成，至少拥有：

- `generationId`、`attempt`、immutable request/context；
- 当前 phase 和 cancellation intent；
- stream subscription、retry timer；
- response/reasoning buffer；
- 只完成一次的 `Completer<ChatGenerationResult>`；
- 一个串行 command/event queue；
- terminal commit guard。

`hasActive` 的含义改为“存在尚未完成的 run”，而不是“stream token 还接受 chunk”。`preparing`、`stopping` 和 `finalizing` 都必须保持 active/busy。

### 5.2 用 awaitable host contract 替代 void observer

coordinator 仍不操作 Riverpod、消息树或 repository，但 controller 不再接收 fire-and-forget typed event。定义最小的 awaitable host contract，例如：

```dart
abstract interface class ChatGenerationHost {
  Future<ChatPreparedGeneration> prepare(ChatGenerationCommand command);
  Future<ChatAttemptDecision> completeAttempt(ChatAttemptSnapshot attempt);
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial);
  void projectProgress(ChatGenerationProgress progress);
}
```

具体命名可调整，关键是 `prepare/completeAttempt/stop` 返回的 Future 必须由 coordinator await。chunk 的 UI progress 可以保持同步节流投影，但 terminal decision 和 persistence 不能脱离 run 的串行控制流。

host 返回 typed result，不直接让 coordinator读取 controller state：

- `prepare` 返回 durable 保存后的 request snapshot，失败返回 persistence failure；
- `completeAttempt` 复用现有消息树/output processing helper，返回 success/retry/failure 及已 durable 的 conversation result；
- `stop` 构造 stopped conversation 并等待 durable save，返回 cancelled 或 persistence failure；
- 所有 host 方法捕获 generation token，并在每次 await 前后验证 token/dispose。

### 5.3 stop 只向 active run 发命令

`stopStreaming()` 退化为 facade：

```dart
Future<ChatConversation?> stopStreaming() => _coordinator.stop();
```

期望语义：

- 无 run：返回当前会话，不清除 unrelated error/empty marker；
- preparing：记录 stop intent，等待正在执行的 pending checkpoint，然后串行写 stopped checkpoint；不启动网络；
- streaming：先 invalidate chunk token/cancel subscription，再在 run queue 中写一次 stopped checkpoint；
- retryWaiting：取消 timer，写一次 cancelled checkpoint；
- stopping：返回同一个 run completion Future；
- finalizing：不改变 outcome，返回同一个 run completion Future；
- terminal/done：返回已完成结果。

controller 不再自行 complete generation completer，也不再根据 coordinator `hasActive` 与 nullable bridge 字段推断 preparing。

### 5.4 persistence 必须属于 run 的串行路径

每个 run 的关键保存顺序固定为：

```text
pending checkpoint
  -> attempt/retry checkpoints（0..n）
  -> exactly one terminal checkpoint
  -> complete public Future
  -> release busy / allow next run
```

同一 run 不允许两个 `saveConversationDurable` 并行。新 run 只能在旧 run completion 后开始，因此无需依赖 repository 是否天然保证跨 Future 的写入顺序。

后台 repository 的 debounce 合并仍保留；本计划不修改 Phase 4 data contract。

### 5.5 state projection 收口

增加一个纯投影函数，把 `ChatGenerationSnapshot` 映射到 compatibility flags：

```dart
ChatSessionsState projectGeneration(
  ChatSessionsState current,
  ChatGenerationSnapshot snapshot,
)
```

业务路径不再单独写 `isStreaming/isAutoRetryWaiting/autoRetryCount`。debug/test 环境增加 invariant assertion：

- busy phase 与 compatibility flags 对应；
- terminal phase 与 outcome subtype 对应；
- snapshot/outcome 的 generationId、attempt 相同；
- terminal snapshot 必须有 outcome，non-terminal snapshot 不得有 outcome。

## 六、实施步骤与提交边界

### Task 1：先补状态机与竞态契约测试

只增加测试，不改生产代码。用 controllable repository 在“真正写入前”设置 gate，不能像现有部分 fake 那样先写 inner repository 再 gate。

必须先加入以下失败用例：

1. A preparing stop，立即发送 B：B 在 A terminal durable 前被 busy guard 拒绝；A 不会晚于 B 写入。
2. streaming stop save 被 gate 阻塞时并发调用两次 stop：两次 Future 都不提前完成，只发生一次 terminal save。
3. attempt completed 到 terminal projection 的任意时点调用 stop：最终只有原 attempt outcome，无 cancelled save。
4. finalizing stop：等待原 terminal completion，不改变 outcome。
5. stop save/pending save/terminal save 分别失败：只得到一次 persistence failure。
6. A 所有迟到 chunk/error/done/host continuation 均不能写 B state 或完成 B Future。
7. preparing snapshot、terminal snapshot 与 outcome identity 一致，attempt 从 1 开始。

提交建议：`test(chat): define serialized generation run contract`

### Task 2：实现独立 run 与串行生命周期

在不接入 controller 的情况下实现新 run/coordinator，用 fake host 覆盖完整 transition matrix。不要复用现有 bridge nullable 字段。

覆盖：normal success、empty、failure、retry、preparing stop、streaming stop、retry-wait stop、concurrent stop、finalizing stop、dispose、persistence failure、late callback。

提交建议：`refactor(chat): serialize generation lifecycle in a single run`

### Task 3：接入 preparing 与普通 success/error

controller 实现 awaitable host，复用现有 request builder、消息树和 finish helper。先迁移 send 的 preparing、streaming、success/error，不接 retry/stop 的复杂分支。

每个 host 调用显式接收 token，不从共享 nullable bridge 字段恢复上下文。上下文放入 immutable `ChatPreparedGeneration`/run context。

提交建议：`refactor(chat): connect controller to generation run host`

### Task 4：迁移 retry 与 stop

把 retry timer、attempt reset、stop intent 和 terminal persistence 全部交给 run。`stopStreaming()` 只调用 coordinator；删除 controller 的 preparing/stopping/finalizing 特判。

提交建议：`refactor(chat): route retry and stop through generation run`

### Task 5：删除旧 bridge 与双写字段

删除：

- `_coordinatorCompleter`；
- `_pendingSaveFuture`；
- `_stoppedSaveFuture`；
- `_coordinatorStreamingConversation/_coordinatorAssistantMessage` 等可由 run context 持有的字段；
- `_handleGenerationEvent()` 及 `void ChatGenerationObserver`；
- controller 对 compatibility lifecycle bool 的业务性写入。

用 `rg` 确认 controller 不再持有 generation Future/completer/subscription/timer，也不根据多个信号猜 phase。

提交建议：`refactor(chat): remove legacy generation bridge ownership`

### Task 6：集成验证与范围审计

按顺序运行：

1. lifecycle/coordinator 单元测试；
2. controller generation/stop/retry/persistence contract tests；
3. `test/integration/chat_lifecycle_integration_test.dart`；
4. `flutter analyze`；
5. 按 `AGENTS.md` 重定向运行全量测试；
6. `dart format --output=none --set-exit-if-changed` 检查所有改动 Dart 文件。

提交建议：`test(chat): verify durable generation lifecycle integration`

## 七、禁止的修复方式

本轮明确禁止：

- 再增加 `_isStopping`、`_terminalSaveInFlight`、`_stopRequestedDuringPreparing` 一类布尔字段；
- 在更多 await 后零散添加 `identical(completer, ...)`；
- 用 `Future.delayed`、debounce 时长或 UI 按钮禁用掩盖竞态；
- 假设 repository 会自动按调用顺序完成并发写入；
- 让 controller 和 coordinator 各自持有一份 phase/outcome；
- 为通过测试而禁止快速发送或延长 stop 返回时间，却没有建立 completion/durable contract；
- 顺便重写 ChatScreen、消息树、repository、schema 或 Phase 10+ 内容。

## 八、验收标准

- [ ] coordinator/run 是 token、phase、attempt、stop intent、terminal outcome 和 completion Future 的唯一 owner。
- [ ] controller 不再持有 generation completer、pending/stop save Future 或 stream/retry handle。
- [ ] 同一 run 的关键 persistence 严格串行，terminal checkpoint 恰好一次。
- [ ] old run terminal durable 完成前，新 generation command 不会开始。
- [ ] concurrent stop 返回同一个 completion 语义，不提前完成、不重复保存。
- [ ] stop 在 finalizing 或 attempt 已 settled 后不能覆盖既定 outcome。
- [ ] snapshot、outcome identity 和 compatibility flags 的 invariant tests 全部通过。
- [ ] 所有可控 race tests 不依赖毫秒级 timing，且修复前稳定失败、修复后稳定通过。
- [ ] 原有消息树、Prompt、Reasoning、inline error、retry 与 finish reason 产品测试不变并通过。
- [ ] `flutter analyze`、相关测试、集成测试和全量测试全部通过。

## 九、是否需要整个重写

不需要重写整个聊天功能。消息树、请求构造、输出处理、repository 和 UI 并不是这些竞态的根因，重写它们只会扩大回归面。

但当前 generation bridge 已经不适合继续小修。它违反了 Phase 9 最核心的目标：coordinator 应是 generation 时序的唯一 owner，而现在 controller 仍共同拥有 completer、checkpoint Future、phase 和 terminal decision。最稳妥的选择是保留外围合同，平行实现一个单 run、串行、awaitable host 的新 orchestration，契约测试通过后一次切换，再删除旧 bridge。

这属于局部重写，而不是大爆炸重构。
