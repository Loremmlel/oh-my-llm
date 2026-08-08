# Phase 15 - 存量测试韧性治理 Implement Plan

> 来源：`docs/第一轮审查/Phase 15 - 存量测试韧性治理.md`
> 对应问题：TD-31（P2）
> 基线提交：`7ddad8e`
> 计划状态：待实施

## 一、执行结论

本阶段只治理测试等待、Finder 与时间依赖，不改变产品动画、节流、防抖和后台写入的业务时长，也不提前实施后续 Phase。实施完成后应达到以下确定状态：

1. `test/` 中不再直接调用 `find.byKey`；所有测试通过可见文本、语义、控件角色或公开状态定位目标。
2. `test/` 中只有共享的有限动画等待实现可以直接调用一次 `WidgetTester.pumpAndSettle`；业务测试只能调用按场景命名的动画 helper，或等待明确的异步完成信号。
3. 5 秒 `pumpAndSettle` 全部删除。视频错误测试改用确定性失败的 fake controller，不再依赖本机无效 URL 和网络超时。
4. 除 UDP 资源释放/负向观测用例外，测试代码中不保留任何 `Future.delayed`（包括 `Duration.zero`）。UDP 用例已经通过 `udp` tag 与 CI 隔离，本阶段只把它登记为经审查的例外，不修改 `dart_test.yaml` 或 CI。
5. 聊天流、自动重试、停止生成、后台保存、同步连接和日志落盘测试改为等待 Provider 状态、受控流、仓储 ACK、既有 gate 或 I/O Future；超时只作为失败保护，不能作为成功路径。
6. Widget 测试中的真实产品 Timer 使用 `WidgetTester` 虚拟时钟精确推进到公开常量或明确的产品契约边界，不再使用 `duration + 50ms` 一类余量。
7. 增加架构测试作为持续门禁，阻止直接 `find.byKey`、散落 `pumpAndSettle`、新增真实延时和 `delay + 2ms` 一类模式回流。
8. `test/helpers/fixtures.dart` 已检查，不含本阶段问题，不修改。
9. 不为 `ChatGenerationRun`、History 搜索或模板变量协调引入生产时钟抽象；现有状态、受控流、ACK 和 WidgetTester 虚拟时钟足以完成治理。唯一需要修改的生产完成语义是 `SseLogBuffer.flush()` 等待已经在途的自动落盘 Future。

Phase 文档中的上下文足以确定上述方案，没有无法消解的矛盾或关键事实缺失，因此本计划没有读取或重新解释 Architecture Review Report。

---

## 二、边界、依赖与禁止事项

### 2.1 已满足的依赖

| 依赖 | 本阶段可直接复用的结果 | 本阶段处理方式 |
|---|---|---|
| Phase 1 | CI 已执行格式、分析和测试；UDP 已有 tag 隔离 | 不修改 CI，不重复 TD-32 环境隔离 |
| Phase 4 | 后台聊天仓储已有批次 ACK，`save()` 和 `flush()` 可表达完成 | 测试直接等待 ACK/Future，不加 sleep |
| Phase 5-14 | 应用层公开状态、Repository/Fake、路由与 UI 契约已经稳定 | 只消费既有公开契约，不重新设计业务架构 |
| Phase 16 | 将继承本阶段测试规则 | 本阶段只建立门禁，不实施 Phase 16 内容 |

### 2.2 Refactor Scope

允许修改：

- `test/helpers/test_harness.dart` 及新增的通用测试等待 helper。
- `test/helpers/fake_chat_completion_client.dart`、聊天 feature 的测试 helper 和当前受影响测试。
- 当前直接使用 `pumpAndSettle`、`find.byKey`、真实延时或时间余量的测试文件。
- 为提供确定性完成信号而需要的最小源码缝隙：`lib/core/logging/sse_log_buffer.dart`。
- 媒体 fake controller，用于确定性模拟初始化失败。
- 一个测试架构门禁文件。

### 2.3 Out Of Scope

执行中不得做以下事项：

- 不修改任何产品动画、搜索防抖、模板变量防抖、流式刷新、后台保存防抖或自动重试时长。
- 不把本阶段扩展为生产架构重写；不得引入全局 Clock、Scheduler 或通用 Debouncer 服务。
- 不机械地把所有 `pumpAndSettle` 替换为 `pump(const Duration(...))`。
- 不删除生产代码中具有列表身份、状态保留或焦点保持用途的 Key；本阶段只取消测试对内部 Key 的依赖。
- 不重复 Phase 9 的测试文件拆分，不重命名现有 case-file 组织。
- 不修改 `.github/workflows/ci.yml`，不修改 `dart_test.yaml` 的并发、timeout 或 UDP tag。
- 不治理 UDP 网络资源隔离本身，不为 UDP 用例新增 fake transport。
- 不顺手重构聊天生成、同步、媒体、设置或历史业务逻辑。
- 不修改 Phase 文档的结论和技术选型。

### 2.4 执行约束

- 每次只完成一个提交节点；提交前该节点的目标测试必须通过。
- 所有新增 Dart 注释使用简体中文，只说明“为什么”；源码和测试注释不得出现审查轮次、TD 或 Phase 编号。
- 新 helper 必须是窄职责 API；禁止提供名为 `waitForEverything`、`settleEverything`、`sleepUntilStable` 一类无法表达等待对象的接口。
- 每个成功等待都必须由可观察事件完成。`.timeout(...)` 仅防止挂死，并在错误消息中说明等待的状态。
- 不手工编辑 `pubspec.yaml` 版本号；提交 hook 自行 bump。

---

## 三、当前基线与存量清单

### 3.1 仓库基线

| 项目 | 当前事实 |
|---|---|
| 基线提交 | `7ddad8e` |
| 工作区 | 计划编写前为 clean |
| Dart test timeout | `dart_test.yaml` 为 120 秒 |
| Dart test concurrency | 当前实际为 8 |
| CI UDP 策略 | `flutter test --exclude-tags=udp --coverage` |
| 最近完整测试 | `+1625: All tests passed!`，约 84 秒 |

实施者开始改动前仍需重新执行“三次 CI 同构基线测试”，记录中位数；上表的 84 秒只作为参考，不替代实施时的可比基线。

### 3.2 `pumpAndSettle` 基线

- 共 376 处，分布于 34 个 Dart 测试文件。
- 其中 372 处显式使用 250ms step，4 处使用 5 秒 step。
- 4 处 5 秒等待全部位于 `test/features/media/presentation/video_player_page_test.dart`。
- 完整文件级清单如下（计数用于迁移后归零校验）：

