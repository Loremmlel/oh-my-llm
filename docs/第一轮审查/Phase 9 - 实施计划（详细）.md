# Phase 9 Generation Lifecycle - 详细实施计划

> 依据《Phase 9 - Generation Lifecycle 修复计划》文档，细化为可执行的代码级方案。
> 目标：一次性消除 generation 时序竞态，建立**单一 owner 的串行生命周期**。
> 已确认决策：① 合并文档 Task 3+4 为一次切换；② Task 1 契约测试写好后 `skip`，Task 3 切换后启用。

---

## 一、根因确认（与文档一致，简述）

当前 generation 生命周期由 **6 个并列 owner** 维护：

1. coordinator `_GenerationHandle` 的 `isActive/outcome/phase`（网络与 retry 生命周期）
2. controller `state.generation.phase`（UI busy）
3. 兼容 bool `isStreaming/isAutoRetryWaiting`（旧 UI）
4. `_coordinatorCompleter`（公开 command 是否完成）
5. `_pendingSaveFuture` / `_stoppedSaveFuture`（两部分 durable checkpoint）
6. `_handleGenerationEvent()` 是 async，但 `ChatGenerationObserver.onGenerationEvent` 是同步 `void`——coordinator 不等 controller 完成投影即可继续投下一事件 / 接 stop。

一次逻辑转换（如 attempt success）被拆成多个非原子步骤（coordinator 投 `AttemptCompleted` → controller helper 改 state → async continuation 进 `finalizing` → 保存 → complete completer → finalize handle），任意 await 让出点都可能插入 stop / dispose / new command。之前的局部 guard 只堵已发现的窗口（dispose guard、finalizing skip、preparing await…），堵不住交叉组合，于是"修一个冒一个"。

**结论**：对 generation orchestration 的窄边界做有边界的重写；外围合同（消息树、Prompt 拼接、`ChatCompletionClient`、`ChatConversationRepository`、Phase 4 durable contract、inline error、retry 语义、UI、schema）原样复用。

---

## 二、关键设计决策

### 决策 1：合并文档 Task 3 + Task 4 为一次切换
preparing / streaming / attempt / retry / stop 共享同一个 run 状态机、同一个 completion Future、同一组 bridge 字段，**无法干净地半接入**。半接入会让新旧两套 completer/字段并存，反而引入新竞态。一次切换 + 契约测试兜底，符合"一次性解决"诉求。

### 决策 2：Task 2 新建独立文件 `chat_generation_run.dart`，旧 coordinator 文件不动
Task 2 期间新 run + host 接口独立存在、用 fake host 覆盖 transition matrix；旧 coordinator / observer 继续工作、controller 继续用旧路径，**主线全绿**。Task 3 一次切换时重写 coordinator 为 run owner、controller 实现 host、删旧。Task 2 的提交因此可独立成立。

### 决策 3：串行执行用 Future 链，不引入并发原语
run 内部维护 `_tail: Future<void>`，preparing / completeAttempt / stop / retry-fire / terminal-commit 都经 `_serialize(action)` 排队。chunk 的 UI 投影 `projectProgress` 保持同步节流（不入队），与文档 5.2 一致。

### 决策 4：去掉 coordinator 的 supersede 路径，靠 busy guard 保证一次一 run
不变量 5（旧 run terminal durable 完成前新 command 被拒）由 controller `_isBusy`（从 `phase.isBusy` 派生）保证。coordinator 同一时刻只有一个 run，新 command 来时若 active 直接被 controller 拒绝；**dispose 是唯一取消 current run 的路径**。消除 supersede 交叉写入的整类问题，大幅收缩状态空间。

### 决策 5：Task 1 契约测试写好、本地验证 red、提交时 `skip`
项目 CI 要求提交绿。端到端竞态测试在修复前必然 red（它们就是要暴露的 bug）。做法：写成测试 → 本地手动跑确认 red（确实验证 bug）→ `skip: '待 Task 3 串行 run 切换后启用'` 提交。Task 3 完成后 unskip 验证 green。每提交都绿，且保留 TDD 红基线价值。

