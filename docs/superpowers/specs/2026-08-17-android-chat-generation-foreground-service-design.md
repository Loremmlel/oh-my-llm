# Android 聊天生成前台服务与动态通知设计

**日期：** 2026-08-17
**状态：** 已批准
**范围：** Android 聊天生成期间的前台服务保护、动态通知、通知动作与失败降级

## 1. 背景

Oh My LLM 当前的聊天生成由 Dart 进程内的 `ChatGenerationCoordinator` / `ChatGenerationRun` 独占完整生命周期：prepare、stream、stop、retry、finalize 与 durable save 都经过显式 `ChatGenerationPhase` 和 `ChatGenerationOutcome`。实际 LLM 请求使用 Dart `package:http`，Chat Completions、Responses 与 Anthropic Messages 三种协议也都在现有 Dart data/application 边界内完成。

Android 应用进入后台后，普通 Flutter Activity 所在进程可能成为 cached process。即使用户把电池策略设为“不受限制”，该设置也不保证进程存活；系统仍可能限制 cached process 的执行时间，或在内存压力下杀死进程。现有 SSE 请求有时能在切换应用或锁屏后继续，只是进程尚未被回收，并非应用获得了系统级执行保障。

本功能不追求不可实现的“永不杀进程”。目标是在用户主动发起聊天生成后，以 Android 官方前台服务提升进程重要性，并用一条低打扰、可操作的动态通知向用户说明正在进行的工作。页面内既有聊天行为、错误卡、重试规则、协议路由和持久化契约保持不变。

Android 官方约束如下：

- 前台服务必须展示用户可感知的通知；
- Android 12+ 通常禁止应用在已经处于后台后任意补启动前台服务，因此服务必须在用户点击发送且 Activity 仍可见时启动；
- Android 14+ 要声明服务类型与对应权限；本场景使用 `dataSync`，其官方用途包含从云端获取和传输数据；
- Android 15+ 的 `dataSync` 前台服务在应用处于后台时受每 24 小时累计 6 小时限制；
- 前台服务只显著降低被杀概率，不保证在系统极端内存回收、用户强制停止或 OEM 额外策略下继续运行。

## 2. 已确认的产品决定

1. 允许聊天生成期间出现一条 Android 常驻通知；应用页面与聊天交互不增加新的可见控件。
2. 采用少量自有 Kotlin 代码实现前台服务和通知，不引入 `flutter_foreground_task`、`flutter_background_service` 等后台框架。
3. Kotlin 不发送 LLM 请求、不解析 SSE、不访问聊天 SQLite、不理解 Riverpod，也不建立第二套 generation 状态机。
4. `ChatGenerationRun` 继续是 generation 的唯一业务 owner；通知只是现有 lifecycle 的平台投影。
5. 前台服务从 `preparing` 开始，在 terminal durable save 完成后停止。
6. 通知展示阶段、attempt、正文字符数和推理字符数，但不显示 prompt、回复片段、API 地址或模型返回原文。
7. 准备、生成和重试等待期间提供“停止生成”；`finalizing` 期间不可取消。
8. 成功或用户停止后移除通知；最终失败、空回复或持久化失败时，把前台服务通知转换为普通、可划掉的错误通知。
9. 点击通知打开对应会话；路由只携带可序列化 conversation ID，不使用 `state.extra`。
10. Android 13+ 通知权限被拒绝时，聊天仍照常发送，前台服务仍按平台允许的方式启动；不把权限拒绝当作聊天错误。
11. 前台服务启动、更新或停止失败采用 fail-open，不得阻塞、取消或篡改聊天生成结果。
12. 从最近任务划掉应用视为用户明确关闭；不保留孤儿前台服务。
13. 不自动重新发送被进程死亡中断的 LLM 请求，避免重复计费和重复回复。
14. 第一阶段不引入第二个 FlutterEngine、后台 Dart Isolate、开机自启、精确闹钟或主动电池优化豁免。

## 3. 目标与非目标

### 3.1 目标