| 文件 | 约计数 | 主要等待对象 |
|---|---:|---|
| `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart` | 74 | tab、dialog、menu、表单保存与 Provider 更新 |
| `test/features/chat/chat_screen/chat_screen_basics_cases.dart` | 56 | 生成完成、overlay、滚动和折叠动画 |
| `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart` | 36 | 生成完成、编辑、模板选择和 remount |
| `test/features/chat/chat_screen/chat_screen_branching_cases.dart` | 23 | 分支生成、重试和确认 dialog |
| `test/features/chat/chat_screen/chat_screen_favorites_cases.dart` | 18 | 生成完成和收藏 dialog |
| `test/features/favorites/manage_collections_dialog_cases.dart` | 16 | dialog 与集合 CRUD |
| `test/features/settings/presentation/output_processing_tab_test.dart` | 15 | tab/overlay 和同步表单状态 |
| `test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart` | 15 | tab、dialog 和列表更新 |
| `test/features/favorites/favorites_screen_detail_cases.dart` | 13 | route、dialog 和收藏状态 |
| `test/features/settings/presentation/model_config_form_dialog_test.dart` | 10 | dialog、异步模型拉取和表单状态 |
| `test/features/chat/chat_screen/chat_screen_streaming_cases.dart` | 8 | 流状态、reasoning 展开和 clipboard |
| `test/features/chat/widgets/message_anchor_rail_test.dart` | 8 | rail 展开/收起和 focus |
| `test/features/history/history_screen/history_screen_actions_cases.dart` | 8 | action dialog 和历史状态 |
| `test/features/media/presentation/image_viewer_page_test.dart` | 8 | PageView、缩放和错误页 |
| `test/features/media/presentation/media_browser_navigation_test.dart` | 8 | route 和播放器单击手势窗口 |
| `test/app/router/app_router_test.dart` | 6 | route/redirect |
| `test/features/settings/presentation/import_confirm_dialog_test.dart` | 6 | import dialog 和异步导入 |
| `test/features/chat/chat_screen/chat_screen_responsive_cases.dart` | 5 | drawer/sheet/sidebar |
| `test/features/favorites/favorites_screen_basics_cases.dart` | 5 | route 和收藏状态 |
| `test/features/sync/sync_screen/sync_screen_render_cases.dart` | 5 | tab 和连接状态 |
| `test/features/history/history_screen/history_screen_search_cases.dart` | 4 | 搜索防抖 |
| `test/features/media/presentation/video_player_page_test.dart` | 4 | 真实网络错误等待 |
| `test/features/media/presentation/shuffle_appbar_actions_test.dart` | 3 | route 和单击手势窗口 |
| `test/features/settings/settings_screen/settings_screen_responsive_cases.dart` | 3 | responsive overlay |
| `test/features/settings/settings_screen/settings_screen_test_helpers.dart` | 3 | tab/dialog helper |
| `test/features/sync/sync_screen/sync_screen_responsive_cases.dart` | 3 | tab 和 responsive layout |
| `test/integration/bootstrap_integration_test.dart` | 3 | setup |
| `test/app/shell/app_shell_scaffold_test.dart` | 2 | route/drawer |
| `test/features/history/history_screen/history_screen_pagination_bar_cases.dart` | 2 | 页码状态 |
| `test/features/media/presentation/media_route_pages_test.dart` | 2 | route 和 fake 初始化 |
| `test/features/sync/presentation/widgets/interface_selector_test.dart` | 1 | 同步 selection |
| `test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart` | 1 | import dialog |
| `test/features/sync/sync_screen/sync_screen_test_helpers.dart` | 1 | dialog helper |
| `test/widget_test.dart` | 1 | setup |

目标不是把等待隐藏到另一个固定时长，而是按第四节的等待分类逐处迁移。

### 3.3 `find.byKey` 基线

共 39 处，分布如下：

| 文件 | 约计数 | 当前依赖 |
|---|---:|---|
| `test/features/settings/settings_screen/settings_screen_test_helpers.dart` | 17 | 表单内部字段 Key |
| `test/features/settings/presentation/model_config_form_dialog_test.dart` | 13 | 字段、拉取按钮和远端模型 checkbox Key |
| `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart` | 7 | 模板变量字段和消息节点 ID Key |
| `test/features/chat/chat_screen/chat_screen_test_helpers.dart` | 1 | composer Key |
| `test/features/chat/widgets/message_anchor_rail_test.dart` | 1 | rail 容器 Key |

### 3.4 真实时间与微时序基线

- `Future.delayed` 共 58 处：13 处 `Duration.zero`，45 处非零延时。
- 非零延时完整分布：
  - `chat_sessions_controller_stop_cases.dart`：29 处；
  - `chat_lifecycle_integration_test.dart`：5 处；
  - `chat_sessions_controller_generation_cases.dart`：4 处；
  - `sync_udp_discovery_test.dart`：3 处；
  - `sse_log_buffer_test.dart`、`chat_generation_run_test.dart`、`background_chat_repository_lifecycle_test.dart`、`fake_chat_completion_client.dart` 各 1 处。
- `Duration.zero` 完整分布：`chat_generation_race_contract_test.dart` 7 处、`chat_generation_coordinator_test.dart` 3 处，`composer_draft_controller_test.dart`、`chat_sessions_controller_persistence_test.dart`、`sync_client_controller_test.dart` 各 1 处。
- History 搜索用例 4 处使用 `searchDebounce + 50ms`。
- 模板变量用例 2 处使用 `variableReconcileDebounce + 50ms`。
- 聊天 fake 的 `chunkDelay` 只有一个测试消费者，不构成应保留的公共测试 API。

### 3.5 已检查且可复用的完成信号

| 位置 | 可复用信号 | 结论 |
|---|---|---|
| `BackgroundChatConversationRepository` | `save()` Future、worker ACK、`flush()` | 足以替代 100ms 等待，不改源码 |
| `ChatSessionsState` | `generation.phase`、`isStreaming`、`isAutoRetryWaiting`、`streamingReply` | 足以表达启动、增量、重试等待和终态 |
| 生成测试 fake host | `prepare/completeAttempt` gate、progress 投影 | 扩充测试侧 wait helper 即可 |
| stop case fake repository | `saveReached`、`stopSaveReached` gate | 直接复用，不增加生产接口 |
| WidgetTester | fake clock 和精确 `pump(Duration)` | 足以测试 History/模板 Timer |
| fake video controller | 可在测试侧扩展初始化结果 | 足以替代真实网络失败 |
| `SseLogBuffer` | 现有 `flush()` 不能保证等待已启动的自动 flush | 需要最小生产语义修正 |

### 3.6 WidgetTester 虚拟时间基线

除 `pumpAndSettle` 外，当前还有 53 处 `tester.pump(Duration)`。这类调用不消耗等量墙钟时间，但仍可能把测试绑在实现时序上，必须按以下类别审计：

| 类别 | 当前代表位置 | 处理 |
|---|---|---|
| fake 初始化/异步状态余量 | video/media route 的 100ms、chat streaming 的 250ms | 改为 fake 完成、受控流/Provider 状态后单帧 |
| Flutter 手势识别窗口 | 双击间隔 100/150ms、单击解析 350/400/500ms、长按 600ms | 改用 `kDoubleTapMinTime`、`kDoubleTapTimeout`、`kLongPressTimeout` 等 Flutter 公开常量 |
| 有限视觉动画 | notification 入退场 300ms、image zoom 250ms | 改用对应 finite-animation helper |
| 产品 Timer 行为 | 中央提示 1 秒、控制栏自动隐藏 3 秒 | 精确推进契约时长；不得使用 4 秒等余量，并保留行为说明 |
| 防抖边界前观察 | 模板变量 50ms | 输入后单帧验证未触发，再精确推进公开 debounce 常量 |

最终不允许 `tester.pump(const Duration(milliseconds: <魔法数字>))`。亚秒级等待必须改成 Flutter/产品公开常量或命名动画 helper；秒级产品 Timer 只保留精确契约值。

---

## 四、目标测试契约与 helper 设计

### 4.1 等待决策表

每一处存量等待必须先归类，再选择唯一对应方案：

| 等待对象 | 允许的方式 | 禁止的方式 |
|---|---|---|
| 同步 Provider/Repository 变更后的 UI 帧 | `tester.pump()` 一次 | `pumpAndSettle`、任意固定毫秒 |
| Provider 应用状态 | `waitForProviderState(...)`，再 `tester.pump()` | polling + `Future.delayed` |
| SSE/受控流开始监听 | `ControlledChatCompletionStream.listened` | `Future.delayed(1ms)` |
| SSE 增量已进入状态 | Provider predicate 或 fake host projection | chunk delay、微任务循环 |
| 后台 SQLite 保存 | `await save()` / `await flush()` / fake gate | 100ms 经验等待 |
| I/O 自动 flush | 公开 `flush()`/`drain()` Future | 写入后 sleep 50ms |
| Route/Dialog/Menu/Tab/Scroll 动画 | 对应命名的 finite-animation helper | 业务文件直接 `pumpAndSettle` |
| 产品 Timer | `tester.pump(公开时长常量或明确契约值)` | `常量 + 50ms`、真实 sleep |
| 负向事件 | 用后续正向事件夹住观察窗口，或等待流/操作终态后断言计数 | 只等待一段时间然后断言“没发生” |
| UDP 资源释放/无数据窗口 | 保留现有非零 delay，登记例外 | 扩大到其他文件 |

