# 跨平台生成终态通知实施计划

> 状态：已深化、待实施；本文件只定义实现与验证步骤，不包含产品代码改动。
>
> 目标分支：`feat/cross-platform-generation-notifications`
>
> 基线：`master` @ `cfbb5299d8293196d1df9d37d11d115470c4ee51`
>
> PR 边界：本计划完整对应一个 PR，不与 PC 返回适配或历史页性能优化互相依赖。

## 1. 结果定义

本 PR 为聊天生成增加 Android 与 Windows 终态系统通知，并把“何时发、能显示什么、何时抑制、点击后去哪里”收敛到一个 Dart 深模块。Android Kotlin 与 Windows runner/plugin adapter 只执行平台命令，不参与生成结果判定。

完成后必须同时满足：

- Android 正在生成时继续显示现有 LOW、静音、ongoing 的前台服务通知。
- Android 在成功、空回复、最终失败、终态持久化失败和前台保护超时时，通过新的 HIGH 渠道播放系统默认声音并请求横幅展示。
- Windows 通过系统 Toast 显示相同终态；不引入 MSIX、安装器或管理员权限要求。
- Windows 应用热启动和完全退出两种情况下，点击 Toast 都能恢复并聚焦窗口，然后打开对应会话。
- 当前会话已删除时只回退聊天根页，不弹错误、不恢复数据。
- Android 与 Windows 共享 Dart 收据、固定安全文案、资格判断、注意力抑制、通知 ID、payload、去重和导航规则。
- 用户正在前台且正查看同一会话时不发送系统通知；其余页面、其他会话、后台或 Windows 失焦时发送。
- 平台权限、注册、展示、设置查询或激活处理失败全部 fail-open，不改变生成 phase/outcome，不产生新的聊天错误。
- 设置页只显示系统通知状态与“打开系统通知设置”按钮，不增加应用内通知开关。

## 2. 范围边界

### 2.1 本 PR 包含

- 纯 Dart 终态收据和安全失败分类。
- 现有 generation notification coordinator 的终态接入与 ongoing 清理修正。
- app-owned 注意力快照、窗口抽象、终态通知深模块和导航激活。
- Android 共享 MethodChannel bridge、HIGH 终态渠道、点击激活和设置入口。
- Windows 未打包 Toast 注册、Toast adapter、窗口恢复和设置入口。
- 定向单元/widget 测试、现有测试替换、Android/Windows smoke 文档。
- `flutter_local_notifications_windows: ^3.1.1` 直接依赖。

### 2.2 本 PR 不包含

- Linux、macOS、iOS 或 Web 通知。
- MSIX、安装器、计划任务、后台常驻进程或开机启动。
- 通过进程名模拟 Windows 通知身份。
- 通知历史、撤回/更新已发送终态通知、快捷回复、按钮操作。
- 提示词、回复正文、推理正文、会话标题、模型名、服务商、URL、Header、原始异常或堆栈进入系统通知。
- 聊天存储、生成协调器所有权、路由体系或设置传输格式重构。
- 开始菜单快捷方式和 HKCU 注册项的卸载清理；删除应用目录后的残留保持现状。
- Windows 多版本、多显示器、多用户、多安装位置测试矩阵。
- 让实机 smoke 阻塞自动门禁；smoke 可以保留 `PENDING`，但不得写成已验证。

## 3. 已确认的产品契约

### 3.1 终态资格

| 来源 | 终态种类 | 系统通知 | ongoing 清理 |
| --- | --- | --- | --- |
| `ChatGenerationPhase.succeeded` | `succeeded` | 是 | 是 |
| `ChatGenerationPhase.emptyReply` | `emptyReply` | 是 | 是 |
| `ChatGenerationPhase.failed` | `failed` | 是 | 是 |
| `ChatGenerationPhase.persistenceFailed` | `persistenceFailed` | 是 | 是 |
| Android `foregroundServiceTimedOut` | `foregroundProtectionTimedOut` | 是 | 是 |
| `ChatGenerationPhase.cancelled` | 无收据 | 否 | 是 |
| `retryWaiting` 前的中间错误 | 无收据 | 否 | 否 |
| `stopping` / `finalizing` | 无收据 | 否 | 否 |

规则：

- 只有 `ChatGenerationRun` 已发布的真正终态快照可以生成前四类收据；不得从 SSE、HTTP 异常或 UI flag 旁路生成。
- 自动重试只在重试耗尽并进入 `failed` 后通知。
- Android 前台保护超时不修改 Dart generation 状态，生成仍可继续并随后产生真正终态。
- 去重键使用 `v1:<generationId>:<terminalKind.name>`。同一种终态只展示一次；同一 generation 的保护超时与后续真正终态分别展示。
- 用户取消只清理 ongoing，不发终态通知。

### 3.2 注意力抑制真值表

| lifecycle | Windows focused | 当前 route | 当前会话 | 结果 |
| --- | --- | --- | --- | --- |
| `resumed` | 是 | `/chat` | 同一 `conversationId` | 抑制 |
| `resumed` | 是 | `/chat` | 其他会话 | 展示 |
| `resumed` | 是 | 非 `/chat` | 任意 | 展示 |
| 非 `resumed` | 任意 | 任意 | 任意 | 展示 |
| `resumed` | 否 | 任意 | 任意 | 展示 |

说明：

- Android/no-op 窗口实现始终视为 focused，因此 Android 只额外依赖 Flutter lifecycle。
- Windows 只有 `lifecycle == resumed && windowFocused == true` 才算 host attentive。
- `/chat` 必须由 GoRouter 当前 `Uri.path` 精确判断，不用 `startsWith`，不通过 `activeConversationId` 猜页面。
- 仅在 route 为 `/chat` 时读取 `activeConversationIdProvider` 作为可见会话。
- 抑制只影响系统通知，不影响 inline assistant 错误、会话状态、持久化或 ongoing 清理。
- 一次收据即使被抑制，也要标记为已处理，避免后续失焦时重放旧事件。

### 3.3 安全收据

聊天 application 只暴露以下端口：

```dart
abstract interface class ChatGenerationTerminalNotifications {
  Future<void> report(ChatGenerationTerminalReceipt receipt);
  Future<void> dispose();
}
```

`ChatGenerationTerminalReceipt` 只能携带：

- `int generationId`
- `String conversationId`
- `ChatGenerationTerminalKind terminalKind`
- `int contentCount`
- `int reasoningCount`
- `ChatGenerationTerminalFailureKind failureKind`

禁止添加：

- `title`、`body`、会话标题。
- `content`、`reasoningContent`、prompt。
- `Object error`、`String errorMessage`、stack trace。
- 任意 `Map<String, dynamic>` 或平台字段。

计数沿用现有 `ChatGenerationCharacterCounts` 的 `countChatWords` 口径。类型名虽含 `Character`，本 PR 不顺手改名。

### 3.4 固定安全文案

所有私有与公开通知均使用下表。平台层接收已经生成的文案，不解释失败：

| terminal kind / failure kind | title | body |
| --- | --- | --- |
| `succeeded` | `生成完成` | `正文 {contentCount} 字 · 推理 {reasoningCount} 字` |
| `emptyReply` | `生成未完成` | `模型返回了空回复` |
| `failed/network` | `生成失败` | `网络不可达` |
| `failed/timeout` | `生成失败` | `请求超时` |
| `failed/authentication` | `生成失败` | `认证失败` |
| `failed/authorization` | `生成失败` | `请求被拒绝` |
| `failed/rateLimited` | `生成失败` | `请求过于频繁` |
| `failed/server` | `生成失败` | `服务暂时不可用` |
| `failed/invalidOutput` | `生成失败` | `输出处理失败` |
| `failed/unknown` | `生成失败` | `请打开应用查看详情` |
| `persistenceFailed` | `结果保存失败` | `回复结果未能保存，请打开应用查看` |
| `foregroundProtectionTimedOut` | `后台保护已结束` | `请打开应用查看生成状态` |

