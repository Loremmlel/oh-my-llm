# 跨平台生成终态通知实施计划

> 状态：已完成两轮外部依赖与原生链路审计、待实施；本文件只定义实现与验证步骤，不包含产品代码改动。
>
> 目标分支：`feat/cross-platform-generation-notifications`
>
> 基线：`master` @ `4776ee8483586e84add776bf41d4250c51e939fb`
>
> PR 边界：本计划完整对应一个 PR，不与 PC 返回适配或历史页性能优化互相依赖。

## 1. 结果定义

本 PR 为聊天生成增加 Android 与 Windows 终态系统通知，并把“何时发、能显示什么、何时抑制、点击后去哪里”收敛到一个 Dart 深模块。Android Kotlin 与 Windows runner/plugin adapter 只执行平台命令，不参与生成结果判定。

完成后必须同时满足：

- Android 正在生成时继续显示现有 LOW、静音、ongoing 的前台服务通知。
- Android ongoing 通知继续保留“点击后打开对应会话”的现有行为；本 PR 只替换终态通知的展示与激活路径。
- Android 在成功、空回复、最终失败、终态持久化失败和前台保护超时时，通过新的 HIGH 渠道播放系统默认声音并请求横幅展示。
- Windows 通过系统 Toast 显示相同终态；不引入 MSIX、安装器或管理员权限要求。
- Windows Toast 不配置自定义声音，使用系统默认通知声音并服从用户通知设置与专注助手。
- Windows 应用热启动和完全退出两种情况下，点击 Toast 都能恢复并聚焦窗口，然后打开对应会话。
- 当前会话已删除时只回退聊天根页，不弹错误、不恢复数据。
- Android 与 Windows 共享 Dart 收据、固定安全文案、资格判断、注意力抑制、通知 ID、payload、去重和导航规则。
- 用户正在前台且正查看同一会话时不发送系统通知；其余页面、其他会话、后台或 Windows 失焦时发送。
- Dart、MethodChannel、runner 注册和平台 adapter 可观察到的权限、注册、展示、设置查询或激活错误全部 fail-open，不改变 generation phase/outcome，不产生新的聊天错误。第三方 Windows 插件 native FFI 未捕获异常不在 Dart 可保证范围内；第 8.0 节必须如实记录该残余风险，Task 6/8 一旦观察到进程终止立即停止，不得把它写成已验证的 fail-open。
- 设置页只显示系统通知状态与“打开系统通知设置”按钮，不增加应用内通知开关。

## 2. 范围边界

### 2.1 本 PR 包含

- 纯 Dart 终态收据和安全失败分类。
- 现有 generation notification coordinator 的终态接入与 ongoing 清理修正。
- app-owned 注意力快照、窗口抽象、终态通知深模块和导航激活。
- Android 共享 MethodChannel bridge、HIGH 终态渠道、点击激活和设置入口。
- Windows 未打包 Toast 注册、Toast adapter、窗口恢复和设置入口。
- 在编写产品 runner 注册代码前，用独立身份的 throwaway Windows 工程验证 `flutter_local_notifications_windows` 3.1.1 的 warm/cold COM 激活、payload 和进程数。
- 定向单元/widget 测试、现有测试替换、Android/Windows smoke 文档。
- `flutter_local_notifications_windows: 3.1.1` 精确直接依赖；任何版本升级必须重新做源码审计和 Task 6 spike。
- 复用现有 `window_manager: ^0.5.0`；它不是本 PR 的依赖变更。

### 2.2 本 PR 不包含

- Linux、macOS、iOS 或 Web 通知。
- MSIX、安装器、计划任务、后台常驻进程或开机启动。
- 通过进程名模拟 Windows 通知身份。
- 通知历史、撤回/更新已发送终态通知、快捷回复、按钮操作。
- 提示词、回复正文、推理正文、会话标题、模型名、服务商、URL、Header、原始异常或堆栈进入系统通知。
- 聊天存储、生成协调器所有权、路由体系或设置传输格式重构。
- 开始菜单快捷方式和 HKCU 注册项的卸载清理；删除应用目录后的残留保持现状。
- Windows 多版本、多显示器、多用户、多安装位置测试矩阵。
- 通用 Windows 单实例基础设施；Task 6 spike 必须先证明通知 warm/cold/快速连续激活以及“手工启动尚未注册 COM 时点击 Toast”都没有产生第二个进程，否则命中停止条件并另行设计 notification-specific runner 协调，不能接受双 Flutter 实例并发写存储。
- 实机 smoke 的自动 CI 集成。第 14 节规定的 Android/Windows 最小原生 smoke 必须在 Ready for review 前由人工执行并为 `PASS`；更广的系统版本、专注助手、声音设备和多安装位置矩阵可以保留 `PENDING`。

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
- app composition 每次进程启动生成一个 128-bit 随机通知 session ID，编码为 32 个小写十六进制字符；不持久化、不复用、不来自会话或用户数据。
- 去重键使用 `v1:<notificationSessionId>:<generationId>:<terminalKind.name>`。同一进程 session 内，同一种终态只展示一次；同一 generation 的保护超时与后续真正终态分别展示。进程重启后即使 `generationId` 又从 1 开始，也不得复用旧通知 ID、Windows Tag 或 Android PendingIntent。
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

- `String notificationSessionId`
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

`notificationSessionId` 必须是 32 个小写十六进制字符，只用于进程级事件命名，不进入通知文案或日志。计数沿用现有 `ChatGenerationCharacterCounts` 的 `countChatWords` 口径。类型名虽含 `Character`，本 PR 不顺手改名。

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

- payload v1 的 JSON 只允许 `v`、`eventKey`、`conversationId` 三个键，UTF-8 编码后总长度不得超过 1024 bytes。
- decoder 只接受 `v == 1`；`eventKey` 必须不超过 128 字符并完全匹配 `v1:<32 lowercase hex>:<positive int64>:<known terminal kind>`；`conversationId` trim 后为 1..256 字符且不含控制字符。未知版本、额外/缺失字段、错类型、超长或语法不合法一律忽略并记录固定诊断类别。
- Android warm activation 由 MethodChannel callback 交付；cold activation 由 Kotlin 一次性 pending slot 交付。
- Windows warm activation 由插件 callback 交付；cold activation 由插件 launch details 交付。
- hot 与 pending 同时出现时按 `eventKey` 只消费一次。
- Android ongoing 通知继续通过 foreground port 的 `openConversationRequested` / `takePendingOpenConversation()` 打开对应会话；不把该既有行为伪装成终态 activation，也不在本 PR 中删除。
- Windows 激活顺序固定为 `restore/show -> focus -> 已保证调度的下一帧导航`。
- 终态导航前在实际导航帧读取 `chatSessionsProvider.state.conversationSummaries` 判断会话是否仍存在，不得在应用启动时捕获并长期复用一个摘要列表快照：
  - 存在：`goNamed(AppDestination.chat.name, queryParameters: {AppRouteParameter.conversationId: id})`。
  - 不存在：`goNamed(AppDestination.chat.name)`。
- 当前 `ChatSessionsController extends Notifier<ChatSessionsState>` 的 `build()` 同步调用 `repository.loadHistorySummaries()`；首次 `ref.read(chatSessionsProvider)` 不暴露“未加载但暂为空”的中间状态，因此 `conversationExists` 保持同步 bool，不新增虚假的 loading 三态。
- 若实施基线把会话初始化改为异步，或实际测试能观察到未加载状态，立即停止并把这里改成显式 readiness interface；不得用固定延时、把超时一律当存在或静默吞掉未知状态。
- hot/pending 并发重复用 `_activationsInFlight` 拦截；只有窗口恢复和导航成功后才加入 `_activatedEventKeys`。恢复或导航失败只记录固定诊断并移出 in-flight，不自动循环重试，但用户后续再次点击同一 Toast 可以重试。

### 3.6 权限和设置

- Android 13+ 复用现有“一次询问、拒绝后不循环弹框”行为。
- Android 8+ 保留两个职责不同的 channel：
  - `chat_generation`：LOW、静音、ongoing，只用于前台服务。
  - `chat_generation_result`：HIGH、默认声音/振动、非 ongoing、auto-cancel，只用于终态。
