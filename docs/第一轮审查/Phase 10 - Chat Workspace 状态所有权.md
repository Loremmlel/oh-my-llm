# Phase 10 - Chat Workspace 状态所有权

## Phase Name

ChatScreen 页面瞬态、会话态与持久态所有权收敛。

## Why this Phase exists

本 Phase 聚合 TD-11 与 TD-25。二者是同一问题的状态与 UI 两个表现：本地 controller/草稿/模板/编辑快照和全局 Provider 双写导致 owner 不清，进而让 `ChatScreen` 用 20+ 参数编排 workspace、收藏、发送和撤销。必须先形成不可变 workspace view-state/bindings 与 command 边界，再逐项迁移 composer，而不是一次重写 Screen。

## Included Technical Debts

- **TD-11（P2）**：ChatScreen 页面本地状态与 Provider state 双重 ownership，恢复和销毁语义隐式。
- **TD-25（P2）**：ChatScreen 1324 行、参数爆炸，并直接编排多个跨 feature/业务用例。

## Dependencies

- 前置 Phase：Phase 7 的 Chat/Favorites command；Phase 9 的 generation lifecycle/command。
- 后续依赖：Phase 12 的路由状态恢复与 Phase 13 的响应式矩阵可在本 Phase 稳定的 workspace contract 上验证。
- 顺序理由：先稳定 application commands，再决定页面仅持有的瞬态 view-state，避免把旧 controller 时序复制进新的参数对象。

## Expected Benefits

- 每个状态都能明确属于页面瞬态、会话态或持久态，避免双写和销毁歧义。
- Chat workspace 参数从 data clump 收敛为可理解的不可变 view-state/bindings。
- 收藏、发送、停止、撤销、模板等 intent 通过稳定 command 组合，而不是 Screen 直接拼接多个 feature 内部调用。
- 页面重建、会话切换和草稿恢复更可预测，Widget tests 装配成本下降。

## File Scope

- 主页面：`lib/features/chat/presentation/chat_screen.dart`、`chat_scroll_controller.dart`。
- Workspace/composer widgets：`lib/features/chat/presentation/widgets/chat_workspace.dart`、`composer_data.dart`、`chat_composer_card.dart`、`composer/**`、与收藏/发送/撤销 intent 直接相关 widgets/dialogs。
- Application state/commands：`composer_draft_controller.dart`、`composer_collapsed_controller.dart`、`chat_template_prompt_selection_controller.dart`、Phase 9 generation command 与 Phase 7 favorites command；仅限 ownership 和绑定。
- Tests：`test/features/chat/chat_screen_test.dart`、`test/features/chat/chat_screen/**`、composer controller/widget tests、相关 chat integration tests。

## Refactor Scope

- 对页面瞬态、会话态和持久态建立明确 ownership 与恢复/销毁契约。
- 将 Chat workspace 所需数据和 intent 收敛为不可变 view-state/bindings 边界，减少长参数链。
- 先处理 composer 相关 view-state/command，再按实际依赖逐项迁移收藏、发送、停止与撤销组装。
- 保持 UI 叶子组件、现有 Provider API 和用户交互可渐进兼容；每一步均可验证。
- 删除不再需要的本地/Provider 双写，但不把纯 UI controller 错误持久化。

## Out Of Scope

- 不重做 generation 状态机；属于 Phase 9。
- 不改变消息树、Prompt 顺序、标题、搜索、inline error 或 streaming 300ms 节流规则。
- 不修改全局路由 shell；属于 Phase 12。
- 不一次性重写 ChatScreen 或整个 chat feature。

## Risks

- 错误归类状态 owner 会导致草稿跨会话泄漏、编辑快照丢失或页面返回后意外重置。
- 参数对象若同时包含业务状态和 UI controller，可能只是隐藏参数爆炸。
- 迁移 intent 时需避免绕过 Phase 7/9 已建立的 command boundary。
- Widget 测试不得转而断言新 view-state 的内部字段或 Key。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- Widget/contract tests 覆盖会话切换、页面重建、草稿恢复、模板选择、编辑取消/发送、收藏、停止和撤销的外部行为。
- 测试证明页面销毁不会丢失会话/持久态，也不会错误保留纯瞬态 UI state。
- 不使用像素位置、内部 Key 或 widget 私有属性作为新契约。

## Completion Criteria

- ChatScreen 的状态 owner 可被清晰说明，本地与 Provider 双写已消除或有明确理由。
- Workspace/body 不再以 20+ 独立参数传递同一 data clump。
- Screen 通过 commands 组合业务 intent，未重新吸收 Phase 7/9 已分离的职责。
- 重构是渐进的、行为兼容的，并可独立回滚。

## Implement Context For Next Agent

当前 `ChatScreen` 约 1324 行，同时管理 controller、草稿、模板选择、编辑快照并读取多个全局 Provider；部分状态双写。`_buildBody`/`_buildWorkspace` 有 20+ 参数，并直接编排收藏、撤销、模板和发送。报告指定先用不可变 `ChatWorkspaceViewState/Bindings` 收敛参数，再迁移 application command，但不能一次重写。Phase 7 应提供 favorites command，Phase 9 应提供 generation command。你的计划必须明确页面瞬态/会话态/持久态，不改变任何核心 chat 业务规则。
