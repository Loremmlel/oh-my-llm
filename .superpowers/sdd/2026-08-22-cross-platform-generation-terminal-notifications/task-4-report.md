# Task 4 实施报告：Android 共享 bridge 与三个窄 adapter

- 状态：DONE
- 提交：`d21717b8abe807cf45de6e2b417af21988a22460` `refactor(android): 收敛生成通知平台桥接`
- 分支：`feat/cross-platform-generation-notifications`
- 版本：post-commit hook 自动 bump 至 `3.76.21+0`（refactor → patch+1，并回本次提交）

## 变更范围

新增：

- `lib/app/platform/android_chat_generation_platform_bridge.dart`
  - `androidChatGenerationPlatformChannelName`（本任务暂用既有
    `yuzu.shiki.oh_my_llm/chat_generation_foreground_service`，注释写明 Task 5 与 Kotlin 同一原子提交切到
    `.../chat_generation_notifications`；不得双写/双 handler）。
  - `chatGenerationPlatformCommandTimeout = 2s`（沿用现有上界；原 foreground 文件中的
    `chatGenerationForegroundChannelTimeout` 常量随职责迁入 bridge，全仓库无其他引用）。
  - `AndroidTerminalNotificationShowException`：终态展示失败的固定异常，不携带平台原文。
  - `AndroidChatGenerationPlatformBridge`：唯一创建 MethodChannel 并安装 handler 的类。Dart→Kotlin 覆盖计划
    7.2 全表九个方法；Kotlin→Dart 回调分发到三条互不重叠窄流：
    - `stopRequested` / `openConversationRequested` → `foregroundActions`；
    - `foregroundServiceTimedOut` → `timeoutActions`（仅流已有 listener 时 ACK true，否则 ACK false 让 Kotlin 走原生 HIGH fallback）；
    - `notificationActivated` → `terminalActivations`（无 listener 时暂存本地 pending 槽，不丢点击）。
  - 所有命令统一 `_invokeCommand` 边界：MissingPluginException→channelUnavailable、PlatformException→nativeFailure、
    TimeoutException→channelTimeout、其他 Exception→nativeFailure；malformed 应答按协议不符处理。
- `lib/app/platform/android_chat_generation_terminal_notification_adapter.dart`：
  `AndroidChatGenerationTerminalNotificationAdapter implements ChatGenerationTerminalNotificationAdapter`，
  全部委托共享 bridge；`initialize()` 为 no-op（channel 由 bridge 构造时就位）；`dispose()` 不释放共享 bridge。
- `lib/app/platform/android_system_notification_settings.dart`：
  `AndroidSystemNotificationSettings implements SystemNotificationSettings`，状态与打开动作只委托 bridge。

修改：

- `lib/app/platform/android_chat_generation_foreground_service.dart`：瘦身为委托 shell。
  - 构造函数 `{AndroidChatGenerationPlatformBridge? bridge}`：未注入时自建 bridge 并在 dispose 时连带释放
    （保持独立使用场景旧契约）；注入的共享 bridge 绝不在端口 dispose 中释放（composition 的 disposeShared 负责），
    兼容既有绑定工厂 tear-off `AndroidChatGenerationForegroundService.new` 零参调用。
  - `actions` 用 broadcast controller + onListen/onCancel 门控桥接订阅：只有端口存在消费方才订阅 bridge 的
    timeout 流，使 timeout 回调的 ACK 端到端如实反映「Dart 有人消费」；stop/open 沿用旧契约不受 listener 影响。
- 对应四个测试文件（三个新增、一个重写），RED 测试名完整覆盖 brief 十条。

## 关键设计决策

1. **timeoutActivationPayload 补传**（Task 3 交接项）：start/update wire map 恒带
   `timeoutActivationPayload` 键（未设置为 null，对齐 actionLabel 恒键约定）；Dart 只透传不解析——测试以
   `'not-a-json'` 字符串原样出现在 wire 上证明无校验。类型/长度校验留给 Task 5 的 Kotlin 协议测试。
2. **pending activation 收敛**：本地槽（warm 无 listener 时到达）优先，槽空走 wire
   `takePendingNotificationActivation`；wire 应答定义为 nullable activation map `{payload: <严格 v1 JSON>}`，
   外层 map 宽松读取、payload 经共享 codec 严格解码。**该 wire 形状是 Dart 侧单方面定义**（计划 7.2 只写了
   "nullable activation map"），已在 bridge doc 注释中固化，Task 5 实现 Kotlin 时须与此对齐；同理
   `notificationActivated` 回调参数取原始 payload JSON 字符串本身。重复投递由上游 eventKey 去重兜底。
