# 跨平台生成终态通知实施计划

> 状态：Tasks 1–5 已实施并通过任务级评审；原 Windows 插件 spike 已真实 FAIL，Windows Tasks 6–9 已改为 runner-owned 原生方案，等待新 spike。
>
> 目标分支：`feat/cross-platform-generation-notifications`
>
> 基线：`master` @ `4776ee8483586e84add776bf41d4250c51e939fb`
>
> PR 边界：本计划完整对应一个 PR，不与 PC 返回适配或历史页性能优化互相依赖。

## 1. 结果定义

本 PR 为聊天生成增加 Android 与 Windows 终态系统通知，并把“何时发、能显示什么、何时抑制、点击后去哪里”收敛到一个 Dart 深模块。Android Kotlin 与 Windows runner 只执行平台命令，不参与生成结果判定。

完成后必须同时满足：

- Android 正在生成时继续显示现有 LOW、静音、ongoing 的前台服务通知。
- Android ongoing 通知继续保留“点击后打开对应会话”的现有行为；本 PR 只替换终态通知的展示与激活路径。
- Android 在成功、空回复、最终失败、终态持久化失败和前台保护超时时，通过新的 HIGH 渠道播放系统默认声音并请求横幅展示。
- Windows 通过系统 Toast 显示相同终态；不引入 MSIX、安装器或管理员权限要求。
- Windows Toast 不配置自定义声音，使用系统默认通知声音并服从用户通知设置与专注助手。
- Windows 应用热启动和完全退出两种情况下，点击 Toast 都能恢复并聚焦窗口，然后打开对应会话。
- Windows 每个用户会话始终只有一个 Flutter engine/聊天存储 owner；第二次手工启动只恢复并聚焦既有窗口，极早期 COM 竞态允许出现不启动 Flutter、不打开存储的短命 native relay 进程。
- 当前会话已删除时只回退聊天根页，不弹错误、不恢复数据。
- Android 与 Windows 共享 Dart 收据、固定安全文案、资格判断、注意力抑制、通知 ID、payload、去重和导航规则。
- 用户正在前台且正查看同一会话时不发送系统通知；其余页面、其他会话、后台或 Windows 失焦时发送。
- Dart、MethodChannel、runner 注册、COM/IPC、Toast 展示、设置查询或激活错误全部 fail-open，不改变 generation phase/outcome，不产生新的聊天错误。所有 C++ entrypoint/callback 必须在 native 边界捕获异常并返回固定失败分类；Task 6B/7 一旦观察到进程终止立即停止，不得把 native 崩溃写成已验证的 fail-open。
- 设置页只显示系统通知状态与“打开系统通知设置”按钮，不增加应用内通知开关。

## 2. 范围边界

### 2.1 本 PR 包含

- 纯 Dart 终态收据和安全失败分类。
- 现有 generation notification coordinator 的终态接入与 ongoing 清理修正。
- app-owned 注意力快照、窗口抽象、终态通知深模块和导航激活。
- Android 共享 MethodChannel bridge、HIGH 终态渠道、点击激活和设置入口。
- Windows runner-owned 未打包 Toast 注册、原生 Toast 展示、COM activator、实例协调、Dart adapter、窗口恢复和设置入口。
- 在编写产品 runner 模块前，用独立身份的 throwaway Windows 工程验证 runner-owned COM/Toast、唯一 Flutter owner、早期 activation 队列和 native relay。
- 定向单元/widget 测试、现有测试替换、Android/Windows smoke 文档。
- 不增加 `flutter_local_notifications_windows` 或 Windows App SDK 依赖；只使用当前 Windows SDK、C++/WinRT/WRL 与 Flutter Windows embedder 已提供的能力。
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
- 跨平台或可复用的通用单实例框架；本 PR 只实现 Windows 当前用户会话内、由 Toast COM 激活需求驱动的 runner 级唯一 Flutter owner。Linux/macOS、跨用户会话和多安装仲裁仍不在范围内。
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
- Windows warm/cold activation 都由 runner-owned `INotificationActivationCallback` 接收；Flutter messenger 未 attach 时进入 native 有界队列，attach 后由 callback 或一次性 pending method 交付。
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
- Windows runner 生成的 Toast XML 不包含 `<audio>`、`scenario` 或自定义音频 URI；声音与横幅交给系统通知设置和专注助手决定，smoke 必须记录实际结果。
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
    ├─ Windows adapter → MethodChannel → runner-owned WindowsNotificationHost
    └─ no-op adapter
