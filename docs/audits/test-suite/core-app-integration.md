# Core、App 与集成测试审计

## 范围与证据

- 范围：`test/core/**`、`test/app/**`、`test/integration/**`、`test/architecture/**`、`test/android/**`、`test/helpers/**` 与根级测试入口。
- 静态规模：76 个 Dart 文件、14,360 行、398 个显式 `test` / `testWidgets` 声明。
- 全仓规模：259 个测试文件、60,975 行测试代码；生产 `lib/**` 为 52,123 行，测试/生产行数比为 1.17。
- 最近一次现有 `logs/fltest.log` 记录 2,131 个测试、总耗时 1 分 46 秒；并行执行下，`app_router_test.dart` 覆盖约 8 秒时间窗，`sync_workspace_screen_test.dart` 覆盖约 9 秒时间窗，说明 widget 集成矩阵是本范围主要运行成本。

## 必须保留的底线

- `app_database_migration_test.dart` 中所有已发布 schema 的顺序迁移、数据保留、回滚和拒绝语义；这些是持久化兼容契约，不以覆盖率换取删减。
- LLM/peer HTTP 信任域隔离、Header/日志脱敏、SSE 任意 byte 切分与 idle timeout、HTTP 错误/取消传播。
- 架构边界的真实仓库门禁和每类禁止依赖的代表用例。
- Windows 返回输入、Android MethodChannel、视频全屏控制器和 generation 通知协调器中的竞态、token 隔离、取消、失败降级等平台边界。
- 每类可序列化 GoRouter 深链至少一个 round-trip、无效/已删除 ID 的恢复路径，以及关键键盘与 Semantics 行为。
- 最小集成脊柱：bootstrap、一次聊天生成与持久化、一次协议路由、一次原生通知停止、一次 Sync loopback、一次 Windows 根部返回。

## Findings（预计净删行数降序）

shrink: 将聊天集成层从“逐终态、逐协议、逐持久化字段重跑完整 ProviderContainer”收敛为一条成功持久化、一条停止/失败和一条协议路由脊柱；其余检查已由 controller、repository、message tree、request builder、三个协议客户端和通知协调器的专门测试覆盖，当前跨层装具重复验证同一 outcome、inline error、finishReason、模板顺序与分支选择，预计净删约 850 行。 保留 `chat_lifecycle_integration_test.dart` 的综合 round-trip、`multi_protocol_chat_generation_integration_test.dart` 的一个代表协议链路、通知 native stop 与消息版本一次重启恢复；删除或合并其余对称场景。 [test/integration/chat_lifecycle_integration_test.dart:31, test/integration/chat_message_version_persistence_integration_test.dart:20, test/integration/chat_multi_conversation_integration_test.dart:26, test/integration/multi_protocol_chat_generation_integration_test.dart:35, test/integration/preset_prompt_request_integration_test.dart:110, test/integration/chat_generation_notification_integration_test.dart:57]

shrink: `SyncWorkspaceScreen` 在 composition 层同时重复静态文案、分组选择、媒体浏览生命周期、平台切换、返回链和六组响应式烟雾；composition 只需证明真实 bindings 接通，feature 层负责组件行为，现有多处断言核心只是 `takeException() == null`，预计净删约 360 行。 保留敏感导入确认、Android/Windows 各一个来源初始化、一个目录返回链和 compact/wide 各一个布局契约。 [test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart:42, test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart:24, test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart:63]

shrink: `app_router_test.dart` 把收藏点击流程、image/video 对称路由、聊天 query 生命周期和 History query 编解码全部塞入 597 行路由集成测试，与各 feature screen/controller 测试重叠且每例重建整棵应用，预计净删约 210 行。 每个 feature 保留一个 canonical 深链、一个缺失实体恢复、一个旧 URL 重定向；纯 query 默认值/非法整数/round-trip 改为单个表驱动测试。 [test/app/router/app_router_test.dart:31]

delete: 删除只复述常量、三元选择、`ConstrainedBox` 组合、no-op 返回值和主题内部 `Container`/`BoxDecoration` 的测试；这些测试不保护用户行为，颜色测试还绑定 widget 层级和 luminance 阈值，合计约 271 行。 由消费这些原语的代表响应式/可访问性测试覆盖，no-op 平台仅在 factory 选择测试验证一次。 [test/core/constants/app_layout_tokens_test.dart:6, test/core/widgets/app_adaptive_actions_test.dart:7, test/core/widgets/app_constrained_content_test.dart:45, test/app/platform/noop_chat_generation_foreground_service_test.dart:17, test/core/widgets/notification_bubble/notification_bubble_theme_test.dart:25]

shrink: `chat_generation_notification_coordinator_test.dart` 的 25 个场景中，null/idle 防御、多个诊断字符串、start/update 不可用和多种 terminal cleanup 以不同装具重复断言精确调用序列，容易在无行为变化的串行实现调整时大面积破裂，预计净删约 130 行。 保留节流尾缘、阶段/attempt 切换、旧 token 隔离、阻塞命令串行化、stop 幂等、terminal 重试、dispose 竞态和终态类别表；把低价值防御分支并为一组表驱动断言。 [test/app/composition/chat_generation_notification_coordinator_test.dart:253]