3. **show 失败语义**：原生 false / malformed / 通道失败统一抛 `AndroidTerminalNotificationShowException`，
   由默认深模块捕获记 `terminal_notification_show_failed` 并保留重试机会（与 Windows adapter 计划语义一致）。
4. **通道名**：沿用现名保证与未迁移 Kotlin runtime 协作；bridge doc 明确最终名切换归属 Task 5 原子提交。

## RED/GREEN 证据

| 测试文件 | RED 日志 | GREEN 日志 | 结果 |
| --- | --- | --- | --- |
| `test/app/platform/android_chat_generation_platform_bridge_test.dart` | `logs/task4-android-bridge-red.log` | `logs/android-bridge-green.log` | EXIT=0，14 用例 |
| `test/app/platform/android_chat_generation_terminal_notification_adapter_test.dart` | `logs/task4-android-terminal-adapter-red.log` | `logs/android-terminal-adapter-green.log` | EXIT=0，5 用例 |
| `test/app/platform/android_system_notification_settings_test.dart` | `logs/task4-android-system-notification-settings-red.log` | `logs/android-system-notification-settings-green.log` | EXIT=0，2 用例 |
| `test/app/platform/android_chat_generation_foreground_service_test.dart` | `logs/task4-android-foreground-adapter-red.log` | `logs/android-foreground-adapter-green.log` | EXIT=0，8 用例 |

RED 全部因新类型/构造签名缺失而失败（编译期缺 API），符合「新类型缺失失败」。格式化后四文件合并复跑
29 用例全绿（`logs/task4-all-four-final.log`）。每个测试命令工具超时 60000ms。

brief 十条 RED 名对应落点：

- 三个 Android 窄适配器共享一个 channel handler / stop open timeout terminal activation 回调分发到对应窄流 /
  timeout action stream 无 listener 时 ACK 为 false / channel timeout 和 PlatformException 均映射为 fail-open 结果 /
  dispose 后 callback 不再分发且可重复 dispose → bridge 测试
- 终态适配器只发送安全通知字段 / pending activation 只取一次 → terminal adapter 测试
- 前台适配器只编码 ongoing 方法 / foreground start update 原样传输 Dart 预编码 timeout activation payload →
  foreground adapter 测试
- Android 设置状态和打开动作只委托共享 bridge → settings 测试（拆为状态映射与打开透传两个用例）

## 回归验证

- `test/app/composition/chat_generation_foreground_service_bindings_test.dart` +
  `test/app/platform/noop_chat_generation_foreground_service_test.dart`：EXIT=0（`logs/task4-bindings-noop-green.log`）。
- `test/app/composition/chat_generation_notification_coordinator_test.dart`：EXIT=0，33 用例
  （`logs/task4-coordinator-green.log`）。
- `test/integration/chat_generation_notification_integration_test.dart` +
  `bootstrap_integration_test.dart`：EXIT=0（`logs/task4-integration-green.log`）。
- `flutter analyze`：No issues found（`logs/task4-analyze.log`）。
- `dart run tool/check_import_boundaries.dart`：406 文件 0 违规（`logs/task4-import-boundaries.log`）。
- 提交前 `dart format` + `--set-exit-if-changed`：EXIT=0；`git diff --cached --check` 通过。

## 停止条件核查

- 未出现同一 MethodChannel 被两个 Dart 对象安装 handler：唯一 `setMethodCallHandler` 调用点在
  `AndroidChatGenerationPlatformBridge` 构造函数（结构上 adapter 已不再接受 channel 参数）。
- 未为兼容旧通道新增双写/双 handler：单一通道名单常量，无第二通道。

## Concerns（移交后续 Task）

1. **Task 5 对齐点**：`takePendingNotificationActivation` 应答 map 键固定为 `payload`（值为严格 v1 JSON 字符串）、
   `notificationActivated` 回调 arguments 为 payload JSON 字符串本身——这两处 wire 形状由本任务 Dart 侧定义并写入
   bridge doc，Kotlin 实现必须一致。
2. 本任务未改 Kotlin：`showTerminalNotification` 等新方法对现行 runtime 会得到 notImplemented
   （MissingPluginException），已按 fail-open 映射（settings→unavailable/false、show→固定异常、pending→null），
   属预期中间态；真实能力在 Task 5 后生效。
3. 前台 adapter 自建 bridge 场景（未注入）下 dispose 会连带释放 bridge；composition（Task 9）注入共享 bridge 时
   各端口 dispose 不触碰 owner，`disposeShared` 单点释放。
