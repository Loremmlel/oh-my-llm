# Task 2 报告：注意力、基础端口与默认终态通知深模块

状态：DONE_WITH_CONCERNS
Commit：`4512203f50f0f0da2f5521279a05ed1489278257`（`refactor(app): 增加生成通知注意力与激活模块`，post-commit hook 已并入版本 bump 3.76.19+0）

## 接管时的盘点结论

前任中断于「RED 已捕获、准备恢复生产文件跑 GREEN」。逐文件对照计划 5.2–5.5 与 3.1/3.2/3.5 后结论：

**保留复用（符合规格）**：

- `lib/app/attention/app_attention_state.dart` — 与 5.4 节签名一致；初值 `detached/false/Uri()` 用 static getter 提供（`Uri()` 非 const），注释说明「可能多发、不能漏发」。
- `lib/app/attention/app_window.dart` / `lib/app/platform/noop_app_window.dart` — 与 5.4 节接口一致；no-op 恒 focused。
- `lib/app/notifications/chat_generation_terminal_notification_adapter.dart` — 5.3 节接口 + `ChatGenerationSafeNotification` / `ChatGenerationNotificationActivation` / 严格 v1 payload codec / FNV-1a ID 函数。eventKey 正则由 `ChatGenerationTerminalKind.values` 拼接保证与收据一致；int64 上界经 `int.tryParse` 校验。
- `lib/app/notifications/chat_generation_notification_session.dart` — 128-bit `Random.secure` → 32 位小写 hex；进程级 provider 单次创建。
- `lib/features/settings/application/ports/system_notification_settings.dart` — 计划 10.1 明确该端口 provider「必须由 composition override」，与 adapter/window 的安全默认值要求不同，保留 throw 绑定语义。
- `lib/app/attention/app_attention_observer.dart` — 订阅顺序（先 focus stream 后异步 isFocused）、focusRevision 竞态防护均符合 5.4 节；同文件定义 `appWindowProvider`（no-op 安全默认绑定）。仅接受格式化修正。

**修改（1 处实质缺陷 + 格式化）**：

- `lib/app/notifications/default_chat_generation_terminal_notifications.dart`：
  - 实质缺陷：`dispose()` 内 `await subscription?.cancel()` 会永久悬挂（见「自审发现」），改为 `unawaited(subscription?.cancel())` 并注释为什么。
  - 其余逻辑（startFuture 共享、四个去重集合及上限 512/32、抑制即完成、展示失败放行重试、post-frame 导航帧读存在性、固定文案表、public 窄文案、fail-open 诊断分类）逐条对照 5.5 节与 3.4/3.5 节后确认正确，保留。
- 全部 13 个新文件：前任遗留 6 个文件不符合 `dart format` 产物，已执行格式化（纯排版，无语义变化）。

**测试文件**：4 个测试文件全部保留复用；24 条 RED 用例名与简报一一对应齐全（含 FNV 预核对向量 1672833428 / 937742124）。

## 实现摘要

按计划第 5.2–5.5 节完成纯 Dart 契约层：

- **稳定通知 ID**（5.2）：FNV-1a 32-bit，`10000 + (positive % 2147473647)`，预核对向量锁入 payload 测试；不与 ongoing ID 4101 冲突。
- **adapter 接口**（5.3）：安全通知值对象不含收据/outcome；codec 对未知版本/额外缺失字段/错类型/超长/控制字符/malformed 一律返回 null 不抛出。
- **注意力模块**（5.4）：observer 统一订阅 lifecycle/route/focus 三源；`appWindowProvider` 与 `chatGenerationTerminalNotificationAdapterProvider` 在平台 composition 前固定 no-op 默认绑定，不抛「未绑定」。
- **默认深模块**（5.5）：report 侧 in-flight/completed 双集合去重（抑制算完成、展示失败不完成可重试）；activation 侧 hot/pending 拦截、恢复失败只移出 in-flight 可重试；导航在 post-frame 回调实时读取会话存在性；completed 上限 512 逐出最旧、in-flight 上限 32 满时记 `notification_in_flight_limit`；诊断只用固定分类。
- 未修改 `lib/app/app.dart`；根部 eager 装配留给 Task 9。

## 测试结果

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 注意力单文件 GREEN | `flutter test test/app/attention/app_attention_observer_test.dart` → `logs/app-attention-green.log` | 9/9 通过 |
| 通知三件套 GREEN | `flutter test test/app/notifications/*.dart ×3` → `logs/terminal-notifications-green.log` | 29/29 通过（工具 timeout 60000ms 内完成） |
| 静态分析 | `flutter analyze` → `logs/task2-analyze.log` | No issues found |
| 依赖门禁 | `dart run tool/check_import_boundaries.dart` | 403 文件 0 违规 |
| 格式复查 | `dart format --output=none --set-exit-if-changed <新增目录>` | EXIT=0 |
| 全量回归 | `flutter test --reporter compact` → `logs/fltest.log` | 2200/2200 通过，EXIT=0 |

RED 证据沿用前任捕获的日志（`logs/app-attention-red.log`、`logs/terminal-notifications-red.log`、`logs/notification-payload-red.log`、`logs/notification-session-red.log`，均为生产文件缺位时的编译失败输出）；GREEN 由本次接管者实跑得出。

## 自审发现

**发现并修复的缺陷（本任务唯一实质改动）**：`DefaultChatGenerationTerminalNotifications.dispose()` 原实现 `await subscription?.cancel()` 在特定事件循环驱动下永久悬挂。

- 现象：全量跑通知套件时用例 `导航排队后 dispose 不执行 openChat` 卡死，且 dart_test per-test 超时（120s）与显式 `--timeout 20s` 均不触发、挂死进程 CPU 空闲。
- 定位过程（探针二分，临时插桩已全部还原并删除）：挂点收敛到 dispose 内部后，做变体矩阵——跳过 completer 完成循环仍挂、跳过 `await subscription.cancel()` 全绿——锁定 await 订阅取消为必要条件。根因是 fake-async 测试环境把 zone 内微任务拦截进自有队列、由显式 flush 循环排空；订阅取消返回的 future 依赖流内部异步清理链被继续排空，在没有后续帧驱动的调用点（测试体直接调 dispose、帧已排队未执行）没有后续排空者，await 它让 dispose 悬挂，进而让整个测试体滞留。
- 处置：改为 `unawaited(subscription?.cancel())`。计划 5.5 第 10 条只要求「取消 subscription」，未要求等待其完成；取消本身不持有待回收资源，真正的释放边界是随后被 await 的 `adapter.dispose()`。生产环境（真实事件循环）下取消始终及时完成，行为不变。修复后原挂死文件 20 例 3 秒内全绿。

**Concerns（供审查者关注）**：

1. `dispose()` 不再等待订阅取消完成。若后续 Task 9 的根部装配依赖「dispose 返回后流必然不再派发事件」这一强时序，需要重新审视；当前消费路径（激活回调入口先查 `_disposed`）已覆盖 disposed 后到达的事件。
2. `chatGenerationTerminalNotificationsProvider` 的诊断出口当前是 `debugPrint('[chat-generation-terminal] $category')`。计划允许固定分类诊断但未指定通道；若仓库后续接入统一 logger，应在此处替换（Task 9 装配时可顺带调整）。
3. settings port 的 `systemNotificationSettingsProvider` 读到即抛 `UnsupportedError`，这是计划 10.1「必须由 composition override」的既定语义（区别于 adapter/window 的安全默认），但在 Task 9 完成前任何误读都会在启动期暴露——属有意设计而非缺陷。
