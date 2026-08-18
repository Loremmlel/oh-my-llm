# Android Chat Generation Foreground Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Android 用户主动发起聊天生成时启动 `dataSync` 前台服务，以低打扰动态通知投影既有 generation 生命周期，并让通知停止动作复用现有 durable stop；任何平台能力失败都不改变聊天结果。

**Architecture:** `ChatGenerationRun` / `ChatGenerationSnapshot` 仍是唯一 generation owner。纯 Dart projector 把既有 snapshot、streaming reply 和终态 outcome 转为脱敏通知 view model；app composition coordinator 负责 1 秒节流、token guard、命令串行化和原生动作回传；application-owned port 由 Android MethodChannel adapter 或非 Android no-op 实现；Kotlin Service 只管理前台服务、标准通知、token guard 与 Android 生命周期，不发网络请求、不访问 SQLite、不建立第二套 generation 状态机。

**Tech Stack:** Flutter 3.44.x（CI 3.44.6）/ Dart `^3.11.5`、Riverpod 3 `NotifierProvider` / `Provider`、GoRouter 17、Flutter `MethodChannel`、Kotlin/JVM 17、Android foreground service `dataSync`、AndroidX Core 1.17.0、JUnit 4.13.2。

**Spec:** `docs/superpowers/specs/2026-08-17-android-chat-generation-foreground-service-design.md`

## Global Constraints

- Android 前台服务只在用户可见 Activity 中发起的 generation 首次进入 `preparing` 时启动；不得从广播、定时器、开机、普通网络回调或后台重试首次启动。
- 前台服务类型固定为 `dataSync`；Manifest 必须声明 `android.permission.FOREGROUND_SERVICE`、`android.permission.FOREGROUND_SERVICE_DATA_SYNC`、`android.permission.POST_NOTIFICATIONS`，Service 必须是 `android:exported="false"`、`android:stopWithTask="true"`。
- Kotlin 不发送 LLM 请求、不解析 SSE、不访问聊天 SQLite、不理解 Riverpod，不持有 API key、prompt、回复正文、reasoning、provider host、URL、response body 或 stack trace。
- `ChatGenerationRun` / `ChatGenerationCoordinator` 继续独占 prepare、stream、stop、retry、finalize、outcome 与 durable save；通知只读取既有 `ChatGenerationSnapshot` / `ChatStreamingReply`，不得新增业务 phase 或第二套 flag 状态机。
- 前台服务从 `preparing` 开始；success/cancel 在 durable terminal 后移除；failed/emptyReply/persistenceFailed 在 durable terminal 后转换为普通、可划掉的安全错误通知。
- `preparing`、`streaming`、`retryWaiting` 可停止；`stopping`、`finalizing` 不可停止。通知动作必须复用 `ChatSessionsController.stopStreaming()`，不得直接关闭 Dart HTTP client。
- 流式通知更新最多每秒一次；phase、attempt、terminal 变化立即投递，不等待节流窗口。
- public/锁屏通知只显示固定安全文案；private 通知只显示阶段、attempt、正文字符数、推理字符数和 allowlist 错误摘要。
- 通知不得显示会话标题、模型名称、prompt、正文片段、reasoning 片段、endpoint、host、URL、凭据、Header、request/response body、异常原文或 stack trace。
- Android 13+ 通知权限拒绝、前台服务启动失败、MethodChannel 失败、ACK 超时和 Android 15 `dataSync` timeout 都 fail-open；不得新增 assistant message、覆盖 `errorMessage`、取消请求或改写 generation outcome。
- Android 15+ `dataSync` 前台服务后台累计 6 小时限制必须实现 `Service.onTimeout(Int, Int)`；原生先停止 Service，再 best-effort 通知 Dart，不能等待 durable save 后才 `stopSelf()`。
- 最近任务划掉或 Flutter engine detach 后不保留孤儿 Service；不自动重发、恢复、开机启动或创建第二 FlutterEngine / 后台 Dart isolate。
- Windows 与非 Android 绑定 no-op port；不得请求通知权限或调用聊天前台服务 MethodChannel。
- 不引入第三方后台 service 插件、`RemoteViews`、wake lock、Wi-Fi lock、精确闹钟或电池优化豁免。
- 不声明 `BOOT_COMPLETED` receiver，不从开机广播恢复或启动 generation。
- 本实现不执行 Google Play Console 前台服务用途申报或公开上架操作；只在代码与 smoke 记录中保留后续申报所需的 `dataSync` 用途事实。
- 代码注释与测试名称使用简体中文；跨 `app/`、`core/`、feature import 使用 `package:oh_my_llm/...`；不得使用 `part` / `part of`。
- 每个生产行为先写失败测试，再写最小实现；全量测试、analyze、架构门禁和 build 日志写入仓库 ignored 的 `logs/`。
- 每次提交前格式化所有改动 Dart 文件，并在暂存后执行 `dart format --output=none --set-exit-if-changed`。

---

## 0. Spec Review and Planning Baseline

### 0.1 审查结论

设计可直接进入单一实施计划，不需要拆成独立子项目。Dart generation ownership、平台边界、通知隐私、terminal durable 时序、Android 15 timeout 和非目标彼此一致；仓库现状也已有可复用的 `ChatGenerationSnapshot.generationId`、`ChatSessionsController.stopStreaming()`、根 `OhMyLlmApp` 与 `appCompositionOverrides()`。

官方 Android 文档复核结果：

- Android 12+ 后台启动限制与 spec 一致：非豁免后台进程调用会抛 `ForegroundServiceStartNotAllowedException`。
- Android 14+ `dataSync` 需要 Manifest service type、`FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_DATA_SYNC`；无 runtime prerequisite。
- Android 13+ 拒绝 `POST_NOTIFICATIONS` 后仍可启动 FGS，但用户只在 Task Manager 的 active apps 区域看到它，普通通知栏和 terminal error 通知不可保证可见。
- Android 15+ 以 target SDK 35+ 为条件，对 `dataSync` / `mediaProcessing` 各自施加每 24 小时累计 6 小时后台额度，并回调 `Service.onTimeout(int, int)`；超时后必须在数秒内 `stopSelf()`。
- 当前 Flutter 3.44.x 工程使用 compile/target SDK 36。AndroidX Core 1.19.0 要求更新的平台编译基线；本功能只需早已稳定的 `NotificationCompat` / `ServiceCompat`，因此显式固定 `androidx.core:core:1.17.0`，避免为本功能升级 compile SDK 语义。

参考：

- <https://developer.android.com/develop/background-work/services/fgs/launch>
- <https://developer.android.com/develop/background-work/services/fgs/service-types>
- <https://developer.android.com/develop/background-work/services/fgs/timeout>
- <https://developer.android.com/develop/ui/compose/notifications/notification-permission>
- <https://developer.android.com/jetpack/androidx/releases/core>

### 0.2 审查中补齐的实施决议

以下是 spec 留给实施计划微调的细节；实施者不得重新选择另一套语义：