### 决策 6：兼容 bool 改为纯投影，但保留 `ChatSessionsState` 字段
`isStreaming/isAutoRetryWaiting/autoRetryCount` 仍存在（presentation 直接消费），但改为由 `projectGeneration` 从 `snapshot.phase` 单向派生，业务路径不再单独 `copyWith` 这些 bool。不改 presentation 消费方，控制范围。

---

## 三、新设计形态

### 3.1 `ChatGenerationHost` 接口（`chat_generation_lifecycle.dart` 新增）

awaitable host contract。coordinator await 这三个 Future，typed result 不让 coordinator 读 controller state：

```dart
/// generation 时序的唯一消费方。controller 实现此接口。
/// prepare/completeAttempt/stop 返回的 Future 由 coordinator await，
/// terminal decision 与 persistence 不脱离 run 的串行控制流。
abstract interface class ChatGenerationHost {
  /// 创建占位 assistant、追加到树、写 preparing snapshot、durable pending checkpoint。
  /// 返回 durable 后的 request snapshot + run context；失败返回 persistence failure。
  Future<ChatPrepareResult> prepare(ChatGenerationCommand command);

  /// attempt 终态决策：复用 finishGenerationSuccess/Error + durable save。
  /// 返回 success / outputRuleFailed / retry(已 durable intermediate) /
  /// giveUp(retry 耗尽) / persistenceFailed。
  Future<ChatAttemptDecision> completeAttempt(ChatAttemptSnapshot attempt);

  /// 构造 stopped conversation + durable save，返回 cancelled / persistenceFailed。
  /// preparing/streaming/retryWaiting 三种 phase 统一经此落盘。
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial);

  /// chunk 的 UI 投影，同步 300ms 节流（不入串行 queue）。
  void projectProgress(ChatGenerationProgress progress);
}
```

配套 typed 类型（均 `Equatable`，放 `chat_generation_lifecycle.dart`）：

```dart
class ChatGenerationCommand { /* conversation/modelConfig/presetPrompt/
  requestConversationMessages/requestCheckpointChain/parentMessageId/
  reasoningEnabled/reasoningEffort/appliedCheckpointTitle/retryDelay */ }

sealed class ChatPrepareResult {}
class ChatPrepareSuccess extends ChatPrepareResult {
  final ChatGenerationRequest request;       // 已构建的 5 步拼接请求
  final ChatConversation streamingConversation;
  final ChatMessage assistantMessage;
  final ChatStreamingReply streamingReply;
}
class ChatPrepareFailure extends ChatPrepareFailure { final Object error; }

class ChatAttemptSnapshot { /* generationId/attempt/attemptOutcome(success|empty|
  failure)/content/reasoning/finishReason/streamingConversation/assistantMessage/
  streamingReply/retryPolicy */ }

sealed class ChatAttemptDecision {}
class ChatAttemptSucceed extends ChatAttemptDecision { final ChatConversation conversation; }
class ChatAttemptOutputRuleFailed extends ChatAttemptDecision { final ChatConversation conversation; }
class ChatAttemptRetry extends ChatAttemptDecision {}        // intermediate 已 durable
class ChatAttemptGiveUp extends ChatAttemptDecision { final ChatGenerationOutcome terminalOutcome; }
class ChatAttemptPersistenceFailed extends ChatAttemptDecision { final Object error; }

class ChatPartialSnapshot { /* content/reasoning/streamingConversation/
  assistantMessage/streamingReply/phase(preparing|streaming|retryWaiting) */ }

sealed class ChatStopDecision {}
class ChatStopCancelled extends ChatStopDecision { final ChatConversation conversation; }
class ChatStopPersistenceFailed extends ChatStopDecision { final Object error; }

class ChatGenerationProgress { final ChatStreamingReply streamingReply; }
```