```

边界约束：

- `ChatGenerationRun` 与 `ChatGenerationCoordinator` 不修改；现有 `_terminal()` 在 durable save 后投影终态的顺序是权威来源。
- `ChatGenerationNotificationCoordinator` 是唯一收据插入点，因为它已经 eager watch `(generation, streamingReply)` 并串行处理 native action。它接收一次进程级 `notificationSessionId`，同时写入 ongoing payload 和终态收据，Kotlin 只把该 ID 当作不透明安全字段。
- coordinator 的 async tail 是一个深模块：调用方只提交状态，不能理解或补偿 native 排队。旧状态是否可入队在入口判定；一旦某 token 的 start/update/terminal operation 已入队，就必须按 FIFO 完成，后续 generation 不得用 `_currentToken` 取消它。operation 完成后只有与当前 token 匹配时才能回写当前 token 的可用性字段。
- `ChatGenerationNotificationProjector` 只投影 ongoing 前台服务 payload，不再持有终态错误摘要或 `retainError`。
- 前台服务端口与终态通知端口分离。
- Android 共享 bridge 只解决一个 MethodChannel 只能有一个 handler 的技术约束，不合并业务端口。
- Windows runner 深模块只拥有 Windows 身份、Toast、COM activation、实例协调和原始安全 payload 队列；它不解析 payload JSON，不处理会话、generation、注意力抑制或路由。
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
5. `report()` 先 `await _startFuture`；若调用时尚未显式 start，则内部幂等启动。初始化不可用时固定诊断后返回，不能在平台 adapter ready 前调用 show。
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

### 8.0 已证伪方案与替换决策

`flutter_local_notifications_windows` 3.1.1 方案已经完成真实 spike，并在关键窗口明确 FAIL：手工实例已经运行、但 Dart 插件尚未调用 `CoRegisterClassObject` 时点击 Toast，RPCSS 按 LocalServer32 启动了第二个完整 Flutter 进程；payload 被第二进程接收。该失败不是 shortcut、CLSID 或 payload 错误，而是 COM class object 的所有权建立得太晚。

因此后续 Windows 实现固定采用以下替换决策：

- 不向 `pubspec.yaml` 添加 `flutter_local_notifications_windows` 或 `flutter_local_notifications`。
- 不 fork 插件、不给插件增加“只展示、不注册 activator”的私有开关。
- Windows runner 在 `DartProject`/Flutter engine/SharedPreferences/SQLite 之前永久拥有 COM activator；runner 同时用窄 C++/WinRT 实现一次性 Toast 展示。
- runner 以 named mutex + named pipe 维护当前用户会话内唯一 Flutter/存储 owner；进程枚举、进程名、窗口标题和固定 sleep 都不是身份判断。
- 极早期竞态中，RPCSS 仍可能创建第二个 OS 进程；该进程只能进入 native relay mode，不得构造 `DartProject`、Flutter engine、窗口、SharedPreferences、SQLite 或 network logger。验收关注唯一 Flutter/存储 owner，不再要求 PID 峰值永远为 1。
- 原插件 FAIL 现场永久保留在 smoke 文档的“被否决方案”章节；新 spike 另建结果表，不得覆盖或改写旧证据。

该决策消除插件 `_isReady` 窗口、FFI 未捕获异常、重复 COM owner、缺少 `CoRevokeClassObject` 和 Ubuntu DLL 加载问题。真实 Windows Shell/COM 仍属于外部环境；Task 6B 必须先验证 runner-owned 方案，再允许写产品模块。

### 8.1 固定身份与进程模式

- appName：`Oh My LLM`
- AUMID：`YuzuShiki.OhMyLlm`
- COM CLSID：`{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}`
- 开始菜单快捷方式：`FOLDERID_Programs\Oh My LLM.lnk`
- Flutter channel：`yuzu.shiki.oh_my_llm/windows_notifications`
- named mutex：`Local\YuzuShiki.OhMyLlm.NotificationHost.7E4B2C915D4A4A8E9F1B2C6D3A80E751`
- activator lease mutex：`Local\YuzuShiki.OhMyLlm.NotificationActivatorLease.7E4B2C915D4A4A8E9F1B2C6D3A80E751`
- ready event：`Local\YuzuShiki.OhMyLlm.NotificationHostReady.7E4B2C915D4A4A8E9F1B2C6D3A80E751`
- named pipe：`\\.\pipe\YuzuShiki.OhMyLlm.NotificationHost.v1`

这些值提交后不得随版本号、构建号或目录变化。runner 只允许三种进程模式：

1. `primary`：当前用户会话内唯一可创建 Flutter engine、窗口和存储连接的进程；拥有长期 COM class object、pipe server 与 Toast notifier。
2. `activationRelay`：命令行含 COM 实测传入的 `-Embedding`，且 named mutex 已存在；只运行原生 COM/message loop，把 payload 交给 primary 后退出。
3. `manualSecondary`：不是 `-Embedding` 且 mutex 已存在；只向 primary 发 `activateWindow`，等待 ACK 后退出。

`-Embedding` 只用于 runner 选择进程模式，不携带 payload，也不进入 Dart。参数比较大小写不敏感，只接受独立的 `-Embedding` 或 `/Embedding` token，不做 substring 匹配。

固定身份意味着开发版、发布版和同一用户会话内的多个目录副本共享 mutex、pipe、AUMID 与 CLSID：先成为 primary 的副本保持所有权；后启动副本不得重写 shortcut/LocalServer32，只恢复既有 primary。primary 全部退出后，下一个成功成为 primary 的副本才幂等修复注册。这是明确的 Windows 单实例产品行为，不扩展到其他平台或其他用户会话。

### 8.2 runner 深模块与启动顺序

新增一个外部 interface 很小、内部实现可拆分的深模块：

- `windows/runner/windows_notification_host.h`
- `windows/runner/windows_notification_host.cpp`
- `windows/runner/windows_notification_registration.h/.cpp`（内部 identity helper）
- `windows/runner/windows_notification_activator.h/.cpp`（内部 COM helper）
- `windows/runner/windows_notification_instance_coordinator.h/.cpp`（内部 mutex/event/pipe helper）
- `windows/runner/windows_notification_protocol.h/.cpp`（内部 framing/validation/XML helper，可由原生测试直接链接）
- `windows/runner/windows_notification_toast.h/.cpp`（内部 C++/WinRT helper）

只有 `windows_notification_host.h` 可以被 `main.cpp` / `flutter_window.*` include；其余 helper 是模块内部 seam，不向 Dart 或 app composition 暴露。

COM activator 不注册在尚未进入 Flutter message loop 的 `wWinMain` STA 上。host 内部启动一条专用 notification STA thread：该线程独立 `CoInitializeEx(COINIT_APARTMENTTHREADED)`、注册/revoke class object并持续 pump native messages；primary 的 pipe server 使用另一条有界 native IO thread（或 overlapped IO），二者都不依赖 Flutter engine/Dart isolate。callback/pipe 只把 payload 写入加锁 native queue并通过 runner 自定义 window message 通知 UI thread；窗口/messenger 尚未 attach 时只排队。Toast show 的 WinRT 调用由已经运行 message loop 的 runner UI STA执行，避免跨 apartment 持有 notifier。

概念 interface：

```cpp
class WindowsNotificationHost {
 public:
  static std::unique_ptr<WindowsNotificationHost> Start(
      const std::vector<std::wstring>& command_line);