- 已创建 channel importance 不可由更新升级，因此终态必须使用新 ID。
- Windows 不显示运行时权限弹窗；系统设置可能关闭应用通知，而未打包 API 无法可靠查询最终开关，所以 Windows 只报告“功能可用”，不伪装成“已开启”。
- Windows `WindowsNotificationDetails()` 保持 `audio == null`，不生成显式 `<audio>` 配置；声音与横幅交给系统通知设置和专注助手决定，smoke 必须记录实际结果。
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
- `ChatGenerationNotificationCoordinator` 是唯一收据插入点，因为它已经 eager watch `(generation, streamingReply)` 并串行处理 native action。它接收一次进程级 `notificationSessionId`，同时写入 ongoing payload 和终态收据，Kotlin 只把该 ID 当作不透明安全字段。
- coordinator 的 async tail 是一个深模块：调用方只提交状态，不能理解或补偿 native 排队。旧状态是否可入队在入口判定；一旦某 token 的 start/update/terminal operation 已入队，就必须按 FIFO 完成，后续 generation 不得用 `_currentToken` 取消它。operation 完成后只有与当前 token 匹配时才能回写当前 token 的可用性字段。
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
    required this.notificationSessionId,
    required this.generationId,
    required this.conversationId,
    required this.terminalKind,
    required this.contentCount,
    required this.reasoningCount,
    required this.failureKind,
  });

  final String notificationSessionId;

  String get eventKey =>
      'v1:$notificationSessionId:$generationId:${terminalKind.name}';
}
```

构造 invariant：

- `notificationSessionId` 完全匹配 `^[0-9a-f]{32}$`。
- `generationId` 在 `1..9223372036854775807`，保证传到 Kotlin `Long` 不溢出。
- `conversationId` trim 后为 1..256 字符且不含控制字符。
- `contentCount >= 0`、`reasoningCount >= 0`。
- `succeeded` 必须配 `none`。
- `emptyReply` 必须配 `emptyReply`。
- `persistenceFailed` 必须配 `persistence`。
- `foregroundProtectionTimedOut` 必须配 `foregroundProtection`。
- `failed` 只能配 network/timeout/authentication/authorization/rateLimited/server/invalidOutput/unknown。

在同文件提供纯函数：

```dart
ChatGenerationTerminalReceipt? projectChatGenerationTerminalReceipt({
  required String notificationSessionId,
  required ChatGenerationSnapshot snapshot,
  required ChatGenerationCharacterCounts counts,
});
```

映射规则：

- 非终态返回 `null`。
- cancelled 返回 `null`。
- `succeeded` 不信任节流后的 `counts`：直接从 `snapshot.outcome as ChatGenerationSuccess` 的完整 `content/reasoningContent` 用 `countChatWords` 计算收据计数。这样最后一个 300ms UI flush 之后到达的 chunk 也不会漏计；正文只在纯函数栈内读取，收据仍只保存整数。
- 其他终态文案不展示计数，可沿用传入的最后安全 counts；不得为了计数修改 `ChatGenerationRun` 或读取持久化层。
- 失败分类只按已存在的安全类型信息：
  - `ChatErrorMessages.outputRuleEmptied` → `invalidOutput`
  - `TimeoutException` 或 `ChatGenerationException.cause is TimeoutException` → `timeout`
  - `SocketException` 或 `ChatGenerationException.cause is SocketException` → `network`
  - HTTP 401 → `authentication`
  - HTTP 403 → `authorization`
  - HTTP 429 → `rateLimited`
  - HTTP 5xx → `server`
  - 其他 → `unknown`
- 当前三个协议客户端都把 `LlmHttpTransportException.statusCode` 原样写入 `ChatGenerationException.statusCode`；HTTP 分类直接读取该 nullable 字段，不从 `message`、`responseBody` 或 `cause` 猜状态码。
- 没有 `statusCode` 的 SSE error、协议解析错误或其他异常按既有类型规则分类，仍无法识别时统一为 `unknown`，对应固定文案“请打开应用查看详情”。
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
- 实现前先用一次性独立 Dart 脚本按上述 UTF-8/32-bit 公式生成向量，再把结果锁入产品测试；脚本不进入生产代码。固定测试 session `000102030405060708090a0b0c0d0e0f` 的预核对向量为：
  - `v1:000102030405060708090a0b0c0d0e0f:7:succeeded` → `1672833428`
  - `v1:000102030405060708090a0b0c0d0e0f:7:foregroundProtectionTimedOut` → `937742124`
- 测试还必须证明两个不同 session、相同 generation/kind 得到不同 event key；若碰巧得到相同 FNV ID，只断言 event key 不同并把该向量换成另一个固定 session，不能把哈希碰撞误判为 session 失效。
- FNV-1a 映射不是无碰撞 ID。不同 `eventKey` 极低概率映射到同一 ID 时，Android/Windows 后一条系统通知会覆盖前一条，Android 的 `FLAG_UPDATE_CURRENT` 也会让点击指向后一条合法 payload；本 PR 接受“丢失一条较早通知”的已知限制，不加入持久化碰撞表。

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

初始值固定为 `detached`、`false`、空 `Uri()`；不得在异步焦点查询完成前假定 attentive。这个启动窗口有意选择“可能多发、不能漏发”，首个真实 lifecycle/route/focus 快照到达后自然收敛，实施者不得把初值改成虚假的前台聚焦状态。

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
- observer 在订阅 focus stream 后再调用异步 `isFocused()`。每个 stream 事件递增 `_focusRevision`；初始查询只在 revision 未变化且 observer 未 dispose 时写回，防止迟到的旧查询覆盖较新的 blur/focus 事件。

### 5.5 默认深模块

新增 `lib/app/notifications/default_chat_generation_terminal_notifications.dart`。

同文件定义 `chatGenerationTerminalNotificationsProvider`；它依赖 `chatGenerationTerminalNotificationAdapterProvider`，后者在 Task 2 先提供 `NoopChatGenerationTerminalNotificationAdapter` 的安全默认值，Task 9 再由平台 composition override。这样 Task 3 接入 coordinator 后每个中间提交都能编译和启动，不会因尚未装配 Android/Windows adapter 触发未绑定 provider；平台终态展示只有在 Task 9 完成后才成为可验收能力。notification session provider 也在 Task 2 创建，Task 3 起 coordinator 与默认深模块都读取同一个值。

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

1. `start()` 幂等，并把完整初始化链保存为同一个 `_startFuture`。
2. 在 `_startFuture` 的第一个 `await` 前订阅 `adapter.activations`，避免初始化期间丢 warm callback。
3. 调 `adapter.initialize()`；错误记录 `terminal_adapter_initialize_failed` 并让 `_startFuture` 以“初始化不可用”完成，保持对象可 dispose，不抛给 generation。
4. 初始化成功后调 `takePendingActivation()`；若存在，走同一 activation 消费路径。
5. `report()` 先 `await _startFuture`；若调用时尚未显式 start，则内部幂等启动。初始化不可用时固定诊断后返回，不能在插件 ready 前调用 show。
6. report 用 `_reportingEventKeys` 拦截并发重复；读取注意力、route 和 active conversation。命中抑制条件时加入 `_reportedEventKeys`；展示成功时再加入；展示失败只移出 in-flight，允许未来重复 terminal snapshot 重试，但不自动循环。
7. 将收据映射为固定安全 copy、ID 和 payload后调用 `adapter.show()`；错误记录 `terminal_notification_show_failed`，不 rethrow。
8. activation 用 `_activationsInFlight` 拦截 hot/pending 并发重复，再 `await restoreHost()`。
9. 注册 `SchedulerBinding.instance.addPostFrameCallback` 后立即调用 `SchedulerBinding.instance.ensureVisualUpdate()`；用 `Completer` 等待回调。在回调中先检查 dispose，再重新调用 `conversationExists(id)` 并执行 `openChat(exists ? id : null)`。成功后移入 `_activatedEventKeys`，失败只移出 in-flight。
10. `dispose()` 标记 disposed、完成/忽略尚未执行的导航 callback、取消 subscription、调用 adapter.dispose；错误只记固定诊断，重复调用安全。

实现必须维护四个独立集合：

- `_reportingEventKeys` / `_reportedEventKeys`：分别防并发展示和已完成重放，抑制也算完成。
- `_activationsInFlight` / `_activatedEventKeys`：分别防并发导航和已完成重放。
- 两个 completed 集合使用 insertion-ordered、上限 512 的实现，超限只逐出最旧 completed key；两个 in-flight 集合各上限 32，满时忽略新输入并记录固定 `notification_in_flight_limit`，不得无界增长或逐出正在处理的 key。

日志只允许固定分类，不插值 payload、conversation ID 或异常文本。

## 6. 现有 coordinator 的准确改法

修改 `lib/app/composition/chat_generation_notification_coordinator.dart`，不新建第二个 lifecycle listener。

### 6.1 构造与状态

- 构造函数新增 `String notificationSessionId` 和 `ChatGenerationTerminalNotifications terminalNotifications`，并保留现有 `openConversation` callback；session ID 由 app composition 每个 ProviderScope 只生成一次，前者只处理新终态通知，后者继续处理 Android ongoing 通知的既有点击行为。
- 把散落的 `_currentToken/_lastCounts/_timedOut/_tokenUnavailable/_terminalDelivered` 和同 token 的 pending/delivery 字段收进私有 `_NotificationGenerationContext`。新 token 替换 `_currentContext`，但旧 context 可继续被已经入队的 closure 持有直到 FIFO 完成；该内部类型不进入端口或 provider interface。
- context 的 `_lastCounts` 只是非成功终态和 timeout 的安全 fallback；成功终态的权威计数来自 `ChatGenerationSuccess` 完整 outcome。
- context 的 `timedOut` 同时表示“Kotlin timeout 路径已经移除 ongoing”；不再增加第二个 cleanup boolean。
- 保留前台服务 `openConversationRequested` / `takePendingOpenConversation()` 处理，确保 ongoing 点击仍直达对应会话；只有旧 LOW 普通错误通知的点击职责移到终态通知深模块。

### 6.2 `onStateChanged` 顺序

固定顺序：

1. token 校验；更小 token 的迟到状态在入口拒绝。更大 token 创建新 context，但不得取消旧 context 已经入队的 operation。
2. 若 `snapshot.phase.isTerminal`：
   - 先用 `projectChatGenerationTerminalReceipt(notificationSessionId: notificationSessionId, snapshot: snapshot, counts: context.lastCounts)` 得到 nullable receipt；成功计数由 projector 从完整 outcome 重算。
   - context 只允许 terminal 入队一次；总是取消该 context 的 pending timer。
   - 捕获 context、receipt、conversationId 和 `skipRemove=context.timedOut`，入 coordinator 的同一个 async tail operation。closure 执行时不得再比较 `_currentContext.token`，也不得读取新 context 的字段。
   - 若捕获的 `skipRemove == false`，先调用前台端口 `remove(token, conversationId)`，沿用现有三次 cleanup ACK 重试；三次重试只受 dispose 取消，不受新 generation 取消。
   - receipt 非 null 时，无论 cleanup 最终成功还是耗尽，再调用 `terminalNotifications.report(receipt)`。
   - cancellation 的 receipt 为 null，因此只执行 cleanup；timeout 已清理时则为完全 no-op。
   - timeout 已清理且 receipt 非 null 时跳过 remove，直接调用 `terminalNotifications.report(receipt)`。
   - report 自己 fail-open；不得让 cleanup 失败阻止真正终态通知。
   - 不再调用 ongoing projector。
3. 非终态才调用 `ChatGenerationNotificationProjector.project()`。
4. projector 接收同一个 `notificationSessionId` 并把它写入 start/update payload。context `timedOut` 后继续抑制尚未入队的 ongoing start/update，不重启前台服务。
5. start/update timer 在触发时先确认捕获的 context 仍是 current 且未 terminal，再入队；一旦入队，operation 必须执行。ACK 返回后只修改捕获 context，绝不能把 token1 的失败写到 token2。

串行 cleanup 后 report 是有意的产品权衡：避免 Android 同时展示“仍在生成”的 ongoing 与“生成已结束”的终态通知。单次 cleanup 在三次 2 秒 channel timeout 全部耗尽并加上 200ms/800ms 退避时，上界为 7 秒；若 tail 前面已有在途 native command，还要加上其剩余等待时间。实现和测试必须记录这个上界，不得写成“立即通知”；若产品改为优先及时提醒，需单独确认后改成 report-first，而不是实施时临场换序。

### 6.3 timeout action

`ChatGenerationForegroundTimedOut` 只在 token 等于当前 token 且尚未真正 terminal 时处理：

1. `context.timedOut = true`。
2. 取消该 context 的 pending update。
3. 不再调用前台端口 `remove`：Kotlin 在发 callback 前已经移除 ongoing 并停止 Service，避免 MethodChannel callback 内再次调用 Kotlin 形成重入。
4. 用同一个 `notificationSessionId` 与 `context.lastCounts` 创建 `foregroundProtectionTimedOut` 收据。
5. 把 `terminalNotifications.report(timeoutReceipt)` 加入 coordinator 现有 async tail，保持 timeout 与后续真正终态的顺序；不调用 stop/cancel/retry/finalize。
6. 后续真正 terminal 仍报告，但因捕获的 `context.timedOut` 跳过 remove。

### 6.4 ongoing projector 收窄

修改 `lib/features/chat/application/generation/chat_generation_notification.dart`：

- 删除 `ChatGenerationNotificationTerminalBehavior`。
- 删除 projection 的 `terminalBehavior` 字段。
- 删除 terminal private/public copy、`summarizeChatGenerationNotificationError()`，并移除只为错误摘要存在的 `dart:async`、`dart:io`、`chat_error_messages.dart`、`chat_generation_client.dart` imports。
- projector 只接受 preparing/streaming/retryWaiting/stopping/finalizing。
- 对 idle 和所有 terminal phase 抛 `ArgumentError`，由 coordinator 保证不会调用。
- projector 新增必填 `notificationSessionId`；`ChatGenerationForegroundPayload` 增加 `timeoutActivationPayload`，由共享 Dart codec 预编码为当前 token 的 `foregroundProtectionTimedOut` 安全 payload。保持字数、截断、ongoing 文案和 action 不变。
- `timeoutActivationPayload` 只含既有三个白名单字段且最长 1024 UTF-8 bytes；Kotlin 只保存并在 fallback PendingIntent 中原样返回，不解析 event key、不复刻 JSON/FNV/session 规则。

修改 `lib/features/chat/application/ports/chat_generation_foreground_service.dart`：

- 保留 `ensureNotificationPermission`、`start`、`update`、`remove`、`takePendingOpenConversation`、`actions`、`dispose`。
- 删除 `fail()`。
- 保留 `ChatGenerationOpenConversationRequested`，仅供 Android ongoing 通知点击；不得用于新终态通知。
- `actions` 允许 `ChatGenerationStopRequested`、`ChatGenerationOpenConversationRequested` 和 `ChatGenerationForegroundTimedOut`。

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
| `startForegroundGeneration` | ongoing payload（含 Dart 预编码 `timeoutActivationPayload`） | command ACK |
| `updateForegroundGeneration` | ongoing payload（沿用同 token 的相同 `timeoutActivationPayload`） | command ACK |
| `removeForegroundGeneration` | token + conversationId | command ACK |
| `takePendingOpenConversation` | 无 | nullable conversation ID（仅 ongoing） |
| `showTerminalNotification` | id + title + body + publicTitle + publicBody + payload | `bool` |
| `takePendingNotificationActivation` | 无 | nullable activation map |
| `getNotificationSettingsStatus` | 无 | `enabled` / `disabled` / `unavailable` |
| `openNotificationSettings` | 无 | `bool` |

删除：

- `failForegroundGeneration`

### 7.3 Kotlin → Dart callback

只包含：

| callback | 参数 |
| --- | --- |
| `stopRequested` | token + conversationId |
| `foregroundServiceTimedOut` | token + conversationId |
| `openConversationRequested` | conversationId（仅 ongoing） |
| `notificationActivated` | payload |

`openConversationRequested` / `takePendingOpenConversation` 只保留给现有 ongoing 通知；新 HIGH 终态和 timeout fallback 点击统一传版本化 payload。bridge 必须把两类激活分发到各自窄流，不能让 terminal adapter 接管或吞掉 ongoing 点击。

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
- 主通知必须调用 `setPublicVersion()`：public builder 只使用传入的固定 `publicTitle/publicBody`、同一 small icon/category/contentIntent，visibility 为 `VISIBILITY_PUBLIC`；不得让 public 字段成为未消费参数。
- small icon：`R.drawable.ic_chat_generation`
- notification ID：Dart 传入的稳定 ID
- PendingIntent request code：同一 notification ID
- PendingIntent flag：`FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`
- Intent data：`oh-my-llm://generation-notification/<notificationId>`
- extras 只保存 payload 字符串

