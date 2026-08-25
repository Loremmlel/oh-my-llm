# 全仓 Ponytail Audit 记录

**审计日期：** 2026-08-25

**审计基线：** `master` / `1e4663c88bad1e54e9399ca45bad8302599bd990`

**审计范围：** 全仓生产代码、测试代码、测试辅助代码与直接依赖

**审计目标：** 降低总代码量和维护复杂度，优先寻找可直接 delete、inline、reuse 或 simplify 的内容，而不是追求 coverage 或架构形式上的完美。

本文只记录候选和建议顺序，不授权批量实施。每个 cleanup PR 都应重新核对当前调用图、已有行为测试和实际 diff，不得把估算 LOC 当作交付指标。

## 基线概况

- 生产 Dart：约 392 个文件、46,967 行。
- 测试 Dart：约 260 个文件、54,153 行。
- 审计时 `master` 与 `origin/master` 一致，工作区干净。
- 测试代码多本身不构成问题；本次关注薄层催生的装配、同一行为跨层重复验证、只证明抽象可扩展的测试，以及只有一个生产 caller/implementation 的名义边界。

## 明确保留的高价值复杂度

以下区域具有真实的数据、安全、并发或平台边界，不应因为 LOC 较多就直接删除：

- 已发布 SQLite migration 链、合法旧库 fixture 与数据保留测试。
- Sync 加密、typed protocol、nonce replay、配对授权和敏感字段确认。
- Chat Completions、Responses、Anthropic 三协议编码、SSE 解析和错误边界。
- generation race、durable stop、持久化终态和通知 token/ACK 竞态。
- history read isolate 的启动、退出、dispose 和 SQLite 文件锁生命周期。
- UDP socket、scheduler、multicast lock 等需要确定性驱动并发/平台行为的 seam。
- 已知真实历史 bug、可访问性、数据安全和平台生命周期回归。

## 前 10 个 cleanup 候选

候选按“高置信度、低风险、可删除净 LOC 多”综合排序。LOC 是审计时的保守估算，不是实施配额。

### 1. 内联收藏 intent 薄编排

**标签：** `yagni`

**预计净减：** 220–280 行

`ChatFavoriteIntentCommand` 只有 `ChatScreen` 一个生产 caller。`restore`、`addToCollection` 和 `createCollection` 大多只是 `ChatFavoritesFacade` 的单行转发；sealed result 类型主要用于让页面重新 pattern-match 刚刚包装的结果。专用单测约 249 行，而真实收藏、取消收藏、新建收藏夹和最近目标行为已在 ChatScreen widget 用例覆盖。

建议删除 command、result 类型及其 Provider，把少量 draft 构造和最近 user message 解析内联到现有页面流程或保留为一个私有纯函数。首轮不要删除 `ChatFavoritesFacade`，它仍承担 Chat 与 Favorites 的跨 feature 类型边界。

涉及文件：