1. **权限一次性询问持久化：** Kotlin 使用名为 `chat_generation_notifications` 的 Android private SharedPreferences，键为 `post_notifications_requested`。API 33+ 在真正发起系统请求前写 `true`；拒绝后跨进程重启也不重复弹。用户划掉权限弹窗仍视为已询问，之后只能从系统设置修改。
2. **权限与发送并行：** coordinator 在 `preparing` 同时触发 `ensureNotificationPermission()` 与 Service `start()`，不 await 权限结果后才开始 generation；这两个 Future 只影响诊断和通知能力。
3. **ACK 边界：** `start` 的 accepted ACK 只能在 Service 已解析命令、建立 token、调用 `ServiceCompat.startForeground()` 后返回；update/remove/fail 的 accepted ACK 只能在当前活跃 Service 实例实际应用命令后返回。仅 `Context.startForegroundService()` 无异常不算 accepted。
4. **ACK 有界等待：** Dart adapter 对单次 MethodChannel 调用使用 2 秒 timeout；terminal cleanup 最多尝试 3 次，重试间隔固定 200ms、800ms，总等待上界为 7 秒左右。重试在通知 coordinator 自己的 async tail 中进行，不阻塞 generation completion。
5. **冷启动点击握手：** warm engine 使用 `openConversationRequested` 事件；cold start / handler 尚未就绪时 Kotlin 缓存最后一个 conversation ID，Dart 初始化后调用 `takePendingOpenConversation` 取走一次。仅 push 事件不足以满足冷启动契约。
6. **路由参数：** 通知点击导航到 `/chat?conversationId=<encoded-id>`；`AppRouteParameter.conversationId` 是唯一参数键，不使用 `state.extra`。缺失、空白或已删除 ID 打开默认 chat route，不显示错误。
7. **token 编码：** Dart `generationId` 直接作为 notification token；MethodChannel 使用正整数，Kotlin 用 `Long`。token 只用于当前进程内乱序保护，不持久化。
8. **固定长度：** `notificationTitleMaxCharacters = 48`、`notificationTextMaxCharacters = 120`，都按 `characters` 的 Unicode 字符簇截断；超限时保留 47/119 个字符并追加单字符 `…`。
9. **attempt 文案：** streaming 的“第 N 次尝试”使用 `snapshot.attempt`；`retryWaiting` 已在 run 中先递增 attempt，因此“第 N 次重试”使用 `max(1, snapshot.attempt - 1)`。
10. **权限拒绝后的 terminal：** 仍完整执行 fail/remove 命令和 Service 清理；普通错误通知是 best-effort，系统因权限阻止显示不算聊天或平台命令失败。
11. **原生命令投递：** start 通过 `ContextCompat.startForegroundService()` + native-internal command ID 回 ACK；Service 活跃后 update/remove/fail 直接分派给同进程活跃实例，避免后台再次 `startService()` 和 stop-after-restart 竞态。活跃实例只保存 Service 自身引用，并在 `onDestroy()` 清除；不得保存 Activity。
12. **timeout 普通通知后续收口：** Android 15 timeout 后 Service 已停止，但同进程 Dart generation 可能继续。Kotlin 以 token + conversation ID 记录这一条 timeout 普通通知；后续 remove 直接 cancel，后续 fail 直接替换为业务错误通知，不重新启动 Service。新 generation start、engine detach 或进程死亡清除此瞬态记录。
13. **Service restart：** `onStartCommand()` 返回 `START_NOT_STICKY`；malformed start 在前台窗口内立即 `stopSelf()` 并返回 typed rejection，不等待 5 秒 promotion deadline。

### 0.3 计划基线

- 计划编写前 HEAD：`6d2c4c6`（`docs(chat): 设计 Android 聊天生成前台服务`）。
- 计划编写前 `git status --short`：无输出。
- 本机 Flutter 3.44.8 / Dart 3.12.2；CI 固定 Flutter 3.44.6，实施不得因此修改 CI 版本。
- 计划阶段只做只读代码、Gradle 与官方文档审查；未运行 Flutter 测试、analyze、Android build 或真机 smoke，不能把本计划当作 runtime 验证证据。

### 0.4 最终数据流

```text
ChatGenerationRun
  -> ChatSessionsState.generation + streamingReply
  -> ChatGenerationNotificationProjector (pure, redacted)
  -> ChatGenerationNotificationCoordinator (1s throttle / token / async tail)
  -> ChatGenerationForegroundServicePort
       -> Android MethodChannel adapter
       -> non-Android no-op
  -> ChatGenerationForegroundChannel.kt
  -> ChatGenerationForegroundService.kt
  -> NotificationManager / PendingIntent

notification stop action
  -> Kotlin token check + immediate "正在停止" projection
  -> MethodChannel stopRequested(token, conversationId)
  -> Dart coordinator token + action-in-flight guard
  -> ChatSessionsController.stopStreaming()
  -> ChatGenerationCoordinator.stop()
  -> ChatGenerationRun host.stop() + durable save
  -> terminal snapshot
  -> remove/fail ACK
```

### 0.5 文件结构

新增生产文件：

```text
lib/features/chat/application/ports/chat_generation_foreground_service.dart
lib/features/chat/application/generation/chat_generation_notification.dart
lib/app/composition/chat_generation_notification_coordinator.dart
lib/app/composition/chat_generation_foreground_service_bindings.dart
lib/app/platform/android_chat_generation_foreground_service.dart
lib/app/platform/noop_chat_generation_foreground_service.dart
android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocol.kt
android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundService.kt
android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundChannel.kt
android/app/src/main/res/drawable/ic_chat_generation.xml
android/app/src/main/res/values/chat_generation_strings.xml
```

新增测试文件：

```text
test/features/chat/application/generation/chat_generation_notification_test.dart
test/app/composition/chat_generation_notification_coordinator_test.dart
test/app/composition/chat_generation_foreground_service_bindings_test.dart
test/app/platform/android_chat_generation_foreground_service_test.dart
test/app/platform/noop_chat_generation_foreground_service_test.dart
test/integration/chat_generation_notification_integration_test.dart
android/app/src/test/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocolTest.kt
docs/testing/android-chat-generation-foreground-service-smoke.md
```

修改文件：

```text
lib/app/app.dart
lib/app/composition/cross_feature_bindings.dart
lib/app/navigation/app_destination.dart
lib/app/router/app_router.dart
lib/bootstrap.dart
lib/features/chat/presentation/chat_screen.dart
test/app/router/app_router_test.dart
test/features/chat/presentation/chat_screen_test.dart
test/helpers/test_harness.dart
test/integration/bootstrap_integration_test.dart
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/MainActivity.kt
```

---

## 1. Exact Dart Contracts

### 1.1 Platform port

`chat_generation_foreground_service.dart` 公开接口固定如下；后续任务必须使用这些名称，不得改成动态 `Map` port：

```dart
enum ChatForegroundFailureCode {
  unsupportedPlatform,
  channelUnavailable,
  channelTimeout,
  startNotAllowed,
  security,
  serviceUnavailable,
  staleToken,
  malformedPayload,
  nativeFailure,
}

final class ChatForegroundCommandResult extends Equatable {
  const ChatForegroundCommandResult.accepted()
    : accepted = true,
      failureCode = null;

  const ChatForegroundCommandResult.unavailable(
    ChatForegroundFailureCode failureCode,
  ) : accepted = false,
      failureCode = failureCode;

  final bool accepted;
  final ChatForegroundFailureCode? failureCode;

  @override
  List<Object?> get props => [accepted, failureCode];
}

enum ChatNotificationPermissionStatus {
  notRequired,
  granted,
  denied,
  skippedAlreadyRequested,
  unavailable,
}

enum ChatGenerationNotificationActionKind { none, stop, openConversation }

final class ChatGenerationForegroundPayload extends Equatable {
  const ChatGenerationForegroundPayload({
    required this.token,
    required this.conversationId,
    required this.title,
    required this.text,
    required this.publicTitle,
    required this.publicText,
    required this.actionKind,
    this.actionLabel,
  });

  final int token;
  final String conversationId;
  final String title;
  final String text;
  final String publicTitle;
  final String publicText;
  final ChatGenerationNotificationActionKind actionKind;
  final String? actionLabel;

  @override
  List<Object?> get props => [
    token,
    conversationId,
    title,
    text,
    publicTitle,
    publicText,
    actionKind,
    actionLabel,
  ];
}

sealed class ChatGenerationForegroundAction {
  const ChatGenerationForegroundAction();
}

final class ChatGenerationStopRequested
    extends ChatGenerationForegroundAction {
  const ChatGenerationStopRequested({
    required this.token,
    required this.conversationId,
  });

  final int token;
  final String conversationId;
}

final class ChatGenerationOpenConversationRequested
    extends ChatGenerationForegroundAction {
  const ChatGenerationOpenConversationRequested(this.conversationId);

  final String conversationId;
}

final class ChatGenerationForegroundTimedOut
    extends ChatGenerationForegroundAction {
  const ChatGenerationForegroundTimedOut({
    required this.token,
    required this.conversationId,
  });

  final int token;
  final String conversationId;
}

abstract interface class ChatGenerationForegroundServicePort {
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission();

  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  );

  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  );

  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  });

  Future<ChatForegroundCommandResult> fail(
    ChatGenerationForegroundPayload payload,
  );

  Stream<ChatGenerationForegroundAction> get actions;

  Future<String?> takePendingOpenConversation();

  void dispose();
}

final chatGenerationForegroundServiceProvider =
    Provider<ChatGenerationForegroundServicePort>(
      (ref) => throw UnsupportedError('聊天生成前台服务必须由 app composition 绑定'),
    );
```