- 降低用户切换应用或锁屏后聊天生成被系统暂停或杀死的概率；
- 让用户通过系统通知了解当前生成阶段、重试次数和输出规模；
- 让通知“停止生成”复用既有、具备 durable save 的停止路径；
- 保持聊天 generation 的单一 owner、协议实现、重试策略和持久化时序不变；
- 平台能力失败时安全降级为现有普通进程内生成；
- 确保通知内容不会在通知栏或锁屏泄漏 prompt、回复正文、凭据、URL 或原始响应；
- 保持 Windows 行为完全不变；
- 对 Android 12～当前目标 SDK 的启动、权限、服务类型与超时约束做显式处理。

### 3.2 非目标

- 不承诺进程永不被杀；
- 不在进程死亡后恢复原 TCP/SSE 连接；
- 不自动重发中断请求；
- 不把聊天生成迁移到 Kotlin；
- 不新建后台 FlutterEngine 或后台 generation Isolate；
- 不给 Sync UDP/HTTP server、媒体播放或其他 feature 增加保活；
- 不增加应用内“后台生成”开关、状态条、SnackBar 或 Dialog；
- 不主动请求 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`；
- 不申请精确闹钟、开机广播或自启动权限；
- 不新增显式 partial wake lock / Wi-Fi lock；
- 不使用自定义 `RemoteViews`，保留 Android 标准通知样式与系统无障碍行为；
- 不在本设计中完成 Google Play Console 的前台服务用途申报或公开上架流程。

## 4. 方案比较与结论

### 4.1 自有薄 Kotlin 前台服务

Kotlin 只管理 `Service`、`NotificationChannel`、`NotificationCompat`、`PendingIntent` 和 MethodChannel。Dart 继续管理所有业务状态，通过窄平台协议发送已经格式化且脱敏的通知投影。

优点是依赖最少、通知与生命周期可精确控制，且不会把现有 generation ownership 拆成 UI isolate 与后台 task handler 两套。仓库已经在 `MainActivity.kt` 使用 Kotlin MethodChannel 管理 multicast lock，因此没有引入新技术栈。

该方案为批准方案。

### 4.2 `flutter_foreground_task`

该插件能够启动前台服务、动态更新通知、提供通知按钮和后台 `TaskHandler`。但它同时引入自己的后台 callback、通信 port 和 task lifecycle。当前聊天生成已经有严格的单一 owner，再引入一套 task handler 容易形成重复状态与处置竞态；本功能也不需要其开机恢复、周期任务或后台 Isolate 能力。

该方案不采用。

### 4.3 独立 FlutterEngine 或原生 Kotlin generation

Application-owned cached FlutterEngine 可以脱离 Activity 继续执行 Dart，完整原生实现也可以让 Service 直接持有网络任务。但两者都要求重做 bootstrap、插件注册、Riverpod、SQLite、HTTP client、协议路由和页面重连边界，明显超过“降低普通后台场景被杀概率”的目标。

该方案不采用；只有未来产品明确要求“从最近任务划掉后仍继续生成”时才重新评估。

## 5. 总体架构与依赖方向

```text
ChatGenerationRun / ChatSessionsState
              │ 唯一 generation lifecycle
              ▼
ChatGenerationNotificationProjector
              │ 纯通知投影，无平台调用
              ▼
ChatGenerationNotificationCoordinator
              │ 序列化命令、token guard、1s 节流
              ▼
ChatGenerationForegroundServicePort
              │ application-owned 窄端口
              ▼
AndroidChatGenerationForegroundServiceAdapter
              │ MethodChannel
              ▼
ChatGenerationForegroundService.kt
              │
              └── Android NotificationManager / PendingIntent