### 4.2 Provider 状态等待 helper

新增 `test/helpers/async_test_signals.dart`，提供以下 API：

```dart
Future<StateT> waitForProviderState<StateT>({
  required ProviderContainer container,
  required ProviderListenable<StateT> provider,
  required bool Function(StateT state) matches,
  required String description,
  Duration timeout = const Duration(seconds: 5),
});
```

实现要求：

1. 使用 Riverpod 3.4.2 的 `ProviderContainer.listen<StateT>`。
2. `fireImmediately: true`，避免调用方在注册监听前状态已经满足而漏事件。
3. listener 首次满足 predicate 时完成 `Completer<StateT>`；重复满足不得二次完成。
4. `onError` 将 Provider 错误和 stack trace 传给 completer。
5. `ProviderSubscription` 必须在 Future `whenComplete` 中关闭；不能在 listener 内引用尚未完成赋值的 subscription。
6. `.timeout` 错误必须包含 `description`，超时仅作为失败保护。
7. 不提供轮询间隔参数，不在实现中调用 `Future.delayed`。

在 `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart` 增加薄封装：

```dart
Future<ChatSessionsState> waitForState(
  bool Function(ChatSessionsState state) matches, {
  required String description,
});
```

薄封装只转调共享 helper，不复制 Riverpod listener 逻辑。

### 4.3 受控聊天流

修改 `test/helpers/fake_chat_completion_client.dart`：

- 删除 `enqueueChunks`/`enqueueDeltas` 的 `chunkDelay` 参数及内部真实 `Future.delayed`。
- 新增 `ControlledChatCompletionStream`，内部持有单订阅 `StreamController<ChatCompletionChunk>`。
- 公开：
  - `Future<void> get listened`：`onListen` 时完成；
  - `void add(ChatCompletionChunk chunk)`；
  - `void addError(Object error, [StackTrace? stackTrace])`；
  - `Future<void> close()`。
- `FakeChatCompletionClient.enqueueControlledStream()` 创建、排队并返回该对象。
- `streamCompletion()` 取到受控流时原样返回其 stream，仍继续记录 `requestHistory` 和 `requestedModels`。
- 测试必须先启动 send/run，再 `await controlled.listened`，之后才发送 chunk。

这套 API 只控制测试输入顺序，不改变生产 SSE 解析或 UI 节流。

### 4.4 有限动画 helper

新增 `test/helpers/widget_test_animation.dart`。业务测试允许使用以下窄职责 API：

```dart
Future<void> settleRouteTransition(WidgetTester tester);
Future<void> settleOverlayTransition(WidgetTester tester);
Future<void> settleTabTransition(WidgetTester tester);
Future<void> settleScrollMotion(WidgetTester tester);
Future<void> settleAnimatedWidgetTransition(WidgetTester tester);
```

所有函数转调同一个私有 `_settleFiniteAnimation(...)`；私有实现是全仓唯一直接调用 `pumpAndSettle` 的位置：

- step 使用 50ms；
- timeout 使用 2 秒；
- timeout 是“有限动画没有结束”的失败保护，不代表测试必须等待 2 秒；
- helper 不导入生产动画时长，不泄露“再多等一点”的余量；
- 不提供通用公开 settle API。

选择规则：

- `Navigator`/GoRouter push、pop、redirect：`settleRouteTransition`；
- Dialog、Menu、BottomSheet、Drawer 开合：`settleOverlayTransition`；
- `TabController`/`TabBarView`：`settleTabTransition`；
- `PageView`、ballistic scroll、scroll-to-bottom：`settleScrollMotion`；
- `AnimatedCrossFade`、`AnimatedSize`、rail 展开收起等有限组件动画：`settleAnimatedWidgetTransition`；
- 如果只是等待 Future、Repository 或 Provider，禁止调用上述任一 helper。

### 4.5 Finder 契约

所有替换必须继续定位用户可以感知的目标：

| 当前 Key 用途 | 替代 Finder |
|---|---|
| composer `chat-message-composer` | 在 ChatScreen 范围内定位带 `正文` label 的 `TextField` |
| anchor rail 容器 | 定位 `第 N 条用户消息：<preview>` 的 semantics；需要 hover 时对第一条语义节点操作 |
| 消息 ID Key | 先按完整可见用户消息文本找到对应消息气泡，再在该气泡内定位 `编辑消息` tooltip/button |
| `template-variable-title` | 在模板变量区域定位 label 为 `title` 的 `TextField` |
| 设置表单字段 Key | 在具体 dialog/widget 类型下，以可见 label 定位 `TextFormField`/`TextField` |
| 模型拉取按钮 Key | `find.widgetWithText(FilledButton, '拉取模型')`；加载态按 `正在拉取...` |
| 模型选择 checkbox Key | 以远端模型名找到所属 row，再找 row 内 `Checkbox` 角色 |

设置 helper 使用以下稳定可见标签：

- 服务商：`服务商名称`、`API URL`、`API Key`；
- 模型：`显示名称`、`API 模型名称`、`支持深度思考`；
- 预设 Prompt：`预设 Prompt 名称`、`标题`、`Prompt 内容`；
- 固定序列：`序列名称`、`步骤标题`、`步骤内容`；
- 模板：`标题`、`模板提示词`，动态变量用变量名或 `变量名（数字）`；
- 记忆 Prompt：`名称`、`记忆总结提示词`。

`标题`、`名称` 等重复标签必须先按 dialog/widget 类型限定祖先范围；禁止直接使用不限定范围的 `find.text('标题').first` 掩盖歧义。

### 4.6 日志在途写入完成语义

修改 `lib/core/logging/sse_log_buffer.dart`：

1. 用 `Set<Future<void>>` 跟踪已经从内存 buffer 取走、但 `store.appendLines` 尚未完成的原始 Future。
2. 自动 flush 启动 append 时先把原始 Future 加入集合；用同时提供 success/error 回调的旁路 listener 在两条路径都移除它，`flush()`/`Future.wait` 仍等待原始 Future，以保留错误。
3. `flush()` 即使发现当前 buffer 为空，也必须复制并等待调用时已经在途的 Future；若本次也启动了 append，该 Future 也属于快照。
4. `drain()` 继续通过 `flush()` 保证返回时缓冲内容和在途写入都完成。
5. append 异常仍通过原始写入 Future 和随后等待该在途工作的 `flush()` 暴露，不吞异常，不改变行内容、阈值和自动 flush 条件。
6. 不新增仅供测试使用的 getter，不更改 flush 阈值或计时。

为避免并发集合修改，等待时先复制当前集合快照；若 append 完成后又产生新的调用，新的调用不属于当前 `flush()` 调用前的工作，不需要追赶无限新增任务。

### 4.7 测试策略门禁

新增 `test/architecture/test_resilience_policy_test.dart`。门禁扫描 `test/**/*.dart`，路径统一为 `/`，并满足：