> 这些类型替代旧 `ChatGenerationEvent` 体系。旧 event 类（`ChatGenerationStarted/Chunk/...`）在 Task 3 切换后随旧 observer 一并删除。

### 3.2 `ChatGenerationRun`（新文件 `chat_generation_run.dart`）

一次 generation 的完整生命周期 owner。纯逻辑，依赖 `ChatCompletionClient` + `ChatGenerationHost`，不依赖 Riverpod：

```dart
class ChatGenerationRun {
  final int generationId;            // preparing 前分配，全程稳定
  final ChatCompletionClient client;
  final ChatGenerationHost host;
  final ChatGenerationCommand command;

  Completer<ChatConversation?> _completion = Completer();
  StreamSubscription<ChatCompletionChunk>? _subscription;
  Timer? _retryTimer;

  // ── 串行执行通道：所有 awaitable 操作排队，保证单一终态、串行持久化 ──
  Future<void> _tail = Future.value();
  Future<void> _serialize(Future<void> Function() action) {
    final done = Completer<void>();
    _tail = _tail.then((_) async {
      try { await action(); done.complete(); }
      catch (e, s) { done.completeError(e, s); }
    });
    return done.future;
  }

  ChatGenerationPhase phase = ChatGenerationPhase.preparing;
  bool _stopIntent = false;
  ChatGenerationOutcome? _outcome;   // 非 null 即已 terminal（单一终态 guard）
  int attempt = 1;
  String _content = '', _reasoning = ''; String? _finishReason;
  /* ctx: streamingConversation/assistantMessage/streamingReply 由 prepare 填充 */

  Future<ChatConversation?> get completion => _completion.future;

  void start() => _serialize(_prepare);

  Future<void> _prepare() async {
    phase = ChatGenerationPhase.preparing; _project();
    final r = await host.prepare(command);
    if (r is ChatPrepareFailure) { _terminalPersistenceFailed(r.error); return; }
    /* 保存 ctx */
    if (_stopIntent) { await _doStop(); return; }   // preparing 期间被 stop：不启动网络
    phase = ChatGenerationPhase.streaming; _project();
    _subscription = client.streamCompletion(...).listen(
      (c) { if (_outcome != null) return;        // terminal 后丢弃迟到 chunk
            _content += c.contentDelta; _reasoning += c.reasoningDelta;
            if (c.finishReason != null) _finishReason = c.finishReason;
            host.projectProgress(...); },          // 同步节流，不入队
      onDone: () => _serialize(_completeAttemptFromDone),
      onError: (e, s) => _serialize(() => _completeAttemptFromError(e, s)),
      cancelOnError: false,
    );
  }

  Future<void> _completeAttemptFromDone() async {
    if (_outcome != null) return;                  // 拦截 onError 后的迟到 onDone
    final outcome = _content.trim().isEmpty && _reasoning.trim().isEmpty
        ? ChatGenerationEmptyReply(...) : ChatGenerationSuccess(...);
    await _settleAttempt(outcome);
  }

  Future<void> _settleAttempt(ChatGenerationOutcome attemptOutcome) async {
    final d = await host.completeAttempt(/* snapshot: attemptOutcome + buffer + ctx */);
    switch (d) {
      case ChatAttemptSucceed(:final conversation): _terminal(ChatGenerationPhase.succeeded, conversation);
      case ChatAttemptOutputRuleFailed(): _terminal(ChatGenerationPhase.failed, null, outcome=Failure(outputRule));
      case ChatAttemptRetry():
        if (_canRetry()) { attempt++; phase = retryWaiting; _project();
          _retryTimer = Timer(_delay(), () => _serialize(_startNextAttempt)); }
        else _terminal(_retryExhausted(attemptOutcome));   // success->Failure, 其余保留
      case ChatAttemptGiveUp(:final terminalOutcome): _terminal(...);
      case ChatAttemptPersistenceFailed(:final e): _terminalPersistenceFailed(e);
    }
  }

  /// stop：幂等。第一次记录 intent + 入队；后续直接返回同一 completion。
  void requestStop() {
    if (_outcome != null || _stopIntent) return;
    _stopIntent = true;
    _serialize(() async {
      if (_outcome != null) return;        // finalizing 期间 stop：completeAttempt 已在前序 terminal，no-op
      _subscription?.cancel(); _retryTimer?.cancel();
      final d = await host.stop(/* partial: buffer + ctx + phase */);
      switch (d) {
        case ChatStopCancelled(:final conversation): _terminal(cancelled, conversation);
        case ChatStopPersistenceFailed(:final e): _terminalPersistenceFailed(e);
      }
    });
  }

  void _terminal(ChatGenerationPhase p, ChatConversation? conv, {ChatGenerationOutcome? outcome}) {
    if (_outcome != null) return;         // 单一终态提交
    _outcome = outcome ?? _attemptOutcome; phase = p; _project();
    _subscription?.cancel(); _retryTimer?.cancel();
    if (!_completion.isCompleted) _completion.complete(conv);
  }

  void dispose() { /* cancel sub/timer; complete(null) if not completed */ }
}
```