`dispose()` 只释放 Dart MethodChannel handler / stream controller；它不清理 generation state。原生 engine detach 清理由 `ChatGenerationForegroundChannel.dispose()` 通知 Service 完成。

### 1.2 Notification projection

`chat_generation_notification.dart` 固定定义：

```dart
const notificationTitleMaxCharacters = 48;
const notificationTextMaxCharacters = 120;

enum ChatGenerationNotificationTerminalBehavior {
  ongoing,
  remove,
  retainError,
}

final class ChatGenerationCharacterCounts extends Equatable {
  const ChatGenerationCharacterCounts({
    required this.content,
    required this.reasoning,
  });

  static const zero = ChatGenerationCharacterCounts(content: 0, reasoning: 0);

  final int content;
  final int reasoning;

  @override
  List<Object?> get props => [content, reasoning];
}

final class ChatGenerationNotificationProjection extends Equatable {
  const ChatGenerationNotificationProjection({
    required this.payload,
    required this.terminalBehavior,
    required this.counts,
  });

  final ChatGenerationForegroundPayload payload;
  final ChatGenerationNotificationTerminalBehavior terminalBehavior;
  final ChatGenerationCharacterCounts counts;

  @override
  List<Object?> get props => [payload, terminalBehavior, counts];
}

final class ChatGenerationNotificationProjector {
  const ChatGenerationNotificationProjector();

  ChatGenerationNotificationProjection project({
    required ChatGenerationSnapshot snapshot,
    required ChatStreamingReply? streamingReply,
    ChatGenerationCharacterCounts fallbackCounts =
        ChatGenerationCharacterCounts.zero,
  });
}
```

映射固定为：

| phase | private title | private text | action | terminal |
|---|---|---|---|---|
| preparing | 正在准备请求 | 正在建立生成任务 | stop / 停止生成 | ongoing |
| streaming | 正在生成 · 第 N 次尝试 | 正文 X 字 · 推理 Y 字 | stop / 停止生成 | ongoing |
| retryWaiting | 请求中断 | 正在等待第 N 次重试 | stop / 停止重试 | ongoing |
| stopping | 正在停止 | 正在停止并保存已有内容 | none | ongoing |
| finalizing | 已接收完成 | 正在保存结果 · 正文 X 字 · 推理 Y 字 | none | ongoing |
| succeeded | 已完成 | 已完成 | none | remove |
| cancelled | 已停止 | 已停止 | none | remove |
| emptyReply | 生成失败 | 模型返回了空回复 | openConversation / 查看详情 | retainError |
| failed | 生成失败 | allowlist 安全摘要 | openConversation / 查看详情 | retainError |
| persistenceFailed | 结果保存失败 | 回复结果未能保存，请打开应用查看 | openConversation / 查看详情 | retainError |

ongoing public 固定为标题“正在生成”、正文“请打开应用查看进度”；retain-error public 固定为标题“生成失败”、正文“请打开应用查看”。remove payload 只为保持类型完整，Kotlin 不显示其 title/text。

错误摘要器只能从类型和安全元数据分类：

```dart
String summarizeChatGenerationNotificationError(ChatGenerationOutcome outcome) {
  if (outcome is ChatGenerationEmptyReply) return '模型返回了空回复';
  if (outcome is ChatGenerationPersistenceFailure) {
    return '回复结果未能保存，请打开应用查看';
  }
  if (outcome is! ChatGenerationFailure) {
    return '生成失败，请打开应用查看详情';
  }

  final error = outcome.error;
  if (error == ChatErrorMessages.outputRuleEmptied) return '输出处理失败';
  if (error is TimeoutException ||
      (error is ChatGenerationException && error.cause is TimeoutException)) {
    return '请求超时';
  }
  if (error is SocketException ||
      (error is ChatGenerationException && error.cause is SocketException)) {
    return '网络不可达';
  }
  if (error is ChatGenerationException) {
    return switch (error.statusCode) {
      401 => '认证失败',
      403 => '请求被拒绝',
      429 => '请求过于频繁',
      final code? when code >= 500 && code <= 599 => '服务暂时不可用',
      _ => '生成失败，请打开应用查看详情',
    };
  }
  return '生成失败，请打开应用查看详情';
}
```

禁止通过 `error.toString()`、`responseBody`、`apiErrorCode`、`uri` 或 message substring 构造通知文案。

### 1.3 MethodChannel protocol

channel name 固定为 `yuzu.shiki.oh_my_llm/chat_generation_foreground_service`。

Dart -> Kotlin 方法：

```text
ensureNotificationPermission
startForegroundGeneration
updateForegroundGeneration
removeForegroundGeneration
failForegroundGeneration
takePendingOpenConversation
```

Kotlin -> Dart 方法：

```text
stopRequested
openConversationRequested
foregroundServiceTimedOut
```

Kotlin -> Dart 的有效 callback 返回 `true`，表示 adapter 已完成类型校验并把 action 加入 stream；malformed/unknown callback 返回 `false`。Service 只有在 stop callback 得到 `true` 时才等待 Dart terminal，否则立即做原生幂等清理。open callback 返回 `false` 或 engine 不存在时，Kotlin 把 conversation ID 放入 cold-start pending slot；timeout callback 是 Service 已停止后的 best-effort 通知，不等待 Dart 返回。

MethodChannel payload key 固定为 camelCase：

```text
token, conversationId, title, text, publicTitle, publicText,
actionKind, actionLabel
```

`commandId` 只存在于 Kotlin Channel -> Service 的显式 Intent 内部协议，由 Channel 生成；Dart 不生成、发送或解释 command ID。

`actionKind` 只接受 `none`、`stop`、`openConversation`。命令结果固定为 `{'accepted': true}` 或 `{'accepted': false, 'failureCode': '<enum-name>'}`；permission 结果固定为 `{'status': '<enum-name>'}`。缺字段、错类型、非正 token、空白 conversation ID、未知 action/method 必须 typed reject 或 `notImplemented`，不能强转崩溃。

---

### Task 1: Implement the Application Port and Pure Notification Projector

**Files:**
- Create: `lib/features/chat/application/ports/chat_generation_foreground_service.dart`
- Create: `lib/features/chat/application/generation/chat_generation_notification.dart`
- Create: `test/features/chat/application/generation/chat_generation_notification_test.dart`

**Interfaces:**
- Consumes: `ChatGenerationSnapshot`, `ChatGenerationOutcome`, `ChatStreamingReply`, `ChatGenerationException`, `ChatErrorMessages`, `characters`.
- Produces: Section 1.1 port types and Section 1.2 projector types consumed by every later task.

- [ ] **Step 1: Write failing projector and privacy tests**

  Add parameterized tests for every `ChatGenerationPhase`, action kind, terminal behavior and exact Chinese copy. Construct snapshots directly and use existing typed outcomes; do not hand-roll dynamic JSON.

  Include this Unicode contract:

  ```dart
  test('正文与推理分别按 Unicode 字符簇计数', () {
    const reply = ChatStreamingReply(
      conversationId: 'conv-1',
      assistantMessageId: 'assistant-1',
      content: '你👨‍👩‍👧‍👦e\u0301',
      reasoningContent: '🤔好',
    );
    final projection = const ChatGenerationNotificationProjector().project(
      snapshot: _snapshot(ChatGenerationPhase.streaming),
      streamingReply: reply,
    );

    expect(projection.counts, const ChatGenerationCharacterCounts(
      content: 3,
      reasoning: 2,
    ));
    expect(projection.payload.text, '正文 3 字 · 推理 2 字');
  });
  ```

  Add a table-driven error test containing `ChatGenerationException` values with status 401/403/429/500/599, `TimeoutException`, `SocketException`, output-rule sentinel, persistence failure and an unknown exception whose text contains `Authorization: secret`, `https://private.example/v1`, prompt text and stack-like lines. Assert only the exact allowlist copy appears and every secret fragment is absent from title/text/public fields.

  Add 49-grapheme title and 121-grapheme text cases; expect length 48/120 and final `…`. Verify `finalizing` with `streamingReply == null` uses provided `fallbackCounts`.