  bool ShouldStartFlutter() const;
  int RunSecondaryMode();
  void AttachMessenger(flutter::BinaryMessenger* messenger);
  void AttachWindowActivation(std::function<void()> activate_window);
  void Shutdown();
};
```

`wWinMain` 固定顺序：

1. runner UI thread 执行既有 `CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)`；`S_OK/S_FALSE` 视为成功，其余记录固定 stage。
2. `WindowsNotificationHost::Start(commandLine)` 完成原子选主；primary 在返回前创建 native queue/pipe IO thread、幂等身份注册并启动 notification STA thread。只有 STA thread 成功 `CoRegisterClassObject` 且开始 pump 后，host 才标记 activator ready。
3. `ShouldStartFlutter()==false` 时直接 `RunSecondaryMode()`，此分支源码和测试必须证明不会执行 `flutter::DartProject project(L"data")`。
4. primary 才创建 `DartProject`、`FlutterWindow` 和 Flutter engine。
5. engine 成功后 `AttachMessenger()`；窗口创建后 `AttachWindowActivation()`，并允许 native workers 用自定义 window message 唤醒 UI thread排空队列/执行 focus。
6. message loop 结束后先 `Shutdown()`：停止接收新工作，令 notification STA thread 在自身 apartment `CoRevokeClassObject` 后退出，停止/join pipe thread，再释放 WinRT 对象/handles；最后 UI thread `CoUninitialize()`。

host start/secondary/callback/shutdown 的 native 最外层全部 `try/catch`，只返回固定 enum/stage，不允许 C++ exception 穿过 `wWinMain`、COM ABI 或 Flutter MethodChannel callback。primary 的通知 host 初始化失败时禁用 Windows 通知但继续启动应用；已经确认 primary 存在的 secondary 不得因 IPC 失败擅自创建第二个 Flutter engine。

仓库 C++ 注释按 `AGENTS.md` 使用简体中文；Windows runner 与 native test target 显式启用 MSVC `/utf-8`，避免 CP936 环境的 C4819。

为在产品 runner 上复验两个早期窗口，CMake 允许仅 Debug 的 `OMLL_NOTIFICATION_HOST_TESTING=ON`，并在该开关下接受 `OMLL_NOTIFICATION_PRE_COM_DELAY_MS` / `OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS`；默认均为 0。Release 或 testing=OFF 时任一非零 delay 必须在 configure 阶段失败，源码不读取环境变量/命令行/Dart define。pre-COM delay 只能延迟 primary 竞争 activator lease，不能停 pipe IO；post-COM delay 只能延迟 `DartProject`，不能停 notification STA message pump。该 test hook 不进入用户设置或运行时协议。

### 8.3 唯一 Flutter owner 与 relay 协议

- 用 `CreateMutexW(nullptr, FALSE, fixedName)` + 紧随其后的 `GetLastError()==ERROR_ALREADY_EXISTS` 原子判断是否已有 primary；`Local\` namespace 已把 kernel objects 限定到当前 logon session，禁止 `GetProcessesByName`、PID 枚举或 exe 名/路径猜测。
- primary 持有 instance mutex handle 到进程退出；创建 native queue、pipe IO thread 与 ready event 后，才执行可能较慢的 shortcut/COM/Flutter 初始化。pipe ACK 与入队不能依赖 Flutter UI thread 正在 pump。
- ready event 是 manual-reset event，只表达“当前 instance-mutex owner 的长期 class object 已注册并开始 pump”。新 primary 选主成功后先 `ResetEvent`，长期 owner ready 后 `SetEvent`，shutdown 在 revoke 前再次 reset；relay 不得设置它。不能把上一任 primary 遗留的 signaled handle 当作当前 ready。
- 长期 COM owner 与短命 relay 通过 activator lease mutex 串行。生产 primary 创建 pipe 后立即竞争 lease，成功后注册长期 class object 并持有 lease 到 shutdown；relay 只有在 primary 尚未标记 ready 且成功取得 lease 时才可注册短命 class object。任何时刻不得有两个本项目 class object owner。
- pipe 使用 `PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS`；一条 request 必须是一个完整 pipe message，最大 1036 bytes。header 固定 12 bytes：ASCII magic `OMLN`（4 bytes）、little-endian `uint16 version=1`、`uint16 kind`（1=`notificationActivation`，2=`activateWindow`）、`uint32 payloadByteLength`；随后恰好是 payload bytes。activation payload 必须是合法 UTF-8 且最长 1024 bytes；focus length 必须为 0。未知 version/kind、超长、截断、focus 带 payload、header length 与 message length 不一致或 `ERROR_MORE_DATA` 一律拒绝。
- 每个 request 都收到固定 8-byte ACK：ASCII magic `OMLA`、little-endian `uint16 version=1`、`uint16 status`（0=`accepted`、1=`invalidFrame`、2=`queueFull`、3=`shuttingDown`）。只有 status 0 允许 secondary 视为交付；一个 pipe connection 串行一条 request/ACK 后关闭，rapid activation 使用各自连接，不需要跨连接 request ID。
- pipe 使用显式 DACL，只允许当前 logon user SID 与 LocalSystem 完全访问，并启用 `PIPE_REJECT_REMOTE_CLIENTS`；SID/DACL 构造失败时 IPC/通知 host unavailable，但已持有的 instance mutex 仍维持唯一 Flutter owner，不能退回宽松 pipe ACL。同一 Windows 用户属于既有本地信任域，native framing/长度与 Dart decoder 仍必须执行两层严格白名单。
- primary 收到 `notificationActivation` 后先写入上限 32、FIFO 的 native pending queue，再返回 ACK；队列满时拒绝新消息并记录固定 `native_activation_queue_full`，不逐出正在等待的旧 payload。
- primary 收到 `activateWindow` 时只合并成一个 pending focus flag；窗口已 attach 时调用 runner 提供的恢复/聚焦 callback，窗口未 attach 时在首次 attach 后执行。
- `activationRelay` 不写注册表、不创建 shortcut、不启动 Flutter。若 primary 已标记 activator ready，则 relay 只等待 RPCSS 将请求交给长期 owner 后有界退出；若尚未 ready，则 relay 竞争 activator lease，成功后注册同一 CLSID 的短命 native class object并运行 message loop，`Activate()` 收到 payload 后为每次 callback 建立独立 pipe request并等待 ACK。relay 不在首个 ACK 后立即退出：每次 callback 重置固定 `relayDrainGrace`，只有没有在途 callback/COM object且 grace 到期后才 revoke、释放 lease并退出；另有固定 `relayMaxLifetime` 防止永驻。两个值由 Task 6B 实测锁定。
- primary 若发现 activator lease 暂由 relay 持有，只等待该 lease 的固定上界；取得后再注册长期 class object并设置 ready event。等待期间 pipe server 必须已经可接收 activation，因而 relay 不依赖 Flutter/Dart。spike 必须证明 `CoRegisterClassObject` 的实际 handoff 行为；不得把“RPCSS 必然重路由到任意进程”的猜测写成实现前提。
- 若 primary 在 relay 期间退出，relay 关闭旧 instance mutex handle 后重新原子选主；只有确认为新 primary 才允许携带已捕获 payload 晋升并继续 Flutter 启动。primary 仍存在但 pipe/ACK 超时时，relay 有界退出，不能以“保底”为名启动第二个 Flutter。
- `manualSecondary` 等待 ready event/pipe 使用固定有界超时；失败后重新选主，只有 primary 已退出才能晋升，否则退出并保持一个 Flutter owner。
- relay OS 进程是预期协调机制，但任何 relay 执行 `DartProject`、出现 Flutter window、打开产品 SQLite/SharedPreferences，或退出后残留，都视为硬 FAIL。

具体 wait/pipe/ACK 上界先在 Task 6B spike 测量后锁定；不得直接沿用 Dart MethodChannel 2 秒 timeout，也不得无限等待。产品值必须写入 named constants 并由 native test 覆盖。

### 8.4 身份注册

只有 primary 调用 `EnsureWindowsNotificationRegistration()`：

1. `GetModuleFileNameW` 取得当前 exe 绝对路径。
2. `SHGetKnownFolderPath(FOLDERID_Programs)` 取得当前用户 Programs。
3. 创建或重写 `Oh My LLM.lnk`：target 指向 exe，working directory 指向 exe 目录，`PKEY_AppUserModel_ID` 写固定 AUMID。
4. 用 `CLSIDFromString` 解析带花括号 CLSID；`PKEY_AppUserModel_ToastActivatorCLSID` 必须写 `PROPVARIANT{vt=VT_CLSID, puuid=<parsed CLSID>}`，不得写 REG_SZ。
5. 写 `HKCU\Software\Classes\CLSID\{CLSID}\LocalServer32`：默认值为带双引号、无参数的 exe 绝对路径；`ServerExecutable` REG_SZ 为不带引号、无参数的同一路径。接受 COM 自动附加 `-Embedding`，注册值不自创参数。
6. 幂等写 `HKCU\Software\Classes\AppUserModelId\<AUMID>`：`DisplayName` 为 `REG_EXPAND_SZ` 的 `Oh My LLM`，`CustomActivator` 为 `REG_SZ` 的带花括号固定 CLSID；不得写动态图标路径或产品数据。
7. 任一步失败只返回固定 `failureStage` 并把 host 标为 unavailable；不向 Dart 返回绝对路径、HRESULT 文本或系统消息。

只写 HKCU，不请求管理员权限，不删除旧注册。原目录覆盖更新不受影响；移动目录后首次成功成为 primary 的手工启动会修复路径。relay/manual secondary 绝不改变 first-running primary 的注册所有权。

### 8.5 COM activator 与早期队列

- runner 原生实现 `INotificationActivationCallback`、`IClassFactory`，notification STA thread 用 `CoRegisterClassObject(CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE)` 注册，并保存 cookie、持续 pump native message loop。
- primary 必须在 `DartProject` 之前启动并等待该 STA thread ready；relay 在确认自身模式并取得 activator lease 后启动同型短命 STA thread。`CoRegisterClassObject` 成功且 message pump 已开始后才对外标记 activator ready。
- `Activate(appUserModelId, invokedArgs, data, count)` 为 `noexcept`，内部 catch-all；只验证 AUMID、nullable/长度和 UTF-16→UTF-8 转换，不解析 JSON、不判断 terminal kind、不读取 user input map。
- 合法 `invokedArgs` 原样进入 native queue/pipe；最终仍由 Dart `ChatGenerationNotificationPayloadCodec` 判定安全性。非法输入记录固定类别并返回稳定 HRESULT，不记录 payload。
- callback 不等待 Flutter、路由或窗口恢复；primary 只入队并向 runner UI window post 自定义 message（尚未 attach 时仅入队），relay 只完成有界 IPC。
- activator/class factory 持有引用计数 shared host state，不保存裸 `FlutterWindow*`/messenger 指针。每次 `Activate()` 取得 in-flight callback lease；shutdown 先标记 stopping、reset ready、revoke class object，再等待所有有界 callback lease 释放，最后销毁 queue/IPC state，防止 callback 与窗口/host 析构 use-after-free。
- `Shutdown()` 必须让注册 cookie 的同一 STA thread 调 `CoRevokeClassObject` 后退出 message pump；多次 shutdown 幂等，不能在其他 apartment 粗暴 revoke，也不能依赖进程退出替代 revoke。
- native pending queue 上限 32，每项最多 1024 UTF-8 bytes；`takePendingNotificationActivations` 原子取走全部并清空，避免 cold/rapid-cold 只保留最后一次。

### 8.6 Toast 展示与唯一 Flutter channel

runner 用当前 Windows SDK 的 C++/WinRT 创建 `ToastNotificationManager::CreateToastNotifier(AUMID)`，不引入第三方 DLL。产品只实现本 PR 所需的一次性 Toast：

- XML 固定为 `toast/visual/binding template="ToastGeneric"/text+text`，root `launch` 为 Dart payload。
- C++ 使用 DOM 或集中 XML escaping helper，禁止把 title/body/payload 直接拼进未转义 XML。
- `ToastNotification.Tag` 使用十进制 notification ID；不实现 schedule、update、cancel、history 或 actions。
- XML 不包含 `<audio>`、`scenario`、图片或自定义 URI，使用 Windows 默认声音语义。
- native 再校验：参数 map 只能含 `id/title/body/payload`；ID 为 `10000..2147483646`，title/body 非空且分别不超过 128/512 UTF-8 bytes，payload 不超过 1024 bytes；不合规则返回 false。

唯一 channel `yuzu.shiki.oh_my_llm/windows_notifications`：

| 方向 | method | 参数/返回 |
| --- | --- | --- |
| Dart → C++ | `getNotificationHostStatus` | 无 → `{available, failureStage?}` |
| Dart → C++ | `showTerminalNotification` | `id/title/body/payload` → `bool` |
| Dart → C++ | `takePendingNotificationActivations` | 无 → `List<String>`，原子清空 |
| C++ → Dart | `notificationActivated` | 原始 payload string |

`AttachMessenger()` 才创建 `flutter::MethodChannel<flutter::EncodableValue>`；host 在此之前收到的 payload 留在 native queue。channel 所有 handler/invoke 与 Toast WinRT show 都在 runner UI thread；notification/pipe workers 只能加锁入队并 post 自定义 window message，不能直接触碰 messenger/window。shutdown 后不再向 Dart 发送。failureStage 只能是固定 token，不返回路径、payload、HRESULT 文本或 exception。

### 8.7 Dart host client 与 terminal adapter

新增 `lib/app/platform/windows_notification_host_client.dart`：

```dart
abstract interface class WindowsNotificationHostClient {
  Stream<String> get activationPayloads;