现有 `chat_generation` channel、ongoing notification ID `4101`、静音、foreground service type 以及点击后打开对应会话的 content intent 保持不变。

当前 Android JVM 测试没有 Robolectric，因此：

- `ChatGenerationNotificationProtocolTest.kt` 测纯 MethodChannel map decoder、token guard、method/callback 常量、request code/ID 冲突规则，以及 `timeoutActivationPayload` 非空/类型/1024-byte 上限；Kotlin 不解析其 JSON 内容。
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
   - payload 直接使用 service 从 start payload 保存的 `timeoutActivationPayload`；其 event key 已由 Dart 固定为 `v1:<notificationSessionId>:<token>:foregroundProtectionTimedOut`，Kotlin 不重建、不解析。
   - notification ID 固定为 `4200`，PendingIntent request code 同为 `4200`，Intent data 固定为 `oh-my-llm://generation-notification/4200`；该 ID 低于 Dart FNV-1a 的 `10000` 下界且不与 ongoing `4101` 冲突。
   - fallback 同一时间语义上至多保留一条；后一次 timeout 覆盖前一次，并由 `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE` 把点击 payload 更新为后一次。Kotlin 不复刻 FNV-1a。

删除现有：

- LOW channel 普通错误/timeout 留存路径。
- `TimedOutNotificationGuard`。
- `failForegroundGeneration` 相关 builder 与 ACK。
- `PUBLIC_ERROR_*`、`OPEN_ACTION_*` 和普通错误通知 action。

fallback 的目的仅是原生前台服务已经失去 Dart 通道时仍告知用户；它不判定生成终态。`hasListener == false` 必须返回 false 并选择 fallback，不能用“stream 存在”伪装事件已被 Dart 接收。

这里有意接受一个窄残余窗口：ACK 为 true 后，Dart report 仍可能在 async tail 等待 cleanup/初始化；若进程恰在系统通知 show 前被终止，Kotlin 已不会 fallback。该 ACK 只覆盖“Dart handler 是否连接”，不是 durable delivery。不得在 PR 中声称 timeout 通知 exactly-once/no-loss；若产品要求关闭该窗口，必须另行设计展示完成握手，不能在同一 MethodChannel callback 中临场加入未经验证的 native 重入。