- [ ] **Step 2: Run the focused test and capture red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/features/chat/application/generation/chat_generation_notification_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-projector-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-projector-red.log
  ```

  Expected: non-zero because the new port/projector files or symbols do not exist.

- [ ] **Step 3: Implement the port types and minimal pure projector**

  Implement Section 1 exactly. Use `dart:async`, `dart:io` and `package:characters/characters.dart`; truncation must be:

  ```dart
  String _truncate(String value, int maxCharacters) {
    final graphemes = value.characters;
    if (graphemes.length <= maxCharacters) return value;
    return '${graphemes.take(maxCharacters - 1)}…';
  }
  ```

  Never read Providers, start timers or invoke the port from the projector. `idle` is not emitted during an active run; make `project()` reject it with `ArgumentError.value(snapshot.phase)` so an accidental idle projection cannot start a Service.

- [ ] **Step 4: Format, run green, stage-check and commit**

  ```powershell
  dart format lib/features/chat/application/ports/chat_generation_foreground_service.dart lib/features/chat/application/generation/chat_generation_notification.dart test/features/chat/application/generation/chat_generation_notification_test.dart
  flutter test test/features/chat/application/generation/chat_generation_notification_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-projector-green.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-projector-green.log
  if ($TestExit -ne 0) { exit $TestExit }
  git add lib/features/chat/application/ports/chat_generation_foreground_service.dart lib/features/chat/application/generation/chat_generation_notification.dart test/features/chat/application/generation/chat_generation_notification_test.dart
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  dart format --output=none --set-exit-if-changed $StagedDartFiles
  git commit -m "feat(chat): 定义生成通知投影与平台端口"
  ```

---

### Task 2: Implement the Serialized Notification Coordinator

**Files:**
- Create: `lib/app/composition/chat_generation_notification_coordinator.dart`
- Create: `test/app/composition/chat_generation_notification_coordinator_test.dart`

**Interfaces:**
- Consumes: Task 1 port/projector; `ChatGenerationSnapshot?`, `ChatStreamingReply?`; injected `stopGeneration`, `openConversation`, clock/timer and fixed-category diagnostic callbacks.
- Produces: `ChatGenerationNotificationCoordinator.onStateChanged({required ChatGenerationSnapshot? snapshot, required ChatStreamingReply? streamingReply})`, `start()`, `dispose()` and deterministic command ordering used by Task 4 composition.

- [ ] **Step 1: Define deterministic test fakes and write failing behavior tests**

  In the test file create:

  ```dart
  final class FakeChatGenerationForegroundService
      implements ChatGenerationForegroundServicePort {
    final actionsController =
        StreamController<ChatGenerationForegroundAction>.broadcast();
    final calls = <String>[];
    final payloads = <ChatGenerationForegroundPayload>[];
    final queuedResults = Queue<Future<ChatForegroundCommandResult>>();

    @override
    Stream<ChatGenerationForegroundAction> get actions =>
        actionsController.stream;

    Future<ChatForegroundCommandResult> _record(
      String name,
      ChatGenerationForegroundPayload? payload,
    ) {
      calls.add(name);
      if (payload != null) payloads.add(payload);
      return queuedResults.isEmpty
          ? Future.value(const ChatForegroundCommandResult.accepted())
          : queuedResults.removeFirst();
    }
  }
  ```

  Complete every interface method explicitly; `dispose()` closes the action controller only in test teardown. Use `fakeAsync` or an injected manual timer scheduler—never `Future.delayed`.

  Tests must prove:

  - preparing queues permission and start immediately;
  - same-phase streaming updates coalesce trailing-edge to at most once per second;
  - phase/attempt changes cancel pending trailing timer and enqueue immediately;
  - finalizing retains last non-null counts;
  - a blocked start Future forces update then terminal to wait, proving no stop-before-start;
  - old token timers, actions, Futures and terminals cannot affect a new token;
  - duplicate valid stop actions call `stopGeneration` once;
  - stop action does not call remove itself; only later terminal snapshot does;
  - start/update failure marks the token unavailable without changing input snapshot or invoking stop;
  - start/update failure 后 terminal 仍尝试 bounded remove/fail cleanup，不因 unavailable 提前跳过；
  - 一个 token start 失败后不自动重试，同一 coordinator 中下一新 token 仍可重新 start；
  - timeout suppresses later streaming update and does not restart;
  - timeout followed by success/cancel calls remove; timeout followed by failure calls fail;
  - terminal ACK failure retries exactly 3 times at 200ms and 800ms, then stops scheduling;
  - dispose cancels timer/subscription and late completions are ignored.

- [ ] **Step 2: Run the coordinator test and capture red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/app/composition/chat_generation_notification_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-coordinator-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-coordinator-red.log
  ```

- [ ] **Step 3: Implement a pure orchestration object with explicit lifecycle**

  Public constructor and entrypoints:

  ```dart
  typedef ChatNotificationTimerFactory = Timer Function(
    Duration duration,
    void Function() callback,
  );

  final class ChatGenerationNotificationCoordinator {
    ChatGenerationNotificationCoordinator({
      required ChatGenerationForegroundServicePort port,
      required Future<void> Function() stopGeneration,
      required void Function(String conversationId) openConversation,
      ChatGenerationNotificationProjector projector =
          const ChatGenerationNotificationProjector(),
      DateTime Function()? now,
      ChatNotificationTimerFactory? timerFactory,
      void Function(String category)? logDiagnostic,
    });

    Future<void> start();

    void onStateChanged({
      required ChatGenerationSnapshot? snapshot,
      required ChatStreamingReply? streamingReply,
    });

    void dispose();
  }
  ```

  Use these constants:

  ```dart
  const chatGenerationNotificationUpdateInterval = Duration(seconds: 1);
  const chatGenerationNotificationCleanupRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 200),
    Duration(milliseconds: 800),
  ];
  ```

  The coordinator owns `_tail = Future<void>.value()`. `_enqueue()` must always repair the tail after an error so one platform failure cannot poison later terminal cleanup:

  ```dart
  void _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
  }
  ```

  Diagnostics accept fixed categories only, for example `permission_unavailable`, `start_not_allowed`, `command_timeout`, `stale_native_action`, `cleanup_retry_exhausted`; never interpolate payload, exception, title, text or conversation ID.

  `start()` synchronously subscribes to `port.actions` before its first `await`, then calls `takePendingOpenConversation()` once. `onStateChanged(snapshot: null)` performs no command. A new positive generation ID resets per-token notification delivery state only after rejecting old timers/Futures via captured-token checks.

- [ ] **Step 4: Run green, format and commit**

  ```powershell
  dart format lib/app/composition/chat_generation_notification_coordinator.dart test/app/composition/chat_generation_notification_coordinator_test.dart
  flutter test test/app/composition/chat_generation_notification_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-coordinator-green.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-coordinator-green.log
  if ($TestExit -ne 0) { exit $TestExit }
  git add lib/app/composition/chat_generation_notification_coordinator.dart test/app/composition/chat_generation_notification_coordinator_test.dart
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  dart format --output=none --set-exit-if-changed $StagedDartFiles
  git commit -m "feat(chat): 编排生成通知生命周期"
  ```

---

### Task 3: Implement Android MethodChannel and Non-Android Adapters

**Files:**
- Create: `lib/app/platform/android_chat_generation_foreground_service.dart`
- Create: `lib/app/platform/noop_chat_generation_foreground_service.dart`
- Create: `test/app/platform/android_chat_generation_foreground_service_test.dart`
- Create: `test/app/platform/noop_chat_generation_foreground_service_test.dart`

**Interfaces:**
- Consumes: Task 1 port contracts and Section 1.3 channel protocol.
- Produces: concrete adapter classes and strict payload codec consumed by Task 4 platform selector and Task 5 Kotlin channel.

