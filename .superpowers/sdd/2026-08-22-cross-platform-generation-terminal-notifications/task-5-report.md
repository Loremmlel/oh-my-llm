# Task 5 实施报告：Android Kotlin HIGH 终态通知与设置

- 状态：DONE
- 提交：`e5acd58bbf6ce492fca7af35529ecd2ec6803953` `feat(android): 增加生成终态高优先级通知`
- 分支：`feat/cross-platform-generation-notifications`
- 版本：post-commit hook 自动 bump 至 `3.77.0+0`（feat → minor+1，并回本次提交）

## 变更范围

重命名（不保留兼容文件，`git mv` 后内容重写）：

- `ChatGenerationForegroundProtocol.kt` → `ChatGenerationNotificationProtocol.kt`
- `ChatGenerationForegroundChannel.kt` → `ChatGenerationNotificationChannel.kt`
- `ChatGenerationForegroundProtocolTest.kt` → `ChatGenerationNotificationProtocolTest.kt`

新增：

- `android/app/src/main/kotlin/yuzu/shiki/oh_my_llm/ChatGenerationTerminalNotification.kt`
  - `chat_generation_result` 渠道幂等创建（API 26+，IMPORTANCE_HIGH + 默认通知声
    USAGE_NOTIFICATION + enableVibration；已有渠道绝不删除重建或升级 importance）；
  - `showTerminalNotification(context, request)`：private 文案 + 经
    `terminalPublicCopy()` 只取传入固定 publicTitle/publicBody 的 public version，
    同 small icon/category/contentIntent、visibility PUBLIC；
  - PendingIntent：request code 与 data URI（`oh-my-llm://generation-notification/<id>`）
    都由通知 ID 同源推导，extras 只携带原始 payload 字符串；
  - `showTimeoutFallback(context, savedPayload)`：自包含吞异常，固定文案
    「后台保护已结束 / 请打开应用查看生成状态」；
  - 设置纯决策：`resolveNotificationSettingsStatus()`、`appNotificationSettingsSpec()`、
    `shouldCreateTerminalChannel()`。
- `android/app/src/main/res/values/chat_generation_strings.xml` 新增终态渠道名
  「生成结果」与描述字符串。

修改：

- `ChatGenerationNotificationProtocol.kt`：
  - channel 名切到最终值 `yuzu.shiki.oh_my_llm/chat_generation_notifications`；
  - 方法表对齐计划 7.2 全部九个方法，新增 callback `notificationActivated`；
  - 删除 `METHOD_FAIL_FOREGROUND_GENERATION` 与 `TimedOutNotificationGuard`；
  - `NativeNotificationPayload` 增加 `timeoutActivationPayload` 必填字段，解析层只校验
    类型（非空 String）与长度（UTF-8 ≤ 1024 bytes），不解析 JSON 内容；
  - `NotificationActionKind` 收敛为 None/Stop（旧 LOW 终态 openConversation 动作随统一
    终态激活移除）；ongoing 点击直达走 content intent + `takePendingOpenConversation`，
    契约常量原样保留（action 字符串与 request code 4104 不变）;
  - 终态 ID 守卫 `parseTerminalNotificationId`：正 int 且 ≥ `MIN_TERMINAL_NOTIFICATION_ID`
    （10000，Dart FNV 契约下界），天然排除 ongoing 4101 / fallback 4200 槽位；
  - `isTimeoutAcceptedByDart`：只有严格 bool true 视为受理。
- `ChatGenerationNotificationChannel.kt`：
  - 新增四个命令处理：`showTerminalNotification`（解析失败/原生失败回 false）、
    `takePendingNotificationActivation`（单槽取走一次，应答 `{payload: <原始字符串>}`）、
    `getNotificationSettingsStatus`（先幂等建渠道；应答为裸字符串 enabled/disabled/
    unavailable）、`openNotificationSettings`（spec 只带当前 package +
    ACTION_APP_NOTIFICATION_SETTINGS + NEW_TASK，失败 false）；
  - `emitTimedOut` 重写为 `emitForegroundServiceTimedOut(token, conversationId,
    onNotAccepted)`：success 非 true / error / notImplemented / 无 instance 一律立即执行
    `onNotAccepted` 原生 fallback；
  - Intent 分发收敛为 `handleNotificationIntent()`：ongoing 打开会话与终态/fallback
    激活按 action 路由到互不重叠的两条窄路径；激活 payload 单槽缓存（后一次覆盖前一次）。
- `ChatGenerationForegroundService.kt`：
  - `onTimeout` 按 7.5 顺序重写：先移除 ongoing 通知并停止前台服务，再发
    `foregroundServiceTimedOut`；ACK 未受理才调 `showTimeoutFallback(applicationContext,
    savedPayload)`；
  - 删除 `failActive` / `failOrResolveTimeout` / `removeOrResolveTimeout` 的 timeout 留存
    分支 / `registerTimedOutNotification` / `showProtectionEndedNotificationBestEffort` /
    `PUBLIC_ERROR_*` / `OPEN_ACTION_FALLBACK_LABEL` / `PROTECTION_ENDED_*`；
    `remove()` 无活跃实例时返回 serviceUnavailable（fail-open，通知已在 onTimeout 移除）；
  - ongoing 构建简化为仅 ongoing 形态（静音 LOW 渠道契约不变：4101、silent、点击直达
    会话 content intent、dataSync 前台类型全部保持）。