### 7.6 Android 设置

状态：

- `showTerminalNotification` 与 `getNotificationSettingsStatus` 都先幂等调用 `ensureTerminalChannel()`；因此用户进入设置页时，即使尚未发生第一条终态通知，API 26+ channel 也已经存在并可由系统配置。已有 channel 绝不删除重建或尝试升级 importance。
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

### 8.0 `flutter_local_notifications_windows` 3.1.1 源码核实

实施计划固定使用 pub.dev 3.1.1 archive；已核实的源码职责是：

- Dart `FlutterLocalNotificationsWindows.initialize()` 调用 native `init()`；C++ `NativePlugin::registerApp()` 随后执行 `RegisterCallback()`，用 `CoRegisterClassObject(..., CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, ...)` 注册运行中 class object。
- 插件 C++ 自带 `INotificationActivationCallback::Activate()` 与 class factory；warm 路径不需要 runner 再实现一套 COM callback。
- `Activate()` 把 Windows 传入的 `args` 作为 UTF-8 payload 交给 Dart；初始化完成后的 Dart `_onDidReceiveNotificationResponse()` 会保存 `_details` 并调用 `onDidReceiveNotificationResponse`，`getNotificationAppLaunchDetails()` 再返回同一 payload。
- 插件初始化会写 AUMID 的通知注册和 `CustomActivator`，但不创建开始菜单 shortcut，也不写 `HKCU\Software\Classes\CLSID\{CLSID}\LocalServer32`；这两项仍由 runner 负责。
- 插件不读取或识别进程命令行参数。LocalServer32 不需要插件专用的 `--notification-activated`；COM 会自行附加 `-Embedding`，runner 和 Dart 都不得依赖该参数判断 activation。
- 插件存在两个不能被计划文字掩盖的 native 风险：Dart `_isReady` 只在 native `init()` 返回后置 true，过早 activation callback 会被丢弃；C++ `UpdateRegistry/RegisterCallback` 使用 `winrt::check_win32/check_hresult`，但导出的 FFI `init` 没有 catch-all，Dart `try/catch` 不能证明异常一定 fail-open。插件也没有 `CoRevokeClassObject`，因此产品只允许进程生命周期内初始化一个 client，不能 dispose 后重建真实 client。

以上是源码契约和已知限制，不代替真实 Windows Shell/COM 验证。Task 6 必须先用 throwaway 工程重复证明 warm/cold payload、手工启动窗口、进程复用和快速连续激活，再允许写产品 runner；任一 native crash/callback 丢失/第二实例都命中停止条件。

### 8.1 固定身份

- appName：`Oh My LLM`
- AUMID：`YuzuShiki.OhMyLlm`
- plugin GUID（传 Dart `WindowsInitializationSettings.guid`，固定 36 字符、无花括号）：`7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751`
- registry/COM CLSID 文本：`{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}`
- 开始菜单快捷方式：`FOLDERID_Programs\Oh My LLM.lnk`
- registration channel：`yuzu.shiki.oh_my_llm/windows_notification_registration`

这些值提交后不得随版本号、构建号或目录变化。

固定 AUMID/CLSID 也意味着开发版、发布版和同一用户安装的多个副本共享同一通知身份；每次手工启动会把 shortcut 与 LocalServer32 修复为该次启动的 exe。并发运行多个安装副本不受支持，最后一次启动者接管后续冷启动激活。这是已知限制，不在本 PR 内引入多安装仲裁或动态身份。

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
   - 用 `CLSIDFromString` 解析带花括号 CLSID；`PKEY_AppUserModel_ToastActivatorCLSID` 必须写 `PROPVARIANT{vt=VT_CLSID, puuid=<parsed CLSID>}`，不得用 `InitPropVariantFromString` 或 REG_SZ 代替。
4. 写入 `HKCU\Software\Classes\CLSID\{CLSID}\LocalServer32` 默认值：
   - `"绝对路径\oh_my_llm.exe"`
   - exe 路径始终带双引号。
   - 同 key 写 `ServerExecutable` REG_SZ，值为不带引号、不带参数的 exe 绝对路径；默认值与 `ServerExecutable` 必须来自同一已解析路径。
   - 不附加自定义 activation 参数；接受 COM 自动附加的 `-Embedding`，应用启动流程不解析它。
5. 返回结构体 `available/aumid/guid/appName`；`guid` 始终是无花括号 36 字符形式，Dart 不再 strip/补花括号。
6. 每次启动幂等修复 shortcut target 和 LocalServer32，因此原目录直接覆盖更新不受影响；移动整个目录后首次手动启动会修复路径。
7. 任一步失败返回 `available=false` 并输出固定 Win32 stage/code；继续启动 Flutter，不抛出会阻断进程的异常。

不写 HKLM，不请求管理员权限，不删除旧注册。

`FlutterWindow` 构造函数接收 registration info，并在 engine 创建后注册只读 MethodChannel：

- method：`getRegistration`
- success：返回 `available`、`appName`、`appUserModelId`、无花括号 `guid`
- failure：返回 `available=false` 与固定 `failureStage`，不返回绝对路径或系统错误文本

`CMakeLists.txt`：

- 把 `windows_notification_registration.cpp` 加入 runner sources。
- link `ole32.lib`、`shell32.lib`、`propsys.lib`、`advapi32.lib`。
- 保留现有 `flutter`、`flutter_wrapper_app`、`dwmapi.lib`。

### 8.3 Dart 注册 decoder

新增 `lib/app/platform/windows_notification_registration.dart`：

- `WindowsNotificationRegistration` 不可变值对象，只含 `available/appName/appUserModelId/guid`。
- `WindowsNotificationRegistrationClient` 只调用 registration channel。
- decoder 要求 GUID 完全匹配固定无花括号值和 `^[0-9A-Fa-f-]{36}$`；缺任何固定字符串、返回带花括号 GUID 或 `available != true` 时返回 unavailable，不抛 raw `PlatformException`。
- 单测用 fake `MethodChannel` handler 覆盖 success、unavailable、malformed、exception。
- 插件 `iconPath` 明确传 `null`：现有 `app_icon.ico` 是 runner 源资源，不会以独立文件进入 ZIP 输出，本 PR 不新增图标复制链。

### 8.4 插件边界

`pubspec.yaml` 增加直接依赖：

```yaml
flutter_local_notifications_windows: 3.1.1
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

生产 client 构造函数不得实例化 `FlutterLocalNotificationsWindows`；真实插件对象只能在 Windows adapter 的 `initialize()` 内、runner registration 已验证可用后惰性创建。这样 import/构造 composition 值对象不会在 Ubuntu CI 尝试打开 `flutter_local_notifications_windows.dll`。真实 client 一旦初始化，无论成功失败都不在同一进程重建第二个实例。

`WindowsNotificationDetails()` 不传 `audio`、`scenario` 或自定义音频 URI：Toast 使用 Windows 默认通知语义，并服从系统关闭通知、声音设置和专注助手。自动测试只断言没有显式静音/自定义声音；真实是否响铃只由 Windows smoke 记录。

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

这里的“插件异常”只指 Dart Future/FFI 正常返回的错误；不能声称捕获第 8.0 节所述、可能越过 FFI 的 C++ 异常。Task 6 和产品最小 smoke 没有观察到 crash 只能证明已测环境可用，不能升级为所有 Windows 环境的绝对进程级 fail-open 保证。

### 8.6 Windows 窗口恢复

`WindowsAppWindow.restoreAndFocus()` 固定：

1. `isVisible == false` 时 `show()`。
2. `isMinimized == true` 时 `restore()`。
3. 最后 `focus()`。

各调用分别 catch 并继续下一步；如果 focus 最终失败，activation 仍导航，诊断记录 `window_restore_or_focus_failed`。不因为窗口 API 失败丢失会话目标。

### 8.7 Windows 设置

新增 `lib/app/platform/windows_system_notification_settings.dart`。

同文件定义内部 `WindowsProcessLauncher` seam：生产 adapter 才调用 `Process.start`，测试 adapter 返回受控 Future 并记录 executable/arguments/mode；`WindowsSystemNotificationSettings` 只依赖该 seam，不直接静态调用进程。

使用：

```dart
Process.start(
  'explorer.exe',
  const ['ms-settings:notifications'],
  mode: ProcessStartMode.detached,
);
```

禁止 `runInShell: true`，不拼接命令字符串。成功启动返回 true，异常返回 false。状态只能可靠报告 `available`（runner 注册先决条件可用，不承诺插件此刻或未来每次展示都成功）或 `unavailable`（注册不可用）；不要伪造系统级精确开关读取。

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

工厂 interface：

```dart
typedef ChatGenerationNotificationPlatformBindingsFactory =
    ChatGenerationNotificationPlatformBindings Function();