- `find.byKey`：允许列表为空；
- 直接 `pumpAndSettle`：只允许 `test/helpers/widget_test_animation.dart`，且精确 1 处；
- 任意 `Future.delayed`：同时识别 `Future.delayed(...)` 与 `Future<void>.delayed(...)` 等泛型写法；只允许 `test/features/sync/data/sync_udp_discovery_test.dart`，且精确 3 处；
- `chunkDelay`：0 处；
- `tester.pump(... + Duration(...))` 或已知 debounce 常量加余量：0 处。
- `tester.pump(const Duration(milliseconds: <字面量>))`：0 处；手势使用 Flutter 常量，有限动画使用命名 helper。

实现要求：

- 扫描器先用一个小型词法状态机把 `//`、`/* ... */` 注释和单/双/三引号字符串内容替换为空白，同时保留换行，之后再计数；不得用会被 URL、转义引号或多行字符串破坏的单个“去注释正则”。
- `Future` 延时匹配使用等价于 `Future(?:<[^>]+>)?\.delayed` 的模式；UDP 外的零时长与非零时长调用都不允许，不能只搜索字面量 `Future.delayed`。
- 亚秒虚拟时间匹配必须覆盖换行写法；至少识别 `tester.pump` 调用中直接构造的 `Duration(milliseconds: ...)`，不能只做单行 grep。
- 策略测试自身仍用字符串片段拼接待查 token，形成第二层自匹配保护。
- 例外使用“路径 -> 精确数量 + 原因”结构；少于允许数量也失败，防止陈旧豁免永远保留。
- UDP 的原因写成“外部 socket 资源释放与负向观测，已有 udp tag 且 CI 排除”；不得使用临时审查编号。
- 门禁由现有 `flutter test` 自动运行，不修改 workflow。

---

## 五、逐文件迁移矩阵

### 5.1 共享 harness 与 feature helpers

| 文件 | 修改 |
|---|---|
| `test/helpers/test_harness.dart` | 保持 `pumpTestApp()` 首帧只 `pump()` 的契约；补充 doc 说明返回时只保证首帧和同步依赖完成，不承诺动画/异步业务完成。不得在这里加入 settle。 |
| `test/helpers/fixtures.dart` | 不修改；已确认仅负责类型安全 fixture。 |
| `test/helpers/async_test_signals.dart` | 新增 Provider 状态等待 helper。 |
| `test/helpers/async_test_signals_test.dart` | 新增立即命中、后续命中、错误、超时和 subscription 清理测试。 |
| `test/helpers/widget_test_animation.dart` | 新增五个按场景命名的有限动画 helper。 |
| `test/helpers/widget_test_animation_test.dart` | 新增有限动画完成和无限动画超时保护测试。 |
| `test/helpers/fake_chat_completion_client.dart` | 新增受控流，删除真实 chunk delay。 |
| `test/features/chat/chat_screen/chat_screen_test_helpers.dart` | composer finder 改为可见 label；增加等待生成 phase/streaming content 的薄 helper；发送动作本身只 pump 一帧。 |
| `test/features/settings/settings_screen/settings_screen_test_helpers.dart` | tab 与 overlay 使用命名 helper；17 个字段 finder 全部改为“dialog 类型 + 可见 label”。 |
| `test/features/sync/sync_screen/sync_screen_test_helpers.dart` | import dialog 使用 overlay helper；普通 Provider 刷新只 pump。 |

### 5.2 聊天 application/data/integration 测试

| 文件 | 精确迁移 |
|---|---|
| `test/features/chat/application/chat_generation_run_test.dart` | 删除本地 `pump([ms])` 延时函数；受控流用 `listened`；prepare/attempt/retry 用 fake host gate 或投影状态等待；停止重试先等待 `retryWaiting` 再 stop；late callback 先 close/完成 run Future 再断言。 |
| `test/features/chat/application/chat_generation_coordinator_test.dart` | `Duration.zero` 改为 host phase/progress wait 和受控流监听。 |
| `test/features/chat/application/chat_generation_race_contract_test.dart` | 保留现有 `awaitReached/release` repository gates；其余零时长 flush 改为 Provider phase、stream listener 或保存 gate。 |
| `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_generation_cases.dart` | 4 处 1ms 等待分别改为受控流 `listened`、`streamingReply.content`/`finishReason` predicate。 |
| `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_stop_cases.dart` | 29 处等待逐类删除：开始监听等 `listened`；partial chunk 等 Provider content；二次 request 等第二条受控流 `listened`；自动重试等 `isAutoRetryWaiting`；慢保存复用 `saveReached/stopSaveReached`；late done/error 先完成 close/send Future；dispose 用 run Future/gate 收口。不得保留 polling loop。 |
| `test/features/chat/application/chat_sessions_controller_persistence_test.dart` | chunk 后的 `Duration.zero` 改为等待 streaming content/保存完成。 |
| `test/features/chat/application/composer_draft_controller_test.dart` | 删除 5 次 `Duration.zero` 的 `_flushMicrotasks`；负向监听断言用“无关修改 -> 下一次相关选择事件”夹住窗口，按通知计数断言无额外回调。 |
| `test/features/chat/data/background_chat_repository_lifecycle_test.dart` | 第一次 `await save()` 已收到 ACK；直接发第二次保存并等待其 Future，删除中间 100ms。 |
| `test/integration/chat_lifecycle_integration_test.dart` | 5 处 5ms 改为受控流 `listened` 和状态 predicate；checkpoint busy guard 明确等进入 generation active phase 后触发。 |

若 `chat_sessions_controller_test.dart` 是 case 注册入口，只添加/调整 import，不把 case 内容搬回入口文件。

### 5.3 聊天 Widget 测试

| 文件 | `pumpAndSettle` 分类与替换 |
|---|---|
| `chat_screen_basics_cases.dart` | setup 用单帧；生成等待 terminal phase；dialog/menu 用 overlay；composer 展开收起用 animated-widget；scroll-to-bottom 用 scroll。 |
| `chat_screen_branching_cases.dart` | 分支发送/重试等 generation 状态；分支选择菜单与删除确认用 overlay；树选择的同步更新只 pump。 |
| `chat_screen_favorites_cases.dart` | 生成等状态；收藏/收藏夹 dialog 用 overlay；Repository 结果只 pump。 |
| `chat_screen_responsive_cases.dart` | 初始布局只 pump；drawer/sheet 用 overlay；sidebar 的有限宽度动画才用 animated-widget。 |
| `chat_screen_streaming_cases.dart` | 受控流逐 chunk 推送并等待状态；reasoning 展开用 animated-widget；复制等同步动作只 pump。 |
| `chat_screen_workspace_ownership_cases.dart` | 生成等状态；模板菜单用 overlay；remount 与编辑状态用单帧；删除全部 7 个 Key finder。 |
| `message_anchor_rail_test.dart` | 用语义项定位；展开/收起动画用 animated-widget；focus/selection 的同步变化只 pump。 |

### 5.4 Settings、History、Favorites

| 文件组 | 迁移规则 |
|---|---|
| `settings_screen_models_and_prompts_cases.dart` | tab 用 tab helper；dialog/menu 用 overlay；CRUD Future 完成后单帧；模型拉取由测试 Completer 控制成功/失败，不用 settle 等网络；模板变量 Timer 精确推进公开 debounce 常量。 |
| `settings_screen_fixed_prompt_sequences_cases.dart` | tab/overlay 分类；序列保存、重排等同步 Controller 更新只 pump。 |
| `settings_screen_responsive_cases.dart` | setup 单帧；窄屏 drawer/sheet 用 overlay；布局变化本身只 pump。 |
| `model_config_form_dialog_test.dart` | 13 个 Key finder 改为 label/role；模型拉取 Future 用 Completer，加载一帧、完成一帧；overlay 动画只在开关 dialog 时等待。 |
| `import_confirm_dialog_test.dart` | dialog 开关用 overlay；导入 Future 完成后单帧。 |
| `output_processing_tab_test.dart` | tab 用 tab helper；添加/编辑 dialog 用 overlay；链式规则状态更新用单帧。 |
| `history_screen_search_cases.dart` | 每次输入后先在边界前断言旧结果，再精确 `pump(HistoryScreen.searchDebounce)`，下一帧断言新结果；删除 `+50ms` 和随后 settle。 |
| `history_screen_actions_cases.dart` | 删除/重命名确认用 overlay；action 完成后单帧。 |
| `history_screen_pagination_bar_cases.dart` | 页码切换是同步状态则只 pump；只有真实滚动时用 scroll helper。 |
| Favorites 三个 case 文件 | 导航用 route；dialog 用 overlay；Repository/Provider 状态用单帧。 |