- `lib/features/chat/application/favorites/chat_favorite_intent_command.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `test/features/chat/application/favorites/chat_favorite_intent_command_test.dart`
- `test/features/chat/presentation/chat_screen/chat_screen_favorites_cases.dart`

### 2. 收缩生成通知的重复测试矩阵

**标签：** `delete` / `shrink`

**预计净减：** 350–500 行

20 行的平台选择绑定对应约 281 行测试；通知集成测试又按三个 LLM 协议重复验证相同的 `start/update/remove/fail` 投递。协议客户端、通知 projector 和 coordinator 已各自拥有详细测试，这一层的协议交叉矩阵没有增加新的通知契约置信度。

建议保留 coordinator 的 token、定时器、串行 tail、ACK retry、dispose 和 stale action 竞态测试；集成层保留一条成功链路、一条 durable stop/落盘链路和一条 fail-open 链路即可。平台选择只保留 Android 与代表性非 Android 断言。

涉及文件：

- `lib/app/composition/chat_generation_foreground_service_bindings.dart`
- `test/app/composition/chat_generation_foreground_service_bindings_test.dart`
- `test/app/composition/chat_generation_notification_coordinator_test.dart`
- `test/integration/chat_generation_notification_integration_test.dart`

### 3. 压缩服务商配置控制器测试

**标签：** `shrink`

**预计净减：** 250–350 行

`LlmProviderConfigsController` 约 153 行，其测试约 821 行。add/update/delete、unknown provider、empty input 和排序分支重复创建完整容器与 fixture；部分测试只是逐方法锁定显然的列表操作。

建议把 CRUD/no-op 组合改成表驱动，复用一个最小持久化断言。保留导入等价键、协议隔离、重复模型、同批输入去重和持久化失败不发布状态等高价值边界。

涉及文件：

- `lib/features/settings/application/providers/llm_model_configs_controller.dart`
- `test/features/settings/application/providers/llm_model_configs_controller_test.dart`

### 4. 删除历史分页的共享契约重复测试

**标签：** `delete` / `shrink`

**预计净减：** 180–260 行

History controller 测试再次验证 `AppPaginationState` 已覆盖的 `hasPrevious/hasNext`、页码夹取、空数据归一和边界导航，并为 `first/last/next/prev` 分别维护大段异步装配。

建议删除共享分页纯函数的重复断言，将机械导航和输入校验表驱动。保留 active + latest pending、旧成功/旧失败不得覆盖新目标、搜索清空在途、rename/delete invalidation、retry、dispose 和错误态保留旧窗口。

涉及文件：

- `lib/features/chat/application/history/history_pagination_controller.dart`
- `test/features/chat/application/history/history_pagination_controller_test.dart`
- `test/core/widgets/pagination/app_pagination_state_test.dart`

### 5. 内联单 caller 的模型目录 workflow

**标签：** `yagni`

**预计净减：** 130–160 行

`ModelCatalogWorkflow`、`ModelCatalogRequest` 和 `ModelCatalogFailure` 只有设置页一个 caller。该层主要把字段重新命名后转发给 `ModelListClient`，再把 `ModelListException` 换成另一种异常；69 行 production 对应约 130 行专用测试。

建议把 endpoint override/解析和稳定错误文案放在 `ModelListClient` 或设置页调用边界，删除 workflow Provider 与专用 DTO/异常层。

涉及文件：

- `lib/features/settings/application/providers/model_catalog_workflow.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `test/features/settings/application/providers/model_catalog_workflow_test.dart`

### 6. 压平 Chat workspace 数据搬运层

**标签：** `yagni` / `shrink`

**预计净减：** 250–380 行

`ChatWorkspaceMessagesState`、`ChatWorkspaceComposerReadModel`、`ChatWorkspaceComposerState`、`ChatWorkspaceReadModel`、`ChatWorkspaceViewState` 与三组 bindings 只在 `ChatScreen -> ChatWorkspace` 一条链路上传递字段。大量构造器、复制和 `Equatable.props` 维护的是结构而非行为。

建议保留模型/服务商/模板选择 resolver 和“编辑无模板消息不回退 normal selection”契约，压平只做数据搬运的 DTO 与 bindings。行为验收优先依赖 workspace ownership widget 用例，而不是为不可变容器本身保留测试。

涉及文件：