Android `NotificationCompat.VISIBILITY_PRIVATE` 的 public version 使用更窄的固定文案：

| terminal kind | public title | public body |
| --- | --- | --- |
| `succeeded` | `生成完成` | `请打开应用查看` |
| `emptyReply` / `failed` | `生成未完成` | `请打开应用查看` |
| `persistenceFailed` | `结果保存失败` | `请打开应用查看` |
| `foregroundProtectionTimedOut` | `后台保护已结束` | `请打开应用查看生成状态` |

public version 不含会话 ID、计数或失败细节。

### 3.5 点击与导航

- payload v1 的 JSON 只允许 `v`、`eventKey`、`conversationId` 三个键。
- decoder 只接受 `v == 1`、非空 `eventKey` 和非空 `conversationId`；未知版本、缺字段、错类型一律忽略并记录固定诊断类别。
- Android warm activation 由 MethodChannel callback 交付；cold activation 由 Kotlin 一次性 pending slot 交付。
- Windows warm activation 由插件 callback 交付；cold activation 由插件 launch details 交付。
- hot 与 pending 同时出现时按 `eventKey` 只消费一次。
- Windows 激活顺序固定为 `restore/show -> focus -> 下一帧导航`。
- 导航前用 `chatSessionsProvider.state.conversationSummaries` 判断会话是否仍存在：
  - 存在：`goNamed(AppDestination.chat.name, queryParameters: {AppRouteParameter.conversationId: id})`。
  - 不存在：`goNamed(AppDestination.chat.name)`。
- 导航失败只记录固定诊断，不重新消费 activation。

### 3.6 权限和设置

- Android 13+ 复用现有“一次询问、拒绝后不循环弹框”行为。
- Android 8+ 保留两个职责不同的 channel：
  - `chat_generation`：LOW、静音、ongoing，只用于前台服务。
  - `chat_generation_result`：HIGH、默认声音/振动、非 ongoing、auto-cancel，只用于终态。
- 已创建 channel importance 不可由更新升级，因此终态必须使用新 ID。
- Windows 不显示运行时权限弹窗；系统设置可能关闭应用通知，而未打包 API 无法可靠查询最终开关，所以 Windows 只报告“功能可用”，不伪装成“已开启”。
- 设置页没有应用内开关，显示 `已开启`、`系统已关闭`、`功能可用（由 Windows 管理）` 或 `不可用`，并提供系统设置入口。

## 4. 唯一架构

```text
ChatGenerationRun
    │ durable save 后发布 terminal snapshot（保持不变）
    ▼
ChatGenerationNotificationCoordinator
    ├─ ongoing snapshot → ChatGenerationForegroundServicePort
    └─ terminal snapshot → ChatGenerationTerminalReceipt
                            │
                            ▼
ChatGenerationTerminalNotifications
    ├─ eventKey / ID / safe copy
    ├─ attention suppression / report dedupe
    ├─ activation dedupe / navigation
    └─ fail-open
        │
        ▼
ChatGenerationTerminalNotificationAdapter
    ├─ Android adapter → AndroidChatGenerationPlatformBridge → Kotlin
    ├─ Windows adapter → flutter_local_notifications_windows → Win32 registration
    └─ no-op adapter
```

边界约束：

- `ChatGenerationRun` 与 `ChatGenerationCoordinator` 不修改；现有 `_terminal()` 在 durable save 后投影终态的顺序是权威来源。
- `ChatGenerationNotificationCoordinator` 是唯一收据插入点，因为它已经 eager watch `(generation, streamingReply)`、缓存最后计数并串行处理 native action。
- `ChatGenerationNotificationProjector` 只投影 ongoing 前台服务 payload，不再持有终态错误摘要或 `retainError`。
- 前台服务端口与终态通知端口分离。
- Android 共享 bridge 只解决一个 MethodChannel 只能有一个 handler 的技术约束，不合并业务端口。
- Windows runner 只保证身份注册并向 Dart 返回注册信息，不处理会话、generation 或路由。
- Settings presentation 只能依赖 settings application provider/port。

## 5. 纯 Dart 契约

### 5.1 终态类型

新增 `lib/features/chat/application/generation/chat_generation_terminal_notification.dart`：

```dart
enum ChatGenerationTerminalKind {
  succeeded,
  emptyReply,
  failed,
  persistenceFailed,
  foregroundProtectionTimedOut,
}

enum ChatGenerationTerminalFailureKind {
  none,
  emptyReply,
  network,
  timeout,
  authentication,
  authorization,
  rateLimited,
  server,
  invalidOutput,
  persistence,
  foregroundProtection,
  unknown,
}

final class ChatGenerationTerminalReceipt extends Equatable {
  const ChatGenerationTerminalReceipt({
    required this.generationId,
    required this.conversationId,
    required this.terminalKind,
    required this.contentCount,
    required this.reasoningCount,
    required this.failureKind,
  });

  String get eventKey => 'v1:$generationId:${terminalKind.name}';
}
```

构造 invariant：

- `generationId > 0`。
- `conversationId.trim().isNotEmpty`。
- `contentCount >= 0`、`reasoningCount >= 0`。
- `succeeded` 必须配 `none`。
- `emptyReply` 必须配 `emptyReply`。
- `persistenceFailed` 必须配 `persistence`。
- `foregroundProtectionTimedOut` 必须配 `foregroundProtection`。
- `failed` 只能配 network/timeout/authentication/authorization/rateLimited/server/invalidOutput/unknown。

在同文件提供纯函数：

```dart
ChatGenerationTerminalReceipt? projectChatGenerationTerminalReceipt({
  required ChatGenerationSnapshot snapshot,
  required ChatGenerationCharacterCounts counts,
});
```

映射规则：

- 非终态返回 `null`。
- cancelled 返回 `null`。
- 失败分类只按已存在的安全类型信息：
  - `ChatErrorMessages.outputRuleEmptied` → `invalidOutput`
  - `TimeoutException` 或 `ChatGenerationException.cause is TimeoutException` → `timeout`
  - `SocketException` 或 `ChatGenerationException.cause is SocketException` → `network`
  - HTTP 401 → `authentication`
  - HTTP 403 → `authorization`
  - HTTP 429 → `rateLimited`
  - HTTP 5xx → `server`
  - 其他 → `unknown`
- 绝不检查异常文本 substring，绝不调用 `error.toString()` 生成通知内容。

### 5.2 稳定通知 ID

`ChatGenerationSafeNotification.id` 由 `eventKey` 的 UTF-8 bytes 计算 FNV-1a 32-bit：

```text
hash = 0x811C9DC5
for each byte:
  hash = ((hash XOR byte) * 0x01000193) AND 0xFFFFFFFF
positive = hash AND 0x7FFFFFFF
notificationId = 10000 + (positive MOD 2147473647)
```

约束：

- 不用 Dart `String.hashCode`。
- 结果始终为 `10000..2147483646`，不与 ongoing ID `4101` 冲突。
- 锁定测试向量：
  - `v1:7:succeeded` → `836870544`
  - `v1:7:foregroundProtectionTimedOut` → `475616968`

### 5.3 平台 adapter 内部接口

新增 `lib/app/notifications/chat_generation_terminal_notification_adapter.dart`：

```dart
abstract interface class ChatGenerationTerminalNotificationAdapter {
  Stream<ChatGenerationNotificationActivation> get activations;

  Future<void> initialize();

  Future<void> show(ChatGenerationSafeNotification notification);

  Future<ChatGenerationNotificationActivation?> takePendingActivation();

  Future<void> dispose();
}
```