**关键不变量如何被结构保证**：

| 不变量 | 结构保证 |
|---|---|
| 单一 owner | run 拥有 token/phase/attempt/stopIntent/outcome/completion/串行 queue |
| 单一终态提交 | `_terminal` 首行 `if (_outcome != null) return` |
| 串行事件 | `_serialize` Future 链；prepare/completeAttempt/stop/retry-fire 全排队 |
| 完成即 durable | `_terminal` 只在 host 方法（prepare/completeAttempt/stop）返回后调用；host 内部 await `saveConversationDurable` |
| 旧 run 不与新 run 交叉 | coordinator 一次一 run（决策 4）；新 command 被 controller `_isBusy` 拒 |
| stop 幂等 | `requestStop` 首 `if (_outcome != null || _stopIntent) return`；二次返回同一 `completion` |
| finalizing 不可取消 | stop action `if (_outcome != null) return`；completeAttempt 已在前序 terminal |
| token 全程稳定 | `generationId` 构造时分配，attempt 从 1 开始，host 方法携带 |
| 每次 await 后验证 run | host（controller）每次 await 后查 `identical(_currentRun, run) && !_disposed` |
| 兼容字段只做投影 | `projectGeneration` 从 phase 单向派生（决策 6） |

### 3.3 `ChatGenerationCoordinator`（Task 3 重写为 run owner）

```dart
class ChatGenerationCoordinator {
  final ChatCompletionClient _client;
  ChatGenerationRun? _currentRun;
  bool _disposed = false;
  int _nextGenerationId = 1;

  /// 启动新 run。调用方（controller）保证：已通过 busy guard，无 active run。
  Future<ChatConversation?> start(ChatGenerationCommand command, ChatGenerationHost host) {
    final run = ChatGenerationRun(
      generationId: _nextGenerationId++,
      client: _client, host: host, command: command,
    );
    _currentRun = run;
    run.start();
    return run.completion;
  }

  /// stop facade：无 run 返回同步空结果；有 run 记录 intent + 返回同一 completion。
  Future<ChatConversation?> stop() {
    final run = _currentRun;
    if (run == null) return Future.value(null);   // 无 run：controller 返回 activeConversation
    run.requestStop();
    return run.completion;
  }

  bool get hasActive => _currentRun != null && _currentRun!._outcome == null;
  Future<ChatConversation?>? get currentCompletion => _currentRun?.completion;

  void dispose() { _disposed = true; _currentRun?.dispose(); _currentRun = null; }
}
```

> 旧 `ChatGenerationObserver` / `_GenerationHandle` / `start(request, observer, generationId:)` / `scheduleRetry` / `finalize` / `markPersistenceFailure` / `stop()` 全部删除。`ChatGenerationEvent` 体系删除。

### 3.4 `projectGeneration` 纯函数（Task 4）