ChatGenerationNotificationPlatformBindings
createChatGenerationNotificationPlatformBindings({
  required TargetPlatform platform,
  ChatGenerationNotificationPlatformBindingsFactory? androidFactory,
  ChatGenerationNotificationPlatformBindingsFactory? windowsFactory,
  ChatGenerationNotificationPlatformBindingsFactory? otherFactory,
});
```

只有被选中的 factory 可以执行；不得先构造所有平台 adapter 再选记录：

- Android：创建一个 `AndroidChatGenerationPlatformBridge`，三个窄 adapter 共享它，`disposeShared` 只 dispose bridge 一次。
- Windows：foreground no-op + Windows terminal adapter + Windows settings adapter。
- 其他：三个 no-op。

端口各自 dispose 不得重复 dispose shared bridge；composition 只在 `disposeShared` 释放 shared owner。
生产调用不传 factory，使用文件内默认实现。测试选择 `TargetPlatform.windows` 时必须传返回 fake/no-op 记录的 `windowsFactory`，从构造源头阻止真实 Windows client 和 DLL 加载；这只是 composition 内部测试 seam，不暴露给 feature。

### 9.2 AppWindow 绑定

新增 `lib/app/composition/app_attention_bindings.dart`：

- Windows → `WindowsAppWindow`
- 其他 → `NoopAppWindow`
- `createAppWindow({required platform, windowsFactory, otherFactory})` 使用同样的惰性 factory 规则；测试选择 Windows 必须注入 fake/no-op，不能先构造全局 `windowManager` client。

新增 `lib/app/platform/noop_system_notification_settings.dart`，供非 Android/Windows 平台与普通测试使用。

### 9.3 `appCompositionOverrides`

修改 `lib/app/composition/cross_feature_bindings.dart`：

- `bindChatGenerationForegroundService` 重命名为 `bindChatGenerationNotifications`。
- 增加 `bindAppWindow`。
- 使用 Task 2 已新增的 `lib/app/notifications/chat_generation_notification_session.dart`：生产 `createChatGenerationNotificationSessionId()` 用 `Random.secure()` 生成 16 bytes 并编码为 32 个小写 hex；同文件 provider 在一个 root ProviderScope 内只创建一次。测试必须 override 固定 session，不读取时间或全局随机状态。
- 一次创建 notification platform bindings，并分别 override：
  - `chatGenerationForegroundServiceProvider`
  - `chatGenerationTerminalNotificationAdapterProvider`
  - `systemNotificationSettingsProvider`
- `ref.onDispose` 只注册一次 shared disposer。
- AppWindow 单独 override。
- `ChatGenerationNotificationCoordinator` provider 与默认终态通知模块读取同一个 session provider；不得各生成一份。

修改所有调用点：

- `lib/bootstrap.dart`
- `test/helpers/test_harness.dart`
- `test/helpers/integration_test_helpers.dart`
- `test/integration/bootstrap_integration_test.dart`
- `test/integration/chat_generation_notification_integration_test.dart`

`bootstrap()` 增加两个只供测试注入的可选参数 `notificationPlatformBindingsFactory` 与 `appWindowFactory`，生产均传 null；它们只向 `appCompositionOverrides` 透传，不改变平台判断。`test_harness` / integration helper 默认传 no-op/fake factory 并 override 固定 session，因此 `hostPlatform: TargetPlatform.windows` 也不触发真实 MethodChannel、`window_manager` 或 Windows DLL。需要 case-specific fake 时可传 `bindChatGenerationNotifications: false` / `bindAppWindow: false` 后自行 override。

Ubuntu CI 必须执行一条 composition/bootstrap 测试：显式选择 `TargetPlatform.windows`、注入 fake factories、完成 root eager start，并证明没有 `DynamicLibrary.open('flutter_local_notifications_windows.dll')` 错误。不得通过跳过 Windows 平台选择测试来规避。

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

该端口文件在 Task 2 创建，早于 Android/Windows adapter 与 Task 9 composition；Task 10 只新增 controller/UI，不得把基础端口留到最后导致前序 Task 无法编译。

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

### Task 1：只新增终态收据，不改变既有投递行为

**文件**

- 新增 `lib/features/chat/application/generation/chat_generation_terminal_notification.dart`
- 新增 `lib/features/chat/application/ports/chat_generation_terminal_notifications.dart`
- 新增 `test/features/chat/application/generation/chat_generation_terminal_notification_test.dart`

**RED 测试**

- `成功终态生成安全计数收据`
- `成功终态从完整 outcome 计数而不使用节流 fallback`
- `空回复使用独立终态与安全分类`
- `最终失败按异常类型映射安全分类`
- `HTTP 401 403 429 和 5xx 只读取 ChatGenerationException.statusCode`
- `缺少 statusCode 且类型不可识别时统一退化为 unknown`
- `持久化失败不归类为普通生成失败`
- `取消和非终态不生成收据`
- `收据拒绝非法 session generation ID 会话 ID 与负计数`
- `不同 session 的相同 generation 生成不同 event key`
- `event key 格式固定且不携带正文`

命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/generation/chat_generation_terminal_notification_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/terminal-receipt-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/terminal-receipt-red.log
```

工具超时 60000ms。RED 必须因新类型/行为缺失失败。

**GREEN**

- 实现第 5.1 节类型、invariant 和纯映射。
- 不修改 ongoing projector、coordinator 或 foreground port；本提交只是可独立编译的新增能力，既有 terminal cleanup/fail 行为必须保持全绿。projector 收窄与 coordinator 迁移在 Task 3 原子完成。
- 同命令写 `logs/terminal-receipt-green.log` 并达到 `EXIT=0`。
- 另运行既有 `test/features/chat/application/generation/chat_generation_notification_test.dart`，日志写入 `logs/terminal-receipt-existing-green.log`；证明新增收据尚未改变 ongoing projector、cleanup 或 fail 契约。

**停止条件**

- 需要把原始错误或回复文本保存在 receipt。
- 无法从现有 snapshot/outcome 区分五类终态。

### Task 2：注意力、基础端口与默认终态通知深模块

**文件**

- 新增 `lib/app/attention/app_attention_state.dart`
- 新增 `lib/app/attention/app_window.dart`
- 新增 `lib/app/attention/app_attention_observer.dart`
- 新增 `lib/app/notifications/chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/notifications/chat_generation_notification_session.dart`
- 新增 `lib/app/notifications/default_chat_generation_terminal_notifications.dart`
- 新增 `lib/app/platform/noop_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/noop_app_window.dart`
- 新增 `lib/features/settings/application/ports/system_notification_settings.dart`
- 新增 `test/app/attention/app_attention_observer_test.dart`
- 新增 `test/app/notifications/chat_generation_notification_session_test.dart`
- 新增 `test/app/notifications/chat_generation_notification_payload_test.dart`
- 新增 `test/app/notifications/default_chat_generation_terminal_notifications_test.dart`

**RED 测试**

- `前台聚焦且查看对应会话时抑制通知`
- `查看其他会话时展示通知`
- `非聊天页面时展示通知`
- `Windows 窗口失焦时展示通知`
- `同一收据重复报告时只展示一次`
- `被抑制的收据不会在失焦后重放`
- `保护超时后仍允许真正终态`
- `平台初始化和展示失败均不向调用者抛出`
- `report 在初始化完成前到达时等待同一个 start future`
- `展示失败不完成 report 去重且后续重复报告可重试`
- `固定 event key 生成固定通知 ID`
- `不同进程 session 的相同终态不会复用通知 ID 向量`
- `payload 只包含三个允许字段`
- `超长 控制字符 额外字段 未知版本和 malformed payload 被忽略`
- `hot 与 pending activation 只导航一次`
- `空闲 scheduler 会主动请求导航帧`
- `导航排队后 dispose 不执行 openChat`
- `窗口恢复或导航失败后再次点击可以重试`
- `已删除会话回退聊天根页`
- `会话存在判断在导航帧读取而不捕获启动期空列表`
- `detached 初值在首个真实注意力快照前选择展示`
- `迟到的初始焦点查询不覆盖较新的 focus event`
- `completed 去重集合和 in-flight 集合都有上限`
- `dispose 幂等并取消激活订阅`

**GREEN**

- 完成第 5.2–5.5 节。
- 定义 `chatGenerationTerminalNotificationsProvider`、`chatGenerationTerminalNotificationAdapterProvider` 与 notification session provider；adapter provider 在平台 composition 完成前固定绑定 no-op，不能抛“未绑定”异常。
- settings port/provider 在本 Task 创建但不接 UI，为 Task 4/8/9 提供可编译 seam。
- provider dispose 调深模块 dispose。
- 本 Task 只完成深模块与 provider 定义，不修改 `lib/app/app.dart`；根部 eager 装配统一留给 Task 9，避免两次临时接线。
- 单文件测试分别写 `logs/app-attention-green.log`、`logs/terminal-notifications-green.log`，工具超时 60000ms。

**停止条件**

- 抑制判断需要 presentation controller。
- adapter 必须理解 generation outcome。

### Task 3：coordinator 接入与前台服务端口瘦身

**文件**