模板变量测试与 History 搜索测试必须各至少保留一条“边界前尚未触发、精确边界触发”的行为断言，证明没有通过放宽产品时间掩盖问题。

### 5.5 App、Media、Sync 与基础集成

| 文件组 | 迁移规则 |
|---|---|
| `test/widget_test.dart`、`bootstrap_integration_test.dart` | setup 完成后只 pump；bootstrap 已 await 的资源不能再用 settle。 |
| `test/core/widgets/notification_bubble_accessibility_test.dart` | 入场/清理的 300ms 改用 animated-widget helper；dismiss 后语义立即退出只 pump 一帧，删除 50ms 魔法值。 |
| `app_router_test.dart` | GoRouter navigation/redirect 用 route helper；静态页 setup 单帧。 |
| `app_shell_scaffold_test.dart` | drawer 用 overlay，页面切换用 route；普通 selection 单帧。 |
| `image_viewer_page_test.dart` | PageView drag/ballistic 用 scroll；双击间隔使用 `kDoubleTapMinTime`，缩放结束用 animated-widget；删除 150/250ms 魔法值。 |
| `media_browser_navigation_test.dart`、`shuffle_appbar_actions_test.dart` | 播放器外层双击识别导致的单击延迟精确推进 `kDoubleTapTimeout`，随后 route helper；删除 400ms。 |
| `media_route_pages_test.dart` | fake 初始化由完成帧表达，删除 100ms；Navigator/GoRouter 用 route。 |
| `video_player_page_test.dart` | 见第六节任务 2；清除全部 5 秒 settle 和真实网络失败。双击/长按使用 Flutter 手势常量；提示消失和控制栏隐藏精确推进 1 秒/3 秒产品契约，有限动画另用 helper。 |
| `video_player_accessibility_test.dart` | fake 初始化和失败只 pump 所需帧；长按/单击使用 Flutter 手势常量；4 秒改为精确 3 秒自动隐藏边界，再等待有限淡出动画。 |
| `interface_selector_test.dart` | 接口选择和持久化是同步/await 后状态，只 pump。 |
| `sync_screen_import_dialog_cases.dart` | dialog 用 overlay；导入状态等 Provider predicate。 |
| `sync_screen_render_cases.dart`、`sync_screen_responsive_cases.dart` | tab 用 tab helper；连接状态等 Provider；布局单帧。 |
| `sync_client_controller_test.dart` | 删除 `flushAsync`/`Duration.zero`；在 fake transport add/close 前注册 Provider phase predicate，等待 connected/disconnected/error。 |
| `sync_udp_discovery_test.dart` | 保留 3 处真实延时与 `udp` tag，代码不改；门禁登记精确例外。 |

---

## 六、实施任务与独立提交节点

以下任务必须按顺序执行。每个提交节点都应保持工作区可分析、目标测试可运行；不得把多个提交压成一个“大治理”提交。

### 任务 0：建立可比较基线（不提交）

1. 确认 `git status --short` 为空；记录 `git rev-parse --short HEAD`。
2. 重新统计：

```powershell
rg -n "pumpAndSettle" test --glob "*.dart"
rg -n "find\.byKey" test --glob "*.dart"
rg --pcre2 -n "Future(?:<[^>]+>)?\.delayed|chunkDelay|searchDebounce|variableReconcileDebounce" test --glob "*.dart"
```

3. 连续运行 3 次 CI 同构测试（包括 `--exclude-tags=udp --coverage`），保留每次耗时和退出码；基线取中位数。每次必须重定向到不同日志，不能直接打印完整测试流：

```powershell
$phase15Baseline = @()
1..3 | ForEach-Object {
  $phase15Run = $_
  $phase15Log = "phase15-baseline-$phase15Run.log"
  $phase15Watch = [System.Diagnostics.Stopwatch]::StartNew()
  flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 |
    Out-File -Encoding utf8 $phase15Log
  $phase15Exit = $LASTEXITCODE
  $phase15Watch.Stop()
  Get-Content -Tail 20 $phase15Log
  if ($phase15Exit -ne 0) {
    throw "baseline run $phase15Run failed: EXIT=$phase15Exit"
  }
  $phase15Baseline += [pscustomobject]@{
    Run = $phase15Run
    Seconds = $phase15Watch.Elapsed.TotalSeconds
    Log = $phase15Log
  }
}
$phase15Baseline | Sort-Object Seconds | Format-Table
```
4. 如基线自身失败，先确认是否与当前提交无关；本阶段不得顺手修其他 Phase 的失败。

验收：有一份本地执行记录，包含 HEAD、三次耗时、三次 `EXIT=0` 和上述计数。

### 任务 1：建立共享等待原语并清理 setup settle

修改：

- 新增 `test/helpers/async_test_signals.dart`；
- 新增 `test/helpers/async_test_signals_test.dart`；
- 新增 `test/helpers/widget_test_animation.dart`；
- 新增 `test/helpers/widget_test_animation_test.dart`；
- `test/helpers/test_harness.dart`；
- `test/features/chat/chat_screen/chat_screen_test_helpers.dart`；
- `test/features/settings/settings_screen/settings_screen_test_helpers.dart`；
- `test/features/sync/sync_screen/sync_screen_test_helpers.dart`；
- `test/widget_test.dart`；
- `test/integration/bootstrap_integration_test.dart`。

步骤：

1. 先为 `waitForProviderState` 写单元测试：立即命中、后续命中、Provider error、timeout、完成后不再监听。timeout 用例传 `Duration.zero`，只验证错误类型和 description，不引入真实毫秒等待。
2. 实现 Riverpod listener helper。
3. 为五类 finite animation helper 写最小测试：有限 animation 能完成；无限 animation 在 2 秒保护超时失败。只需覆盖私有实现一次，不为五个薄包装复制同构测试。
4. 更新三个 feature helper，只在能明确命名动画对象的位置转调新 helper。
5. 移除 widget/bootstrap setup 中的 settle，保持一帧 pump。

禁止：此时不要一次性改完全部 34 个业务文件；本提交只建立原语、helper 接口和 setup 契约。

目标测试：共享 helper 自身测试、`test/widget_test.dart`、`bootstrap_integration_test.dart`，以及三个 feature 的测试入口各跑一次。

提交：`test: 收紧共享测试等待工具`

### 任务 2：先消除 5 秒播放器等待

修改：

- `test/features/media/helpers/fake_video_player_controller.dart`；
- `test/features/media/presentation/video_player_page_test.dart`；
- `test/features/media/presentation/video_player_accessibility_test.dart`（只统一 fake 初始化/失败完成方式，不改无关 a11y 契约）。

步骤：