  Future<bool> getAvailable();

  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  Future<List<String>> takePendingActivationPayloads();

  Future<void> dispose();
}
```

生产 client 只包装上述 MethodChannel；构造/initialize 时先安装唯一 Dart handler，再执行任何 `await`。`dispose()` 只移除 Dart handler/关闭 stream，不调用 native host shutdown；native lifetime 始终归 runner 进程。

新增 `lib/app/platform/windows_chat_generation_terminal_notification_adapter.dart`：

- `initialize()` 先订阅 client activation stream，再查询 host status；unavailable 时保持 no-op。
- live 与 pending payload 都走共享严格 decoder；raw payload 不向上游暴露。
- `takePendingActivation()` 一次取走 native list，返回首个合法 activation；其余合法项按 FIFO 发到 adapter stream，默认深模块继续按 event key 去重。
- `show()` 直接传 Dart 已生成的 id/title/body/payload；false 或异常交给默认深模块记录固定分类。
- `dispose()` 幂等并取消 adapter 自己的 activation 订阅，但不 dispose 共享 client；client 只由第 9.1 节 `disposeShared` 释放。不解释 generation、不 import presentation。

### 8.8 Windows 窗口恢复

`WindowsAppWindow.restoreAndFocus()` 固定：

1. `isVisible == false` 时 `show()`。
2. `isMinimized == true` 时 `restore()`。
3. 最后 `focus()`。

各调用分别 catch 并继续下一步；如果 focus 最终失败，activation 仍导航，诊断记录 `window_restore_or_focus_failed`。不因为窗口 API 失败丢失会话目标。

### 8.9 Windows 设置

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

禁止 `runInShell: true`，不拼接命令字符串。成功启动返回 true，异常返回 false。状态只通过共享 `WindowsNotificationHostClient.getAvailable()` 可靠报告 `available`（runner host 可用，不承诺系统开关开启或未来每次展示成功）或 `unavailable`；不要伪造系统级精确开关读取。

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
- Windows：创建一个 `WindowsNotificationHostClient`，terminal adapter 与 settings adapter 共享它；foreground 使用 no-op，`disposeShared` 只 dispose client 一次。runner-owned `WindowsNotificationHost` 在 Dart composition 之前由 `main.cpp` 启动，不归 Provider 生命周期所有。
- 其他：三个 no-op。

端口各自 dispose 不得重复 dispose shared bridge/client；composition 只在 `disposeShared` 释放 Dart shared owner。Dart client 的 dispose 只撤销 MethodChannel handler/关闭 stream，不得关闭 runner 的 COM class object、mutex、pipe 或原生队列；这些资源只由 `main.cpp` 的宿主生命周期释放。

生产调用不传 factory，使用文件内默认实现。测试选择 `TargetPlatform.windows` 时必须传返回 fake/no-op 记录的 `windowsFactory`，从构造源头阻止真实 MethodChannel client；这只是 composition 内部测试 seam，不暴露给 feature。测试不实例化 Windows runner，也不依赖 Windows SDK。

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

`bootstrap()` 增加两个只供测试注入的可选参数 `notificationPlatformBindingsFactory` 与 `appWindowFactory`，生产均传 null；它们只向 `appCompositionOverrides` 透传，不改变平台判断。`test_harness` / integration helper 默认传 no-op/fake factory 并 override 固定 session，因此 `hostPlatform: TargetPlatform.windows` 也不触发真实 MethodChannel 或 `window_manager`。需要 case-specific fake 时可传 `bindChatGenerationNotifications: false` / `bindAppWindow: false` 后自行 override。

Ubuntu CI 必须执行一条 composition/bootstrap 测试：显式选择 `TargetPlatform.windows`、注入 fake factories、完成 root eager start，并证明没有调用真实 MethodChannel 或依赖 Windows runner。不得通过跳过 Windows 平台选择测试来规避；C++/WinRT runner 编译与原生 helper 测试由 Windows gate 承担。

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

### Task 6：Windows runner-owned 激活 spike（阻塞）

#### Task 6A：归档已证伪插件方案（已完成，FAIL）

既有 `flutter_local_notifications_windows: 3.1.1` throwaway spike 是有效反例，不再重跑来争取偶然 PASS：手工实例已创建 Flutter、插件尚未 `CoRegisterClassObject` 时点击 Toast，RPCSS 启动第二个完整 Flutter 进程并把 payload 交给它。`docs/testing/windows-chat-generation-notifications-smoke.md` 中对应 OS、命令、PID 与 payload 记录必须原样保留，并明确标记“被否决方案”；它不再阻塞 Dart/Android 已完成工作，但禁止按原 Task 7–9 继续插件实现。

#### Task 6B：验证 runner-owned COM + 唯一 Flutter owner（新阻塞 gate）

本 Task 必须在修改产品 `windows/runner/` 前完成；它验证第 8 节仍属于外部环境的 Windows Shell/COM/SCM 行为，不产出可复用产品模块。

**隔离方式**

- 在仓库外新建最小 Flutter Windows 工程，不添加任何本地通知插件；不得原地改写保留旧证据的插件 spike 工程。新工程使用与旧 spike、产品都不同的临时 AUMID、CLSID、shortcut、mutex、event、pipe 与注册表 key。
- spike 在 runner 原生层实现最小 `INotificationActivationCallback`、`IClassFactory`、ToastGeneric show、instance/activator 两把 mutex、ready event、pipe 与内存队列；COM activator 运行在 Flutter 前已启动并持续 pump 的独立 notification STA thread，pipe 不依赖 Dart/UI thread。Dart 只显示固定状态和收到的 opaque payload。
- 每个进程写结构化证据：PID、mode、是否创建 `DartProject`、COM register/revoke stage、pipe ACK、payload hash/byte count、正常退出。日志不得写产品绝对路径、完整通知正文或异常文本。
- 正常、`PRE_COM_DELAY_MS=10000`、`POST_COM_PRE_FLUTTER_DELAY_MS=10000` 是三个独立 native build 变体；delay 由 throwaway CMake compile definition 写入 C++，不得用 Dart define、外部 `Start-Sleep` 或阻塞已启动的 pipe/notification STA message loop。pre-COM delay 位于 primary 创建 pipe 后、竞争 activator lease 前；post-COM delay 位于 notification STA 已注册并开始 pump 后、`DartProject` 前。
- 注册格式严格使用第 8.4 节；LocalServer32 不自创参数，只接受 COM 自动附加的 `-Embedding`/`/Embedding`。
- 完成后只清理经逐项回读仍属于 spike 身份的 shortcut、HKCU key、Toast backup 与临时目录；不得碰产品身份或其他注册项。
- 把 OS/SDK/Flutter 版本、三个 build 命令、实际使用的 Windows SDK link libraries、每个 case 的 PID/mode/payload/耗时与 `PASS|FAIL` 追加到 smoke 文档“runner-owned spike”章节；不得覆盖 Task 6A。

**阻塞验收清单**

1. **身份与原生 show**：shortcut `VT_CLSID`、AUMID、quoted LocalServer32 default、unquoted `ServerExecutable` 全部回读匹配；runner 自己显示的 Toast 可点击，原始 UTF-8 payload 可达 activator。
2. **warm**：primary 已 ready 时点击，payload 进入 primary native callback/queue 并到 Dart 一次；Flutter owner PID 不变；若 RPCSS 短暂创建 relay，该 relay 不创建 `DartProject` 且有界退出。
3. **cold 20 轮**：完全退出、发送 Toast、点击的完整循环至少 20 次；每轮恰有一个 `flutter_started=true` owner、payload 一次交付、注册与 revoke 无 native crash。
4. **快速连续 cold**：完全退出后快速点击两条不同 payload；允许出现短命 relay，但最终只有一个 Flutter/storage owner，两条合法 payload 按 FIFO 到达且没有残留 relay。
5. **pre-COM race**：手工启动 pre-COM 变体，在 10 秒窗口点击；relay 必须通过 activator lease 成为短命 COM owner，并把 payload 经已就绪 pipe 交给 primary；relay 不启动 Flutter，primary 随后取得 lease、注册长期 owner并只启动一个 Flutter engine。
6. **post-COM/pre-Flutter race**：手工启动 post-COM 变体，在 10 秒窗口点击；独立 notification STA 必须在 Flutter 未启动时完成 callback 并把 payload 放入 native queue，Flutter attach 后一次取出，不启动第二个 Flutter engine。若只能等 Flutter message loop 启动后才收到 callback，则本项 FAIL。
7. **第二次手工启动**：primary warm 时再次双击 exe，secondary 只发送 `activateWindow` 并退出；现有窗口恢复/聚焦，未创建第二个 Flutter engine。
8. **边界输入**：中文 payload warm/cold 完整一致；1024-byte 边界接受，1025-byte、未知 frame version/kind、截断 frame 被 native 拒绝且不写 payload。
9. **失效恢复**：primary 正常退出后下一次启动可重新选主；primary 在 relay 交付期间退出时，最多一个进程按第 8.3 节重新选主并携带已捕获 payload 晋升；不存在仍有 primary 却由 secondary 启动 Flutter 的路径。
10. **native 生存性与时限**：所有 case 无 access violation、`std::terminate`、未捕获异常或永不退出；记录 p50/max 的 primary registration、relay handoff、pipe ACK，据此锁定产品 named constants。单次 harness 硬上界 60 秒不等于产品 wait 值。

**硬停止条件**

- 任一时刻出现两个 `flutter_started=true` 进程，或 relay 打开窗口/产品存储。
- warm/cold/race payload 丢失、重复、乱序，或只能通过未验证的进程名/PID 枚举修补。
- relay/secondary 需要无限等待，或 primary 仍存活时 IPC 失败会晋升第二个 Flutter owner。
- `CoRegisterClassObject` handoff、activator lease 或 COM shutdown 无法做到无 native 进程终止。
- 可靠实现必须依赖第三方通知插件、MSIX、安装器或管理员权限。

任一项失败就保留证据并停止 Task 7–11；不得把“通常只有一个进程”替代“唯一 Flutter/storage owner”。全部 PASS 后才把实测 wait 上界、RPCSS 参数和 handoff 规则回写第 8 节，再开始产品实现。

### Task 7：Windows runner 通知宿主与 Dart host client

**文件**

- 新增 `windows/runner/windows_notification_host.h/.cpp`
- 新增 `windows/runner/windows_notification_registration.h/.cpp`
- 新增 `windows/runner/windows_notification_activator.h/.cpp`
- 新增 `windows/runner/windows_notification_instance_coordinator.h/.cpp`
- 新增 `windows/runner/windows_notification_protocol.h/.cpp`
- 新增 `windows/runner/windows_notification_toast.h/.cpp`
- 新增 `windows/runner/tests/windows_notification_host_test.cpp`
- 修改 `windows/runner/main.cpp`
- 修改 `windows/runner/flutter_window.h/.cpp`
- 修改 `windows/runner/CMakeLists.txt`
- 新增 `scripts/test-windows-notification-host.ps1`
- 新增 `lib/app/platform/windows_notification_host_client.dart`
- 新增 `test/app/platform/windows_notification_host_client_test.dart`

本 Task 不修改 `pubspec.yaml`/`pubspec.lock`，不添加 Windows 通知插件或 Windows App SDK。仅使用仓库 Flutter Windows embedder、当前 Windows SDK、WRL/C++/WinRT 与 Win32。

**RED 测试/编译契约**

- 原生 test executable 覆盖：精确 `-Embedding` token 解析；primary/relay/manual secondary 模式决策；manual-reset ready event 的新 owner reset/长期 owner set/shutdown reset；当前 user SID + LocalSystem 的 pipe DACL 构造及失败时 host unavailable/instance mutex 仍持有；v1 frame round-trip 与未知/超长/截断拒绝；并发入队下的 FIFO 32 queue 与 focus 合并；UTF-8 byte 上限；XML escaping；notification ID/title/body/payload validation；固定 AUMID/CLSID/shortcut/registry value 构造；notification STA ready/register/revoke/shutdown 状态机幂等；in-flight callback 与 shutdown 竞态不发生 use-after-free；worker 只能 post UI dispatch、不能直接调用 messenger/window。
- CMake configure test 覆盖默认 delay 为 0、testing=OFF/Release 拒绝非零 delay、testing=ON Debug 才能生成两个 race 变体；不得把 runtime delay 开关暴露给 Dart 或最终 release。
- `main.cpp` 的可审计 control flow 保证 `ShouldStartFlutter()==false` 分支在任何 `DartProject` 构造之前 return；native test 用注入的 process-actions seam 断言 relay/manual secondary 的 `flutterStartCount==0`。
- Dart tests：`host client 先安装唯一 handler 再查询状态`、`pending activation 一次取走完整列表`、`live callback 原样进入单一 stream`、`malformed 返回与 PlatformException 固定映射为 unavailable 或 false`、`dispose 幂等且不调用 native shutdown`。
- 真实 shortcut/registry/COM/Toast OS 行为不伪装成纯测试已覆盖，沿用 Task 6B 与下方产品回读/smoke。

**GREEN**

- 严格实现第 8.1–8.7 节 runner host 与 Dart client；`main.cpp` 只依赖 `windows_notification_host.h`，内部 helpers 不泄漏到 Flutter/app composition。
- runner 和 native test target 显式启用 C++17 与 MSVC `/utf-8`；notification STA、pipe IO thread 与 runner UI thread 的 ownership 写成类级中文 doc；所有 COM/WinRT/pipe callback 最外层 catch-all，日志只写固定 stage/token。
- `windows/runner/CMakeLists.txt` 显式链接 Task 6B 已验证的最小 Windows SDK libraries（预计包含 Toast/WinRT、shell property store、HKCU 与 COM 所需的 `runtimeobject`/`windowsapp`、`shell32`、`propsys`、`advapi32`、`ole32`、`oleaut32`、`uuid`；以 spike 实际 link set 为准）。不得照抄官方 sample 中与本实现无关的 ODBC/GDI 库，也不得靠机器隐式 linker state。
- `scripts/test-windows-notification-host.ps1` 负责构建并运行原生 test executable，非零立即退出；不得引入 gtest 或另一个测试框架。
- 运行 Dart client 单测并写 `logs/windows-notification-host-client-green.log`，工具超时 60000ms。
- 运行原生测试与 Windows build：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
.\scripts\test-windows-notification-host.ps1 2>&1 | Out-File -Encoding utf8 logs/windows-notification-host-native-green.log; $NativeExit = $LASTEXITCODE; Write-Host "EXIT=$NativeExit"; Get-Content -Tail 150 logs/windows-notification-host-native-green.log
flutter build windows 2>&1 | Out-File -Encoding utf8 logs/build-windows-notification-host.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows-notification-host.log
```

