# Phase 7 - 跨 Feature 组合边界

## Phase Name

Sync 高扇出、Chat/Favorites command 与组合页面边界。

## Why this Phase exists

本 Phase 聚合 TD-06、TD-08、TD-14、TD-15、TD-27。它们共同描述 feature ownership 不清与高层 composition 泄漏：Sync controller 自行构造 transport/media 基础设施并读取多类 settings controller；SyncScreen 直接组合 persistence/media presentation；chat 与 favorites presentation 双向知道；history 名为独立 feature 实为 chat read model。只抽一个接口无法降低跨 feature 扇出，必须以少量稳定 facade/command 和 app composition 边界一起收敛，但保持各 feature 内部实现不重写。

## Included Technical Debts

- **TD-06（P2）**：chat↔favorites 双向知道，sync→settings/media 高扇出。
- **TD-08（P3）**：history ownership 不明确，实际是 chat read model。
- **TD-14（P1）**：`SyncServerController` 直接构造 server、scanner、cache、generator、handlers，媒体缩略图直接运行 ffmpeg。
- **TD-15（P1）**：大型 Notifier 尤其 sync 通过多处 `ref.read` 隐式服务定位。
- **TD-27（P1）**：media presentation→data、SyncScreen→persistence/media presentation 穿透。

## Dependencies

- 前置 Phase：Phase 3 提供 peer HTTP 边界；Phase 5 提供 settings application 工作流；Phase 6 提供资源生命周期策略。
- 后续依赖：Phase 8 的 typed/authenticated sync protocol 使用本 Phase 的 transport、snapshot/importer 与 media route 边界；Phase 10 的 ChatScreen 拆分在本 Phase 已收敛 chat↔favorites command 后进行；Phase 11 将这些新 port 纳入可执行依赖规则。
- 顺序理由：先把基础设施 construction 和跨 feature 读取移到显式边界，再升级协议和拆大 UI，避免新协议/视图继续绑定内部 controller。

## Expected Benefits

- Sync application 只依赖可替换的 transport、settings snapshot/importer 与 media route contract，测试不必启动真实 socket/process。
- ffmpeg/process 与 media route construction 位于明确 data/composition 边界。
- Chat 与 Favorites 通过稳定 command/facade 协作，任一 presentation 不必知道另一方内部 controller。
- History 被明确声明为 chat read model，无纯目录整齐目的的大搬迁。
- MIME 分类归 domain，偏好经 application，Sync+Media 组合归 app/composite ownership。

## File Scope

- Sync application/data/presentation：`lib/features/sync/application/sync_server_controller.dart`、`sync_client_controller.dart`、`lib/features/sync/data/**`、`lib/features/sync/presentation/sync_screen.dart`。
- Settings 边界：`lib/features/settings/application/**` 中 snapshot/importer 相关契约与 composition binding；不重做 Phase 5 内部工作流。
- Media：`lib/features/media/data/media_thumbnail_generator.dart`、HTTP handlers/scanner/cache、`lib/features/media/data/media_mime_types.dart`、`lib/features/media/domain/**`、`lib/features/media/application/**`、相关 presentation。
- Chat/Favorites/History：`lib/features/chat/presentation/**`、`lib/features/chat/application/**`、`lib/features/favorites/application/**`、`lib/features/favorites/presentation/**`、`lib/features/history/presentation/**`，仅限跨 feature command 与 ownership 声明。
- App composition：`lib/app/**`、`lib/bootstrap.dart`，仅限 provider binding 和 composite page ownership。
- 对应 tests：sync/media controller 与 handler tests、chat/favorites integration tests、history tests、composition/widget tests。

## Refactor Scope

- 为 Sync 建立可替换的 transport、settings snapshot/importer、media route factory 与 thumbnail/process backend 边界，使基础设施 construction 不再散落于 controller。
- 将 sync 对多类 settings controller 的读取收敛为聚合 application facade，而非扩展 service locator。
- 将 chat↔favorites 的用户 intent 收敛为少量稳定 command/facade，消除 presentation 对另一 feature 内部 application 的直接了解。
- 将 MIME 分类的业务含义归 domain、偏好访问归 application，并将 Sync+Media 组合责任放到 app/composite 层。
- 明确 history 是 chat read model；优先用边界声明与 import 规则表达，不为目录美观搬文件。

## Out Of Scope

- 不实现同步配对、认证、敏感分类确认或协议迁移；属于 Phase 8。
- 不拆 `ChatSessionsController` generation 状态机；属于 Phase 9。
- 不重写 `ChatScreen` 或把全部横向 import 消灭。
- 不为纯函数或每个 handler 创建无价值接口。
- 不改变 history 产品功能或搜索规则。

## Risks

- 此 Phase 文件跨度较大，必须按同一“跨 feature composition contract”审查，避免夹带各 feature 内部重构。
- Facade 粒度过大可能形成新的 God Service；过细则只把 service locator 换成接口海洋。
- 移动 media composition 可能影响路由和资源释放，必须遵守 Phase 6 的生命周期策略。
- Chat/Favorites command 若改变现有收藏、撤销或详情行为，会扩大到 Phase 10/12 的范围。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- Sync controller tests 可用 fake transport/snapshot/media backend 覆盖主要路径，不启动真实 socket/process。
- Import 检查证明 media presentation 不再 import media data，SyncScreen 不直接读取 persistence 或嵌入 feature-internal composition。
- Chat/Favorites integration tests 保持现有收藏与导航 intent 行为。
- History 搜索、标题与分页行为保持不变，并在文档/边界中被识别为 chat read model。

## Completion Criteria

- Sync 高扇出依赖已通过少量显式 facade/ports 收敛，controller 不再是隐藏 composition root。
- Chat/Favorites presentation 的双向内部依赖被稳定 command 边界替代。
- Media 与 Sync 的分层穿透已按报告目标修复，History ownership 清楚。
- Phase 不包含协议认证、chat 状态机或全项目 port 搬迁。

## Implement Context For Next Agent

报告认定 Sync 是实际组合模块：controller 直接 new HTTP server、media scanner/cache/generator/handlers，并通过 ref.read 读取约 8 类 settings controller；thumbnail generator 直接运行 ffmpeg。SyncScreen 还直接读取 persistence 并嵌入 media presentation。Chat presentation 调 favorites application，favorites presentation 又调 chat application；history 只是 chat 历史查询视图。你的计划要建立少量跨 feature facade/command 与 app composition boundary，不追求零横向 import，也不为目录整齐搬 history。保持现有 Riverpod、HTTP handlers 和 UI 行为，禁止提前实现 Phase 8/9/10。