内部值对象：

- `ChatGenerationSafeNotification`：`id`、`title`、`body`、`publicTitle`、`publicBody`、`payload`。public 字段只供 Android 锁屏副本使用，Windows adapter 明确忽略。
- `ChatGenerationNotificationActivation`：`eventKey`、`conversationId`。
- `ChatGenerationNotificationPayloadCodec`：严格 v1 JSON encode/decode。

adapter 只接收安全通知，不接收 `ChatGenerationTerminalReceipt` 或 outcome。

### 5.4 注意力状态与窗口端口

新增 `lib/app/attention/app_attention_state.dart`：

```dart
final class AppAttentionState extends Equatable {
  const AppAttentionState({
    required this.lifecycleState,
    required this.windowFocused,
    required this.location,
  });

  final AppLifecycleState lifecycleState;
  final bool windowFocused;
  final Uri location;

  bool get hostIsAttentive =>
      lifecycleState == AppLifecycleState.resumed && windowFocused;
}
```

初始值固定为 `detached`、`false`、空 `Uri()`；不得在异步焦点查询完成前假定 attentive。

新增 `lib/app/attention/app_window.dart`：

```dart
abstract interface class AppWindow {
  Stream<bool> get focusChanges;

  Future<bool> isFocused();

  Future<void> restoreAndFocus();

  Future<void> dispose();
}
```

- `WindowsAppWindow` 包装 `window_manager` 的 listener、`isFocused`、`isVisible`、`isMinimized`、`show`、`restore`、`focus`。
- `windows_app_window.dart` 内定义可注入的 `WindowsWindowManagerClient`；生产实现才调用全局 `windowManager`，测试使用 fake client 验证顺序，不直接 mock plugin singleton。
- `NoopAppWindow` 对 Android/其他平台返回 focused=true，restore/dispose 为 no-op。
- `AppAttentionObserver` 统一订阅 `WidgetsBindingObserver`、`appRouterProvider.routeInformationProvider` 和 `AppWindow.focusChanges`。
- observer 只更新 `appAttentionStateProvider`；终态通知模块读取快照，不自行监听 Flutter/window API。

### 5.5 默认深模块

新增 `lib/app/notifications/default_chat_generation_terminal_notifications.dart`。

构造依赖：

```dart
DefaultChatGenerationTerminalNotifications({
  required ChatGenerationTerminalNotificationAdapter adapter,
  required AppAttentionState Function() readAttention,
  required String Function() readActiveConversationId,
  required bool Function(String conversationId) conversationExists,
  required Future<void> Function() restoreHost,
  required void Function(String? conversationId) openChat,
  required void Function(String category) logDiagnostic,
});
```

生命周期：

1. `start()` 幂等。
2. 在第一个 `await` 前订阅 `adapter.activations`，避免初始化期间丢 warm callback。
3. 调 `adapter.initialize()`；错误记录 `terminal_adapter_initialize_failed` 并保持对象可 dispose。
4. 调 `takePendingActivation()`；若存在，走同一 activation 消费路径。
5. `report()` 先验证 event key 尚未处理；加入 report 去重集合。
6. 读取注意力、route 和 active conversation；命中唯一抑制条件则返回。
7. 将收据映射为固定安全 copy、ID 和 payload。
8. 调 `adapter.show()`；错误记录 `terminal_notification_show_failed`，不 rethrow。
9. activation 先按 event key 去重，再 `await restoreHost()`；用 `SchedulerBinding.instance.addPostFrameCallback` 在下一帧调用 `openChat(exists ? id : null)`，避免冷启动时 router 尚未挂载。
10. `dispose()` 取消 subscription、调用 adapter.dispose；两者错误只记固定诊断；重复调用安全。

实现必须维护两个独立集合：

- `_reportedEventKeys`：防重复展示，抑制也算处理。
- `_activatedEventKeys`：防 hot/pending 重复导航。

日志只允许固定分类，不插值 payload、conversation ID 或异常文本。

## 6. 现有 coordinator 的准确改法

修改 `lib/app/composition/chat_generation_notification_coordinator.dart`，不新建第二个 lifecycle listener。

### 6.1 构造与状态

- 构造函数用 `ChatGenerationTerminalNotifications terminalNotifications` 替换现有 `openConversation` callback。
- 保留 `_lastCounts`，它是 finalizing/terminal 无 streaming reply 时的权威计数。
- 保留 `_timedOut`，并明确它同时表示“Kotlin timeout 路径已经移除 ongoing”；不再增加第二个 cleanup boolean。
- 删除前台服务 open conversation/pending activation 处理；这些职责移到终态通知深模块。

### 6.2 `onStateChanged` 顺序

固定顺序：

1. token 校验/新 token reset。
2. 若 `snapshot.phase.isTerminal`：
   - 先用 `projectChatGenerationTerminalReceipt(snapshot, _lastCounts)` 得到 nullable receipt。
   - 总是取消 pending timer。
   - 入 coordinator 的同一个 async tail operation。
   - 若 timeout 尚未由 Kotlin 清理，先调用前台端口 `remove(token, conversationId)`，沿用现有三次 cleanup ACK 重试。
   - receipt 非 null 时，无论 cleanup 最终成功还是耗尽，再调用 `terminalNotifications.report(receipt)`。
   - cancellation 的 receipt 为 null，因此只执行 cleanup；timeout 已清理时则为完全 no-op。
   - timeout 已清理且 receipt 非 null 时跳过 remove，直接调用 `terminalNotifications.report(receipt)`。
   - report 自己 fail-open；不得让 cleanup 失败阻止真正终态通知。
   - 不再调用 ongoing projector。
3. 非终态才调用 `ChatGenerationNotificationProjector.project()`。
4. `_timedOut` 后继续抑制 ongoing start/update，不重启前台服务。

### 6.3 timeout action

`ChatGenerationForegroundTimedOut` 只在 token 等于当前 token 且尚未真正 terminal 时处理：

1. `_timedOut = true`。
2. 取消 pending update。
3. 不再调用前台端口 `remove`：Kotlin 在发 callback 前已经移除 ongoing 并停止 Service，避免 MethodChannel callback 内再次调用 Kotlin 形成重入。
4. 用 `_lastCounts` 创建 `foregroundProtectionTimedOut` 收据。
5. 把 `terminalNotifications.report(timeoutReceipt)` 加入 coordinator 现有 async tail，保持 timeout 与后续真正终态的顺序；不调用 stop/cancel/retry/finalize。
6. 后续真正 terminal 仍报告，但因 `_timedOut` 跳过 remove。

### 6.4 ongoing projector 收窄

修改 `lib/features/chat/application/generation/chat_generation_notification.dart`：

- 删除 `ChatGenerationNotificationTerminalBehavior`。
- 删除 projection 的 `terminalBehavior` 字段。
- 删除 terminal private/public copy、`summarizeChatGenerationNotificationError()`，并移除只为错误摘要存在的 `dart:async`、`dart:io`、`chat_error_messages.dart`、`chat_generation_client.dart` imports。
- projector 只接受 preparing/streaming/retryWaiting/stopping/finalizing。
- 对 idle 和所有 terminal phase 抛 `ArgumentError`，由 coordinator 保证不会调用。
- 保持字数、截断、ongoing 文案和 action 不变。

修改 `lib/features/chat/application/ports/chat_generation_foreground_service.dart`：

- 保留 `ensureNotificationPermission`、`start`、`update`、`remove`、`actions`、`dispose`。
- 删除 `fail()`。
- 删除 `ChatGenerationOpenConversationRequested`。
- 删除 `takePendingOpenConversation()`。
- `actions` 只允许 `ChatGenerationStopRequested` 和 `ChatGenerationForegroundTimedOut`。