两个命令级硬超时各 600000ms。

**产品注册回读**

- 启动当前 build 一次，通过 host status 回读 `available=true` 与固定 failureStage 为空。
- 用 Windows 属性存储 API 回读 `Oh My LLM.lnk` target/AUMID/`VT_CLSID`，再回读 LocalServer32 default 与 `ServerExecutable`；记录匹配结果，不把绝对路径提交到文档。
- 覆盖同目录 exe 后重新启动，确认 primary 幂等修复；移动目录后先完全退出旧 primary，再手工启动新目录并确认修复。
- 本 Task 已能用 runner channel 显示固定测试 Toast 与取得 native activation，但尚未接 terminal/domain adapter；不得把固定测试 payload 冒充端到端会话导航验收。

**硬停止条件**

- native tests、build 或产品回读证明模式隔离、注册、COM/pipe queue、Toast show 或 shutdown 链不成立。
- relay/manual secondary 的任一路径能够构造 Flutter engine/窗口/存储。
- 必须把 HWND、runner 对象或原始 HRESULT/异常暴露给 Dart 才能实现。
- 可靠实现必须引入第三方插件、MSIX、安装器或管理员权限。

发生硬停止时不继续 Task 8–11；保留 Task 6B 与 native 日志，不降级成“只支持应用运行时 Toast”。