```dart
/// 从 snapshot.phase 单向派生兼容 bool，业务路径不再单独写这些字段。
ChatSessionsState projectGeneration(ChatSessionsState current, ChatGenerationSnapshot? snapshot) {
  if (snapshot == null) return current;   // idle：不动兼容字段
  return current.copyWith(
    isStreaming: snapshot.phase == ChatGenerationPhase.streaming,
    isAutoRetryWaiting: snapshot.phase == ChatGenerationPhase.retryWaiting,
    autoRetryCount: snapshot.attempt - 1,   // attempt=1 -> count=0
    generation: snapshot,
  );
}
```

run 的 `_project` 统一经此函数写 state，移除 controller 各调用点对 `isStreaming/isAutoRetryWaiting/autoRetryCount` 的业务性 `copyWith`。debug/test 加 invariant assertion（phase↔bool、phase↔outcome、identity 一致、terminal 必有 outcome）。

### 3.5 完整状态流转

```
start → preparing ──prepare──→ streaming ──onDone──→ [settleAttempt]
                  │                  │                     │
                  │stop(preparing)   │stop(streaming)      │
                  ↓                  ↓                     ↓
              cancelled ←─host.stop─────────────── success/empty/failure
                                                   │
                                                   ├─ Succeed → succeeded (terminal)
                                                   ├─ OutputRuleFailed → failed (terminal)
                                                   ├─ Retry → retryWaiting ──timer──→ streaming(新 attempt)
                                                   │                          │stop
                                                   │                          ↓
                                                   │                      cancelled
                                                   └─ GiveUp/PersistenceFailed → terminal
```

---

## 四、分阶段实施

### Task 1：契约测试 + 共享 controllable repository

**目标**：用可控 gate 把所有竞态交叉组合固化成"修复前 red、修复后 green"的契约测试。不改生产代码。

**新增文件**：
- `test/helpers/controllable_chat_conversation_repository.dart`：从 `chat_sessions_controller_stop_cases.dart:977` 的 `_PendingSaveRepository` 抽取，改为**按 save 内容/调用序号命名的 gate**，而非脆弱的 call-count。API：
  ```dart
  class ControllableChatConversationRepository implements ChatConversationRepository {
    final ChatConversationRepository _inner;
    // 每个 gate：await reached 知 save 进入；complete gate 放行 save 完成。
    final Map<String, (Completer<void> reached, Completer<void> gate)> _gates;
    Future<void> awaitSaveReached(String key);
    void releaseSave(String key);
    void failNextSave(String key, Object error);
    ... // 其余方法委托 _inner
  }
  ```
  gate key 按"这次 save 落盘的 conversation 内容特征"匹配（如 assistantMessageId / isStreaming 标志），避免 call-count 脆弱性。
- `test/features/chat/application/chat_generation_race_contract_test.dart`：7 组契约测试（见下）。

**7 组契约测试**（对应文档 Task 1 清单，均用 `ControllableChatConversationRepository` gate + `FakeChatCompletionClient.enqueueStream(StreamController)`，**不依赖毫秒级 timing**）：

1. **A preparing stop + 立即发 B**：A 的 pending save 被 gate 阻塞 → 发 B → 断言 B 被 busy guard 拒绝（`hasActive` 为 true / B 的 `requestHistory` 不增长）→ release A → A terminal cancelled → 此时 B 才能成功；A 的 stopped 落盘不晚于 B 的 pending 落盘。
2. **streaming stop save 被 gate 阻塞时并发两次 stop**：两次 `stopStreaming()` Future 都不提前完成；release gate 后只发生**一次** terminal save（`requestHistory` / save 计数断言）。
3. **attempt completed 到 terminal projection 任意时点 stop**：在 `onDone` 后、durable 前 stop → 最终只有原 attempt outcome（succeeded），**无 cancelled save**。
4. **finalizing stop**：`onDone` 触发后立即 stop → 等待原 terminal completion，outcome 仍为 success，不被改 cancelled。
5. **stop save / pending save / terminal save 分别失败**：每种失败只得到**一次** `persistenceFailed`，不重试、不假成功、不重复保存。
6. **A 迟到 chunk/error/done/host continuation 不写 B**：A streaming 中切到 B（先 stop A）→ A 的 stream controller 再 `add`/`addError`/`close` → B 的 state/completion 不被污染。
7. **identity 一致**：preparing snapshot、terminal snapshot、outcome 的 `generationId` 相同；`attempt` 从 1 开始；retry 时 attempt 递增；snapshot↔outcome 的 generationId/attempt 相等。