## 7. Android 平台协议

### 7.1 文件与唯一 channel owner

执行以下重命名，不保留兼容文件：

- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocol.kt`
  → `ChatGenerationNotificationProtocol.kt`
- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundChannel.kt`
  → `ChatGenerationNotificationChannel.kt`
- `android/app/src/test/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocolTest.kt`
  → `ChatGenerationNotificationProtocolTest.kt`

新增：

- `lib/app/platform/android_chat_generation_platform_bridge.dart`
- `lib/app/platform/android_chat_generation_terminal_notification_adapter.dart`
- `lib/app/platform/android_system_notification_settings.dart`
- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationTerminalNotification.kt`

修改：

- `lib/app/platform/android_chat_generation_foreground_service.dart`
- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundService.kt`
- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/MainActivity.kt`
- `android/app/src/main/res/values/chat_generation_strings.xml`

channel 名固定为：

```text
yuzu.shiki.oh_my_llm/chat_generation_notifications
```

只有 `AndroidChatGenerationPlatformBridge` 创建 Dart `MethodChannel` 并安装 handler。foreground adapter、terminal adapter 和 system settings adapter 都委托同一个 bridge，不创建第二个 handler。

### 7.2 Dart → Kotlin 方法

协议只包含：

| 方法 | 参数 | 返回 |
| --- | --- | --- |
| `ensureNotificationPermission` | 无 | 现有固定权限状态字符串 |
| `startForegroundGeneration` | ongoing payload | command ACK |
| `updateForegroundGeneration` | ongoing payload | command ACK |
| `removeForegroundGeneration` | token + conversationId | command ACK |
| `showTerminalNotification` | id + title + body + publicTitle + publicBody + payload | `bool` |
| `takePendingNotificationActivation` | 无 | nullable activation map |
| `getNotificationSettingsStatus` | 无 | `enabled` / `disabled` / `unavailable` |
| `openNotificationSettings` | 无 | `bool` |

删除：

- `failForegroundGeneration`
- `takePendingOpenConversation`

### 7.3 Kotlin → Dart callback

只包含：

| callback | 参数 |
| --- | --- |
| `stopRequested` | token + conversationId |
| `foregroundServiceTimedOut` | token + conversationId |
| `notificationActivated` | payload |

删除 `openConversationRequested`。所有通知点击统一传版本化 payload。

### 7.4 HIGH 终态通知

`ChatGenerationTerminalNotification.kt` 固定：

- channel ID：`chat_generation_result`
- channel name/resource：`生成结果`
- API 26+ importance：`NotificationManager.IMPORTANCE_HIGH`
- API 26+ channel sound：`Settings.System.DEFAULT_NOTIFICATION_URI`，`AudioAttributes.USAGE_NOTIFICATION`
- API 26+ channel vibration：`enableVibration(true)`
- pre-26 builder defaults：`NotificationCompat.DEFAULT_SOUND | NotificationCompat.DEFAULT_VIBRATE`
- pre-26 priority：`NotificationCompat.PRIORITY_HIGH`
- `setOngoing(false)`
- `setAutoCancel(true)`
- `setCategory(NotificationCompat.CATEGORY_STATUS)`
- `setVisibility(NotificationCompat.VISIBILITY_PRIVATE)`
- small icon：`R.drawable.ic_chat_generation`
- notification ID：Dart 传入的稳定 ID
- PendingIntent request code：同一 notification ID
- PendingIntent flag：`FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`
- Intent data：`oh-my-llm://generation-notification/<notificationId>`
- extras 只保存 payload 字符串

现有 `chat_generation` channel、ongoing notification ID `4101`、静音和 foreground service type 保持不变。

当前 Android JVM 测试没有 Robolectric，因此：

- `ChatGenerationNotificationProtocolTest.kt` 测纯 payload decoder、token guard、method/callback 常量、request code/ID 冲突规则。
- channel importance、sound、PendingIntent、系统设置 Intent 通过把参数选择抽成不依赖 Android framework 的纯配置函数测试。
- 不把未执行的 framework 行为写成 JVM 已验证；真实横幅/声音留在 smoke。
- 不引入 Robolectric 或新测试框架。

### 7.5 timeout fallback

修改 `ChatGenerationForegroundService` timeout 顺序：

1. 移除 ongoing notification 并停止 foreground service。
2. 向 Dart 发 `foregroundServiceTimedOut`。
3. Dart bridge 只有在 payload 类型校验通过且 timeout action stream 已有 listener 时才立即回 `true`；该 ACK 只表示事件已进入 Dart，不等待系统通知展示。
4. Dart ACK 为 `true` 时，由 Dart 统一 terminal adapter 展示。
5. 无 Flutter channel、callback 返回 false 或抛错时，Kotlin 直接用 HIGH channel 展示固定 fallback：
   - title：`后台保护已结束`
   - body：`请打开应用查看生成状态`
   - event key 固定为 `v1:<token>:foregroundProtectionTimedOut`，payload 仍只含 v1/event key/conversation ID。

删除现有：

- LOW channel 普通错误/timeout 留存路径。
- `TimedOutNotificationGuard`。
- `failForegroundGeneration` 相关 builder 与 ACK。
- `PUBLIC_ERROR_*`、`OPEN_ACTION_*` 和普通错误通知 action。

fallback 的目的仅是原生前台服务已经失去 Dart 通道时仍告知用户；它不判定生成终态。

### 7.6 Android 设置

状态：

- `NotificationManagerCompat.areNotificationsEnabled() == false` → `disabled`
- API 26+ 且 `chat_generation_result` 已存在并为 `IMPORTANCE_NONE` → `disabled`
- 其他 → `enabled`
- 获取系统服务失败 → `unavailable`

打开：

- 使用 `Settings.ACTION_APP_NOTIFICATION_SETTINGS`。
- extra 使用当前 package。
- `FLAG_ACTIVITY_NEW_TASK`。
- 无 Activity handler 或抛错返回 false，不崩溃。

`AndroidManifest.xml` 已有 `POST_NOTIFICATIONS` 与 foreground service 权限，本 PR 不重复添加或改变 service type。

## 8. Windows 未打包 Toast

### 8.1 固定身份

- appName：`Oh My LLM`
- AUMID：`YuzuShiki.OhMyLlm`
- Toast activator CLSID：`{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}`
- 开始菜单快捷方式：`FOLDERID_Programs\Oh My LLM.lnk`
- runner 参数：`--notification-activated`
- registration channel：`yuzu.shiki.oh_my_llm/windows_notification_registration`

这些值提交后不得随版本号、构建号或目录变化。

### 8.2 runner 注册

新增：

- `windows/runner/windows_notification_registration.h`
- `windows/runner/windows_notification_registration.cpp`

修改：

- `windows/runner/main.cpp`
- `windows/runner/flutter_window.h`
- `windows/runner/flutter_window.cpp`
- `windows/runner/CMakeLists.txt`

在 `main.cpp` 已有 `CoInitializeEx` 之后、创建 `DartProject` 之前执行：

```cpp
const auto notification_registration =
    EnsureWindowsNotificationRegistration();
```

`EnsureWindowsNotificationRegistration()`：

1. `GetModuleFileNameW` 取得当前 exe 绝对路径。
2. 用 `SHGetKnownFolderPath(FOLDERID_Programs)` 取得当前用户 Programs。
3. 创建或重写 `Oh My LLM.lnk`：
   - target 指向当前 exe。
   - working directory 指向 exe 目录。
   - `PKEY_AppUserModel_ID` 写固定 AUMID。
   - `PKEY_AppUserModel_ToastActivatorCLSID` 写固定 CLSID。
4. 写入 `HKCU\Software\Classes\CLSID\{CLSID}\LocalServer32` 默认值：
   - `"绝对路径\oh_my_llm.exe" --notification-activated`
   - exe 路径始终带双引号。