1. 给 fake controller 增加可配置的 `initializeError`、`initializeCallCount` 和 `waitForInitializeCount(int expected)`；默认仍立即成功，不影响现有测试。waiter 对已经达到的计数立即完成，对未来计数用按 expected 保存的 Completer 完成，并带 5 秒失败保护。
2. `initialize()` 每次先递增计数并完成所有 `expected <= initializeCallCount` 的 waiter；被配置失败时再确定性抛出错误，否则更新 fake value。
3. 错误页测试统一通过 production 已有 controller factory 注入该 fake；删除真实 controller 和无效端口 URL 路径。
4. 首次错误：pump build 帧，等待 fake 初始化信号，再 pump 一帧，断言 inline 错误和重试入口。
5. 重试错误：点击重试后等待第二次初始化信号，再 pump 一帧，断言 `initializeCallCount == 2` 且错误仍可见。初始化信号需要按调用次数等待，不能复用首次已经完成的单个 Completer。
6. `_pumpInit` 与 accessibility 的 `_pumpVideo` 删除“初始化完成”100ms，改为初始化信号 + 单帧。
7. accessibility 中的私有失败 subclass 改用同一个可配置 fake，避免两套失败时序。
8. 删除 4 处 5 秒 settle；不改变产品 retry、控制栏和手势时长。手势魔法时长的全面迁移留在任务 12，避免本提交混入另一类改动。

目标测试：`video_player_page_test.dart` 连续运行 10 次；确认无网络访问和 5 秒墙钟等待。

提交：`test(media): 移除播放器错误用例的真实网络等待`

### 任务 3：修正 SSE 日志已有在途写入的完成语义

修改：

- `lib/core/logging/sse_log_buffer.dart`；
- `test/core/logging/sse_log_buffer_test.dart`。

步骤：

1. 先增加失败测试：达到自动 flush 阈值后立即 `await buffer.flush()`，返回时文件必须已经含目标行。
2. 增加 in-flight Future 集合并实现第四节完成语义。
3. 使用当前真实临时文件存储覆盖“空 buffer 但存在 in-flight append”：达到阈值后立刻调用第二次 `flush()`，其 Future 返回后直接读文件；不得为测试给 `AppLogStore` 增加延时或 mock 接口。
4. 保持异常链不被 `then/whenComplete` 的清理逻辑吞掉；不要求通过平台相关的只读文件权限制造错误测试。
5. 删除原测试中的 50ms delay。
6. 检查 `AppNetworkLogger.drain()` 现有调用仍按原 API 工作。

目标测试：`sse_log_buffer_test.dart`、相关 network logger 测试、`flutter analyze`。

提交：`fix(logging): 让日志 flush 等待在途写入`

### 任务 4：建立聊天受控流与生成状态等待

修改：

- `test/helpers/fake_chat_completion_client.dart`；
- chat application 的 controller harness；
- `chat_generation_run_test.dart`；
- `chat_generation_coordinator_test.dart`；
- `chat_generation_race_contract_test.dart`。

步骤：

1. 实现 `ControlledChatCompletionStream` 和 `enqueueControlledStream()`。
2. 删除 `chunkDelay`，将唯一消费者迁到受控流。
3. 给生成 fake host 添加按 phase/projection 完成的测试侧 waiter；不得轮询。
4. 按“启动 run -> await listened -> add chunk -> await projection -> close -> await run”顺序重写生成 run 用例。
5. coordinator 和 race contract 优先复用现有 gate；只有公开状态才走 `waitForProviderState`。
6. 搜索三个文件确认 `Future.delayed` 为 0。

目标测试：上述三个文件各连续 10 次；fake client 全部测试。

提交：`test(chat): 用受控流验证生成生命周期`

### 任务 5：治理 ChatSessionsController 的停止、重试与持久化竞态

修改：

- `chat_sessions_controller_generation_cases.dart`；
- `chat_sessions_controller_stop_cases.dart`；
- `chat_sessions_controller_persistence_test.dart`；
- case 注册入口/测试 harness 的必要 import。

步骤：

1. 逐个用例在改动前写下所等待事件，按 5.2 表映射为唯一信号。
2. 删除 50×10ms、50×100ms 一类 polling loop。
3. 对第二次请求，不等 `requestHistory.length` 轮询；为第二条受控流预排队并等待其 `listened`。
4. 对自动重试，等待 `isAutoRetryWaiting == true`；触发 stop 后等待 terminal/cancelled phase。
5. 对 partial content，等待 `streamingReply.content` 精确等于期望片段后才 stop。
6. 对慢保存，严格按 `saveReached -> stop -> stopSaveReached/release -> Future 完成` 的顺序操作。
7. 对 late done/error，保存 send Future，完成/关闭受控流，再 await send Future；之后断言状态未被旧 callback 覆盖。
8. dispose 场景在 `runZonedGuarded` 中也必须有可 await 的 run/stream/gate 终态，不用 10ms 收集错误。

目标测试：controller 入口全文件连续 10 次，单独 stop case 入口连续 20 次；不得出现未处理异步错误。

提交：`test(chat): 移除停止与重试竞态的时间轮询`

### 任务 6：治理聊天集成、后台保存和负向监听等待

修改：

- `test/integration/chat_lifecycle_integration_test.dart`；
- `test/features/chat/data/background_chat_repository_lifecycle_test.dart`；
- `test/features/chat/application/composer_draft_controller_test.dart`。

步骤：

1. 集成测试使用受控流和 Provider phase，不保留 5ms。
2. 后台仓储 sequential batch 用两次 `await save()`/`flush()` 的 ACK 边界，不保留 100ms。
3. composer draft 用下一次相关正向事件夹住负向观察窗口，删除 `_flushMicrotasks`。
4. 逐文件确认不存在 `Future.delayed`。

目标测试：三个文件连续 10 次；后台仓储测试同时验证两批保存没有被错误合并。

提交：`test(chat): 以完成信号替代集成与持久化等待`

### 任务 7：治理同步状态等待，登记 UDP 例外

修改：

- `test/features/sync/application/sync_client_controller_test.dart`；
- 暂不改 `sync_udp_discovery_test.dart`。

步骤：

1. 删除 `flushAsync` 和零时长 microtask flush。
2. fake transport 发事件前注册 phase predicate，分别等待 connected、disconnected、error。
3. 容器 dispose 前关闭 fake transport 并等待 controller 终态，避免 dangling listener。
4. 记录 UDP 文件 3 个非零 delay 的用途和 tag，供最终门禁使用。

目标测试：sync client controller 连续 10 次；UDP 单文件在本机可用时跑一次，但不得因本机 UDP 不可用修改全局配置。

提交：`test(sync): 以连接状态替代微任务等待`

### 任务 8：清除聊天测试内部 Key Finder

修改：

- `test/features/chat/chat_screen/chat_screen_test_helpers.dart`；
- `chat_screen_workspace_ownership_cases.dart`；
- `test/features/chat/widgets/message_anchor_rail_test.dart`。

步骤：

1. composer finder 改为 `正文` label，先限定 ChatScreen/Composer 区域。
2. 模板变量按变量 label 定位，断言使用实际用户可见文本。
3. 编辑旧消息：以唯一的消息正文找到所属消息气泡，再在气泡内点 `编辑消息` tooltip。
4. anchor rail 以现有 semantics label 定位；hover/tap 施加在语义项，不再定位容器 Key。
5. 不删除 `KeyedSubtree(message.id)` 等可能负责元素身份的生产 Key。
6. `rg "find\.byKey"` 在这些文件中必须无输出。

目标测试：workspace ownership、anchor rail、chat screen 全入口。

提交：`test(chat): 改用可见行为定位聊天控件`

### 任务 9：清除 Settings 内部 Key Finder

修改：

- `test/features/settings/settings_screen/settings_screen_test_helpers.dart`；
- `test/features/settings/presentation/model_config_form_dialog_test.dart`。

步骤：