- [ ] **Step 1: Write failing binary messenger codec tests**

  Use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler()` on a test-only MethodChannel with the production channel name. Assert exact method names and maps for start/update/remove/fail, including `int token`, all text fields, `actionKind.name` and nullable action label.

  Install a Dart handler and invoke native callbacks through `handlePlatformMessage` / the paired test MethodChannel. Tests must cover:

  - valid stop, open and timeout callbacks emit the exact typed action once;
  - valid callbacks return `true`; malformed/unknown callbacks return `false` and emit nothing;
  - missing token, token `0`, `double` token, blank conversation ID, unknown method and unknown action are ignored without throwing;
  - `PlatformException`, `MissingPluginException` and a never-completing invoke map to typed failure, not thrown generation errors;
  - `takePendingOpenConversation` accepts a non-blank String and turns null/blank/wrong type into null;
  - `dispose()` removes the MethodCallHandler and closes the stream once.

  Noop tests assert every command returns `unsupportedPlatform`, permission returns `notRequired`, pending ID is null and actions never emit.

- [ ] **Step 2: Capture adapter red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/app/platform/android_chat_generation_foreground_service_test.dart test/app/platform/noop_chat_generation_foreground_service_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-adapter-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-adapter-red.log
  ```

- [ ] **Step 3: Implement the strict adapter and 2-second invoke boundary**

  Constructor injection must allow tests to pass their own channel and timeout:

  ```dart
  const chatGenerationForegroundChannelTimeout = Duration(seconds: 2);

  final class AndroidChatGenerationForegroundService
      implements ChatGenerationForegroundServicePort {
    AndroidChatGenerationForegroundService({
      MethodChannel? channel,
      Duration commandTimeout = chatGenerationForegroundChannelTimeout,
    }) : _channel = channel ?? const MethodChannel(
           'yuzu.shiki.oh_my_llm/chat_generation_foreground_service',
         ),
         _commandTimeout = commandTimeout {
      _channel.setMethodCallHandler(_handleNativeMethod);
    }
  }
  ```

  Encode payloads with one private `_encodePayload()` and decode results only after `value is Map`. Never cast a dynamic map wholesale. `_invokeCommand` catches platform/missing-plugin/timeout/other exceptions and returns fixed failure codes; it does not log exception text.

  Noop must be a real class in app/platform, not conditional imports in feature application.

- [ ] **Step 4: Format, run green and commit**

  ```powershell
  dart format lib/app/platform/android_chat_generation_foreground_service.dart lib/app/platform/noop_chat_generation_foreground_service.dart test/app/platform/android_chat_generation_foreground_service_test.dart test/app/platform/noop_chat_generation_foreground_service_test.dart
  flutter test test/app/platform/android_chat_generation_foreground_service_test.dart test/app/platform/noop_chat_generation_foreground_service_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-adapter-green.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-adapter-green.log
  if ($TestExit -ne 0) { exit $TestExit }
  git add lib/app/platform/android_chat_generation_foreground_service.dart lib/app/platform/noop_chat_generation_foreground_service.dart test/app/platform/android_chat_generation_foreground_service_test.dart test/app/platform/noop_chat_generation_foreground_service_test.dart
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  dart format --output=none --set-exit-if-changed $StagedDartFiles
  git commit -m "feat(android): 实现生成前台服务通道适配"
  ```

---

### Task 4: Wire Root Composition, Durable Stop and Serializable Navigation