5. 返回结构体 `available/aumid/clsid/appName`。
6. 每次启动幂等修复 shortcut target 和 LocalServer32，因此原目录直接覆盖更新不受影响；移动整个目录后首次手动启动会修复路径。
7. 任一步失败返回 `available=false` 并输出固定 Win32 stage/code；继续启动 Flutter，不抛出会阻断进程的异常。

不写 HKLM，不请求管理员权限，不删除旧注册。

`FlutterWindow` 构造函数接收 registration info，并在 engine 创建后注册只读 MethodChannel：

- method：`getRegistration`
- success：返回 `available`、`appName`、`appUserModelId`、`guid`
- failure：返回 `available=false` 与固定 `failureStage`，不返回绝对路径或系统错误文本

`CMakeLists.txt`：

- 把 `windows_notification_registration.cpp` 加入 runner sources。
- link `ole32.lib`、`shell32.lib`、`propsys.lib`、`advapi32.lib`。
- 保留现有 `flutter`、`flutter_wrapper_app`、`dwmapi.lib`。

### 8.3 Dart 注册 decoder

新增 `lib/app/platform/windows_notification_registration.dart`：

- `WindowsNotificationRegistration` 不可变值对象，只含 `available/appName/appUserModelId/guid`。
- `WindowsNotificationRegistrationClient` 只调用 registration channel。
- decoder 缺任何固定字符串或 `available != true` 时返回 unavailable，不抛 raw `PlatformException`。
- 单测用 fake `MethodChannel` handler 覆盖 success、unavailable、malformed、exception。
- 插件 `iconPath` 明确传 `null`：现有 `app_icon.ico` 是 runner 源资源，不会以独立文件进入 ZIP 输出，本 PR 不新增图标复制链。

### 8.4 插件边界

`pubspec.yaml` 增加直接依赖：

```yaml
flutter_local_notifications_windows: ^3.1.1
```

不添加 `flutter_local_notifications` 主包。

新增 `lib/app/platform/windows_local_notifications_client.dart`，把插件封在可 fake 接口后：

```dart
abstract interface class WindowsLocalNotificationsClient {
  Future<bool> initialize({
    required WindowsNotificationRegistration registration,
    required void Function(String? payload) onActivated,
  });

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  Future<String?> takeLaunchPayload();

  Future<void> dispose();
}
```

生产实现固定调用：

- `FlutterLocalNotificationsWindows.initialize`
- `WindowsInitializationSettings(appName, appUserModelId, guid, iconPath: null)`
- `show(..., WindowsNotificationDetails())`
- `getNotificationAppLaunchDetails`
- `dispose`

本 PR 不调用 cancel/getActiveNotifications，因为未打包应用对这些 API 没有稳定要求，产品契约也不需要。

### 8.5 Windows terminal adapter

新增 `lib/app/platform/windows_chat_generation_terminal_notification_adapter.dart`：

- `initialize()` 先读取 runner registration；unavailable 时记录固定分类并保持 no-op。
- registration available 后初始化 plugin client。
- plugin callback payload 走共享严格 decoder，成功后发到 `activations`。
- launch details 只在 `takePendingActivation()` 读取一次并清空。
- `show()` 直接使用 Dart 已生成的 id/title/body/payload。
- 任意插件异常映射为 adapter 异常，由默认深模块捕获；adapter 不解释 generation。
- `dispose()` 幂等，关闭 stream 并释放 plugin。

### 8.6 Windows 窗口恢复

`WindowsAppWindow.restoreAndFocus()` 固定：

1. `isVisible == false` 时 `show()`。
2. `isMinimized == true` 时 `restore()`。
3. 最后 `focus()`。

各调用分别 catch 并继续下一步；如果 focus 最终失败，activation 仍导航，诊断记录 `window_restore_or_focus_failed`。不因为窗口 API 失败丢失会话目标。

### 8.7 Windows 设置

新增 `lib/app/platform/windows_system_notification_settings.dart`。

使用：

```dart
Process.start(
  'explorer.exe',
  const ['ms-settings:notifications'],
  mode: ProcessStartMode.detached,
);
```

禁止 `runInShell: true`，不拼接命令字符串。成功启动返回 true，异常返回 false。状态只能可靠报告 `available`（注册可用）或 `unavailable`（注册不可用）；不要伪造系统级精确开关读取。

## 9. 平台 composition

### 9.1 统一绑定记录

重命名：

- `lib/app/composition/chat_generation_foreground_service_bindings.dart`
  → `lib/app/composition/chat_generation_notification_platform_bindings.dart`
- `test/app/composition/chat_generation_foreground_service_bindings_test.dart`
  → `test/app/composition/chat_generation_notification_platform_bindings_test.dart`

定义：

```dart
typedef ChatGenerationNotificationPlatformBindings = ({
  ChatGenerationForegroundServicePort foregroundService,
  ChatGenerationTerminalNotificationAdapter terminalAdapter,
  SystemNotificationSettings systemNotificationSettings,
  Future<void> Function() disposeShared,
});
```

工厂 `createChatGenerationNotificationPlatformBindings(TargetPlatform)`：

- Android：创建一个 `AndroidChatGenerationPlatformBridge`，三个窄 adapter 共享它，`disposeShared` 只 dispose bridge 一次。
- Windows：foreground no-op + Windows terminal adapter + Windows settings adapter。
- 其他：三个 no-op。

端口各自 dispose 不得重复 dispose shared bridge；composition 只在 `disposeShared` 释放 shared owner。

### 9.2 AppWindow 绑定

新增 `lib/app/composition/app_attention_bindings.dart`：

- Windows → `WindowsAppWindow`
- 其他 → `NoopAppWindow`

新增 `lib/app/platform/noop_system_notification_settings.dart`，供非 Android/Windows 平台与普通测试使用。

### 9.3 `appCompositionOverrides`

修改 `lib/app/composition/cross_feature_bindings.dart`：

- `bindChatGenerationForegroundService` 重命名为 `bindChatGenerationNotifications`。
- 增加 `bindAppWindow`。
- 一次创建 notification platform bindings，并分别 override：
  - `chatGenerationForegroundServiceProvider`
  - `chatGenerationTerminalNotificationAdapterProvider`
  - `systemNotificationSettingsProvider`
- `ref.onDispose` 只注册一次 shared disposer。
- AppWindow 单独 override。

修改所有调用点：

- `lib/bootstrap.dart`
- `test/helpers/test_harness.dart`
- `test/helpers/integration_test_helpers.dart`
- `test/integration/bootstrap_integration_test.dart`
- `test/integration/chat_generation_notification_integration_test.dart`

测试 harness 默认绑定 no-op Windows platform adapters，不触发真实插件；需要 fake 时传 `bindChatGenerationNotifications: false` 或 `bindAppWindow: false` 后 override。

## 10. 设置 application 与 UI

### 10.1 端口

新增 `lib/features/settings/application/ports/system_notification_settings.dart`：

```dart
enum SystemNotificationStatus { enabled, disabled, available, unavailable }

abstract interface class SystemNotificationSettings {
  Future<SystemNotificationStatus> getStatus();

  Future<bool> openSettings();
}
```

同文件定义必须由 composition override 的 provider。

新增 `lib/features/settings/application/system_notifications/system_notification_status_controller.dart`：

- `SystemNotificationStatusController extends AsyncNotifier<SystemNotificationStatus>`。
- provider 固定命名为 `systemNotificationStatusProvider`，用 `AsyncNotifierProvider<SystemNotificationStatusController, SystemNotificationStatus>` 手写声明，不引入代码生成。
- `build()` 调 `getStatus()`，异常映射为 `unavailable`。
- `refresh()` 重新查询并保持 loading 可观察。
- `openSettings()` 返回 bool，不直接操作 UI。