**提交**：`test(chat): define serialized generation run contract`（测试 `skip`，本地验证 red）。

---

### Task 2：run + host 独立实现 + transition matrix 测试

**目标**：实现新 run + host 类型，用 fake host 覆盖完整 transition matrix，不接入 controller，主线全绿。

**改动**：
- `lib/features/chat/application/chat_generation_lifecycle.dart`：新增 §3.1 的 host 接口 + typed 类型（`ChatGenerationCommand` / `ChatPrepareResult` / `ChatAttemptSnapshot` / `ChatAttemptDecision` / `ChatPartialSnapshot` / `ChatStopDecision` / `ChatGenerationProgress`）。保留旧 event 类不动（Task 3 删）。
- `lib/features/chat/application/chat_generation_run.dart`（新）：`ChatGenerationRun`（§3.2）。
- `test/features/chat/application/chat_generation_run_test.dart`（新）：用 `_FakeHost`（记录 prepare/completeAttempt/stop 调用，可控返回 decision）+ `_FakeCompletionClient` 覆盖：
  - normal success / empty / failure
  - retry（可达 + 耗尽 GiveUp）
  - preparing stop / streaming stop / retry-wait stop
  - concurrent stop（两次 requestStop 同一 completion）
  - finalizing stop（completeAttempt 返回 Succeed 后 stop 不改 outcome）
  - dispose（complete null）
  - persistence failure（prepare/completeAttempt/stop 各路径返回 PersistenceFailed）
  - late callback（stream 关闭后迟到 chunk/onDone 被丢弃）
  - 串行性（两个操作入队顺序保证）

**提交**：`refactor(chat): serialize generation lifecycle in a single run`

---

### Task 3：一次切换（controller 实现 host，删旧 bridge）

**目标**：controller 实现 `ChatGenerationHost`，重写 coordinator，删旧 bridge 字段与 void observer。Task 1 契约测试 unskip → green。

**改动**（建议内部分 3 个子提交）：

**3a. 重写 coordinator + host 实现（preparing/streaming/success/error/failure）**
- `chat_generation_coordinator.dart`：重写为 §3.3 的 run owner。删 `ChatGenerationObserver`、`_GenerationHandle`、旧 `start/stop/scheduleRetry/finalize/markPersistenceFailure`。
- `chat_generation_lifecycle.dart`：删旧 `ChatGenerationEvent` 体系。
- `chat_sessions_controller.dart`：
  - `implements ChatGenerationObserver` → `implements ChatGenerationHost`。
  - 实现 `prepare`：搬 `_runGenerationViaCoordinator` 的准备段（占位消息、appendNodeToTree、streamingConversation/streamingReply、state 写 preparing snapshot、`saveConversationDurable` pending），返回 `ChatPrepareSuccess` / `ChatPrepareFailure`。
  - 实现 `completeAttempt`：搬 `_handleGenerationDecision` 的 finish helper + durable 逻辑，返回 `ChatAttemptDecision`。
  - 实现 `projectProgress`：搬 chunk 累积 buffer + 300ms 节流 `replaceStreamingReplyInMemory`。
  - `sendMessage/editMessage/retryLatestAssistant` → `_sendWithOptionalAutoRetry` → `coordinator.start(command, this)`，await `completion`。
  - 保留旧 stop/retry 桥接字段**临时**（3b 删）。