- 修改 `lib/app/composition/chat_generation_notification_coordinator.dart`
- 修改 `lib/features/chat/application/generation/chat_generation_notification.dart`
- 修改 `lib/features/chat/application/ports/chat_generation_foreground_service.dart`
- 修改 `test/app/composition/chat_generation_notification_coordinator_test.dart`
- 修改 `test/features/chat/application/generation/chat_generation_notification_test.dart`
- 修改 `lib/app/platform/android_chat_generation_foreground_service.dart`
- 修改 `lib/app/platform/noop_chat_generation_foreground_service.dart`
- 修改 `test/app/platform/android_chat_generation_foreground_service_test.dart`
- 修改 `test/app/platform/noop_chat_generation_foreground_service_test.dart`
- 修改 `test/app/composition/chat_generation_foreground_service_bindings_test.dart`
- 修改 `test/integration/chat_generation_notification_integration_test.dart`

**RED 测试**

- `成功先清理 ongoing 再报告终态`
- `三次 cleanup channel timeout 与退避使 report 最晚在 cleanup 开始后 7 秒执行`
- `空回复失败和持久化失败都清理 ongoing`
- `取消只清理不报告`
- `中间重试不清理也不报告`
- `成功终态使用完整 outcome 计数而 timeout 使用 context 最后安全计数`
- `保护超时只报告且不调用 remove 或停止生成`
- `保护超时后真正终态仍报告且不重复清理`
- `terminal report 失败不毒化 coordinator`
- `尚未入队的旧 token terminal 和 timeout 被拒绝`
- `token1 terminal 入队后 token2 启动仍按 start1 cleanup1 report1 start2 顺序完成`
- `token1 ACK 迟到只修改 token1 context 不毒化 token2`
- `ongoing warm 与 pending 点击仍转发到现有 openConversation 回调`

**GREEN**

- 严格按第 6 节调整。
- coordinator provider 读取 Task 2 的 `chatGenerationTerminalNotificationsProvider` 与 notification session provider；不得在构造函数现场生成第二个 session。此时 adapter 安全默认为 no-op，直到 Task 9 一次性装配真实平台 adapter。
- 在同一 Task 原子收窄 ongoing projector；不得先提交“projector 拒绝 terminal、coordinator 仍调用 projector”的行为断层。
- 删除 `fail` 端口职责与旧 LOW terminal 测试，不保留 deprecated shim；保留并回归 ongoing 的 open/pending 职责。
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
- 新增 `lib/app/platform/android_system_notification_settings.dart`
- 修改 `lib/app/platform/android_chat_generation_foreground_service.dart`
- 新增 `test/app/platform/android_chat_generation_platform_bridge_test.dart`
- 新增 `test/app/platform/android_chat_generation_terminal_notification_adapter_test.dart`
- 新增 `test/app/platform/android_system_notification_settings_test.dart`
- 修改 `test/app/platform/android_chat_generation_foreground_service_test.dart`

**RED 测试**

- `三个 Android 窄适配器共享一个 channel handler`
- `前台适配器只编码 ongoing 方法`
- `终态适配器只发送安全通知字段`
- `foreground start update 原样传输 Dart 预编码 timeout activation payload`
- `stop open timeout terminal activation 回调分发到对应窄流`
- `pending activation 只取一次`
- `timeout action stream 无 listener 时 ACK 为 false`
- `channel timeout 和 PlatformException 均映射为 fail-open 结果`
- `Android 设置状态和打开动作只委托共享 bridge`
- `dispose 后 callback 不再分发且可重复 dispose`

**GREEN**

- channel owner 只存在于 bridge。
- 本 Task 暂时使用现有 `yuzu.shiki.oh_my_llm/chat_generation_foreground` channel 名，保证此提交与尚未修改的 Kotlin runtime 可协作；Task 5 在同一个原子改动中同时切换 Dart/Kotlin 到最终 `.../chat_generation_notifications`。不得双写或安装双 handler。
- command timeout 沿用现有 2 秒。
- 所有原生错误只映射为固定分类。
- 三个新增测试分别写 `logs/android-bridge-green.log`、`logs/android-terminal-adapter-green.log`、`logs/android-system-notification-settings-green.log`；修改后的 foreground adapter 测试写 `logs/android-foreground-adapter-green.log`。每个单文件工具超时 60000ms。

**停止条件**

- 同一 MethodChannel 被两个 Dart 对象安装 handler。
- 为兼容旧 runtime channel 新增双写/双 handler。

### Task 5：Android Kotlin HIGH 通知与设置

**文件**

- 按第 7.1 节重命名 protocol/channel/test
- 修改 `lib/app/platform/android_chat_generation_platform_bridge.dart`，与 Kotlin 同时切换最终 channel 名
- 新增 `ChatGenerationTerminalNotification.kt`
- 修改 `ChatGenerationForegroundService.kt`
- 修改 `MainActivity.kt`
- 修改 `chat_generation_strings.xml`

**RED 测试**

- `终态渠道配置为 HIGH 且不是 silent`
- `前台渠道仍为 LOW 且 silent`
- `终态通知 ID 不与 4101 冲突`
- `每个终态 PendingIntent request code 与 data URI 唯一`
- `终态通知构造同时使用 private 和固定 public version`
- `Kotlin 只校验 timeout activation payload 类型与长度不解析 JSON`
- `timeout callback 未受理时选择 HIGH fallback`
- `timeout fallback 固定使用通知 ID 与 request code 4200`
- `timeout fallback 原样复用 Dart session scoped payload`
- `ongoing content intent 仍打开对应会话`
- `首次设置状态查询会创建终态 channel 且不重建已有 channel`
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

### Task 6：Windows 插件激活机制 spike（阻塞）

本 Task 必须在修改产品 `windows/runner/` 或实现 Windows adapter 前完成；它验证 true external dependency，不产出可复用产品模块。

**隔离方式**

- 在仓库外的临时目录创建最小 Flutter Windows 工程，固定 `flutter_local_notifications_windows: 3.1.1`，使用与产品不同的临时 AUMID、CLSID、shortcut 名和 LocalServer32 key。
- spike 只显示固定测试 Toast、进程 PID、warm callback payload 和 launch-details payload，不读取/写入 oh-my-llm SQLite、SharedPreferences 或应用目录。
- shortcut 同时写 string AUMID 与 `VT_CLSID` activator；LocalServer32 默认值写带引号 exe，`ServerExecutable` 写不带引号 exe，不添加 `--notification-activated`；进程允许接收 COM 自动附加的 `-Embedding`。
- spike 提供固定的 `SPIKE_INIT_DELAY_MS=10000` 构建模式，只延迟 plugin initialize，不延迟进程 PID 记录；用于重现手工启动但 class object 尚未注册的窗口。
- 完成后只删除 spike 自己的 shortcut、`HKCU\Software\Classes\CLSID\{spike CLSID}`、`HKCU\Software\Classes\AppUserModelId\<spike AUMID>`、`HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications\Backup\<spike AUMID>` 和临时目录；删除前逐项回读确认仍是 spike 身份，任何产品身份或其他注册项都不得触碰。
- 把 OS 版本、插件版本、命令、PID、payload 与 PASS/FAIL 写入 `docs/testing/windows-chat-generation-notifications-smoke.md` 的“插件激活 spike”章节；不得只留口头结论。

正常 build 与延迟 build 的命令都必须记录；延迟 build 使用 `flutter build windows --dart-define=SPIKE_INIT_DELAY_MS=10000`，不得通过 `sleep` 阻塞 runner message loop 或 COM apartment。

**阻塞验收清单**

1. **LocalServer32**：注册值是正确引用的当前 spike exe；手工启动和 COM 启动都能进入同一 Flutter entrypoint，`-Embedding` 不导致参数解析失败。
2. **warm class object**：应用已运行时点击 Toast，插件 callback 收到一次原 payload，PID 保持不变，进程列表没有第二个 spike 实例。
3. **cold payload**：完全退出后点击 Toast，COM 启动一个进程；warm-style callback 收到原字符串，随后 `getNotificationAppLaunchDetails()` 也返回 `didNotificationLaunchApp == true` 与同一 `show(payload)` 原字符串，应用侧按 event key 去重后只记录一次。完全退出、重新发 Toast、点击、记录的循环至少执行 20 次，用于暴露插件 `_isReady` 窗口，不得只测一次。
4. **连续 cold/多实例**：完全退出后快速连续点击同一或两条 Toast，最终只有一个 spike 进程；没有两个 Flutter engine 并行启动。
5. **手工启动窗口**：使用 10 秒延迟模式手工启动，记录首个 PID；在 plugin initialize 前点击 Toast。最终仍只能有该一个 PID/Flutter engine，且原 payload 在 class object 注册后交付一次。这个 case 与“完全退出后连续 cold”不可互相替代。
6. **非 ASCII**：payload 含中文时 warm/cold 都与输入 UTF-8 字符串完全一致。
7. **native 生存性**：上述所有 case 进程退出码正常，没有 access violation、`std::terminate` 或未捕获 native exception；只捕获 Dart 异常不算通过。

**硬停止条件**

- warm 点击启动第二个实例。
- cold 点击不能启动，或 payload 与 `show(payload)` 不一致/丢失。
- 快速连续 cold 激活产生两个进程。
- 手工启动尚未注册 COM 时点击产生第二进程、payload 丢失或无法在默认 60 秒窗口内交付。
- 任一初始化/激活 case 终止 native 进程。
- 只有增加 MSIX、安装器、管理员权限或产品级单实例 IPC 才能通过。