### 10.2 UI

修改 `lib/features/settings/presentation/widgets/tabs/other_settings_tab.dart`：

- `OtherSettingsTab` 由 `ConsumerWidget` 改为 `ConsumerStatefulWidget`。
- state 创建 `AppLifecycleListener`；`onResume` 调 controller.refresh。
- dispose listener。
- 在“显示”和“自动重试”之间插入 `SettingsSectionCard`：
  - title：`系统通知`
  - description：`生成完成或失败时由系统显示通知；声音、横幅和权限由系统管理。`
  - loading：`CircularProgressIndicator` + `正在读取系统通知状态`
  - enabled：`系统通知已开启`
  - disabled：`系统通知已关闭`
  - available：`系统通知功能可用，具体横幅和声音由 Windows 管理`
  - unavailable：`当前平台无法使用系统通知`
  - 按钮：`打开系统通知设置`
- unavailable 时按钮 disabled；enabled/disabled/available 时可点击。
- 点击时只调用 controller.openSettings；返回 false 时使用现有 `context.showErrorBubble('无法打开系统通知设置')`。
- 不显示 Switch，不持久化应用内偏好，不进入设置传输。

状态查询期间保留流畅 loading 动画；数据返回后再渲染状态，不阻塞 UI isolate，不使用 `pumpAndSettle` 作为测试同步手段。

## 11. 分步实施与 RED/GREEN

每个 Task 开始前执行：

```powershell
git branch --show-current
git status --short
```

必须看到 `feat/cross-platform-generation-notifications`，且 diff 只包含本计划范围。出现另外两个 PR 的文件时立即停止。

### Task 1：终态收据与 ongoing projector 收窄

**文件**

- 新增 `lib/features/chat/application/generation/chat_generation_terminal_notification.dart`
- 新增 `lib/features/chat/application/ports/chat_generation_terminal_notifications.dart`
- 新增 `test/features/chat/application/generation/chat_generation_terminal_notification_test.dart`
- 修改 `lib/features/chat/application/generation/chat_generation_notification.dart`
- 修改 `test/features/chat/application/generation/chat_generation_notification_test.dart`

**RED 测试**

- `成功终态生成安全计数收据`
- `空回复使用独立终态与安全分类`
- `最终失败按异常类型映射安全分类`
- `持久化失败不归类为普通生成失败`
- `取消和非终态不生成收据`
- `收据拒绝非法 generation ID 会话 ID 与负计数`
- `event key 格式固定且不携带正文`
- `ongoing 投影器拒绝所有终态`

命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/generation/chat_generation_terminal_notification_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/terminal-receipt-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/terminal-receipt-red.log
```

工具超时 60000ms。RED 必须因新类型/行为缺失失败。

**GREEN**

- 实现第 5.1 节类型、invariant 和纯映射。
- 收窄 ongoing projector，替换旧 terminal projector 测试。
- 同命令写 `logs/terminal-receipt-green.log` 并达到 `EXIT=0`。

**停止条件**

- 需要把原始错误或回复文本保存在 receipt。
- 无法从现有 snapshot/outcome 区分五类终态。

### Task 2：注意力与默认终态通知深模块

**文件**

- 新增 `lib/app/attention/app_attention_state.dart`
- 新增 `lib/app/attention/app_window.dart`
- 新增 `lib/app/attention/app_attention_observer.dart`
- 新增 `lib/app/notifications/chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/notifications/default_chat_generation_terminal_notifications.dart`
- 新增 `lib/app/platform/noop_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/noop_app_window.dart`
- 新增 `test/app/attention/app_attention_observer_test.dart`
- 新增 `test/app/notifications/chat_generation_notification_payload_test.dart`
- 新增 `test/app/notifications/default_chat_generation_terminal_notifications_test.dart`
- 修改 `lib/app/app.dart`

**RED 测试**

- `前台聚焦且查看对应会话时抑制通知`
- `查看其他会话时展示通知`
- `非聊天页面时展示通知`
- `Windows 窗口失焦时展示通知`
- `同一收据重复报告时只展示一次`
- `被抑制的收据不会在失焦后重放`
- `保护超时后仍允许真正终态`
- `平台初始化和展示失败均不向调用者抛出`
- `固定 event key 生成固定通知 ID`
- `payload 只包含三个允许字段`
- `未知版本和 malformed payload 被忽略`
- `hot 与 pending activation 只导航一次`
- `已删除会话回退聊天根页`
- `dispose 幂等并取消激活订阅`

**GREEN**

- 完成第 5.2–5.5 节。
- 在 `OhMyLlmApp` eager watch observer 与 terminal notifications provider。
- provider dispose 调深模块 dispose。
- 单文件测试分别写 `logs/app-attention-green.log`、`logs/terminal-notifications-green.log`，工具超时 60000ms。

**停止条件**

- 抑制判断需要 presentation controller。
- adapter 必须理解 generation outcome。

### Task 3：coordinator 接入与前台服务端口瘦身

**文件**

- 修改 `lib/app/composition/chat_generation_notification_coordinator.dart`
- 修改 `lib/features/chat/application/ports/chat_generation_foreground_service.dart`
- 修改 `test/app/composition/chat_generation_notification_coordinator_test.dart`
- 修改现有 foreground port fake/no-op 测试

**RED 测试**

- `成功先清理 ongoing 再报告终态`
- `空回复失败和持久化失败都清理 ongoing`
- `取消只清理不报告`
- `中间重试不清理也不报告`
- `终态使用最后一次 streaming 计数`
- `保护超时只报告且不调用 remove 或停止生成`
- `保护超时后真正终态仍报告且不重复清理`
- `terminal report 失败不毒化 coordinator`
- `旧 token 的 terminal 和 timeout 被拒绝`

**GREEN**

- 严格按第 6 节调整。
- 删除 fail/open/pending port 职责与旧测试，不保留 deprecated shim。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/composition/chat_generation_notification_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/terminal-coordinator-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/terminal-coordinator-green.log
```

工具超时 60000ms。

**停止条件**

- 需要修改 `ChatGenerationRun` 或创建第二套 terminal flag。
- 无法保证 durable save 后才收到真正终态。

### Task 4：Android 共享 bridge

**文件**

- 新增 `lib/app/platform/android_chat_generation_platform_bridge.dart`
- 新增 `lib/app/platform/android_chat_generation_terminal_notification_adapter.dart`
- 修改 `lib/app/platform/android_chat_generation_foreground_service.dart`
- 新增 `test/app/platform/android_chat_generation_platform_bridge_test.dart`
- 新增 `test/app/platform/android_chat_generation_terminal_notification_adapter_test.dart`
- 新增 `test/app/platform/android_system_notification_settings_test.dart`
- 修改 `test/app/platform/android_chat_generation_foreground_service_test.dart`

**RED 测试**

- `三个 Android 窄适配器共享一个 channel handler`
- `前台适配器只编码 ongoing 方法`
- `终态适配器只发送安全通知字段`
- `stop timeout activation 回调分发到对应流`
- `pending activation 只取一次`
- `channel timeout 和 PlatformException 均映射为 fail-open 结果`
- `Android 设置状态和打开动作只委托共享 bridge`
- `dispose 后 callback 不再分发且可重复 dispose`

**GREEN**

- channel owner 只存在于 bridge。
- command timeout 沿用现有 2 秒。
- 所有原生错误只映射为固定分类。
- 三个新增测试分别写 `logs/android-bridge-green.log`、`logs/android-terminal-adapter-green.log`、`logs/android-system-notification-settings-green.log`；修改后的 foreground adapter 测试写 `logs/android-foreground-adapter-green.log`。每个单文件工具超时 60000ms。