```

依赖规则如下：

1. `ChatGenerationRun`、协议 client 和 repository 不导入平台通知代码，也不为了通知增加第二套 phase 或终态；
2. projector 只读取 `ChatGenerationSnapshot`、`ChatStreamingReply` 和安全的终态信息，输出不可变通知 view model；
3. coordinator 只负责跨异步边界投递和平台动作回传，不决定 generation 的业务状态；
4. application port 不暴露 `BuildContext`、`MethodChannel`、Android `Service`、`Notification` 或 Kotlin 类型；
5. Android adapter 位于 app/platform，生产 composition 注入真实实现；Windows 与测试可以注入 no-op/fake；
6. Kotlin 接收的是已经本地化、截断和脱敏的字符串及计数，不解析 Dart domain JSON；
7. 通知 action 必须携带 generation token 与 conversation ID，Dart 再次校验后才接受；
8. 所有平台调用失败只影响通知保护，不反向改变 generation outcome。

## 6. Dart 组件职责

### 6.1 ChatGenerationForegroundServicePort

application-owned 窄端口表达以下能力：

- 查询并按需请求 Android 通知权限；
- 开始一次带唯一 token 的 foreground generation；
- 更新当前 token 的通知投影；
- 成功/取消时移除前台通知并停止服务；
- 失败时停止前台服务并留下普通错误通知；
- 暴露来自通知的 `stopRequested` / `openConversationRequested` 动作；
- 报告前台服务因平台超时或原生异常而不再可用。

端口方法返回可观察的成功/失败结果，但调用方不得把失败转换成聊天失败。

### 6.2 ChatGenerationNotificationProjector

projector 是纯函数，负责：

- 把 phase 映射为标题、正文、是否允许停止和终态通知策略；
- 用 `characters` 按 Unicode 字符簇分别统计正文与推理字符数；
- 生成 attempt / retry 文案；
- 对终态错误生成通知专用安全摘要；
- 输出锁屏 public text 与解锁后 private text；
- 对标题、正文和错误摘要应用固定长度上限。

projector 不读取 Provider、不调用平台、不持有 Timer，也不负责命令去重。

### 6.3 ChatGenerationNotificationCoordinator

app composition 在应用根部 eager 创建 coordinator，使其生命周期不依赖 ChatScreen 是否挂载。它通过 `ref.listen` 观察 generation snapshot 与 streaming reply 的窄投影，并负责：

- `preparing` 第一次出现时立即请求启动前台服务；
- 对相同 token 的 streaming 更新按最多每秒一次投递；
- phase 变化、attempt 变化和 terminal 立即投递，不等待节流窗口；
- finalizing 时沿用最后一次已知字数，不把暂时清空的 UI streaming projection 误显示为 0；
- 以单一 Future tail 串行化 start/update/terminal，防止快速失败出现“先 stop 后 start”；
- 丢弃旧 token 的迟到 Future、迟到 native action 和迟到定时器；
- 收到一次有效 stop action 后进入 action-in-flight guard，重复 action 不重复调用 stop；
- 等现有 stop path 完成 durable save 并进入 terminal 后，才停止前台服务；
- 平台方法抛错时记录脱敏诊断并继续观察后续 terminal 清理；
- 当前 token 遇到 Android 前台服务超时后不在后台自动重启服务，并停止投递 ongoing 更新；
- terminal cleanup 必须等待 Kotlin 已接收命令的 ACK；ACK 失败时做有界重试，但不反向阻塞或改写已经完成的 generation outcome。

coordinator 持有的是通知投递瞬态，不是 generation 状态；其重建不得改变业务结果。

## 7. Kotlin 组件职责

### 7.1 ChatGenerationForegroundService

原生 Service 负责：

- 建立稳定的低打扰通知 channel；
- 在 Android 要求的时间窗口内调用 `ServiceCompat.startForeground()`；
- 使用固定非零 notification ID 更新同一条通知；
- 维护当前 active generation token，拒绝其他 token 的 update/terminal；
- 构造打开会话与停止生成的 `PendingIntent`；
- 在终态调用 `stopForeground` / `stopSelf`；
- 失败终态把同一 notification ID 转为普通、可划掉且 `autoCancel` 的错误通知；
- `onTaskRemoved` / `stopWithTask=true` 时停止自身并清理通知；
- Android 15+ `onTimeout` 中在系统期限内停止自身，并尽力报告 Dart 当前 token 已失去保护；
- 所有 Intent、action 与 payload 做类型和 token 校验，malformed 输入安全忽略。

Service 不持有 Activity 引用，不访问 Flutter Widget，也不缓存 API key、prompt、回复正文或错误响应体。

### 7.2 ChatGenerationForegroundChannel

平台桥接在 `MainActivity.configureFlutterEngine` 注册，复用当前 FlutterEngine 的 `BinaryMessenger`。它负责：

- 接收 Dart 的 permission/start/update/terminal 方法；
- 把 Service 的 stop action 与平台 timeout 事件发送给当前 Dart engine；
- Activity/engine detach 时清理 channel 引用，不能泄漏 Activity；
- cold-start 与 `onNewIntent` 时缓存并交付一次待处理的 conversation ID；
- 对 Flutter engine 不存在的 stop action，让 Service 只做原生幂等清理；不存在 engine 时也不存在仍可继续的当前 Dart generation。

不顺带重构现有 multicast lock channel；两者只共享 `MainActivity` 注册入口。

## 8. 通知状态与显示契约

| generation phase | 通知标题/正文 | 停止动作 | terminal 行为 |
|---|---|---|---|
| `preparing` | “正在准备请求” | “停止生成” | 保持前台服务 |
| `streaming` | “正在生成 · 第 N 次尝试”；“正文 X 字 · 推理 Y 字” | “停止生成” | 保持前台服务 |
| `retryWaiting` | “请求中断 · 正在等待第 N 次重试” | “停止重试” | 保持前台服务 |
| `stopping` | “正在停止并保存已有内容” | 禁用 | 保持前台服务直到 durable |
| `finalizing` | “已接收完成 · 正在保存结果” | 无 | 保持前台服务直到 durable |
| `succeeded` | 不再显示 | 无 | 移除通知并停止服务 |
| `cancelled` | 不再显示 | 无 | 移除通知并停止服务 |
| `emptyReply` | “生成失败”；“模型返回了空回复” | “查看详情” | 转普通错误通知 |
| `failed` | “生成失败”；安全摘要 | “查看详情” | 转普通错误通知 |
| `persistenceFailed` | “结果保存失败”；固定安全摘要 | “查看详情” | 转普通错误通知 |

显示规则：

- 使用标准 `NotificationCompat` 样式和应用专用单色 small icon；
- channel importance 为 low，`onlyAlertOnce`，流式更新不重复响铃、振动或点亮屏幕；
- ongoing 阶段不可由普通横划移除，terminal error 转为普通通知后可划掉；
- public/锁屏版本只显示“正在生成”或“生成失败，请打开应用查看”；
- private 版本才显示字数、attempt 和安全错误摘要；
- 不展示会话标题、模型名称、prompt、回复片段、reasoning 片段、provider host 或 URL；
- 字数按正文与推理分别显示，不把二者合并为一个含糊计数；
- 同一秒内累计多个 chunk 时只投递最后投影；phase/terminal 变化立即更新；
- 通知点击只导航到当前 conversation ID，不自动重新发送、重试或修改选中分支。

## 9. 通知动作与停止语义

“停止生成”必须复用现有停止契约：

1. Service 收到 notification action，校验 active token；
2. Service 立即把通知改为“正在停止”，移除按钮，防止重复点击；
3. Channel 向 Dart 发送 `stopRequested(token, conversationId)`；
4. coordinator 校验 token 仍是当前 active generation；
5. coordinator 调用现有 Chat application stop facade，最终进入 `ChatGenerationCoordinator.stop()`；
6. `ChatGenerationRun` 取消订阅/重试 timer，调用 host.stop 保存 partial snapshot；
7. stop save 成功或失败后进入唯一 terminal；
8. terminal snapshot 再驱动 Service remove/failure 通知。

Kotlin 不直接关闭 Dart HTTP client，也不在收到按钮时直接声称聊天已停止。若 action 重复、token 过期或 terminal 已发生，Dart 与 Kotlin 两侧都幂等忽略。

## 10. 生命周期矩阵

| 场景 | Flutter/Dart | Kotlin Service | 通知 |
|---|---|---|---|
| 正常前台生成 | 原 generation 运行 | 前台服务运行 | 动态更新 |
| 切换应用 | FlutterEngine 与 root isolate 继续 | 提高进程重要性 | 保持更新 |
| 锁屏 | 原 SSE best-effort 继续 | 前台服务运行 | public text 隐藏细节 |
| 回到应用 | 复用同一 run/state | 无需重启 | 点击/页面状态一致 |
| 正常成功 | terminal save 后完成 | stopForeground + stopSelf | 移除 |
| 用户通知停止 | 走现有 durable stop | 等 terminal 后停止 | 先“正在停止”，后移除 |
| 最终错误 | 现有 inline error 保留 | 停止前台服务 | 转普通安全错误通知 |
| 最近任务划掉 | Activity/engine 按现有宿主销毁 | `stopWithTask` 收口 | 移除，不自启 |
| Android 活跃应用中停止 | 进程被系统终止，无回调保证 | 同进程终止 | 系统移除 |
| 极端内存回收 | 进程与 SSE 终止 | 同进程终止 | 消失 |
| Android 15 dataSync 超时 | generation 可继续 best-effort，不自动重发 | `onTimeout` 必须及时 stopSelf | 转“后台保护已结束”普通通知（权限允许时） |
| 手机重启 | 不恢复 run | 不处理 BOOT_COMPLETED | 不恢复 |

第一阶段不使用 cached FlutterEngine。普通切后台和锁屏不会主动销毁当前 Activity engine；显式划掉任务则按用户关闭处理。若未来要支持 Activity 完全销毁后仍继续生成，应单独设计 Application-owned engine、bootstrap 单例、插件注册和数据库 ownership，不在本功能中隐式加入。

Android 15 timeout 后，coordinator 把当前 token 标记为“无前台保护”，不再向已停止的 Service 发送 streaming 更新，也不在后台尝试重新启动。若该 generation 随后成功或被用户取消，移除“后台保护已结束”普通通知；若随后业务失败，则用实际的安全错误摘要替换它。timeout 不伪造成 generation terminal。

## 11. 权限与平台兼容

Manifest 需要：

- `android.permission.FOREGROUND_SERVICE`；
- `android.permission.FOREGROUND_SERVICE_DATA_SYNC`；
- `android.permission.POST_NOTIFICATIONS`；
- `<service android:foregroundServiceType="dataSync" android:exported="false" android:stopWithTask="true">`。

权限流程：

1. Android 13+ 第一次已接受的 generation 进入 `preparing` 时，在 Activity 仍可见的窗口请求通知权限；
2. 权限请求不得成为发送前置条件，也不得等待用户决定后才启动网络；
3. 用户拒绝后不在每次发送时重复弹窗；
4. 被拒绝时继续启动前台服务，接受系统可能只在“活跃应用”区域显示其存在；
5. permission API 或 Activity 状态不允许请求时安全跳过，generation 不受影响。

前台服务启动：

- 只响应用户在可见 Activity 中发起 generation 后的 `preparing`；
- 不从后台广播、定时器、启动完成或普通网络回调首次启动；
- Android 12+ `ForegroundServiceStartNotAllowedException`、Android 14+ 类型/权限 `SecurityException` 以及 OEM 异常都转换为平台能力失败；
- start 失败后当前 generation 不循环重试 start，避免后台反复触发系统限制；下一次新的用户 generation 可以重新尝试。

## 12. 错误、隐私与日志

### 12.1 通知错误摘要

通知不能直接复用现有详细 inline `formatStreamingError()`。新增纯函数摘要器只输出允许名单：

- 网络不可达；
- 请求超时；
- HTTP 401：认证失败；
- HTTP 403：请求被拒绝；
- HTTP 429：请求过于频繁；
- HTTP 5xx：服务暂时不可用；
- 模型返回空回复；
- 输出处理失败；
- 结果保存失败；
- 未知错误：生成失败，请打开应用查看详情。

摘要不得包含：

- API key、Authorization、Cookie 或自定义 Header；
- request/response body；
- endpoint、host、完整 URL、文件路径；
- prompt、回复、reasoning 或会话标题；
- exception `toString()` 原文、stack trace、代码块；
- 任意未经过 allowlist 分类的厂商错误字段。

### 12.2 平台错误

- notification permission denied：不是错误，不写 inline message；
- start/update/stop channel failure：记录固定类别与 Android API level，不记录 payload；
- start/update 命令以 Kotlin ACK 作为“平台已接收”边界；terminal cleanup 的 ACK 失败执行有界重试，耗尽后只记录诊断，不改变聊天结果；
- malformed native action：忽略并记录固定类别；
- notification tap 的 conversation 不存在：正常打开应用默认 chat route，不弹错误；
- Service terminal 清理重复到达：幂等 no-op；
- Android 15 timeout：Service 先满足系统 stopSelf 时限，再 best-effort 告知 Dart；不得因等待 Dart durable save 而让系统抛 fatal exception。

现有聊天错误展示规则不变：错误仍以内联 assistant card 呈现，不新增 SnackBar 或错误 Dialog。

## 13. 并发、顺序与幂等

以下不变量必须同时成立：

1. 同一进程内 generation token 单调递增；所有平台消息都携带 token；
2. 同一时刻最多一个 active foreground generation，与 Chat controller busy guard 对齐；
3. start/update/terminal 经过单一 async tail 串行投递；
4. terminal 一旦投递，旧 token 后续 update 永久丢弃；
5. 新 generation start 可以替换已经完成的旧 token，但不能被旧 terminal 清理；
6. 每个 accepted stop action 最多调用一次 application stop；
7. notification stop 只有在 generation terminal 后才完成正常清理；
8. platform start 失败不会导致 update 队列无限累积；当前 token 标记为 unavailable，terminal 仍执行幂等 stop；
9. terminal cleanup 只有收到当前 token 的 Kotlin ACK 才算平台清理完成；重试有固定次数/总时限，不创建永久 timer；
10. permission result、MethodChannel result、Timer 和 native action 在 coordinator dispose 后不再写状态；
11. Kotlin 只接受当前 active token 的更新与终态，防止 Dart 迟到 Future 覆盖新通知。

这些 guard 属于通知投递一致性，不得演变为第二套 generation phase machine。

## 14. 测试设计

### 14.1 纯 Dart projector 单元测试

- 每个 `ChatGenerationPhase` 映射到唯一通知状态；
- preparing/streaming/retryWaiting/stopping/finalizing 的停止按钮规则；
- succeeded/cancelled remove，failed/emptyReply/persistenceFailed retain-error；
- 中文、emoji、组合字符与 surrogate pair 按 `characters` 计数；
- 正文与推理分别计数；
- public text 不包含私密细节；
- HTTP/timeout/network/persistence/unknown 错误映射到 allowlist；
- 原始 body、URL、Header、stack 字符串无法进入摘要；
- 标题和正文按固定上限截断。

### 14.2 Coordinator 单元测试

使用 fake port、fake clock/timer 与受控 generation state 验证：

- preparing 在网络 stream 监听前请求 start；
- 300ms UI chunk 投影被通知层合并为最多 1 秒一次；
- phase、attempt 与 terminal 立即更新；
- finalizing 保留最后字数；
- start/update/terminal 串行且不会 stop-before-start；
- 旧 token 的迟到 update/terminal/action 被丢弃；
- 重复 stop action 只触发一次现有 stop；
- stop 通知在 partial durable save 完成前保持“正在停止”；
- stop save 失败转持久化失败通知；
- platform start/update/stop 异常不改变 generation completion/outcome；
- terminal cleanup ACK 失败按有界策略重试，成功后停止，耗尽后不污染 generation；
- permission denied 仍启动 generation，且不重复请求；
- platform timeout 后当前 token 不自动重新 start；
- platform timeout 后不再投递 streaming update，后续业务 terminal 会移除或替换 timeout 通知；
- dispose 清理 timer/subscription，迟到回调无副作用。

测试不得使用任意 `Future.delayed`。节流使用 fake clock/timer；durable stop 使用受控 repository ACK/Completer。

### 14.3 MethodChannel adapter 测试

使用 `TestDefaultBinaryMessenger` 验证：

- permission/start/update/remove/fail 的精确方法名与 payload；
- token、conversation ID、title、text、public text、action 状态编码完整；
- native `stopRequested` / timeout / open-conversation 事件正确解码；
- 缺字段、错类型、未知方法安全忽略或返回 typed failure；
- channel 异常转换为端口失败，不向 generation controller 抛出；
- Windows/no-op adapter 不调用平台 channel。

### 14.4 Composition 与 generation 回归测试

- app composition eager 建立 coordinator，不依赖 ChatScreen 是否挂载；
- Android 选择真实 adapter，Windows 选择 no-op；
- 三种协议 client 的正常成功、错误、空回复与自动重试行为不变；
- 通知 action 经过现有 controller/coordinator stop，并保存部分内容；
- finalizing 与 persistence failure 继续遵守 generation busy/durable 不变量；
- 现有 inline error、停止消息、finishReason 和消息树分支语义不变；
- notification failure 不新增 assistant message、不覆盖 `errorMessage`。

### 14.5 Kotlin 与真实平台验证

仓库当前没有 Android `src/test` / `src/androidTest` 基础设施。实施计划应把可抽离的 token/payload/notification-state 判定保持为纯 Kotlin 或 Dart 并自动测试；Android framework 行为通过 debug APK + 真机 ADB smoke 验证。只有在实现中出现无法由 Dart/纯 Kotlin 覆盖的稳定原生缺陷时，才增加最小 instrumentation/Robolectric 基础设施，不为单个 Service 机械引入庞大测试栈。

## 15. Android 真机 smoke

至少在一台 Android 13+ 真机验证：

1. 首次通知权限允许：发送不中断，通知进入 ongoing；
2. 首次通知权限拒绝：发送仍继续，应用不重复弹权限；
3. 前台长流：正文/推理字符数约每秒更新且不重复响铃；
4. 切换到其他应用后完成流式请求；
5. 锁屏后继续并在解锁后看到正确状态；
6. 通知“停止生成”保存已有部分内容，重复点击无副作用；
7. 自动重试显示正确 attempt，停止重试走 durable stop；
8. 401、429、超时、空回复与持久化失败只显示允许名单摘要；
9. 点击 ongoing/error 通知进入正确 conversation；
10. 最近任务划掉后 Service 与 ongoing 通知消失且不自启；
11. `adb shell cmd activity stop-app yuzu.shiki.oh_my_llm` 后不自启；
12. 强制 Doze/锁屏场景退出后应用状态能够正常恢复；
13. `dumpsys activity services` 能看到 active generation 期间的 `dataSync` foreground service；
14. terminal 后 `dumpsys` 不再存在该 Service；
15. Windows 运行路径无通知权限请求、MethodChannel 调用或行为变化。

Android 15+ 可在专用测试设备上缩短 `data_sync_fgs_timeout_duration` 验证 `onTimeout`，但不得修改用户日常设备的全局参数；测试完成后必须恢复系统配置。

## 16. 预计文件边界

最终实施计划可以微调不影响职责的文件名，但不得改变以下 ownership：

| 位置 | 职责 |
|---|---|
| `lib/features/chat/application/ports/chat_generation_foreground_service.dart` | 平台无关端口、typed result 与 native action |
| `lib/features/chat/application/generation/chat_generation_notification.dart` | 纯通知 view model、phase projector、错误摘要 |
| `lib/app/composition/chat_generation_notification_coordinator.dart` | Provider 观察、节流、token guard、命令串行化、stop action 转发 |
| `lib/app/platform/android_chat_generation_foreground_service.dart` | MethodChannel adapter 与 Android payload codec |
| `lib/app/platform/noop_chat_generation_foreground_service.dart` | Windows/非 Android no-op |
| `lib/app/composition/cross_feature_bindings.dart` 或等价根 composition | 生产绑定与 eager coordinator 生命周期 |
| `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundService.kt` | Android Service、通知、action、timeout、token guard |
| `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationForegroundChannel.kt` | FlutterEngine channel 与 cold/warm intent 交付 |
| `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/MainActivity.kt` | 注册新 channel、转发 `onNewIntent`；保留 multicast lock 行为 |
| `android/app/src/main/AndroidManifest.xml` | 权限、service type 与 service 声明 |
| `android/app/src/main/res/drawable/ic_chat_generation.xml` | Android 标准单色通知 small icon |

测试按职责镜像放置，不把 projector、coordinator、adapter 和现有 generation controller 的全部 case 塞进同一个文件。

## 17. 验证门禁

实施完成前至少执行：

1. projector、coordinator、adapter 的定向单元测试；
2. notification stop 的 generation/controller 定向回归测试；
3. `test/features/chat`；
4. app composition/platform 相关测试；
5. `dart run tool/check_import_boundaries.dart`；
6. `flutter analyze`；
7. 全量 `flutter test --reporter compact`，按仓库要求重定向到 `logs/fltest.log`；
8. Android Debug APK build；
9. Android Release APK build；
10. 第 15 节真机 smoke，或逐项明确标记 pending。

所有测试、analyze 和 build 日志写入仓库 ignored 的 `logs/`。缺陷回归测试必须提供修复前失败、修复后通过的 red/green 证据。

本设计文档提交不改变 runtime，不要求运行 Flutter 测试；实现提交必须执行上述验证。

## 18. 验收标准

1. Android 用户发起 generation 后，在 `preparing` 阶段启动 `dataSync` 前台服务；
2. 切换应用或锁屏时，现有 Dart generation 继续由同一 `ChatGenerationRun` 驱动；
3. 通知准确显示 preparing、streaming、retryWaiting、stopping、finalizing 与终态语义；
4. streaming 正文/推理按 Unicode 字符簇分别计数，通知更新不超过每秒一次；
5. phase、attempt 与 terminal 更新不受一秒节流延迟；
6. 通知停止复用现有 durable stop，且重复/过期 token 无副作用；
7. finalizing 不提供停止动作；
8. success/cancel 移除通知，failure/empty/persistence failure 转安全普通通知；
9. 通知与锁屏不包含 prompt、回复片段、reasoning 片段、URL、凭据、原始 body 或 stack；
10. 点击通知通过 conversation ID 打开正确会话；
11. 通知权限拒绝或平台 Service 失败不阻断、不取消、不篡改 generation；
12. Android 15 timeout 能及时停止 Service，不触发系统 fatal timeout；
13. 最近任务划掉、用户强停和 terminal 后不留下孤儿前台服务；
14. 不自动恢复、重发或开机启动 generation；
15. 不引入第三方后台 service 插件、第二 FlutterEngine 或后台 generation Isolate；
16. Chat generation 仍只有一个 lifecycle owner，通知层只做投影与投递；
17. Windows 页面、权限、网络、通知和测试行为不变；
18. 定向测试、chat 测试、架构门禁、analyze、全量测试与 Android build 通过；
19. 真机 smoke 的完成与 pending 状态如实记录。

## 19. 风险与缓解

| 风险 | 缓解 |
|---|---|
| start/update/terminal 异步乱序留下错误通知 | coordinator 单一 Future tail + Dart/Kotlin 双侧 token guard |
| 通知按钮绕过 durable stop | Kotlin 只发 action；Dart 复用现有 coordinator.stop，terminal 后才清理 |
| 高频 chunk 造成 SystemUI 与电池压力 | UI 300ms 节流之外再做通知 1s trailing projection，phase 立即更新 |
| 锁屏泄漏对话或错误正文 | public/private text 分离，错误 allowlist，不显示会话标题和内容 |
| 权限或 OEM 异常反向破坏发送 | 所有平台能力 fail-open，generation outcome 不依赖通知结果 |
| terminal MethodChannel 失败留下孤儿通知 | Kotlin ACK + coordinator 有界 cleanup retry；任务移除和 Service 自身生命周期继续提供最终兜底 |
| Activity 被划掉后 Service 孤立 | `stopWithTask=true` + `onTaskRemoved` 幂等清理，不使用独立 engine |
| Android 15 dataSync timeout 导致进程异常 | 实现 `onTimeout`，先满足原生 stopSelf 时限，再 best-effort 通知 Dart |
| 新 port 污染 Chat generation 状态机 | Run/client/repository 不依赖 port；app composition 观察既有 snapshot |
| notification error 复用详细 inline formatter 泄密 | 独立通知摘要器，只允许固定类别，不接受原始异常文本 |
| MainActivity 新 channel 破坏 multicast lock | 不顺带重构旧 channel；分别测试注册、detach 与现有 lock 生命周期 |
| 用户误以为前台服务绝不被杀 | 文档与验收明确仅降低概率，强停/极端回收仍会终止 |

## 20. 设计完成定义

本设计完成并可进入实施计划的条件是：

- 前台服务、通知状态、权限、动作和 terminal 清理语义均明确；
- Dart generation、app composition、platform adapter 与 Kotlin Service 的 ownership 明确；
- 普通后台、锁屏、最近任务划掉、强停、进程死亡和 Android 15 timeout 均有明确行为；
- 通知隐私、错误 allowlist 和 fail-open 边界清晰；
- 自动化测试、真机 smoke、验证门禁与非目标明确；
- 文档没有占位符、矛盾状态、隐式自动重发或未经批准的 Sync 保活扩展。