### Task 8：Windows terminal adapter、AppWindow 与设置

**文件**

- 新增 `lib/app/platform/windows_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/windows_app_window.dart`
- 新增 `lib/app/platform/windows_system_notification_settings.dart`
- 新增 `test/app/platform/windows_chat_generation_terminal_notification_adapter_test.dart`
- 新增 `test/app/platform/windows_app_window_test.dart`
- 新增 `test/app/platform/windows_system_notification_settings_test.dart`

**RED 测试**

- `安全 payload 和固定字段原样传给共享 Windows host client`
- `host unavailable 时展示为 no-op`
- `host show 返回 false 或异常时不泄漏原始异常`
- `live 与 pending payload 使用同一严格 decoder`
- `pending 列表一次取走且多个合法 activation 按 FIFO 交付`
- `同一 pending payload 只取一次`
- `超长 未知版本 额外字段和 malformed payload 被忽略`
- `窗口不可见时先 show 再 focus`
- `窗口最小化时先 restore 再 focus`
- `窗口恢复部分失败仍尝试 focus`
- `Windows 设置状态只反映共享 host 可用性`
- `Windows 设置通过 launcher seam 只用 explorer 参数数组且异常返回 false`

**GREEN**

- 实现第 8.7–8.9 节；terminal/settings 由构造函数接收同一 `WindowsNotificationHostClient`，不得各自创建 MethodChannel handler。
- adapter 不判定 generation outcome、不 import chat presentation；AppWindow 继续只包装 `window_manager`。
- 测试只 fake `WindowsNotificationHostClient`、`WindowsWindowManagerClient` 与 `WindowsProcessLauncher`，不依赖 Windows runner、不显示 Toast、不启动 explorer。
- 三个单文件日志分别写 `logs/windows-terminal-adapter-green.log`、`logs/windows-app-window-green.log`、`logs/windows-system-notification-settings-green.log`，每个工具超时 60000ms。

