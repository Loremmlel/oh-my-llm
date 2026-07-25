# Phase 9 - Chat Generation 生命周期

## Phase Name

Chat generation 显式生命周期与契约测试分解。

## Why this Phase exists

本 Phase 聚合 TD-04 与 TD-35。生产端约 2000 行 controller/mixins 共同形成隐式异步状态机，而其 2076 行测试文件也按同一集中结构增长。状态机提取和测试按公开契约分解必须同步发生，否则会得到“生产边界已变但测试仍绑定旧 God Controller”或“机械搬测试却没有新业务边界”的无收益中间态。

## Included Technical Debts

- **TD-04（P1）**：`ChatSessionsController` 与 streaming/support mixins 共同承担 generation、stop、retry、树、持久化和 checkpoint 的隐式异步状态机。
- **TD-35（P2）**：`chat_sessions_controller_test.dart` 与若干 case 文件成为测试维护热点。

## Dependencies

- 前置 Phase：Phase 4 的 durable persistence/失败语义；Phase 7 的跨 feature command 边界。
- 后续依赖：Phase 10 的 ChatScreen state/command 拆分消费本 Phase 稳定的 generation command；Phase 15 会治理测试等待和 Key，但不负责本 Phase 的契约重组。
- 顺序理由：先使 generation 生命周期显式并保留 provider API，再调整 Screen ownership；否则 UI 重构仍需理解旧时序标志。

## Expected Benefits

- generation、stop、异常 finish reason 自动重试、取消、失败和完成具有显式生命周期。
- 会话 CRUD、checkpoint 与 generation 协调的责任边界可单独理解和测试。
- 保持 `chatSessionsProvider` 公共 API，允许 presentation 和其他 feature 渐进迁移。
- 测试按 generation、CRUD、branching、checkpoint 等公开契约组织，review 与回归定位成本下降。

## File Scope

- Chat application：`lib/features/chat/application/chat_sessions_controller.dart`、`chat_sessions_controller_streaming.dart`、`chat_sessions_controller_support.dart`、`chat_sessions_state.dart`、`checkpoint_request_context.dart`，以及 generation lifecycle/coordinator 的 application 文件。
- Chat domain/pure functions：`chat_message_tree.dart`、请求 builder/filter、现有 chat domain models；仅限保持状态机输入输出契约。
- Chat data ports：现有 completion/repository contracts，仅限被 coordinator 消费，不在本 Phase 搬迁 ownership。
- Tests：`test/features/chat/application/chat_sessions_controller_test.dart`、与 generation/CRUD/branching/checkpoint 对应的新 case/test 文件、`test/integration/chat_lifecycle_integration_test.dart` 等直接生命周期测试。

## Refactor Scope

- 将 generation 的开始、流式接收、停止、取消、异常 finish、自动重试、成功与失败定义为显式 application 生命周期。
- 将 generation coordination 从会话 CRUD、消息树纯操作与 checkpoint command 中分离，同时保持现有 `chatSessionsProvider` 对外行为。
- 让持久化完成/失败消费 Phase 4 的明确契约，不依赖任意 delay 或隐藏 flag。
- 按公开行为域分解超大 controller tests，并保持共享 harness 最小。
- 每个渐进迁移步骤都必须处于可运行状态，不一次性替换整个 Controller。

## Out Of Scope

- 不重写 ChatScreen、本地 composer state 或 workspace 参数；属于 Phase 10。
- 不改变消息树核心规则、Prompt 拼接顺序、Reasoning/Content 分离、inline error 或自动重试产品语义。
- 不迁移所有 ports；属于 Phase 11。
- 不以代码生成或另一状态管理框架替代 Riverpod Notifier。

## Risks

- stop/cancel/retry 的时序边界最容易出现竞态与重复写入。
- 为追求“显式状态机”而改变外部 provider state 形状，会无意扩大到 presentation。
- 测试拆文件若只按文件长度而非公开契约，会保留相同耦合。
- generation 与消息树 branch edit 的交互必须保持“仅最新 assistant 可重试”等既有规则。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 覆盖 generation success、empty reply、inline error、user stop、cancel、异常 finish 自动重试、重试失败、持久化失败和 controller dispose。
- 覆盖发送期间分支/会话切换等现有竞态路径，并确认不会重复持久化或泄漏订阅。
- 现有 `chatSessionsProvider` 消费者无需一次性迁移，公开行为回归测试保持通过。

## Completion Criteria

- Generation 生命周期不再由多个 mixin 的隐式 flags 共同定义。
- 会话 CRUD、branching、checkpoint 与 generation 可按独立公开契约理解和测试。
- 超大测试入口已按这些契约分解，而不是机械切行数。
- Phase 以多个内部小步完成，但最终可作为一个独立 Phase Commit/Review/回滚，不包含 Screen 重写。

## Implement Context For Next Agent

`ChatSessionsController` 约 1045 行，streaming mixin 约 813 行，support mixin 约 225 行，共享订阅、generation、stop、retry、消息树、持久化和 checkpoint 状态。报告要求提取 `ChatGenerationCoordinator`/显式生命周期，但保持现有 Provider API，禁止大爆炸。`chat_sessions_controller_test.dart` 约 2076 行，应随新的公开边界按 generation、CRUD、branching、checkpoint 拆分。Phase 4 应已提供 durable persistence 完成语义；不得改变核心域规则或提前拆 ChatScreen。