- `MainActivity.kt`：channel 类型更名；冷启动 intent 与 `onNewIntent` 统一走
  `handleNotificationIntent()`。
- `lib/app/platform/android_chat_generation_platform_bridge.dart`：
  `androidChatGenerationPlatformChannelName` 与 Kotlin 同一原子提交切换到
  `yuzu.shiki.oh_my_llm/chat_generation_notifications`，无双写双 handler；wire 形状与
  Task 4 固化定义逐字对齐（pending activation 应答 `{payload: <v1 JSON>}`、
  `notificationActivated` 参数为 payload JSON 字符串本身）。
- 四个 Dart 平台测试文件的通道名字面量与注释同步更新。

## 关键设计决策

1. **无 Robolectric 的可测性**：渠道 importance/sound/vibration、pre-26 defaults/priority、
   category/visibility 全部抽成 `ChatGenerationTerminalNotificationSpec` 编译期常量；
   request code/data URI 推导、fallback 决策、设置状态判定、设置 Intent 参数全部是纯
   Kotlin 函数，JVM 测试直接断言这些「被测决策就是实际执行路径」（builder 一律经
   `terminalPublicCopy()` 取公开文案）。真实横幅/声音留待 smoke，未在 JVM 测试伪装已验证。
2. **终态 ID 冲突规则**：Kotlin 只引入 Dart FNV 契约下界 10000 作为守卫（文档化 wire
   常量），不复刻 FNV-1a、不复刻 event key/session 规则；4200 fallback 与 4101 ongoing
   由区间关系天然隔离并有常量断言。
3. **timeoutActivationPayload 校验边界**：非空 String + UTF-8 ≤ 1024 bytes（与 Dart codec
   上限一致），乱串原样接受（测试用非 JSON 文本证明不解析）；start/update 缺失即
   malformedPayload（与 Dart port doc「null 时按协议不符拒绝」一致）。Service 在 start/
   update 时保存该字符串，fallback PendingIntent 原样带回。
4. **pending 单槽哲学**：终态激活 payload 单槽、后一次覆盖前一次；warm ACK true 清槽、
   否则留给 `takePendingNotificationActivation` 取走一次——与 fallback 的
   FLAG_UPDATE_CURRENT 覆盖语义一致。
5. **ACK 残余窗口**：如实实现并注释「ACK 只覆盖 Dart handler 是否连接，不是 durable
   delivery」；PR/报告不声称 exactly-once/no-loss。

## RED/GREEN 证据

| 阶段 | 日志 | 结果 |
| --- | --- | --- |
| RED（checkout HEAD~1 旧源码 + 新测试文件跑 `:app:testDebugUnitTest`） | `logs/android-terminal-notification-red.log` | EXIT=1，编译期 `Unresolved reference 'KEY_TIMEOUT_ACTIVATION_PAYLOAD'` / `'KEY_ID'` 等——新类型/符号缺失导致失败 |
| GREEN（恢复提交后同命令复跑） | `logs/android-terminal-notification-test.log` | EXIT=0，BUILD SUCCESSFUL，40 用例 0 失败（JUnit XML `build/app/test-results/testDebugUnitTest/TEST-yuzu.shiki.oh_my_llm.ChatGenerationNotificationProtocolTest.xml`: tests=40 failures=0 errors=0） |
| 编译预热（首次冷 daemon 单独构建 `:app:compileDebugKotlin`） | `logs/android-app-compile.log` | EXIT=0，BUILD SUCCESSFUL in 50s |

brief 十三条 RED 名对应落点（全部在 `ChatGenerationNotificationProtocolTest`，40 用例内）：

- `终态渠道配置为HIGH且不是silent` / `前台渠道仍为LOW且silent` → Spec/常量断言
  （HIGH + 默认声 + 振动 vs ONGOING_CHANNEL_IMPORTANCE==LOW && ONGOING_CHANNEL_SILENT）。
- `终态通知ID不与4101冲突` → `终态通知ID不与ongoing及fallback保留槽位冲突`
  （4101/4200/9999 拒绝、10000/2147483646 接受）。
- `每个终态PendingIntent request code与data URI唯一` →
  `每个终态PendingIntent_request_code与data_URI由通知ID唯一推导`。
- `终态通知构造同时使用private和固定public version` →
  `终态通知构造同时使用private和固定public文案`（terminalPublicCopy 只返回传入 public 字段）。
