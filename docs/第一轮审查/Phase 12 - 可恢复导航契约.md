# Phase 12 - 可恢复导航契约

## Phase Name

收藏详情 ID 路由与统一媒体导航契约。

## Why this Phase exists

TD-28 同时指出不可序列化 `state.extra as Favorite`、GoRouter/MaterialPageRoute 混用，以及顶层切页状态可能丢失。可立即、安全交付的是 ID route 与媒体子路由；StatefulShellRoute 只在 UX 触发条件成立时评估，不能因技术偏好在本 Phase 强制迁移整个 shell。因此该 TD 单独成 Phase，以保持导航变更范围可审查和回滚。

## Included Technical Debts

- **TD-28（P2）**：收藏详情依赖 `state.extra`，媒体使用另一套路由栈，顶层 GoRoute 平铺导致 deep link/刷新与状态恢复风险。

## Dependencies

- 前置 Phase：Phase 7 明确 app/composite 与 feature ownership；Phase 10 稳定 Chat workspace 页面状态。
- 后续依赖：Phase 13/14 可在统一 route matrix 上验证响应式与可访问性；Phase 16 的 device smoke 覆盖 deep link/启动恢复。
- 顺序理由：先让 route state 可序列化、导航栈单一，再评估 shell 状态保持，避免把 feature 内部页面直接塞入另一套 Navigator。

## Expected Benefits

- 收藏详情可通过 URL/route ID 恢复，缺少 `extra` 不会崩溃。
- Media 页面使用同一 GoRouter 导航契约，返回行为与深链更可预测。
- 顶层 shell 是否保留页面状态由可观察 UX 需求决定，而非一次性架构迁移。

## File Scope

- 路由与 shell：`lib/app/router/app_router.dart`、`lib/app/shell/app_shell_scaffold.dart`、`lib/app/navigation/app_destination.dart`。
- Favorites：`lib/features/favorites/presentation/favorite_detail_screen.dart`、`favorites_screen.dart`、application/provider 中按 ID 加载详情的现有边界。
- Media：`lib/features/media/presentation/media_browser_tab.dart`、`pages/image_viewer_page.dart`、`pages/video_player_page.dart` 及发起导航的 widgets。
- 相关 tests：`test/app/**`、`test/features/favorites/**`、`test/features/media/presentation/**`。

## Refactor Scope

- 将收藏详情从内存对象 extra 改为可序列化 ID route，并通过 application/provider 加载当前详情。
- 定义详情缺失、已删除或无效 ID 时的可恢复 UI 状态。
- 将 media viewer/player 纳入 GoRouter 子路由，统一 URL、返回和恢复语义。
- 以明确 UX 证据评估 StatefulShellRoute；只有顶层状态丢失已影响用户或新增顶层模块时才进入当前实施范围，否则记录为条件未触发。

## Out Of Scope

- 不因“最佳实践”强制迁移 StatefulShellRoute。
- 不改变 favorites 数据模型、收藏业务规则或 media playback 功能。
- 不重做 AppShell 视觉设计。
- 不引入第二套路由库或继续保留 MaterialPageRoute 作为 feature 特例。

## Risks

- ID 加载存在详情删除/不存在的异步状态，不能用强制 cast 替代。
- Media route 参数若仍携带不可序列化对象，只是移动了问题。
- Shell 迁移若无 UX 触发会扩大回归面，影响所有顶层 destination。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 测试覆盖直接打开收藏详情 URL、刷新/重建、无效 ID、已删除详情和正常返回。
- Media viewer/player 通过 GoRouter 打开、返回，并在必要参数缺失时可恢复。
- 若实施 shell 状态保持，必须有先失败后通过的用户状态丢失行为测试证明触发条件成立。

## Completion Criteria

- 收藏详情不依赖 `state.extra as Favorite`。
- Media 不再使用 feature 内部 `Navigator.push(MaterialPageRoute)` 形成平行栈。
- StatefulShellRoute 已依据报告条件明确实施或明确不触发，不能凭偏好扩大范围。
- Route 行为可独立测试和回滚。

## Implement Context For Next Agent

`app_router.dart` 当前用 `state.extra as Favorite` 打开收藏详情，deep link/刷新缺 extra 会失败；media 又用 `Navigator.push(MaterialPageRoute)`。报告建议详情近期改成 ID route + Provider 加载、media 变子路由；StatefulShellRoute 只在状态丢失已影响 UX 或新增顶层模块时做。先验证是否存在该触发条件。不要把“评估”误写为必做 shell 重构，也不要改变收藏/媒体产品行为。