**停止条件**

- terminal/settings 需要分别拥有 channel handler 或关闭 runner host。
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
- `Windows production factory 只创建一个共享 host client 且只 dispose 一次`
- `Windows 平台 fake factory 在 Ubuntu 不调用真实 MethodChannel 或 Windows runner`
- `其他平台只绑定 no-op`
- `shared bridge 只 dispose 一次`
- `测试 harness 默认不触发真实 MethodChannel 或 Windows runner`
- `bootstrap 的测试 factory 透传不改变生产默认绑定`
- `固定 session override 同时进入 coordinator ongoing payload 与 terminal receipt`
- `应用根部 eager 启动注意力 observer 和终态通知模块`
- `chatSessionsProvider 首次同步加载摘要时 cold activation 不误判为已删除`

**GREEN**

- 严格按第 9 节装配。
- `lib/app/app.dart` 的 observer/terminal eager watch 只在本 Task 一次性接入；Task 2 不做临时装配。
- 用 provider override 测平台选择，不修改全局 `debugDefaultTargetPlatformOverride`。
- Windows 平台选择测试必须通过第 9.1 节的 factory seam 构造 fake 记录；不得先实例化 production client 后再用 provider override 覆盖。production Windows factory 必须把一个 `WindowsNotificationHostClient` 共享给 terminal/settings，并只由 `disposeShared` 释放一次；Dart dispose 不得触发 runner `Shutdown()`。
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
  - 保留 Task 6A 插件方案的原始 FAIL 证据，并明确其已被 runner-owned 方案替代；不得删改 PID/payload 现场。
  - 追加 Task 6B runner-owned spike 的 OS/SDK/Flutter 版本、三个 build 变体、进程 mode、Flutter owner、COM register/revoke、pipe ACK、payload 与清理结果。
  - 前台、失焦、最小化。
  - warm/cold 点击。
  - 快速连续 cold 激活、pre-COM race、post-COM/pre-Flutter race；允许短命 native relay，但必须只有一个 Flutter/storage owner，且 relay 有界退出。
  - primary warm 时第二次手工启动只恢复/聚焦既有窗口，不创建第二个 Flutter engine。
  - 默认声音在系统声音开启/关闭与专注助手下的实际表现；不声称应用强制响铃。
  - 文档记录通知 ID 碰撞会让后一条覆盖前一条的已知限制；不要求人工构造碰撞或在生产中枚举碰撞。
  - 同目录覆盖更新。
  - 覆盖同目录、移动目录后完全退出旧 primary 并首次手工启动，再点击。
  - 系统设置入口。
- 每项只写 `PASS`、`FAIL` 或 `PENDING`；无实机证据保持 `PENDING`，但下面列出的最小原生 gate 不允许为 `PENDING`。

**Ready 前最小原生 gate（人工、阻塞）**

- Android：至少一台受支持 emulator/设备执行并 `PASS`：生成成功后出现 `chat_generation_result` HIGH 通知；点击打开精确会话；现有 ongoing 点击仍打开精确会话；应用前台查看同一会话时抑制。系统是否实际响铃受设备设置控制，可记录“channel 配置正确但设备静音”，不能把设备静音判成实现 FAIL。
- Windows：用最终 Release 产品 build 执行 warm、至少 20 轮完全退出后的 cold、快速连续两条 cold activation、primary warm 时第二次手工启动、最小化恢复后导航与删除会话回退根页；再用第 8.2 节同一产品源码生成的两个 testing=ON Debug instrumented build执行 pre-COM 与 post-COM/pre-Flutter race。全部必须 `PASS`。记录每个 PID 的 mode/`flutter_started`、AUMID/CLSID、class registration/relay handoff/pipe ACK 耗时和 payload event key；Release configure/build 另证明确实拒绝非零 delay。允许观测到短命 relay PID，但任一 case 只能有一个 Flutter/storage owner，所有 relay 必须在固定上界内退出。
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

Windows build 后再次执行 `scripts/test-windows-notification-host.ps1`；该脚本与 executable 必须 `EXIT=0`，日志使用 `logs/windows-notification-host-native-final.log`。这不替代真实 Shell/COM smoke。

**范围审计**