**3b. 迁移 retry 与 stop**
- 实现 `host.stop`：搬 `stopStreaming` 的 stopped 构造（`buildConversationAfterStreamingInterrupt`）+ `saveConversationDurable`，返回 `ChatStopCancelled` / `ChatStopPersistenceFailed`。
- `_settleAttempt` 的 retry 决策（`scheduleRetry` / `_retryExhaustedOutcome`）由 run 接管；`host.completeAttempt` 返回 `ChatAttemptRetry`，run 判断可达上限。
- `stopStreaming()` 退化为 §5.3 facade：
  ```dart
  Future<ChatConversation?> stopStreaming() async {
    final completion = _coordinator.currentCompletion;
    if (completion == null) return state.activeConversation;  // 无 run：按文档不清 unrelated marker
    _coordinator.stop();
    return (await completion) ?? state.activeConversation;
  }
  ```
- 删除：`_coordinatorCompleter`、`_pendingSaveFuture`、`_stoppedSaveFuture`、`_coordinatorGenerationId`、`_coordinatorStreamingConversation`、`_coordinatorAssistantMessage`、`_coordinatorStreamingReply`、buffer、`_coordinatorRetryPolicy`、`_attempt`、`_coordinatorLastUiFlushAt`、`_handleGenerationEvent`、`_handleGenerationDecision`、`_completeGeneration`、`_cleanupCoordinatorBridge`、`_handleGenerationPersistenceFailure`、`_setPhase`/`_projectTerminalSnapshot`（改由 run `_project` 经 `projectGeneration`）。
- run context（streamingConversation/assistantMessage/streamingReply/buffer/retryPolicy）移入 `ChatGenerationRun` / `ChatPrepareSuccess` / `ChatAttemptSnapshot`，不再由 controller 持有。
- `ref.onDispose`：`_coordinator.dispose()`；dispose 后 host 回调 `_disposed` 守卫 + `identical(_currentRun, run)`。
- Task 1 契约测试 `skip` 去除 → 验证 green。

**3c. 测试对齐**
- `chat_generation_coordinator_test.dart`：从 `_CollectingObserver` 改写为 `_FakeHost` 测新 coordinator。
- 现有 `chat_sessions_controller_*_cases.dart` / `chat_sessions_controller_persistence_test.dart` / `chat_lifecycle_integration_test.dart`：应**原样通过**（行为契约不变）。若有因实现细节失效的断言，最小化调整并注明原因；`_PendingSaveRepository` 等局部 fake 可替换为共享 `ControllableChatConversationRepository`。

**提交**：
- `refactor(chat): rewrite coordinator as serialized run owner`
- `refactor(chat): route retry and stop through generation run`
- `test(chat): align generation tests to host contract`

---

### Task 4：投影收口 + invariant

**目标**：兼容 bool 改为纯投影，加 invariant assertion。

**改动**：
- `chat_sessions_state.dart` 或 `chat_generation_lifecycle.dart`：加 `projectGeneration`（§3.4）。
- run `_project` 统一经 `projectGeneration` 写 state；删除 controller 各调用点对 `isStreaming/isAutoRetryWaiting/autoRetryCount` 的业务性 `copyWith`（在 `assert(() { ... })` 内加 invariant 校验：phase↔bool、phase↔outcome subtype、snapshot↔outcome identity、terminal 必有 outcome / non-terminal 不得有 outcome）。
- `isChatBusyProvider` 简化为 `state.generation?.phase.isBusy ?? (兼容回退)`。

**提交**：`refactor(chat): project compatibility flags from generation snapshot`

---

### Task 5：集成验证与范围审计

**执行顺序**（对应文档 Task 6）：
1. `chat_generation_run_test.dart` + `chat_generation_coordinator_test.dart`（lifecycle/状态机）。
2. `chat_generation_race_contract_test.dart`（已 unskip）。
3. controller generation/stop/retry/persistence cases。
4. `test/integration/chat_lifecycle_integration_test.dart`。
5. `flutter analyze`。
6. 全量测试（重定向）：
   ```bash
   flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
   ```