任一项失败就保留 spike 证据并停止 Task 7–11；不得先写产品 runner 再把失败留给最终 smoke，也不得把双实例风险标成“接受”。全部 PASS 后才继续，并把实测命令行/注册格式回写第 8 节（若与源码审计不同则以实测触发重新设计，不直接改成猜测值）。

### Task 7：Windows runner 注册

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

- `注册 channel 只接受固定 AUMID 与无花括号 GUID`
- `带花括号 GUID 被 Dart decoder 判为 unavailable`
- `注册不可用和 malformed 返回 unavailable`
- `注册 channel 异常不阻断 Dart 初始化`
- 仓库当前没有 C++ runner test target；把 LocalServer32 默认值、`ServerExecutable`、GUID/CLSID 两种表示与固定身份构造集中在无 Win32 副作用的 helper，避免多处手拼。这里不虚构自动 C++ 断言：默认值引号、`ServerExecutable` 无引号、无自定义 activation 参数和 shortcut `VT_CLSID` 由代码审查、Task 6 真实 spike 与本 Task 的产品注册回读共同验证，Windows build 只承担 C++ 编译/链接门禁；本 PR 不为这一处 helper 新建测试框架。

**GREEN**

- 实现第 8.1–8.3 节。
- 精确写入 `flutter_local_notifications_windows: 3.1.1`，`flutter pub get` 更新 lock；回读 lock 确认仍为 3.1.1。
- 运行 Dart test，日志 `logs/windows-notification-registration-green.log`。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter build windows 2>&1 | Out-File -Encoding utf8 logs/build-windows-registration.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows-registration.log
```

构建命令级硬超时 600000ms。

**注册回读检查**

- 启动当前 build 一次，通过 registration channel 回读固定 AUMID 与无花括号 GUID，并确认 `available=true`。
- 用 Windows 属性存储 API 回读 `Oh My LLM.lnk` 的 target、AUMID 与 `VT_CLSID`，再回读 LocalServer32 默认值和 `ServerExecutable`；只记录是否匹配，不把绝对路径写入仓库文档。
- 覆盖同目录 exe 后重新启动，确认 runner 幂等修复仍成功。
- 本阶段 adapter 尚未实现，不能从产品代码发送 Toast，也不能把 Task 6 throwaway smoke 冒充为产品验收。warm/cold 产品 smoke 统一留到 Task 11。

**硬停止条件**

- 自动测试或 build 证明 shortcut/AUMID/CLSID/LocalServer32 链不成立。
- 已执行注册回读明确得到 shortcut、AUMID、CLSID 或 LocalServer32 `FAIL`。
- 可靠实现必须引入 MSIX、安装器或管理员权限。

发生硬停止时不继续 Task 8–11，不把“仅应用运行时 Toast”写成完成方案。

### Task 8：Windows adapter 与 AppWindow

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
- `插件收到无花括号 GUID 且真实 client 只惰性构造一次`
- `安全 payload 原样传给 Windows 插件`
- `WindowsNotificationDetails 不显式静音或配置自定义声音`
- `warm callback 与 cold launch details 转成统一 activation`
- `同一 cold payload 只取一次`
- `registration unavailable 时展示为 no-op`
- `插件异常不向上抛出原始异常`
- `窗口不可见时先 show 再 focus`
- `窗口最小化时先 restore 再 focus`
- `窗口恢复部分失败仍尝试 focus`
- `Windows 设置通过 launcher seam 只用 explorer 参数数组且异常返回 false`

**GREEN**

- 实现第 8.4–8.7 节。
- 测试只 fake `WindowsLocalNotificationsClient`、`WindowsWindowManagerClient` 和 `WindowsProcessLauncher`，不加载真实插件或启动 explorer。
- 单文件日志写 `logs/windows-terminal-adapter-green.log`，超时 60000ms。

**停止条件**

- 必须在 adapter 内 import chat presentation。
- 必须依赖 cancel/getActiveNotifications 才能完成一次性终态通知。

### Task 9：平台 composition 与根生命周期

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
- `Windows 平台选择只调用注入的 windowsFactory 并得到前台 no-op/terminal/settings 三个角色`
- `Windows 平台 fake factory 在 Ubuntu 不构造真实插件 DLL`
- `其他平台只绑定 no-op`
- `shared bridge 只 dispose 一次`
- `测试 harness 默认不触发真实 MethodChannel 或 Windows plugin`
- `bootstrap 的测试 factory 透传不改变生产默认绑定`
- `固定 session override 同时进入 coordinator ongoing payload 与 terminal receipt`
- `应用根部 eager 启动注意力 observer 和终态通知模块`
- `chatSessionsProvider 首次同步加载摘要时 cold activation 不误判为已删除`

**GREEN**

- 严格按第 9 节装配。
- `lib/app/app.dart` 的 observer/terminal eager watch 只在本 Task 一次性接入；Task 2 不做临时装配。
- 用 provider override 测平台选择，不修改全局 `debugDefaultTargetPlatformOverride`。
- Windows 平台选择测试必须通过第 9.1 节的 factory seam 构造 fake 记录；不得先实例化 production client 后再用 provider override 覆盖。
- 运行所有 app composition 定向测试，日志 `logs/notification-composition-green.log`，单文件超时 60000ms。

### Task 10：系统通知设置 UI

**文件**

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

### Task 11：文档、回归与范围审计

**smoke 文档**

- 修改 `docs/testing/android-chat-generation-foreground-service-smoke.md`：
  - 成功/空回复/最终失败/持久化失败/保护超时。
  - HIGH channel、默认声音、横幅。
  - 精确会话抑制、其他会话/其他页面展示。
  - ongoing 点击仍打开对应会话。
  - warm/cold 点击、已删除会话回退。
  - 权限拒绝、设置入口。
- 新增/更新 `docs/testing/windows-chat-generation-notifications-smoke.md`：
  - Task 6 插件激活 spike 的 OS/插件版本、命令、PID、payload 与清理结果。
  - 前台、失焦、最小化。
  - warm/cold 点击。
  - 快速连续 cold 激活时只有一个进程。
  - 默认声音在系统声音开启/关闭与专注助手下的实际表现；不声称应用强制响铃。
  - 文档记录通知 ID 碰撞会让后一条覆盖前一条的已知限制；不要求人工构造碰撞或在生产中枚举碰撞。
  - 同目录覆盖更新。
  - 移动目录后首次手动启动再点击。
  - 系统设置入口。
- 每项只写 `PASS`、`FAIL` 或 `PENDING`；无实机证据保持 `PENDING`，但下面列出的最小原生 gate 不允许为 `PENDING`。

**Ready 前最小原生 gate（人工、阻塞）**

- Android：至少一台受支持 emulator/设备执行并 `PASS`：生成成功后出现 `chat_generation_result` HIGH 通知；点击打开精确会话；现有 ongoing 点击仍打开精确会话；应用前台查看同一会话时抑制。系统是否实际响铃受设备设置控制，可记录“channel 配置正确但设备静音”，不能把设备静音判成实现 FAIL。
- Windows：用最终产品 build 执行并 `PASS`：warm 点击、完全退出后的 cold 点击、手工启动到 plugin ready 之间点击，三者 payload/导航正确且各只有一个产品进程；最小化恢复后导航；删除会话回退根页。必须记录 PID、进程数、AUMID/GUID 表示与启动到 class registration 的耗时。
- 任一最小 gate 为 `FAIL`：停止 Ready 并修复；无法执行：PR 保持 draft。只有扩展矩阵（其他 Windows 版本、专注助手组合、多个声音设备、多安装位置）允许 `PENDING`。

**定向测试**

- 逐个运行所有修改到的 `*_test.dart`。
- 单文件工具超时 60000ms。
- 超时先运行 `.\scripts\kill-stale-test-processes.ps1`，再诊断；不得直接重跑。

**格式**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR master...HEAD -- '*.dart'
if ($DartFiles) {
  dart format $DartFiles
  dart format --output=none --set-exit-if-changed $DartFiles
} else {
  Write-Host '没有需要格式化的 Dart 文件'
}
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

工具超时按仓库 `AGENTS.md` 固定为 240000ms；超时先清理 stale processes。不得因一次本机慢跑擅自提高硬上界；若基线本身稳定超过 4 分钟，先保留基线日志并单独修订仓库级规则。

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
rg -n '\bcontent\b|reasoningContent|errorMessage|stackTrace' lib/app/notifications lib/app/platform
rg -n "MSIX|linux|macos|通知开关" lib android windows
rg -n "flutter_local_notifications_windows:" pubspec.yaml pubspec.lock
```

逐项人工确认：

- 没有 PC 返回、历史查询或聊天存储改动。
- 没有 Linux/macOS/MSIX/安装器文件。
- 没有应用内通知开关或设置传输参与者。
- 平台 payload 无正文、推理、原始错误。
- notification session 只生成一次、只含 32 lowercase hex、未持久化或写日志。
- Android ongoing 与 terminal channel 分离。
- Android ongoing 点击直达会话的旧契约仍有生产调用与回归测试；只有旧 LOW terminal 点击路径被替换。
- Kotlin/runner 不判定 generation outcome。
- Windows 只写 HKCU，未添加清理器。
- 所有新测试标题和注释为简体中文。