```powershell
git status --short
git diff --check
git diff --stat master...HEAD
git diff --name-only master...HEAD
rg -n '\bcontent\b|reasoningContent|errorMessage|stackTrace' lib/app/notifications lib/app/platform
rg -n "MSIX|linux|macos|通知开关" lib android windows
rg -n "flutter_local_notifications_windows|FlutterLocalNotificationsWindows|WindowsLocalNotificationsClient" pubspec.yaml pubspec.lock lib windows
rg -n "GetProcessesByName|CreateToolhelp32Snapshot|Process32First|Process32Next" windows/runner
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
- Windows runner 只存在一个长期 COM owner 和一个 Flutter/storage owner；relay/manual secondary 源码路径不能构造 `DartProject`。
- Windows 身份判断只使用固定 named kernel objects/pipe，不依赖进程名、PID 枚举、窗口标题或 exe 路径猜测。
- Dart client dispose 不关闭 runner host；runner shutdown 明确 revoke COM 并关闭 IPC/handles。
- 所有新测试标题和注释为简体中文。

当前 CI 只有 Ubuntu gate，没有 Linux/macOS 桌面 build 矩阵。Windows 通知实现没有第三方 DLL，但 runner C++/WinRT 仍只能由 Windows build/native test 验证；第 9.1 节 factory seam 必须确保 Ubuntu 测试在构造 production MethodChannel client 前选择 fake/no-op。`flutter analyze`、全量 `flutter test` 与 CI 回读负责证明 Dart composition 跨平台可编译；不得把未存在的 macOS/Linux desktop build 或未运行的 Windows native gate 写成已通过。

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
| `flutter_local_notifications_windows` 的 Dart 初始化后 COM owner | runner 在 `DartProject` 前托管 COM、Toast show 与 native queue |
| 进程名/PID 枚举式“单实例”猜测 | instance/activator named mutex + ready event + v1 named pipe |
| 第二个完整 Flutter 冷启动实例 | 无 Flutter 的 activation relay 或 manual secondary；仅 primary 可拥有存储 |
| Windows composition 构造真实 MethodChannel client 后再 override | platform factory seam 在对象构造前选择 production 或 fake |

完成范围审计时，以上旧 symbol 应由 `rg` 得到零生产调用；仅迁移说明文档可出现。

`ChatGenerationOpenConversationRequested` 与 `takePendingOpenConversation()` 不属于待删除旧 symbol：二者继续承载 Android ongoing 点击直达会话的既有产品契约。范围审计只应证明新 HIGH terminal/fallback 不再走这条旧终态路径。

## 13. 提交顺序

本计划文档已单独提交；产品实施按以下可独立构建、可独立审查，并按依赖逆序回滚的顺序提交。Task 3–8 是尚未完成平台 composition 的中间态，不得把其中任一 commit 单独发布或描述为跨平台终态通知已可用。Task 6A 已有失败证据；Task 6B 只有真实 runner-owned spike 全 PASS 才允许提交第 7 项：

1. `refactor(chat): 分离生成终态通知收据`
2. `refactor(app): 增加生成通知注意力与激活模块`
3. `refactor(app): 原子迁移生成通知协调与前台端口`
4. `refactor(android): 收敛生成通知平台桥接`
5. `feat(android): 增加生成终态高优先级通知`
6. `test(windows): 验证 runner 托管 Toast 激活链路`（提交 Task 6A/6B 文档证据，不提交 throwaway 工程）
7. `feat(windows): 增加 runner 通知宿主与单实例协调`
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

Windows runner host 任一自动验证/注册回读失败不得作为“功能完成”提交。Task 6B 和第 14 节最小原生 gate 未通过时，允许保留已验证的 Dart/Android 中间提交，但 Windows Task 7 不得开始，PR 必须保持 draft；不能用 `PENDING` 标记 Ready。

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
- Task 6A 插件方案 FAIL 证据被保留且明确标为被否决；产品依赖中没有 `flutter_local_notifications_windows`。
- Task 6B runner-owned throwaway spike 已以真实 Windows Shell/COM 证明至少 20 轮 cold、warm、连续 cold、pre-COM、post-COM/pre-Flutter、第二次手工启动、非 ASCII/边界 payload、失效恢复与 native 生存性；失败时不得进入产品 Task 7。
- Windows runner 在 `DartProject` 前注册长期 COM owner；instance/activator mutex、ready event、v1 pipe、relay 和 native queue 有自动原生测试及实测 wait 上界，不要求 MSIX/管理员权限。
- 任一时刻只有一个 Flutter/storage owner；允许的 relay/manual secondary 从源码、原生测试和 smoke 三处都证明不会构造 Flutter engine、窗口或产品存储，且在固定上界内退出。
- Windows warm/cold payload、窗口恢复、删除会话回退有自动测试。
- Windows GUID/CLSID 两种表示、shortcut `VT_CLSID`、LocalServer32 quoted default 与 unquoted `ServerExecutable` 均有 Task 6B、native test、build 与产品回读证据。
- Ubuntu 平台选择测试在 production MethodChannel client 构造前选择 fake；Windows runner native test 和 Windows build 均有日志。
- Windows 不显式配置声音，smoke 如实记录系统设置/专注助手下的结果。
- 设置页有 loading/状态/打开系统设置，没有开关。
- Dart/MethodChannel/runner 可观察平台故障不改变 generation；所有 COM/WinRT/pipe/channel native 边界 catch-all，已测路径没有未捕获 exception 或进程终止。
- 定向测试、analyze、import boundary、全量测试、Windows build 有日志证据。
- Android/Windows smoke 文档存在，第 11 节最小原生 gate 均为 `PASS`；只有扩展矩阵未执行项可为 `PENDING`。
- `git diff --check` 通过，base...head 无无关范围。

## 15. 全局停止条件

出现任一条件立即停止并报告，不自行扩大范围：

- Windows 可靠冷启动必须依赖 MSIX、安装器或管理员权限。
- Task 6B 的 warm、20 轮 cold、快速连续 cold、pre-COM、post-COM/pre-Flutter、第二次手工启动或失效恢复任一 gate 明确 `FAIL`。
- 任一 race 产生两个 Flutter/storage owner，或 relay/manual secondary 构造 `DartProject`、窗口、SharedPreferences、SQLite/network logger。
- runner 无法可靠交付 cold/queued/relay payload，或只能接受 payload 丢失、重复、乱序和无界等待。
- instance/activator ownership 只能靠进程名、PID 枚举、窗口标题、固定 sleep 或可伪造的 exe 特征判断。
- COM/WinRT/pipe/MethodChannel 初始化、激活或 shutdown 出现 access violation、`std::terminate`、未捕获 native exception、未 revoke class object 或残留 relay。
- Ubuntu Dart composition 测试必须构造真实 Windows runner/MethodChannel 才能通过，或 Windows runner 无法由独立 Windows build/native test 覆盖。
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
- Microsoft classic Desktop Toast C++ sample（`INotificationActivationCallback`）：<https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/DesktopToasts/CPP/DesktopToastsSample.cpp>
- Microsoft LocalServer32 注册与 `-Embedding`：<https://learn.microsoft.com/en-us/windows/win32/com/localserver32>
- Microsoft `CoRegisterClassObject` / `CoRevokeClassObject`：<https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coregisterclassobject>
- Microsoft out-of-process COM server/SCM 启动模型：<https://learn.microsoft.com/en-us/windows/win32/com/out-of-process-server-implementation-helpers>
- Microsoft named mutex：<https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createmutexw>
- Microsoft named pipe：<https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipes>
- Microsoft Toast activation：<https://learn.microsoft.com/en-us/previous-versions/windows/desktop/win32_tile_badge_notif/respond-to-toast-activations>
- 被否决插件方案的版本记录：<https://pub.dev/packages/flutter_local_notifications_windows>

实施前只复核当前 Windows SDK、Flutter runner API 与官方平台文档；不再复核或引入插件 3.1.1，不得借机升级无关依赖。