1. 为每种 dialog 建立类型限定的字段 finder；不要建立全局“第 N 个 TextField”助手。
2. 迁移 17 个 helper 和 13 个 dialog 测试使用点。
3. 拉取模型按钮按可见文本定位；远端模型 checkbox 按“模型名所在 row + Checkbox”定位。
4. 对模型加载过程使用测试 Completer：完成前断言 `正在拉取...`，完成后断言模型行，不用 settle 代替 Future。
5. `rg "find\.byKey" test/features/settings` 必须无输出。

目标测试：model dialog、settings screen 入口。

提交：`test(settings): 改用标签与角色定位表单控件`

### 任务 10：迁移聊天 Widget 的直接 settle

修改 5.3 列出的 7 个文件。

执行方式：

1. 按文件逐个迁移，不能全局替换字符串。
2. 每个原 settle 标记为：single frame、provider state、controlled stream、route、overlay、scroll、animated widget 七类之一。
3. 生成/保存类必须走前面完成信号；只有后四类可以调用 animation helper。
4. 每完成一个 case 文件就跑对应 chat screen 入口，避免 100+ 修改后才定位问题。
5. 最终 `rg "pumpAndSettle" test/features/chat` 无输出。

目标测试：chat screen、message anchor、application controller 全入口；chat screen streaming/branching/workspace 各连续 10 次。

提交：`test(chat): 按可观察状态收敛 Widget 等待`

### 任务 11：迁移 Settings、History 与 Favorites 的直接 settle

修改 5.4 列出的所有文件。

步骤：

1. Settings 先迁共享 tab/dialog helper，再迁各 case；异步模型拉取/保存走 Completer/Future。
2. History 搜索精确推进 `HistoryScreen.searchDebounce`，删除四处 `+50ms`。
3. 模板变量精确推进 `TemplatePromptFormDialog.variableReconcileDebounce`，删除两处 `+50ms`。
4. Favorites 的 route、overlay、同步 Repository 更新分别使用对应等待。
5. 每个 feature 完成后分别搜索直接 settle 和加余量模式。

目标测试：settings、history、favorites 三个 feature 的全部测试；搜索/模板 debounce 用例连续 20 次。

提交：`test: 收敛设置历史与收藏界面的等待`

### 任务 12：迁移 Core Widget、App、Media、Sync 和基础集成的直接 settle/魔法时长

修改 5.5 中除 UDP 之外的文件。

步骤：

1. Notification bubble 入退场用 animated-widget helper；dismiss 语义退出只 pump 一帧。
2. App 路由/壳层按 route/overlay 分类。
3. ImageViewer 的 PageView 与缩放分别用 scroll/animated-widget；双击两次 tap 的间隔用 `kDoubleTapMinTime`。
4. Media navigation 中等待单击胜出双击手势竞技场时使用 `kDoubleTapTimeout`，随后 route helper，删除 400ms。
5. Video 双击间隔用 `kDoubleTapMinTime`，单击解析用 `kDoubleTapTimeout`，长按触发用 `kLongPressTimeout`；fake method 完成后的 100ms 改为单帧。
6. 中央 seek/speed hint 消失精确推进 1 秒；控制栏自动隐藏精确推进 3 秒，再用 animated-widget helper 等待淡出动画。不得继续使用 4 秒或 500/600ms 余量。
7. Media route fake 初始化等待任务 2 的计数信号，删除 100ms。
8. Sync tab/dialog 用对应 helper，connection/import 完成走 Provider。
9. 清理 `test/widget_test.dart` 和 bootstrap 中残余 setup settle。
10. 全仓搜索确认直接 settle 只剩共享动画文件 1 处，且不存在 literal-millisecond `tester.pump`。

目标测试：app、media、sync、integration 全部测试。

提交：`test: 收敛导航媒体与同步界面的等待`

### 任务 13：增加持续门禁并完成审计

修改：

- 新增 `test/architecture/test_resilience_policy_test.dart`。

步骤：

1. 实现第四节精确 allowlist 扫描。
2. 在同一测试文件中对扫描器的内存 source map 写单元测试：注释/字符串不计数，泛型与非泛型 `Future.delayed` 都计数，多行 `tester.pump(Duration(milliseconds: ...))` 能识别；分别构造额外 `find.byKey`、额外 raw settle、额外 1ms delay、缺少一个允许项，证明新增违规和 stale allowance 都会失败。
3. 执行真实 `test/` 树门禁与全仓审计命令，确认：
   - raw settle 精确 1；
   - `find.byKey` 为 0；
   - 任意 `Future.delayed` 只有 UDP 3 处；
   - `chunkDelay` 为 0；
   - debounce 加余量为 0；
   - `tester.pump` 直接构造毫秒字面量为 0。
4. 检查保留的产品 Timer 虚拟 pump，每处都确实对应提示消失/自动隐藏行为；无需统一添加冗长注释，但等待意图必须能从测试名和上下文判断。

目标测试：policy test 单文件、全部 architecture tests、全量测试。

提交：`test: 防止脆弱等待与内部 Finder 回流`

---

## 七、测试与验证策略

### 7.1 每个提交前的最小验证

1. 对本提交所有 Dart 文件执行 `dart format`。
2. 对本提交涉及的 feature 运行单文件/入口测试，必须按项目要求重定向：

```powershell
flutter test path/to/test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 phase15-target.log
$phase15Exit = $LASTEXITCODE
Write-Host "EXIT=$phase15Exit"
Get-Content -Tail 150 phase15-target.log
```

3. 运行 `flutter analyze`。
4. 暂存后取得本提交 Dart 文件列表，再执行：

```powershell
dart format --output=none --set-exit-if-changed <本提交暂存的 Dart 文件列表>
```

非零退出不得提交。

### 7.2 高风险重复测试

最终至少连续 10 次运行以下集合；任一次失败即视为不稳定，禁止通过扩大 timeout 或增加延时解决：

- `test/features/chat/application/chat_generation_run_test.dart`；
- `test/features/chat/application/chat_generation_race_contract_test.dart`；
- `test/features/chat/application/chat_sessions_controller_test.dart`；
- `test/integration/chat_lifecycle_integration_test.dart`；
- `test/features/media/presentation/video_player_page_test.dart`；
- `test/features/settings/settings_screen_test.dart`；
- `test/core/logging/sse_log_buffer_test.dart`；
- `test/features/sync/application/sync_client_controller_test.dart`；
- `test/architecture/test_resilience_policy_test.dart`。

循环每轮写独立日志或追加带轮次前缀的摘要；不要把未经重定向的完整测试输出打到终端。

使用以下固定循环，确保每个文件各运行 10 次，而不是把同一个随机失败掩盖在组合入口中：

```powershell
$phase15HighRisk = @(
  'test/features/chat/application/chat_generation_run_test.dart',
  'test/features/chat/application/chat_generation_race_contract_test.dart',
  'test/features/chat/application/chat_sessions_controller_test.dart',
  'test/integration/chat_lifecycle_integration_test.dart',
  'test/features/media/presentation/video_player_page_test.dart',
  'test/features/settings/settings_screen_test.dart',
  'test/core/logging/sse_log_buffer_test.dart',
  'test/features/sync/application/sync_client_controller_test.dart',
  'test/architecture/test_resilience_policy_test.dart'
)
1..10 | ForEach-Object {
  $phase15Round = $_
  foreach ($phase15Target in $phase15HighRisk) {
    $phase15Name = [System.IO.Path]::GetFileNameWithoutExtension($phase15Target)
    $phase15Log = "phase15-repeat-$phase15Round-$phase15Name.log"
    flutter test $phase15Target --reporter compact 2>&1 |
      Out-File -Encoding utf8 $phase15Log
    $phase15Exit = $LASTEXITCODE
    if ($phase15Exit -ne 0) {
      Get-Content -Tail 150 $phase15Log
      throw "round $phase15Round failed: $phase15Target, EXIT=$phase15Exit"
    }
  }
}
```