7. `dart format --output=none --set-exit-if-changed`（所有改动 Dart 文件）。
8. `rg` 审计：controller 不再持有 generation completer / pending-stop save Future / stream-retry handle / 多信号猜 phase：
   ```bash
   rg '_coordinatorCompleter|_pendingSaveFuture|_stoppedSaveFuture|_handleGenerationEvent|ChatGenerationObserver|scheduleRetry|_handleGenerationDecision' lib/
   ```

**提交**：`test(chat): verify durable generation lifecycle integration`

---

## 五、文件改动清单

| 文件 | Task | 改动 |
|---|---|---|
| `test/helpers/controllable_chat_conversation_repository.dart` | 1 | 新建 |
| `test/features/chat/application/chat_generation_race_contract_test.dart` | 1 | 新建（skip） |
| `lib/features/chat/application/chat_generation_lifecycle.dart` | 2/3 | T2 加 host+typed 类型；T3 删旧 event 体系 |
| `lib/features/chat/application/chat_generation_run.dart` | 2 | 新建 |
| `test/features/chat/application/chat_generation_run_test.dart` | 2 | 新建 |
| `lib/features/chat/application/chat_generation_coordinator.dart` | 3 | 重写为 run owner |
| `lib/features/chat/application/chat_sessions_controller.dart` | 3/4 | T3 实现 host + 删 bridge；T4 投影收口 |
| `test/features/chat/application/chat_generation_coordinator_test.dart` | 3 | 改写为 fake host |
| `test/.../chat_sessions_controller_*_cases.dart` 等 | 3 | 对齐（应基本不变） |
| `lib/features/chat/application/chat_sessions_state.dart` | 4 | projectGeneration |

---

## 六、风险与回滚

| 风险 | 缓解 |
|---|---|
| 一次切换改动大、回归面广 | Task 1 契约测试 + Task 2 transition matrix 测试双重兜底；现有 controller/integration 测试要求原样通过 |
| `stopStreaming` 无 run 兜底行为变化（文档不清 unrelated marker） | Task 3c 比对现有 stop_cases 测试；若测试要求清 marker 则保留最小兜底，否则遵循文档 |
| `_PendingSaveRepository` 局部 fake 与新 gate 不兼容 | Task 3c 替换为共享 `ControllableChatConversationRepository`，gate key 按内容匹配 |
| retry 耗尽 outcome 转换（success→Failure）逻辑迁移错位 | 保留 `_retryExhaustedOutcome` 语义，移入 run，配 transition matrix 测试 |
| Task 2 期间新文件与旧 coordinator 共存命名冲突 | host/run 用新名，旧 coordinator API 不动，无冲突 |
| 回滚 | 每个 Task 独立提交；Task 3 若出问题可单独 revert 回旧 bridge（旧代码在 Task 3 提交前完整） |

---

## 七、验收 checklist（对齐文档第八节）

- [ ] coordinator/run 是 token/phase/attempt/stop intent/terminal outcome/completion Future 的唯一 owner
- [ ] controller 不再持有 generation completer、pending/stop save Future 或 stream/retry handle
- [ ] 同一 run 的关键 persistence 严格串行，terminal checkpoint 恰好一次
- [ ] old run terminal durable 完成前，新 generation command 不会开始
- [ ] concurrent stop 返回同一个 completion 语义，不提前完成、不重复保存
- [ ] stop 在 finalizing 或 attempt 已 settled 后不能覆盖既定 outcome
- [ ] snapshot/outcome identity 和 compatibility flags 的 invariant tests 全过
- [ ] 所有可控 race tests 不依赖毫秒级 timing，修复前 red、修复后 green
- [ ] 原有消息树/Prompt/Reasoning/inline error/retry/finish reason 产品测试不变并通过
- [ ] `flutter analyze`、相关测试、集成测试、全量测试全过
- [ ] `dart format --set-exit-if-changed` 通过