**停止条件**

- 同一 MethodChannel 被两个 Dart 对象安装 handler。
- 为兼容旧 runtime channel 新增双写/双 handler。

### Task 5：Android Kotlin HIGH 通知与设置

**文件**

- 按第 7.1 节重命名 protocol/channel/test
- 新增 `ChatGenerationTerminalNotification.kt`
- 修改 `ChatGenerationForegroundService.kt`
- 修改 `MainActivity.kt`
- 修改 `chat_generation_strings.xml`

**RED 测试**

- `终态渠道配置为 HIGH 且不是 silent`
- `前台渠道仍为 LOW 且 silent`
- `终态通知 ID 不与 4101 冲突`
- `每个终态 PendingIntent request code 与 data URI 唯一`
- `终态 payload decoder 只接受 v1 安全字段`
- `timeout callback 未受理时选择 HIGH fallback`
- `通知禁用或终态渠道为 NONE 时返回 disabled`
- `打开设置 Intent 只使用当前 package`

**GREEN**

- 实现第 7 节协议、HIGH channel、timeout fallback 和设置。
- 不修改 Manifest，不引入 Robolectric。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
.\android\gradlew.bat -p android :app:testDebugUnitTest 2>&1 | Out-File -Encoding utf8 logs/android-terminal-notification-test.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/android-terminal-notification-test.log
```

命令级硬超时 120000ms。仓库 module 为 `:app`，使用上述确定 task，不在实施时重新选择测试框架。

**停止条件**

- 只能升级已有 LOW channel 才能得到横幅。
- Kotlin 需要参与真正 generation outcome 判定。
- 需要重复弹 POST_NOTIFICATIONS 权限。

### Task 6：Windows runner 注册

**文件**

- 新增 `windows/runner/windows_notification_registration.h`
- 新增 `windows/runner/windows_notification_registration.cpp`
- 修改 `windows/runner/main.cpp`
- 修改 `windows/runner/flutter_window.h`
- 修改 `windows/runner/flutter_window.cpp`
- 修改 `windows/runner/CMakeLists.txt`
- 新增 `lib/app/platform/windows_notification_registration.dart`
- 新增 `test/app/platform/windows_notification_registration_test.dart`
- 修改 `pubspec.yaml`、`pubspec.lock`

**RED 测试/编译契约**

- `注册 channel 解码固定 AUMID CLSID 与图标`
- `注册不可用和 malformed 返回 unavailable`
- `注册 channel 异常不阻断 Dart 初始化`
- 仓库当前没有 C++ runner test target；把 LocalServer32 quoting 与固定身份构造保持为无 Win32 副作用的 helper，以 Windows build 作为 C++ 编译门禁，不新建测试框架。

**GREEN**

- 实现第 8.1–8.3 节。
- `flutter pub get` 更新 lock。
- 运行 Dart test，日志 `logs/windows-notification-registration-green.log`。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter build windows 2>&1 | Out-File -Encoding utf8 logs/build-windows-registration.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows-registration.log
```

构建命令级硬超时 600000ms。

**非阻塞 smoke**

- 从当前 build 发送测试 Toast。
- 应用运行时点击并确认 payload 一次。
- 再发 Toast，完全退出后点击，确认进程被启动且 payload 一次。
- 覆盖同目录 exe 后重试。
- 记录到 `docs/testing/windows-chat-generation-notifications-smoke.md`，允许 `PENDING`。

**硬停止条件**

- 自动测试或 build 证明 shortcut/AUMID/CLSID/LocalServer32 链不成立。
- 已执行 smoke 明确得到冷启动 `FAIL`。
- 可靠实现必须引入 MSIX、安装器或管理员权限。

发生硬停止时不继续 Task 7–9，不把“仅应用运行时 Toast”写成完成方案。

### Task 7：Windows adapter 与 AppWindow

**文件**

- 新增 `lib/app/platform/windows_local_notifications_client.dart`
- 新增 `lib/app/platform/windows_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/windows_app_window.dart`
- 新增 `lib/app/platform/windows_system_notification_settings.dart`
- 新增 `test/app/platform/windows_chat_generation_terminal_notification_adapter_test.dart`
- 新增 `test/app/platform/windows_app_window_test.dart`
- 新增 `test/app/platform/windows_system_notification_settings_test.dart`

**RED 测试**

- `插件初始化使用固定 runner 注册信息`
- `安全 payload 原样传给 Windows 插件`
- `warm callback 与 cold launch details 转成统一 activation`
- `同一 cold payload 只取一次`
- `registration unavailable 时展示为 no-op`
- `插件异常不向上抛出原始异常`
- `窗口不可见时先 show 再 focus`
- `窗口最小化时先 restore 再 focus`
- `窗口恢复部分失败仍尝试 focus`
- `Windows 设置只用 explorer 参数数组且异常返回 false`

**GREEN**

- 实现第 8.4–8.6 节。
- 测试只 fake `WindowsLocalNotificationsClient` 和 AppWindow backend，不加载真实插件。
- 单文件日志写 `logs/windows-terminal-adapter-green.log`，超时 60000ms。

**停止条件**

- 必须在 adapter 内 import chat presentation。
- 必须依赖 cancel/getActiveNotifications 才能完成一次性终态通知。

### Task 8：平台 composition 与根生命周期

**文件**

- 重命名 `lib/app/composition/chat_generation_foreground_service_bindings.dart` 为 `lib/app/composition/chat_generation_notification_platform_bindings.dart`
- 重命名 `test/app/composition/chat_generation_foreground_service_bindings_test.dart` 为 `test/app/composition/chat_generation_notification_platform_bindings_test.dart`
- 新增 `lib/app/composition/app_attention_bindings.dart`
- 新增 `lib/app/platform/noop_system_notification_settings.dart`
- 修改 `lib/app/composition/cross_feature_bindings.dart`
- 修改 `lib/bootstrap.dart`
- 修改 `lib/app/app.dart`
- 修改 `test/helpers/test_harness.dart`
- 修改 `test/helpers/integration_test_helpers.dart`
- 修改 `test/app/composition/chat_generation_notification_platform_bindings_test.dart`
- 修改 `test/integration/bootstrap_integration_test.dart`
- 修改 `test/integration/chat_generation_notification_integration_test.dart`

**RED 测试**

- `Android 绑定共享 bridge 与三个窄端口`
- `Windows 绑定 no-op 前台服务和真实终态适配器`
- `其他平台只绑定 no-op`
- `shared bridge 只 dispose 一次`
- `测试 harness 默认不触发真实 MethodChannel 或 Windows plugin`
- `应用根部 eager 启动注意力 observer 和终态通知模块`

**GREEN**

- 严格按第 9 节装配。
- 用 provider override 测平台选择，不修改全局 `debugDefaultTargetPlatformOverride`。
- 运行所有 app composition 定向测试，日志 `logs/notification-composition-green.log`，单文件超时 60000ms。

### Task 9：系统通知设置 UI

**文件**

- 新增 `lib/features/settings/application/ports/system_notification_settings.dart`
- 新增 `lib/features/settings/application/system_notifications/system_notification_status_controller.dart`
- 修改 `lib/features/settings/presentation/widgets/tabs/other_settings_tab.dart`
- 新增 `test/features/settings/application/system_notifications/system_notification_status_controller_test.dart`
- 新增 `test/features/settings/presentation/settings_screen/settings_screen_system_notification_cases.dart`
- 修改 `test/features/settings/presentation/settings_screen/settings_screen_test_helpers.dart` 注册 fake
- 修改 `test/features/settings/presentation/settings_screen_test.dart` 注册新 cases

**RED 测试**