**Files:**
- Create: `lib/app/composition/chat_generation_foreground_service_bindings.dart`
- Create: `test/app/composition/chat_generation_foreground_service_bindings_test.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart:57-176`
- Modify: `lib/app/app.dart:21-44`
- Modify: `lib/bootstrap.dart:38-74`
- Modify: `lib/app/navigation/app_destination.dart:55-64`
- Modify: `lib/app/router/app_router.dart:21-47`
- Modify: `lib/features/chat/presentation/chat_screen.dart:14-121`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/features/chat/presentation/chat_screen_test.dart` and the appropriate existing `chat_screen/*_cases.dart`
- Modify: `test/helpers/test_harness.dart:30-174`
- Modify: `test/integration/bootstrap_integration_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3 and existing `chatSessionsProvider`, `appRouterProvider`, `ChatSessionsController.stopStreaming()`.
- Produces: production Android/no-op binding; eager root provider; `/chat?conversationId=` navigation contract.

- [ ] **Step 1: Write failing platform selection, eager lifecycle and route tests**

  `chat_generation_foreground_service_bindings_test.dart` must call a pure selector:

  ```dart
  ChatGenerationForegroundServicePort createChatGenerationForegroundService({
    required TargetPlatform platform,
    AndroidChatGenerationForegroundService Function()? androidFactory,
  });
  ```

  Assert Android invokes the injected factory once; Windows, Linux, macOS, iOS and Fuchsia return noop and never create Android adapter.

  Add an eager composition test with a fake port override and `OhMyLlmApp`; override `appRouterProvider` with a router whose initial location is `/settings`, so `ChatScreen` is genuinely not mounted. Starting a generation through `chatSessionsProvider.notifier` must still make the preparing snapshot record `start`. Unmounting the root must dispose the coordinator and port exactly once.

  Add router/widget cases:

  - initial `/chat?conversationId=<existing>` selects that conversation after a post-frame callback;
  - changing only the query to a second existing ID applies via `didUpdateWidget`;
  - blank/deleted IDs leave the default conversation and show no dialog/SnackBar/error text;
  - route URI contains encoded Unicode/special-character ID and `state.extra` is never used.

  Add a composition stop test where fake port emits `ChatGenerationStopRequested` for the active token and a fake stop callback is observed once; stale/duplicate token is ignored.

- [ ] **Step 2: Capture composition/navigation red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/app/composition/chat_generation_foreground_service_bindings_test.dart test/app/router/app_router_test.dart test/features/chat/presentation/chat_screen_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-composition-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-composition-red.log
  ```

- [ ] **Step 3: Add production binding and eager coordinator provider**

  `appCompositionOverrides()` gains `TargetPlatform? hostPlatform` and an override exclusion switch, then binds the port exactly once:

  ```dart
  List<dynamic> appCompositionOverrides({
    bool useInMemorySyncSecureStore = false,
    bool bindChatGenerationClient = true,
    bool bindChatConversationRepository = true,
    bool bindMediaLibraryFactory = true,
    bool bindChatGenerationForegroundService = true,
    TargetPlatform? hostPlatform,
  }) {
    final effectivePlatform = hostPlatform ?? defaultTargetPlatform;
    return [
      if (bindChatGenerationForegroundService)
        chatGenerationForegroundServiceProvider.overrideWith((ref) {
          final port = createChatGenerationForegroundService(
            platform: effectivePlatform,
          );
          ref.onDispose(port.dispose);
          return port;
        }),
    ];
  }
  ```

  Merge this entry into the existing returned overrides; do not replace other composition bindings. `bootstrap()` passes its existing `effectivePlatform`; test harness passes `TargetPlatform.windows` explicitly so host CI never opens a real Android channel. Tests that inject a fake foreground port pass `bindChatGenerationForegroundService: false`, matching the repository's existing duplicate-override exclusion pattern.

  Define `chatGenerationNotificationCoordinatorProvider` in the coordinator file. It reads the port, calls `start()`, listens to this narrow projection, and disposes:

  ```dart
  final chatGenerationNotificationCoordinatorProvider =
      Provider<ChatGenerationNotificationCoordinator>((ref) {
        final coordinator = ChatGenerationNotificationCoordinator(
          port: ref.watch(chatGenerationForegroundServiceProvider),
          stopGeneration: () async {
            await ref.read(chatSessionsProvider.notifier).stopStreaming();
          },
          openConversation: (conversationId) {
            ref.read(appRouterProvider).goNamed(
              AppDestination.chat.name,
              queryParameters: {
                AppRouteParameter.conversationId: conversationId,
              },
            );
          },
          logDiagnostic: (category) {
            debugPrint('[chat-generation-fgs] $category');
          },
        );
        unawaited(coordinator.start());
        ref.listen(
          chatSessionsProvider.select(
            (state) => (state.generation, state.streamingReply),
          ),
          (previous, next) => coordinator.onStateChanged(
            snapshot: next.$1,
            streamingReply: next.$2,
          ),
          fireImmediately: true,
        );
        ref.onDispose(coordinator.dispose);
        return coordinator;
      });
  ```

  The coordinator file imports `dart:async` for `unawaited`, `Timer` and `StreamSubscription`; no fire-and-forget Future may be left as a bare expression.

  `OhMyLlmApp.build()` eagerly `ref.watch(chatGenerationNotificationCoordinatorProvider)` beside the existing custom header root watch.

- [ ] **Step 4: Add serializable chat navigation consumption**

  Add `AppRouteParameter.conversationId = 'conversationId'`. The chat route builder passes the query only:

  ```dart
  builder: (context, state) => ChatScreen(
    initialConversationId:
        state.uri.queryParameters[AppRouteParameter.conversationId],
  ),
  ```

  `ChatScreen` adds an optional final `initialConversationId`. In `initState` and `didUpdateWidget`, schedule one post-frame selection only when the trimmed ID is non-empty and changed. The callback checks `mounted` and calls existing `selectConversation(id)`; invalid IDs already no-op. Do not add visible recovery UI or persist the query parameter.

- [ ] **Step 5: Run focused green, architecture gate and commit**

  ```powershell
  $DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
  dart format $DartFiles
  flutter test test/app/composition/chat_generation_foreground_service_bindings_test.dart test/app/composition/chat_generation_notification_coordinator_test.dart test/app/router/app_router_test.dart test/features/chat/presentation/chat_screen_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-composition-green.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-composition-green.log
  if ($TestExit -ne 0) { exit $TestExit }
  dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-boundaries.log
  $BoundaryExit = $LASTEXITCODE
  Write-Host "EXIT=$BoundaryExit"
  Get-Content -Tail 150 logs/chat-fgs-boundaries.log
  if ($BoundaryExit -ne 0) { exit $BoundaryExit }
  git add lib/app/app.dart lib/app/composition/chat_generation_notification_coordinator.dart lib/app/composition/chat_generation_foreground_service_bindings.dart lib/app/composition/cross_feature_bindings.dart lib/app/navigation/app_destination.dart lib/app/router/app_router.dart lib/bootstrap.dart lib/features/chat/presentation/chat_screen.dart test/app/composition/chat_generation_foreground_service_bindings_test.dart test/app/router/app_router_test.dart test/features/chat/presentation/chat_screen_test.dart test/features/chat/presentation/chat_screen test/helpers/test_harness.dart test/integration/bootstrap_integration_test.dart
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  dart format --output=none --set-exit-if-changed $StagedDartFiles
  git commit -m "feat(chat): 在应用根部绑定生成通知"
  ```

---

### Task 5: Implement the Native Android Service, Channel and Notification

**Files:**
- Create: `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocol.kt`
- Create: `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundService.kt`
- Create: `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundChannel.kt`
- Create: `android/app/src/test/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocolTest.kt`
- Create: `android/app/src/main/res/drawable/ic_chat_generation.xml`
- Create: `android/app/src/main/res/values/chat_generation_strings.xml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/MainActivity.kt`

**Interfaces:**
- Consumes: Section 1.3 channel protocol and Task 3 Dart adapter.
- Produces: real `dataSync` foreground Service, dynamic/private/public notifications, native permission flow, command ACK and notification actions.

- [ ] **Step 1: Add minimal JVM test dependencies and write failing pure Kotlin protocol tests**

  Add only:

  ```kotlin
  dependencies {
      implementation("androidx.core:core:1.17.0")
      testImplementation("junit:junit:4.13.2")
  }
  ```

  Do not add Robolectric or instrumentation dependencies.

  `ChatGenerationForegroundProtocolTest.kt` must cover positive Long tokens, blank conversation IDs, unknown action kinds, duplicate start, stale update, current terminal, old terminal after a replacement and malformed map values. The pure guard contract is:

  ```kotlin
  internal enum class TokenDecision { ACCEPTED, STALE, MALFORMED }

  internal class ActiveGenerationTokenGuard {
      var activeToken: Long? = null
          private set

      fun start(token: Long): TokenDecision
      fun accepts(token: Long): TokenDecision
      fun finish(token: Long): TokenDecision
      fun clear()
  }

  internal class TimedOutNotificationGuard {
      fun record(token: Long, conversationId: String): TokenDecision
      fun matches(token: Long, conversationId: String): Boolean
      fun clear()
  }
  ```

  A start is accepted only for a positive token when no different token is active; a duplicate same-token start is idempotently accepted; finish clears only the matching token. Timeout guard tests prove only the exact token + conversation pair can cancel/replace the ordinary timeout notification and that clear makes later terminal commands stale.

- [ ] **Step 2: Capture native red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  & .\android\gradlew.bat -p android :app:testDebugUnitTest 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-native-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-native-red.log
  ```

  Expected: non-zero because protocol/guard types are absent.

- [ ] **Step 3: Implement strict native protocol parsing and token guard**

  `ChatGenerationForegroundProtocol.kt` owns all channel names, method names, payload keys, command result maps, notification/channel IDs and action strings. Use:

  ```kotlin
  internal const val CHAT_GENERATION_CHANNEL =
      "yuzu.shiki.oh_my_llm/chat_generation_foreground_service"
  internal const val CHAT_GENERATION_NOTIFICATION_CHANNEL_ID = "chat_generation"
  internal const val CHAT_GENERATION_NOTIFICATION_ID = 4101

  internal sealed interface NotificationActionKind {
      data object None : NotificationActionKind
      data object Stop : NotificationActionKind
      data object OpenConversation : NotificationActionKind
  }
  ```

  Parse `Map<*, *>` field by field. Dart small ints may arrive as `Int` or `Long`; accept `Number.toLong()` only when the value is mathematically integral and positive. Reject Double fractions, booleans, blank IDs, blank titles/text and action-label mismatch. Never call `toString()` to coerce payload values.

- [ ] **Step 4: Add Manifest, icon and notification resources**

  Manifest additions are exact:

  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

  <service
      android:name=".ChatGenerationForegroundService"
      android:exported="false"
      android:foregroundServiceType="dataSync"
      android:stopWithTask="true" />
  ```

  `ic_chat_generation.xml` is the following white-only 24dp vector with transparent background, suitable for Android notification masking:

  ```xml
  <vector xmlns:android="http://schemas.android.com/apk/res/android"
      android:width="24dp"
      android:height="24dp"
      android:viewportWidth="24"
      android:viewportHeight="24">
      <path
          android:fillColor="#FFFFFFFF"
          android:pathData="M20,2H4C2.9,2 2,2.9 2,4v18l4,-4h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2zM20,16H6l-2,2V4h16v12z" />
  </vector>
  ```

  `chat_generation_strings.xml` is:

  ```xml
  <resources>
      <string name="chat_generation_notification_channel_name">聊天生成</string>
      <string name="chat_generation_notification_channel_description">聊天回复生成期间保持后台连接</string>
  </resources>
  ```

- [ ] **Step 5: Implement Service start/update/remove/fail and standard notifications**

  Service constants and lifecycle:

  ```kotlin
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
      handleStartCommand(intent, startId)
      return START_NOT_STICKY
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
      stopAndRemoveNotification()
      super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy() {
      clearActiveInstance(this)
      tokenGuard.clear()
      super.onDestroy()
  }
  ```

  `handleStartCommand` accepts only the explicit internal start action, parses payload and command ID, clears any previous timeout registry entry, establishes active instance/token, creates the low-importance channel, builds notification, then calls:

  ```kotlin
  ServiceCompat.startForeground(
      this,
      CHAT_GENERATION_NOTIFICATION_ID,
      notification,
      ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
  )
  ```

  Only after that succeeds may it send accepted ACK. The Channel catches `ForegroundServiceStartNotAllowedException` thrown by `ContextCompat.startForegroundService()` itself; the Service catches `SecurityException`, missing-type and other promotion/runtime failures from parsing or `ServiceCompat.startForeground()`. Both sides map to fixed failure codes and log only category + `Build.VERSION.SDK_INT`, never exception text or payload.

  The companion active instance dispatch methods are main-thread-only:

  ```kotlin
  fun update(payload: NativeNotificationPayload): NativeCommandResult
  fun removeOrResolveTimeout(
      context: Context,
      token: Long,
      conversationId: String,
  ): NativeCommandResult
  fun failOrResolveTimeout(
      context: Context,
      payload: NativeNotificationPayload,
  ): NativeCommandResult
  fun stopForEngineDetach(context: Context)
  ```

  update uses the same ID. Active-service remove uses `ServiceCompat.STOP_FOREGROUND_REMOVE` then `stopSelf()`. Active-service fail rebuilds the same ID as non-ongoing + auto-cancel, uses `STOP_FOREGROUND_DETACH`, posts through `NotificationManagerCompat`, clears active token, then `stopSelf()`.

  `removeOrResolveTimeout` / `failOrResolveTimeout` first try the active instance; if absent, they accept only a matching timeout registry entry. The former cancels notification ID 4101; the latter rebuilds the ordinary error notification from the already-safe Dart payload. Both clear the timeout registry and never call `startService()`.

  Build notifications with `NotificationCompat.Builder`, `setSmallIcon`, `setContentTitle`, `setContentText`, `setCategory(CATEGORY_PROGRESS)`, `setOnlyAlertOnce(true)`, `setSilent(true)`, `setOngoing(true)` during active phases, `setVisibility(VISIBILITY_PRIVATE)`, and a separate fixed-copy `publicVersion`. Use `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE` PendingIntents.

  Stop action targets the Service and carries token/conversation ID. Content/open action targets `MainActivity` and carries conversation ID. Do not put title/text/prompt/reply in either PendingIntent.

- [ ] **Step 6: Implement stop action and Android 15 timeout**

  A valid stop action must first replace the notification with fixed private text “正在停止并保存已有内容”, remove all actions, then emit `stopRequested`. If no current Dart channel accepts the event, remove the notification and stop the Service; Kotlin must not pretend a Dart durable save occurred.

  API 35 timeout implementation:

  ```kotlin
  override fun onTimeout(startId: Int, fgsType: Int) {
      val token = tokenGuard.activeToken
      val conversationId = activeConversationId
      showProtectionEndedNotificationBestEffort()
      if (token != null && conversationId != null) {
          registerTimedOutNotification(token, conversationId)
      }
      tokenGuard.clear()
      clearActiveInstance(this)
      stopSelf(startId)
      if (token != null && conversationId != null) {
          ChatGenerationForegroundChannel.emitTimedOut(token, conversationId)
      }
  }
  ```

  `showProtectionEndedNotificationBestEffort()` converts the same ID to a normal auto-cancel notification with public-safe copy “后台保护已结束，请打开应用查看”；it catches notification-permission/OEM failures and still reaches `stopSelf()`. `registerTimedOutNotification` stores only token + conversation ID in process memory; it stores no text or domain payload. A later matching success/cancel cancels this notification; a later matching failure replaces it.

- [ ] **Step 7: Implement native channel, permission persistence and Activity lifecycle**

  `ChatGenerationForegroundChannel` constructor receives `MainActivity` and `BinaryMessenger`. It registers the method handler, owns pending start results keyed by monotonically increasing native-only `commandId`, and exposes companion callbacks for Service ACK/events. Before starting, it generates the ID and inserts it into the explicit Service Intent. `dispose()` errors pending results with fixed `channelUnavailable`, clears handler/static channel reference and calls `ChatGenerationForegroundService.stopForEngineDetach(activity.applicationContext)`; that cleanup also cancels a matching timeout ordinary notification.

  Permission flow:

  ```kotlin
  private const val PERMISSION_PREFS = "chat_generation_notifications"
  private const val KEY_POST_NOTIFICATIONS_REQUESTED =
      "post_notifications_requested"
  private const val REQUEST_POST_NOTIFICATIONS = 4102
  ```

  API <33 returns `notRequired`; granted returns `granted`; persisted true + denied returns `skippedAlreadyRequested`; otherwise first reject as `unavailable` when Activity is finishing/destroyed or lacks window focus, then write true immediately before `ActivityCompat.requestPermissions`. Hold at most one pending MethodChannel result and finish it in `onRequestPermissionsResult`; Activity destruction returns `unavailable`.

  `MainActivity` keeps multicast behavior intact and adds only:

  ```kotlin
  private var chatGenerationChannel: ChatGenerationForegroundChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
      super.configureFlutterEngine(flutterEngine)
      // 现有 multicast channel 保持原样，不在本功能中重构。
      chatGenerationChannel = ChatGenerationForegroundChannel(
          activity = this,
          messenger = flutterEngine.dartExecutor.binaryMessenger,
      ).also { it.handleOpenConversationIntent(intent) }
  }

  override fun onNewIntent(intent: Intent) {
      super.onNewIntent(intent)
      setIntent(intent)
      chatGenerationChannel?.handleOpenConversationIntent(intent)
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
      chatGenerationChannel?.dispose()
      chatGenerationChannel = null
      super.cleanUpFlutterEngine(flutterEngine)
  }
  ```

  Forward `onRequestPermissionsResult` to the channel after calling `super`. Cold open IDs live in a companion pending slot and are consumed once by `takePendingOpenConversation`; duplicate `onNewIntent` does not deliver twice.

- [ ] **Step 8: Run native unit tests and Debug APK build**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  & .\android\gradlew.bat -p android :app:testDebugUnitTest 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-native-green.log
  $NativeTestExit = $LASTEXITCODE
  Write-Host "NATIVE_TEST_EXIT=$NativeTestExit"
  Get-Content -Tail 150 logs/chat-fgs-native-green.log
  if ($NativeTestExit -ne 0) { exit $NativeTestExit }
  flutter build apk --debug 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-build-debug.log
  $BuildExit = $LASTEXITCODE
  Write-Host "BUILD_EXIT=$BuildExit"
  Get-Content -Tail 150 logs/chat-fgs-build-debug.log
  if ($BuildExit -ne 0) { exit $BuildExit }
  ```

- [ ] **Step 9: Commit native platform implementation**

  ```powershell
  git add android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/MainActivity.kt android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocol.kt android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundService.kt android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundChannel.kt android/app/src/main/res/drawable/ic_chat_generation.xml android/app/src/main/res/values/chat_generation_strings.xml android/app/src/test/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundProtocolTest.kt
  git commit -m "feat(android): 添加聊天生成前台服务"
  ```

---

### Task 6: Add Cross-Layer Durable Stop and Failure Regression Coverage

**Files:**
- Create: `test/integration/chat_generation_notification_integration_test.dart`
- Modify only if an existing helper is missing the needed signal: `test/helpers/chat/controllable_chat_conversation_repository.dart`
- Modify only to strengthen an existing contract rather than duplicate it: `test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_stop_cases.dart`

**Interfaces:**
- Consumes: production Riverpod coordinator/provider wiring, fake platform port, existing fake generation client and controllable repository.
- Produces: deterministic proof that native stop enters the existing durable stop path and platform failure never changes chat outcome.

- [ ] **Step 1: Write the integration test before changing helpers**

  Build a real ProviderContainer with `appCompositionOverrides(hostPlatform: TargetPlatform.windows, bindChatGenerationClient: false, bindChatConversationRepository: false, bindChatGenerationForegroundService: false)`, then override the generation client, repository and foreground port with fakes. Eagerly read `chatGenerationNotificationCoordinatorProvider`, send a message through `chatSessionsProvider.notifier`, and wait on existing Completer signals.

  Required cases:

  1. emit content/reasoning, emit matching native stop, block stop-save ACK, assert Service calls contain `update`/stopping but no remove; release save, assert state terminal is cancelled, persisted conversation contains partial content/reasoning, then remove occurs;
  2. fail stop-save, assert phase `persistenceFailed`, inline persistence error remains the existing one, and port receives safe retain-error payload;
  3. queue start/update/remove platform failures, complete a normal generation, assert conversation/message/outcome/finishReason are identical to a control run and no extra assistant message is created;
  4. run one success/error/empty scenario through each existing Chat Completions, Responses and Anthropic fake routing path only where the current multi-protocol integration helper already supports it; do not duplicate parser unit tests.

  Tests must wait for fake port call signals and repository ACKs. Do not use arbitrary delay or unconditional `pumpAndSettle()`.

- [ ] **Step 2: Capture integration red evidence**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/integration/chat_generation_notification_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-integration-red.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-integration-red.log
  ```

  Expected: failure at the missing/incorrect cross-layer behavior, not merely a missing test fixture assertion. If Tasks 1-5 already make the new test green immediately, temporarily replace the coordinator stop callback with a no-op to capture deterministic red, restore it immediately, and record both logs.

- [ ] **Step 3: Make the smallest wiring/helper correction and run focused regression suites**

  Do not change `ChatGenerationRun`, protocol clients or repository behavior unless the new integration test proves a real contract break. Prefer strengthening the fake signal/helper rather than adding timing sleeps.

  ```powershell
  $DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
  if ($DartFiles) { dart format $DartFiles }
  flutter test test/integration/chat_generation_notification_integration_test.dart test/integration/chat_lifecycle_integration_test.dart test/integration/multi_protocol_chat_generation_integration_test.dart test/features/chat/application/generation test/features/chat/application/sessions/chat_sessions_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-integration-green.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/chat-fgs-integration-green.log
  if ($TestExit -ne 0) { exit $TestExit }
  ```

- [ ] **Step 4: Stage-check and commit regression coverage**

  ```powershell
  git add test/integration/chat_generation_notification_integration_test.dart test/helpers/chat/controllable_chat_conversation_repository.dart test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_stop_cases.dart
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  dart format --output=none --set-exit-if-changed $StagedDartFiles
  git commit -m "test(chat): 覆盖通知停止与平台降级链路"
  ```

  If the two optional existing files did not change, omit them from `git add`; do not create a no-op diff.

---

### Task 7: Complete Automated Gates and Android Device Smoke

**Files:**
- Create: `docs/testing/android-chat-generation-foreground-service-smoke.md`
- Modify only for checked results/pending reasons: `docs/testing/android-chat-generation-foreground-service-smoke.md`

**Interfaces:**
- Consumes: complete feature.
- Produces: reproducible automated evidence plus an honest device verification matrix.

- [ ] **Step 1: Create the device smoke runbook with exact reset commands**

  The document records device model, Android version/API, app version, timestamp and PASS/FAIL/PENDING for all 15 spec smoke cases. Include:

  ```powershell
  adb shell dumpsys activity services yuzu.shiki.oh_my_llm
  adb shell cmd activity stop-app yuzu.shiki.oh_my_llm
  adb shell am force-stop yuzu.shiki.oh_my_llm
  adb shell pm revoke yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
  adb shell pm grant yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
  ```

  For Android 15 timeout testing, first capture the old value, enable the compat flag, set a short duration only on the dedicated test device, and restore/delete the override in `finally`-style documented steps:

  ```powershell
  adb shell device_config get activity_manager data_sync_fgs_timeout_duration
  adb shell am compat enable FGS_INTRODUCE_TIME_LIMITS yuzu.shiki.oh_my_llm
  adb shell device_config put activity_manager data_sync_fgs_timeout_duration 60000
  adb shell device_config delete activity_manager data_sync_fgs_timeout_duration
  adb shell am compat disable FGS_INTRODUCE_TIME_LIMITS yuzu.shiki.oh_my_llm
  ```

  Never run the timeout override on the user's daily device. If no Android 15+ dedicated device is available, mark that row PENDING with the exact missing prerequisite.

- [ ] **Step 2: Run architecture, analyze and focused suites**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-boundaries-final.log
  $BoundaryExit = $LASTEXITCODE
  Write-Host "BOUNDARY_EXIT=$BoundaryExit"
  Get-Content -Tail 150 logs/chat-fgs-boundaries-final.log
  if ($BoundaryExit -ne 0) { exit $BoundaryExit }

  flutter analyze 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-analyze.log
  $AnalyzeExit = $LASTEXITCODE
  Write-Host "ANALYZE_EXIT=$AnalyzeExit"
  Get-Content -Tail 150 logs/chat-fgs-analyze.log
  if ($AnalyzeExit -ne 0) { exit $AnalyzeExit }

  flutter test test/features/chat test/app test/integration/chat_generation_notification_integration_test.dart test/integration/chat_lifecycle_integration_test.dart test/integration/multi_protocol_chat_generation_integration_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-focused.log
  $FocusedExit = $LASTEXITCODE
  Write-Host "FOCUSED_EXIT=$FocusedExit"
  Get-Content -Tail 150 logs/chat-fgs-focused.log
  if ($FocusedExit -ne 0) { exit $FocusedExit }
  ```

- [ ] **Step 3: Run the full redirected Flutter suite**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/fltest.log
  if ($TestExit -ne 0) { exit $TestExit }
  ```

  If startup stalls before cases begin, run `./scripts/kill-stale-test-processes.ps1` and rerun the exact redirected command.

- [ ] **Step 4: Build Debug and Release APKs**

  ```powershell
  flutter build apk --debug 2>&1 | Out-File -Encoding utf8 logs/chat-fgs-build-debug-final.log
  $DebugExit = $LASTEXITCODE
  Write-Host "DEBUG_EXIT=$DebugExit"
  Get-Content -Tail 150 logs/chat-fgs-build-debug-final.log
  if ($DebugExit -ne 0) { exit $DebugExit }

  flutter build apk --release 2>&1 | Out-File -Encoding utf8 logs/build-android.log
  $ReleaseExit = $LASTEXITCODE
  Write-Host "RELEASE_EXIT=$ReleaseExit"
  Get-Content -Tail 150 logs/build-android.log
  if ($ReleaseExit -ne 0) { exit $ReleaseExit }
  ```

- [ ] **Step 5: Execute and record the Android/Windows smoke matrix**

  On at least one Android 13+ physical device verify permission allow/deny, foreground/background/lock screen, one-second counts, stop/retry/terminal errors, notification navigation, task removal, `stop-app`, Doze exit, active/removed `dumpsys` Service and no repeated alert. On Android 15+ dedicated hardware also verify timeout if available.

  Run Windows once and verify no permission prompt, no MethodChannel error, normal generation success/stop/error and unchanged inline UI. Mark unavailable device-dependent rows PENDING; do not report them as pass.

- [ ] **Step 6: Stage format check, commit the smoke record and final status audit**

  ```powershell
  $ChangedDartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
  if ($ChangedDartFiles) { dart format $ChangedDartFiles }
  git add docs/testing/android-chat-generation-foreground-service-smoke.md
  $StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  if ($StagedDartFiles) {
    dart format --output=none --set-exit-if-changed $StagedDartFiles
  }
  git commit -m "docs(android): 记录生成前台服务验证"
  git status --short
  ```

  Expected final status: only ignored `logs/` / build artifacts may exist; no uncommitted source or test changes. Final handoff must list automated exits, device rows still PENDING, tested Android versions and the limitation that FGS lowers—not eliminates—process death risk.

---

## Final Acceptance Checklist

- [ ] Android user generation enters `preparing` and Service accepted ACK occurs after `startForeground`.
- [ ] Existing Dart run remains the only generation owner across stream/retry/stop/finalize/durable terminal.
- [ ] Ongoing notification phases, attempt and separate Unicode content/reasoning counts are correct.
- [ ] Streaming update rate is <=1/s; phase/attempt/terminal is immediate.
- [ ] Stop action is token-guarded, idempotent and waits for existing durable stop terminal before normal cleanup.
- [ ] Finalizing has no stop action and retains last known counts.
- [ ] Success/cancel remove; empty/failure/persistence failure retain only safe ordinary notification text.
- [ ] Public/private notifications and PendingIntents contain no prompt, generated text, reasoning, URL, credentials, raw body or exception text.
- [ ] Notification permission denial and every platform failure leave conversation, outcome, inline error and message tree semantics unchanged.
- [ ] Cold/warm notification taps route through serialized conversation ID; invalid/deleted ID safely opens default chat.
- [ ] Android 15 timeout stops Service in time, marks token unprotected and never restarts it in background.
- [ ] Task removal/engine detach/force stop leaves no orphan Service; no boot or automatic request restart exists.
- [ ] Windows uses noop without permission/channel calls or behavior changes.
- [ ] Projector/coordinator/adapter/composition/integration/native tests, chat/app suites, architecture gate, analyze, full Flutter suite and Debug/Release APK builds pass.
- [ ] Android real-device smoke results and PENDING items are recorded honestly.