当前 CI 只有 Ubuntu gate，没有 Linux/macOS 桌面 build 矩阵。`flutter_local_notifications_windows` 在支持 FFI 的 Dart VM 会导出 FFI implementation，因此“只 import 不调用”不是隔离保证；第 9.1 节 factory seam 必须确保 Ubuntu 测试在对象构造前选择 fake/no-op。`flutter analyze`、全量 `flutter test` 与 CI 回读负责证明现有非 Windows gate 可编译且不会尝试打开 Windows DLL。不得把未存在的 macOS/Linux desktop build 写成已通过。

## 12. 替换而非叠加

实施时必须删除旧职责，避免新旧两套通知并存：

| 删除/替换对象 | 替代 |
| --- | --- |
| projector terminal behavior / retainError | terminal receipt projector |
| 仅由 generationId 组成的跨进程可复用 event key | process-scoped notification session + generationId + terminal kind |
| coordinator 全局 token 字段取消旧 queued operation | captured `_NotificationGenerationContext` + FIFO tail ownership |
| foreground port `fail()` | remove + terminal notifications |
| foreground port 中旧 LOW terminal 的 open action | unified terminal activation；ongoing open/pending 原样保留 |
| Kotlin LOW 普通错误通知 | HIGH terminal notification |
| `TimedOutNotificationGuard` | timeout receipt + Kotlin fixed fallback |
| Dart foreground channel 独占 handler | shared Android platform bridge |
| Kotlin 自行重建 timeout JSON/event key | Dart 预编码 opaque timeout activation payload |
| `bindChatGenerationForegroundService` | `bindChatGenerationNotifications` |
| 旧 bindings 文件名/测试名 | notification platform bindings |
| Windows composition 构造真实插件后再 override | platform factory seam 在对象构造前选择 production 或 fake |

完成范围审计时，以上旧 symbol 应由 `rg` 得到零生产调用；仅迁移说明文档可出现。

`ChatGenerationOpenConversationRequested` 与 `takePendingOpenConversation()` 不属于待删除旧 symbol：二者继续承载 Android ongoing 点击直达会话的既有产品契约。范围审计只应证明新 HIGH terminal/fallback 不再走这条旧终态路径。

## 13. 提交顺序

本计划文档已单独提交；产品实施按以下可独立构建、可独立审查，并按依赖逆序回滚的顺序提交。Task 3–8 是尚未完成平台 composition 的中间态，不得把其中任一 commit 单独发布或描述为跨平台终态通知已可用：

1. `refactor(chat): 分离生成终态通知收据`
2. `refactor(app): 增加生成通知注意力与激活模块`
3. `refactor(app): 原子迁移生成通知协调与前台端口`
4. `refactor(android): 收敛生成通知平台桥接`
5. `feat(android): 增加生成终态高优先级通知`
6. `test(windows): 验证未打包 Toast 激活链路`（只提交 Task 6 文档证据，不提交 throwaway 工程）
7. `feat(windows): 注册未打包 Toast 身份`
8. `feat(windows): 接入生成终态通知与窗口恢复`
9. `refactor(app): 装配跨平台生成通知生命周期`
10. `feat(settings): 增加系统通知设置入口`
11. `docs(testing): 补充跨平台生成通知验证手册`

Task 1 不收窄 projector；Task 3 必须在同一个提交中同时迁移 coordinator、收窄 projector、删除 foreground `fail()` 并更新全部实现/fake。Task 4 暂用旧 Android channel 名，Task 5 在同一提交内同时切换 Dart/Kotlin 最终名称。任何中间 commit 都不得出现编译通过但 ongoing cleanup/点击行为失效的窗口。

每次提交前：

- 对本次所有 Dart 文件执行 `dart format`。
- 暂存后执行 `dart format --output=none --set-exit-if-changed <暂存 Dart 文件>`。
- 检查 `git diff --cached --check`。
- 提交信息使用简体中文。
- post-commit hook 自动 bump 后重新读取 `HEAD`、`pubspec.yaml` 和 changed paths。

Windows 注册若自动验证失败不得作为“功能完成”提交。Task 6 spike 和第 14 节最小原生 gate 未通过时，允许保留已验证的中间提交，但 PR 必须保持 draft；不能用 `PENDING` 标记 Ready。

## 14. PR 完成定义

只有以下全部成立，才能 Ready for review：

- 终态收据无正文、标题、原始异常或动态 Map。
- 进程级 notification session 为一次性 128-bit hex，event key 跨进程不复用，未持久化或写日志。
- 真正终态只从现有 terminal snapshot 产生。
- 成功计数来自完整 `ChatGenerationSuccess` outcome，不受 300ms UI flush 节流影响。
- 精确会话抑制、其他会话/页面/失焦展示有自动测试。
- report 与 activation 分别区分 in-flight/completed 去重，失败可由后续输入重试且集合有界。
- token1 terminal 已入队后启动 token2 的 FIFO/ACK 竞态有自动回归测试，旧 cleanup/report 不会被新 token 取消。
- timeout 后真正终态仍能报告。
- 所有真正终态和取消都清理 ongoing；失败不再残留 LOW 普通通知。
- Android terminal 使用新 HIGH channel、默认声音/振动；ongoing LOW 静音及点击直达对应会话保持不变。
- Android 权限保持官方一次性请求行为。
- Task 6 throwaway spike 已以真实 Windows Shell/COM 证明至少 20 轮 cold、warm、连续 cold、手工启动未 ready 窗口、非 ASCII payload 与单进程/native 生存性；失败时不得进入产品实现。
- Windows 未打包注册通过 Dart 测试和 Windows build，不要求 MSIX/管理员权限。
- Windows warm/cold payload、窗口恢复、删除会话回退有自动测试。
- Windows GUID/CLSID 两种表示、shortcut `VT_CLSID`、LocalServer32 quoted default 与 unquoted `ServerExecutable` 均有 spike/build/回读证据。
- `flutter_local_notifications_windows` 精确锁定 3.1.1，Ubuntu 平台选择测试不构造真实 DLL。
- Windows 不显式配置声音，smoke 如实记录系统设置/专注助手下的结果。
- 设置页有 loading/状态/打开系统设置，没有开关。
- Dart/MethodChannel/runner 可观察平台故障不改变 generation；Windows plugin 未捕获 native exception 的残余边界在风险中如实披露，已测路径没有进程终止。
- 定向测试、analyze、import boundary、全量测试、Windows build 有日志证据。
- Android/Windows smoke 文档存在，第 11 节最小原生 gate 均为 `PASS`；只有扩展矩阵未执行项可为 `PENDING`。
- `git diff --check` 通过，base...head 无无关范围。

## 15. 全局停止条件

出现任一条件立即停止并报告，不自行扩大范围：

- Windows 可靠冷启动必须依赖 MSIX、安装器或管理员权限。
- Windows warm activation、快速连续 cold activation或手工启动尚未注册 COM 时点击产生两个 Flutter 进程。
- 已执行 Windows cold activation smoke 明确失败。
- 插件/runner 无法交付 cold payload。
- 插件初始化/激活出现 access violation、`std::terminate` 或其他 native 进程终止。
- Windows 支持必须在 Ubuntu test 构造真实 `flutter_local_notifications_windows.dll` 才能验证 composition。
- 无法在一个原子 Task/commit 中保持 Android channel 两端一致或保持既有 ongoing cleanup/点击行为。
- 无法给 event key 增加进程 session 而必须持久化通知碰撞表或修改聊天存储。
- Android 横幅只能通过升级既有 LOW channel 实现。
- 必须把正文、prompt 或原始异常传给平台层。
- 必须让 Kotlin/runner 参与 generation outcome 判定。
- 必须修改 `ChatGenerationRun` 的终态所有权。
- 必须引入 Linux/macOS、常驻进程、清理器或应用内通知开关。
- 自动测试/build 暴露需要大范围重构的问题；保留证据，另开计划。

## 16. 参考资料

- Android 通知渠道：<https://developer.android.com/develop/ui/compose/notifications/channels>
- Android 13 通知权限：<https://developer.android.com/develop/ui/compose/notifications/notification-permission>
- Android 锁屏 public version：<https://developer.android.com/develop/ui/compose/notifications/create-notification#lockscreenNotification>
- Flutter post-frame 调度：<https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html>
- Flutter `ensureVisualUpdate`：<https://api.flutter.dev/flutter/scheduler/SchedulerBinding/ensureVisualUpdate.html>
- Microsoft 未打包桌面 Toast：<https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl>
- Microsoft LocalServer32 注册与 `-Embedding`：<https://learn.microsoft.com/en-us/windows/win32/com/localserver32>
- Microsoft Toast activation：<https://learn.microsoft.com/en-us/previous-versions/windows/desktop/win32_tile_badge_notif/respond-to-toast-activations>
- `flutter_local_notifications_windows`：<https://pub.dev/packages/flutter_local_notifications_windows>

实施前只复核当前 lock、插件 3.1.1 API 与官方平台文档；不得借机升级无关依赖。