### 7.3 CI 同构测试

按当前 workflow 排除 UDP，并使用 `dart_test.yaml` 当前 concurrency 8：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 | Out-File -Encoding utf8 phase15-ci.log
$phase15CiExit = $LASTEXITCODE
Write-Host "EXIT=$phase15CiExit"
Get-Content -Tail 150 phase15-ci.log
```

最终连续运行 3 次，取中位数与任务 0 同机基线比较：

- 三次都必须 `EXIT=0`；
- 不得出现偶发 retry 才通过；
- 中位时间不得劣于基线；若有显著变慢，先用测试日志定位等待对象，不能提高全局 timeout。

### 7.4 本地完整测试

最终严格执行项目规定命令，包括 UDP：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
$phase15FullExit = $LASTEXITCODE
Write-Host "EXIT=$phase15FullExit"
Get-Content -Tail 150 fltest.log
```

只有 `EXIT=0` 才算通过。如果 UDP 因本机网络权限失败，记录为环境结果并另行确认 CI 同构集合，但不得静默宣称“全量通过”，也不得在本阶段修改 UDP 隔离策略。

### 7.5 最终静态审计

```powershell
rg -n "find\.byKey" test --glob "*.dart"
rg -n "pumpAndSettle" test --glob "*.dart"
rg --pcre2 -n "Future(?:<[^>]+>)?\.delayed|chunkDelay" test --glob "*.dart"
rg -n "searchDebounce\s*\+|variableReconcileDebounce\s*\+|Duration\([^)]*\)\s*\+" test --glob "*.dart"
rg -U --pcre2 -n "tester\s*\.\s*pump\s*\(\s*(?:const\s+)?Duration\s*\(\s*milliseconds" test --glob "*.dart"
```

预期：

- 第一条无输出；
- 第二条只有共享 animation helper 的 1 处实现；
- 第三条只有 UDP 文件 3 个 delay，不存在任何 `Duration.zero`；
- 第四、第五条无输出。

### 7.6 最终代码质量检查

- `flutter analyze` 为 0 issue。
- 完整测试 `EXIT=0`。
- `git diff --check` 无空白错误。
- `git status --short` 只包含本阶段预期文件。
- 检查所有提交消息第一行符合 Conventional Commits。
- 检查没有测试专用生产 API、没有产品时长改动、没有 `.github`/`dart_test.yaml` 改动。

---

## 八、失败诊断规则

实施者遇到失败时按以下顺序处理，禁止第一反应增加等待时长：

1. **状态永不满足**：检查 waiter 是否在触发事件前注册、predicate 是否使用正确 phase、流是否已经 `listened`。
2. **受控流 add 时报未监听**：先 `await controlled.listened`，不要插入 1ms。
3. **Widget 只差一帧**：如果 Future/Provider 已明确完成，只 `tester.pump()`；如果是 route/overlay 动画，使用相应 helper。
4. **无限 animation 导致 timeout**：确认该屏幕是否存在持续 spinner；业务测试不应 settle 全树，应等待目标状态后 pump 单帧。不能提高 2 秒 helper timeout。
5. **Finder 找到多个**：增加用户可感知的祖先范围或语义，而不是 `.first`、索引或重新加 Key。
6. **Finder 找不到 label**：先确认当前 UI 实际可见文本；如果控件缺少必要可访问语义，可在不改变业务的前提下补 Semantics，但必须同时增加语义行为测试。不能添加仅供测试的隐形文字。
7. **日志 flush 测试挂起**：检查 in-flight Future 是否在所有成功/失败路径移除，以及 `flush()` 是否等待快照。
8. **重复测试偶发失败**：保存失败轮日志，定位未收口 Future/stream/subscription；不能用重跑掩盖。
9. **UDP 失败**：只记录环境和 tag 行为，不把 UDP 改造扩入本阶段。

---

## 九、独立提交清单

| 顺序 | Commit message | 主要内容 |
|---:|---|---|
| 1 | `test: 收紧共享测试等待工具` | Provider waiter、有限动画 helper、setup 契约 |
| 2 | `test(media): 移除播放器错误用例的真实网络等待` | fake 初始化失败、删除 5 秒 settle |
| 3 | `fix(logging): 让日志 flush 等待在途写入` | 最小生产完成语义与测试 |
| 4 | `test(chat): 用受控流验证生成生命周期` | controlled stream、run/coordinator/race |
| 5 | `test(chat): 移除停止与重试竞态的时间轮询` | controller stop/retry/persistence |
| 6 | `test(chat): 以完成信号替代集成与持久化等待` | integration、background ACK、composer |
| 7 | `test(sync): 以连接状态替代微任务等待` | sync controller，UDP 不改 |
| 8 | `test(chat): 改用可见行为定位聊天控件` | chat Key finder 清零 |
| 9 | `test(settings): 改用标签与角色定位表单控件` | settings Key finder 清零 |
| 10 | `test(chat): 按可观察状态收敛 Widget 等待` | chat Widget settle 迁移 |
| 11 | `test: 收敛设置历史与收藏界面的等待` | settings/history/favorites |
| 12 | `test: 收敛导航媒体与同步界面的等待` | app/media/sync/bootstrap |
| 13 | `test: 防止脆弱等待与内部 Finder 回流` | policy gate、最终审计 |

每个提交都应独立可回滚。第 3 个提交是唯一包含生产源码的提交；如果实施中发现还需要修改其他 production application/core 文件，必须先证明现有状态、ACK、gate 和虚拟时钟无法表达完成，并重新核对 Phase 范围，不能直接扩张。

---

## 十、Definition of Done

以下项目必须全部满足：

- [ ] 共享 setup helper 只负责首帧，不含全局 settle。
- [ ] 4 处 5 秒 settle 全部删除，视频错误测试不访问真实网络。
- [ ] 34 个原直接 settle 文件均已逐处分类；业务测试不直接调用 `pumpAndSettle`。
- [ ] raw `pumpAndSettle` 全仓只在 animation helper 中精确 1 处。
- [ ] `find.byKey` 在 `test/` 中为 0。
- [ ] `chunkDelay` 为 0。
- [ ] UDP 外 `Future.delayed` 为 0；UDP 精确保留 3 处并由门禁登记。
- [ ] History 和模板变量测试不含 `+50ms` 或其他边界余量。
- [ ] 聊天停止、重试、late callback、dispose、慢保存测试全部由受控流/状态/gate 收口。
- [ ] 后台聊天保存测试等待 ACK，不含固定等待。
- [ ] `SseLogBuffer.flush()` 等待调用前已经在途的 append，并覆盖成功/失败测试。
- [ ] Sync controller 测试等待公开 phase，不做 microtask flush。
- [ ] 所有保留虚拟时间等待都对应明确的产品动画、手势窗口或 Timer。
- [ ] 韧性架构门禁能拒绝新增直接 settle、Key finder、真实 delay 和余量。
- [ ] `dart_test.yaml`、CI workflow 和产品业务时长未改变。
- [ ] 所有改动 Dart 文件已格式化，暂存后格式检查通过。
- [ ] `flutter analyze` 通过。
- [ ] 高风险集合连续 10 次通过。
- [ ] CI 同构全量连续 3 次通过，时间中位数不劣于实施前同机基线。
- [ ] 包含 UDP 的本地完整测试 `EXIT=0`；若环境阻塞，已如实记录而非隐藏。
- [ ] 最终工作区只含 Phase 15 预期改动，提交粒度与第九节一致。