- `状态查询异常时映射为不可用`
- `刷新时重新查询平台状态`
- `打开设置返回平台端口结果`
- `读取状态时显示流畅加载提示`
- `系统通知开启时显示已开启和设置按钮`
- `系统通知关闭时显示系统已关闭和设置按钮`
- `Windows 功能可用时不显示已开启断言`
- `不可用时显示不可用且禁用按钮`
- `点击设置按钮只调用 application controller`
- `打开失败时显示非阻塞错误气泡`
- `应用恢复前台时刷新状态`
- `通知设置不出现应用内开关`

测试以 provider/fake completion 作为完成信号，setup 默认 `pump()`，不用通用 `pumpAndSettle()`。

**GREEN**

- 实现第 10 节。
- settings entry 文件继续只 import/register case。
- 先运行 application controller 单测并写 `logs/system-notification-status-controller-green.log`，工具超时 60000ms。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/presentation/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-system-notifications-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/settings-system-notifications-green.log
```

工具超时 60000ms。

### Task 10：文档、回归与范围审计

**smoke 文档**

- 修改 `docs/testing/android-chat-generation-foreground-service-smoke.md`：
  - 成功/空回复/最终失败/持久化失败/保护超时。
  - HIGH channel、默认声音、横幅。
  - 精确会话抑制、其他会话/其他页面展示。
  - warm/cold 点击、已删除会话回退。
  - 权限拒绝、设置入口。
- 新增/更新 `docs/testing/windows-chat-generation-notifications-smoke.md`：
  - 前台、失焦、最小化。
  - warm/cold 点击。
  - 同目录覆盖更新。
  - 移动目录后首次手动启动再点击。
  - 系统设置入口。
- 每项只写 `PASS`、`FAIL` 或 `PENDING`；无实机证据保持 `PENDING`。

**定向测试**

- 逐个运行所有修改到的 `*_test.dart`。
- 单文件工具超时 60000ms。
- 超时先运行 `.\scripts\kill-stale-test-processes.ps1`，再诊断；不得直接重跑。

**格式**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR master...HEAD -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
```

**静态与架构**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/analyze-terminal-notifications.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/analyze-terminal-notifications.log
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/import-boundaries-terminal-notifications.log; $BoundaryExit = $LASTEXITCODE; Write-Host "EXIT=$BoundaryExit"; Get-Content -Tail 150 logs/import-boundaries-terminal-notifications.log
```

**全量测试**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

工具超时 240000ms；超时先清理 stale processes。

**构建**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter build windows 2>&1 | Out-File -Encoding utf8 logs/build-windows.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows.log
flutter build apk --debug 2>&1 | Out-File -Encoding utf8 logs/build-android.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-android.log
```

两个构建工具超时各 600000ms。若 Android 只执行 Gradle 单测而未构建 APK，PR 必须写“未执行 Android APK build”。

**范围审计**

```powershell
git status --short
git diff --check
git diff --stat master...HEAD
git diff --name-only master...HEAD
rg -n "content|reasoningContent|errorMessage|stackTrace" lib/app/notifications lib/app/platform
rg -n "MSIX|linux|macos|通知开关" lib android windows
```

逐项人工确认：

- 没有 PC 返回、历史查询或聊天存储改动。
- 没有 Linux/macOS/MSIX/安装器文件。
- 没有应用内通知开关或设置传输参与者。
- 平台 payload 无正文、推理、原始错误。
- Android ongoing 与 terminal channel 分离。
- Kotlin/runner 不判定 generation outcome。
- Windows 只写 HKCU，未添加清理器。
- 所有新测试标题和注释为简体中文。

## 12. 替换而非叠加

实施时必须删除旧职责，避免新旧两套通知并存：

| 删除/替换对象 | 替代 |
| --- | --- |
| projector terminal behavior / retainError | terminal receipt projector |
| foreground port `fail()` | remove + terminal notifications |
| foreground port open action/pending open | unified terminal activation |
| Kotlin LOW 普通错误通知 | HIGH terminal notification |
| `TimedOutNotificationGuard` | timeout receipt + Kotlin fixed fallback |
| Dart foreground channel 独占 handler | shared Android platform bridge |
| `bindChatGenerationForegroundService` | `bindChatGenerationNotifications` |
| 旧 bindings 文件名/测试名 | notification platform bindings |

完成范围审计时，以上旧 symbol 应由 `rg` 得到零生产调用；仅迁移说明文档可出现。

## 13. 提交顺序

本计划阶段不提交。实施时按以下独立提交：

1. `refactor(chat): 分离生成终态通知收据`
2. `refactor(app): 增加生成通知注意力与激活模块`
3. `feat(android): 增加生成终态高优先级通知`
4. `feat(windows): 适配未打包生成终态通知`
5. `feat(settings): 增加系统通知设置入口`
6. `docs(testing): 补充跨平台生成通知验证手册`

每次提交前：

- 对本次所有 Dart 文件执行 `dart format`。
- 暂存后执行 `dart format --output=none --set-exit-if-changed <暂存 Dart 文件>`。
- 检查 `git diff --cached --check`。
- 提交信息使用简体中文。
- post-commit hook 自动 bump 后重新读取 `HEAD`、`pubspec.yaml` 和 changed paths。

Windows 注册若自动验证失败不得作为“功能完成”提交。手工 smoke 为 `PENDING` 不阻塞提交，但正文必须写清未执行。

## 14. PR 完成定义

只有以下全部成立，才能 Ready for review：

- 终态收据无正文、标题、原始异常或动态 Map。
- 真正终态只从现有 terminal snapshot 产生。
- 精确会话抑制、其他会话/页面/失焦展示有自动测试。
- report 与 activation 分别去重。
- timeout 后真正终态仍能报告。
- 所有真正终态和取消都清理 ongoing；失败不再残留 LOW 普通通知。
- Android terminal 使用新 HIGH channel、默认声音/振动；ongoing LOW 静音保持不变。
- Android 权限保持官方一次性请求行为。
- Windows 未打包注册通过 Dart 测试和 Windows build，不要求 MSIX/管理员权限。
- Windows warm/cold payload、窗口恢复、删除会话回退有自动测试。
- 设置页有 loading/状态/打开系统设置，没有开关。
- 平台故障不改变 generation。
- 定向测试、analyze、import boundary、全量测试、Windows build 有日志证据。
- Android/Windows smoke 文档存在，未执行项明确为 `PENDING`。
- `git diff --check` 通过，base...head 无无关范围。

## 15. 全局停止条件

出现任一条件立即停止并报告，不自行扩大范围：

- Windows 可靠冷启动必须依赖 MSIX、安装器或管理员权限。
- 已执行 Windows cold activation smoke 明确失败。
- 插件/runner 无法交付 cold payload。
- Android 横幅只能通过升级既有 LOW channel 实现。
- 必须把正文、prompt 或原始异常传给平台层。
- 必须让 Kotlin/runner 参与 generation outcome 判定。
- 必须修改 `ChatGenerationRun` 的终态所有权。
- 必须引入 Linux/macOS、常驻进程、清理器或应用内通知开关。
- 自动测试/build 暴露需要大范围重构的问题；保留证据，另开计划。

## 16. 参考资料

- Android 通知渠道：<https://developer.android.com/develop/ui/views/notifications/channels>
- Android 13 通知权限：<https://developer.android.com/develop/ui/views/notifications/notification-permission>
- Microsoft 未打包桌面 Toast：<https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl>
- Microsoft Toast activation：<https://learn.microsoft.com/en-us/previous-versions/windows/desktop/win32_tile_badge_notif/respond-to-toast-activations>
- `flutter_local_notifications_windows`：<https://pub.dev/packages/flutter_local_notifications_windows>

实施前只复核当前 lock、插件 3.1.1 API 与官方平台文档；不得借机升级无关依赖。