- `Kotlin只校验timeout activation payload类型与长度不解析JSON` →
  `Kotlin只校验timeout_payload类型与长度不解析JSON内容` + 类型/空白/1024 边界三例
  （含中文多字节 341/342 字边界）。
- `timeout callback未受理时选择HIGH fallback` → `timeout_callback未受理时选择HIGH_fallback`。
- `timeout fallback固定使用通知ID与request code 4200` → 同名测试（含 data URI 4200 断言）。
- `timeout fallback原样复用Dart session scoped payload` →
  `timeout_fallback原样复用Dart_session_scoped_payload`（原字符串透传，null 直通）。
- `ongoing content intent仍打开对应会话` → 同名测试（action 字符串 + request code 4104 +
  takePendingOpenConversation 常量不变）。
- `首次设置状态查询会创建终态channel且不重建已有channel` →
  `首次设置状态查询创建终态channel且不重建已有channel`。
- `通知禁用或终态渠道为NONE时返回disabled` →
  `通知禁用或终态渠道为NONE时返回disabled其余enabled`（含 pre-26 与渠道未建矩阵）。
- `打开设置Intent只使用当前package` → 同名测试（action/extra key/package 透传/NEW_TASK）。

## 回归验证

- Gradle 单测：`.\android\gradlew.bat -p android :app:testDebugUnitTest`，EXIT=0，
  40/40（`logs/android-terminal-notification-test.log`）；命令级工具硬超时 120000ms。
- 受影响 Dart 平台测试四文件合跑：EXIT=0，29 用例全过
  （`logs/task5-dart-platform-tests.log`）。
- `flutter analyze`：No issues found（`logs/task5-flutter-analyze.log`）。
- 提交前 `dart format` + `--set-exit-if-changed`（五个暂存 Dart 文件）：EXIT=0；
  `git diff --cached --check` 通过。
- AndroidManifest.xml 未修改；POST_NOTIFICATIONS 权限与 foregroundServiceType 未动。

## 环境备注（Gradle 执行）

- 系统 JAVA_HOME 为 JDK 25，Gradle 8.14.5 内嵌 Kotlin 无法解析版本串 "25.0.2"
  （`JavaVersion.parse` IllegalArgumentException），构建在 Kotlin script 阶段失败；改用
  Android Studio JBR（JDK 21）注入 `JAVA_HOME` 后正常。此为环境事实，不影响 CI（Ubuntu 固定工具链）。
- 首次冷 daemon 构建曾在 `:app:compileDebugKotlin` 停滞（CPU 近零增长），按挂起处理：
  停止 daemon、清理 java 进程后重试即恢复正常（50s 完成），后续复跑稳定。
- 因冷构建无法在 brief 规定的 120000ms 工具硬超时内完成，采用两阶段：预热编译为后台
  构建（不受测试超时约束），正式测试命令在 warm daemon 下以 120000ms 硬超时同步执行
  （20s / 8s 完成）。

## 停止条件核查

- 未出现「只能升级已有 LOW channel 才能得到横幅」：终态使用全新 `chat_generation_result`
  HIGH 渠道，ongoing LOW 渠道参数未动。
- Kotlin 未参与真正 generation outcome 判定：只渲染 Dart 安全文案与不透明 payload，
  fallback 仅表达「前台保护已结束」，不判定终态。
- 未重复弹 POST_NOTIFICATIONS 权限：沿用既有一次询问持久化逻辑，本任务零改动。

## Concerns

1. **Kotlin 收敛了 openConversation 动作**：`parseActionKind("openConversation")` 现返回
   null（§12「旧 LOW terminal 的 open action → 统一终态激活」的落地）。Dart 侧
   `ChatGenerationNotificationActionKind.openConversation` 枚举值仍在（Task 3 范围），
   生产 projector 从不产生该值；若未来 Dart 发送会被原生按 malformedPayload 显式拒绝
   （loud failure），不会静默丢按钮。
2. **remove() 在超时后的语义变化**：timeout 瞬态记录删除后，Dart 在 timeout 后调用
   remove 会得到 serviceUnavailable（而非旧的 registry 匹配取消）。ongoing 通知已在
   onTimeout 第一步移除，coordinator 对 remove 失败 fail-open，无用户可见影响。
3. **MIN_TERMINAL_NOTIFICATION_ID=10000** 把 Dart FNV 下界编码为 Kotlin 守卫常量：这是
   文档化 wire 契约（adapter doc 注明 FNV 映射 10000..2147483646），不是哈希复刻；若
   Dart 侧未来改变下界需同步两处。
4. **真实横幅/声音/PendingIntent 行为未经设备验证**（无 Robolectric，属计划预期）：
   需在 smoke 手册阶段用真机确认 HIGH 横幅、默认声、锁屏 public 副本与 cold/warm 点击
   激活链路；JVM 层已覆盖的是全部参数选择决策。
5. **android/.gitignore 追加 `/.kotlin/`**：Gradle 运行产生的新 Kotlin 构建产物目录，
   属仓库卫生修正，随本提交入库。