shrink: shell 与 Windows 返回测试按四个 viewport、四个顶层 destination、两种 compact viewport 和三种根部输入重复同一分支；同一布局模式或同一 `AppDestination` 分支无需穷举，预计净删约 125 行。 shell 仅保留 compact/wide 各一例、一个 drawer 边缘手势、一个 local-back 和一个非 chat 返回；根部集成仅保留一种 Windows 输入，鼠标/键盘差异由 adapter 单元测试负责。 [test/app/shell/app_shell_scaffold_test.dart:84, test/integration/windows_back_navigation_integration_test.dart:69]

shrink: 分页纯函数已验证 clamp/页码折叠，widget 层又分别测试合法跳转、空输入、越界、当前页点击和宽窄分支，形成同规则双份矩阵；16 个 state 测试也可在不丢边界的情况下合并成四个表驱动测试，预计净删约 115 行。 保留 zero/one/many 页、两侧省略、busy、容量变化、48px 命中区、pageIdentity 滚动复位和已有内容的 inline error。 [test/core/widgets/pagination/app_pagination_state_test.dart:7, test/core/widgets/pagination/app_pagination_bar_test.dart:39, test/core/widgets/pagination/app_paginated_list_shell_test.dart:62]

shrink: 日志测试为每个 `AppNetworkLogger` 方法重复创建临时目录、打开文件和回读全文，`SseLogBuffer` 也把 flush/drain/empty 分拆为近同义场景，预计净删约 100 行并减少磁盘装具启动次数。 合并为“写入/不写正文/轮转”三条文件契约与“容量丢弃/并发 flush”两条 buffer 契约；脱敏测试保持独立完整。 [test/core/logging/app_log_store_test.dart:22, test/core/logging/sse_log_buffer_test.dart:31]

shrink: 架构扫描器和测试韧性扫描器对自身词法器、allowlist、排序及多种等价非法 import 建了过细微型测试，虽然门禁值得保留，但不需要同时测试每个内部实现分支，预计净删约 90 行。 保留真实仓库零违规、stale allowance、相对/absolute import 等价和每个 rule id 的代表输入；韧性门禁仅保留 masking 代表例与整树扫描。 [test/architecture/import_boundary_checker_test.dart:21, test/architecture/test_resilience_policy_test.dart:12]

shrink: notification bubble 的 type 枚举、无/有 action 语义、Semantics tap、键盘 tap 和关闭操作多次验证相同 callback/节点，预计净删约 85 行。 保留一个完整 live region、一个键盘 action+close 流、退出动画禁用交互、不抢焦点和最多三条的行为。 [test/core/widgets/notification_bubble/notification_bubble_accessibility_test.dart:46]

shrink: 测试 helper 的六个自测用例覆盖了已完成后监听关闭与“命中后同 provider 同步抛错”的极窄内部时序，装具代码量超过 helper 本体三倍，预计净删约 70 行。 保留“初始已满足、后续命中、错误/超时”四个外部契约并删除为制造内部竞态而存在的 `ToggleNotifier`。 [test/helpers/async/async_test_signals_test.dart:10, test/helpers/async/async_test_signals.dart:7]

delete: 根级 Flutter 模板 smoke test 与 `bootstrap_integration_test.dart` 的“正常启动后渲染聊天页”重复，且测试名仍为英文；整文件约 51 行没有独立故障检测价值。 仅保留 bootstrap 集成测试，它还覆盖注入与平台初始化顺序。 [test/widget_test.dart:15, test/integration/bootstrap_integration_test.dart:61]

shrink: SSE decoder 把 data 空格、event 覆盖/泄漏、comment、EOF、CRLF、空事件拆成九个一次性装具；这些协议边界必须保留，但可用一个表驱动测试表达，预计净删约 35 行且不降低语义覆盖。 任意 byte 切分、idle timeout、上游错误和取消订阅继续独立。 [test/core/http/sse_event_decoder_test.dart:11]

shrink: endpoint resolver 为每个 URL 表格行注册独立测试，实际把约六十个纯断言呈现为约六十个用例，增加报告噪声却没有更好的隔离；预计净删约 10 行并减少约 60 个测试节点。 每个 API 方法保留一个测试，在循环断言中用 input/protocol 写入 `reason`，全部 URL 行继续保留。 [test/core/llm/llm_endpoint_resolver_test.dart:6]

## 不建议削减

- `test/core/persistence/app_database_migration_test.dart`：764 行看似突出，但每个历史 schema fixture 与数据保留断言都受仓库长期兼容规则保护。
- `test/core/http/http_client_provider_test.dart`、`network_log_redactor_test.dart` 与 SSE timeout/cancellation：属于密钥隔离、隐私与流取消边界。
- `test/app/platform/windows_video_fullscreen_controller_test.dart`、`android_chat_generation_foreground_service_test.dart` 的异常/超时/回调解码：平台竞态无法由普通页面 smoke test 替代。
- `test/core/widgets/adaptive_grid/adaptive_grid_geometry_test.dart` 的单调性/容差性质测试：比为每个 viewport 写 widget 测试更小、更稳定。

net: -2400 lines, -0 deps possible.
