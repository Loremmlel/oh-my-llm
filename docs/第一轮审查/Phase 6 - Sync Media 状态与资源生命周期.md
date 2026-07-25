# Phase 6 - Sync Media 状态与资源生命周期

## Phase Name

Sync/Media 状态不可变性与资源生命周期策略。

## Why this Phase exists

本 Phase 聚合 TD-12 与 TD-13。两项都决定 sync/media 状态能否被 Riverpod 稳定推理：暴露可变集合会绕过 Notifier 通知；资源型 Provider 没有 keep-alive policy 会让状态和 socket/process 生命周期由容器偶然决定。它们修改范围集中且风险可控，应在 Phase 7 注入 transport/media backend 前先明确状态与资源所有权。

## Included Technical Debts

- **TD-12（P2）**：`SyncClientState.selectedCategories`、`MediaBrowserState.items/pathHistory` 暴露可变集合，部分 state 缺少值相等。
- **TD-13（P2）**：sync/media 资源 Provider 的页面级或会话级保活策略未显式声明。

## Dependencies

- 前置 Phase：Phase 1。
- 后续依赖：Phase 7 的 transport、media route 与 process backend 注入必须遵循本 Phase 明确的资源生命周期；Phase 8 的配对 session 也需要明确归属页面、会话或应用生命周期。
- 顺序理由：先明确 owner 和保活策略，再更换 construction 边界，避免 facade 创建后仍依赖隐式容器生命周期。

## Expected Benefits

- 调用者无法在 Notifier 之外原地修改公开集合。
- State 的相等与通知语义一致，更易测试和推理。
- 每个 socket、server、scanner、media session 或 process 资源都有可读的 keep-alive policy 与释放责任。
- 页面离开与后台保活行为成为产品契约，而不是 Provider 默认值的副作用。

## File Scope

- Sync state/providers：`lib/features/sync/application/sync_client_controller.dart`、`sync_server_controller.dart`、`broadcast_prefix_length_provider.dart`、`network_interface_provider.dart`。
- Media state/providers：`lib/features/media/application/media_browser_controller.dart`、`media_root_directory_controller.dart`、`shuffle_playback_controller.dart`。
- Composition consumers：`lib/features/sync/presentation/sync_screen.dart`、`lib/features/media/presentation/**`，仅限生命周期观察与释放契约。
- 对应 tests：`test/features/sync/application/**`、`test/features/media/application/**` 和相关 screen/page tests。
- 资源策略文档位置：相关 Provider doc 或 feature 内现有架构说明；不新建平行架构规范体系。

## Refactor Scope

- 将公开 State collection 与 state snapshot 定义为不可变值，并统一必要的值相等语义。
- 逐一声明 sync/media 资源是页面级、会话级还是应用级，以及页面离开、重连、失败和应用关闭时的预期状态。
- 仅按已声明策略调整 Provider 生命周期；页面级资源可采用自动释放与显式保活，会话级资源可继续全局保活。
- 建立资源释放与状态重建的行为验证，为后续可注入 backend 提供稳定契约。

## Out Of Scope

- 不机械地把所有 Provider 改成 autoDispose。
- 不注入 SyncServerTransport、MediaRouteFactory 或 ProcessRunner；属于 Phase 7。
- 不增加配对 session 或协议状态；属于 Phase 8。
- 不更换 Riverpod 或引入代码生成以获得值相等。

## Risks

- 错误的 autoDispose 决策会中断后台同步或媒体播放。
- 不可变集合转换若发生在高频热路径，可能产生不必要分配；需以边界快照为目标。
- 资源释放测试若依赖固定 delay，会引入 TD-31 的新实例。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 测试证明公开集合不可被外部原地修改，等值状态不会产生错误推理。
- 每类资源的离开页面、重建、重连、dispose 与保活行为均与声明策略一致。
- 不使用微秒级 timing 或任意 delay 作为释放完成的唯一证据。

## Completion Criteria

- TD-12 指出的所有公开可变集合和不一致值语义已处理。
- TD-13 涉及的资源均有明确 keep-alive policy，代码与测试一致。
- 没有统一机械 autoDispose，也没有提前实现 Phase 7/8 的资源或协议功能。

## Implement Context For Next Agent

本 Phase 只固化 sync/media 的 state 与 resource ownership。报告指出 `SyncClientState.selectedCategories`、`MediaBrowserState.items/pathHistory` 暴露可变集合，且部分 state 没有值相等；资源型 Provider 多为全局非 autoDispose，但后台保活是否需求并未显式表达。先盘点每个现有资源的使用生命周期并形成可测试契约，再做最小范围调整。不要假设“全部 autoDispose”正确，也不要在这里抽 transport 或实现认证。