- `lib/features/chat/application/workspace/chat_workspace_view_state.dart`
- `lib/features/chat/presentation/widgets/workspace/chat_workspace_bindings.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `test/features/chat/application/workspace/chat_workspace_view_state_test.dart`
- `test/features/chat/presentation/chat_screen/chat_screen_workspace_ownership_cases.dart`

### 7. 删除 Settings Transfer 的假想扩展性证明

**标签：** `delete`

**预计净减：** 300–450 行

Settings Transfer 测试中存在“新增 fake participant 无需 coordinator 分支”“test-only participant 可注册到独立 catalog”“生产 catalog 固定九项顺序”等主要验证抽象自身可扩展的用例。typed fixture、participant codec、coordinator 和 Sync integration 已从多个层次覆盖相同路径。

建议删除 test-only extensibility 证明和重复 catalog 顺序/类型快照。必须保留版本拒绝、malformed payload、敏感导入导出确认、准备阶段零写入、stale fingerprint、部分失败摘要和 writer 临界区不重叠。

涉及文件：

- `test/features/settings/application/transfer/settings_transfer_coordinator_test.dart`
- `test/features/settings/application/transfer/settings_transfer_catalog_test.dart`
- `test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart`
- `test/features/settings/application/transfer/settings_transfer_participants_test.dart`
- `test/integration/sync_multi_category_integration_test.dart`

### 8. 去重视频交互的 controller/page/accessibility 测试

**标签：** `delete` / `shrink`

**预计净减：** 200–320 行

M/F/方向键/Escape/长按/滚轮在 desktop controller、desktop page 和 accessibility 三层重复验证。controller 已逐状态覆盖输入状态机，page 层不需要再次穷举内部转移。

建议 controller 保留完整状态机测试；page 层每种输入保留一条 wiring smoke；accessibility 只验证语义、焦点顺序、keyboard equivalent 和 live region。失焦、销毁后 Future、全屏恢复失败和控制栏焦点等真实历史回归继续保留。

涉及文件：

- `test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart`
- `test/features/media/presentation/pages/video_player_desktop_test.dart`
- `test/features/media/presentation/pages/video_player_accessibility_test.dart`
- `test/features/media/presentation/pages/video_player_page_test.dart`

### 9. 删除由测试催生的持久化 writer seam

**标签：** `yagni`

**预计净减：** 120–200 行

`SettingsKeyValueStore` 只有 SharedPreferences 一个生产实现；History、Favorites 和 Media 又各自增加 Writer typedef/Provider，主要用途是让测试模拟写入失败。由此产生额外 constructor、adapter、override 和 fake，而实际产品行为只是非关键偏好写入。

建议直接使用已注入的 `SharedPreferences`，删除仅验证 writer 抛错/返回 false 的测试和 fake。版本化 JSON envelope、malformed/unsupported 数据、敏感设置和真实 repository round-trip 测试继续保留。

涉及文件：

- `lib/core/persistence/settings_key_value_store.dart`
- `lib/features/chat/application/history/history_browse_preferences_controller.dart`
- `lib/features/favorites/application/favorites_browse_preferences_controller.dart`
- `lib/features/media/application/media_grid_density_controller.dart`
- 对应 persistence/preferences 测试

### 10. 用函数 Provider 替代单方法名义 port

**标签：** `yagni`

**预计净减：** 80–140 行

`FavoriteSourceConversationCommand`、`SyncMediaRouteFactory` 和 `SyncClock` 都只有一个生产实现，且 nominal interface 没有提供比函数签名更多的协议价值。composition 中还需为其创建私有 adapter class。

建议改为命名 typedef/函数 Provider，保留注入 seam 而删除 interface、单实现 adapter 和对应 fake class。不要把这项机械推广到 UDP socket/scheduler、Sync crypto/transport 或其他真实多实现/并发边界。

涉及文件：

- `lib/features/favorites/application/favorite_source_conversation_command.dart`
- `lib/features/sync/application/ports/sync_media_route_factory.dart`
- `lib/features/sync/application/ports/sync_clock.dart`
- `lib/app/composition/cross_feature_bindings.dart`

## 推荐的第一个 Cleanup PR

推荐先实施候选 1：**内联收藏 intent 薄编排**。

建议范围：

1. 保留 `ChatFavoritesFacade` 及 composition 实现，不扩大跨 feature 依赖。
2. 删除 `ChatFavoriteIntentCommand`、sealed result 类型和 Provider。
3. 在 `ChatScreen` 现有收藏处理方法中直接调用 facade。
4. 最近 user message 解析如仍需独立验证，只保留一个私有纯函数和最小参数化测试。
5. 删除 command 专用 fake/unit test，保留并运行现有 ChatScreen 收藏行为测试。

选择理由：

- 单一 feature、单一行为目标，review 范围清晰。
- 不涉及数据库 schema、交换格式、网络协议或并发状态机。
- 不移除真正的跨 feature seam。
- 已有 widget 测试覆盖用户可见结果，适合验证“删薄层、保行为”的 cleanup 方法。
- 预计净减约 250 行，收益足以形成有意义但仍易审查的首个 PR。

建议 PR 标题：

```text
refactor(chat): 内联收藏 intent 薄编排
```

## 总体收益估算

- 预计可净减约 2,100–3,000 行。
- `cupertino_icons` 与 `meta` 未被源码直接引用，可在独立依赖清理中移除 2 个直接依赖。
- 上述估算存在交叠；实施时应以每个独立 PR 的 `master...HEAD` 实际净变化为准。

## 执行原则

- 一次只实施一个候选，不做“全仓大扫除”式 PR。
- cleanup 前先确认保留下来的测试覆盖用户行为或关键边界，再删除实现细节测试。
- 删除抽象时优先内联到已有 owner，不新建另一套 generic framework。
- 测试缩减的标准是移除重复或低价值装配，不是追求更低测试数量。
- 如果 cleanup 需要修改 schema、协议、安全确认、持久化兼容或竞态语义，停止并拆成独立设计。
- 每个 PR 在正文中记录删除内容、保留契约、实际净 LOC 和未触及的高风险边界。
