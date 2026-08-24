# Android 聊天生成前台服务 — 真机 Smoke 手册

**目的：** 按设计文档 `docs/specs/2026-08-17-android-chat-generation-foreground-service-design.md` 第 15 节，在至少一台 Android 13+ 真机上验证生成前台服务、动态通知、权限与生命周期降级，并如实记录 PASS / FAIL / PENDING。

**对应任务：** Task 7（计划 `docs/plans/2026-08-18-android-chat-generation-foreground-service.md`），在 Task 1–6 实现完成（HEAD `2dcec61`）之后执行。

> **诚实记录原则：** 未在真机上实际执行的行必须标 `PENDING`，并注明缺失的前置条件。任何行不得把 `PENDING` 当作通过。`PENDING` 不表示行为正确或错误，只表示「本环境无法验证」。

---

## 0. 被测对象与环境

| 项 | 值 |
|---|---|
| 应用包名 | `yuzu.shiki.oh_my_llm` |
| 前台服务 | `yuzu.shiki.oh_my_llm/.ChatGenerationForegroundService`（`dataSync`，`stopWithTask=true`，不导出） |
| 通知 channel | 低打扰 channel（importance low，`onlyAlertOnce`，固定 notification ID） |
| 生成通知 Action | `stopRequested(token, conversationId)` / `openConversationRequested(conversationId)` |
| App 版本 | 以 `pubspec.yaml` `version:` 为准（构建产物 versionName 同源） |
| Smoke 执行时间 | 2026-08-18（本表最后更新） |
| 本机 Android 设备 | **无设备接入**（`adb devices` 为空；`adb` 位于 `C:\tools\AndroidSdk\platform-tools\adb.exe`） |
| 本机 Android SDK | `C:\tools\AndroidSdk`（可用于 APK 构建） |
| JDK（Gradle 构建） | `C:\tools\JDK\jdk-21.0.11`（系统 JDK 25 与 Gradle 8.14.5 不兼容，构建时必须设 `JAVA_HOME`） |

### 执行环境速查命令

```powershell
# 设备与版本信息
adb devices -l                                    # 查看接入设备（当前为空）
adb shell getprop ro.product.model                # 设备型号
adb shell getprop ro.build.version.release        # Android 版本
adb shell getprop ro.build.version.sdk            # API level

# 前台服务/通知/权限状态
adb shell dumpsys activity services yuzu.shiki.oh_my_llm
adb shell dumpsys notification --noredact | Select-String "yuzu.shiki.oh_my_llm"
adb shell dumpsys package yuzu.shiki.oh_my_llm | Select-String "POST_NOTIFICATIONS"

# 通知权限复位（13+）
adb shell pm revoke yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
adb shell pm grant yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
```

---

## 1. 复位与验证命令（Runbook）

> **危险警告：** Android 15+ 的 `data_sync_fgs_timeout_duration` 全局参数修改**只允许**在专用测试设备上执行，**绝不允许**在用户日常设备上执行。Android 15 超时测试前必须确认设备是专用测试设备，并走「先捕获旧值 → 改短 → finally 恢复/删除」流程。

### 1.1 通知权限复位（每次权限用例前后）

```powershell
adb shell pm revoke yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
adb shell pm grant yuzu.shiki.oh_my_llm android.permission.POST_NOTIFICATIONS
```

### 1.2 应用与 Service 复位

```powershell
adb shell cmd activity stop-app yuzu.shiki.oh_my_llm
adb shell am force-stop yuzu.shiki.oh_my_llm
```

### 1.3 前台服务存在性检查（第 13/14 行）

```powershell
adb shell dumpsys activity services yuzu.shiki.oh_my_llm
# active generation 期间应能看到 ChatGenerationForegroundService 且 type 含 dataSync
# terminal 之后 dumpsys 中不再出现该 Service
```

### 1.4 Android 15+ 超时（仅专用测试设备）

前置：专用 Android 15+ 测试设备；该设备不承载用户日常使用。

```powershell
# ① 捕获旧值（可能是空/null，需记录）
adb shell device_config get activity_manager data_sync_fgs_timeout_duration

# ② 启用 15+ 前台服务时限约束
adb shell am compat enable FGS_INTRODUCE_TIME_LIMITS yuzu.shiki.oh_my_llm

# ③ 把 dataSync 超时缩短到 60s（仅专用测试设备）
adb shell device_config put activity_manager data_sync_fgs_timeout_duration 60000

# …… 执行超时用例（验证 Service 在约 60s 内 stopSelf、通知转“后台保护已结束”普通通知）……

# ④ finally：恢复/删除覆盖
adb shell device_config delete activity_manager data_sync_fgs_timeout_duration
adb shell am compat disable FGS_INTRODUCE_TIME_LIMITS yuzu.shiki.oh_my_llm
# ⑤ 恢复旧值（若 ④ 的 delete 之前存在非默认旧值，用 device_config put 写回旧值）
```

---

## 2. 验证矩阵（15 项 Spec Smoke Case）

> **当前执行状态：** 本机 `adb devices` 为空，没有任何 Android 设备接入；下述所有 Android 设备依赖行一律 `PENDING`，缺失前置条件为「无 Android 13+ 真机接入」。第 15 行（Windows）在具备交互式桌面会话时可执行，见行内状态。
>
> **修复待真机验证（2026-08-24）：** 「remove 立即清空守卫 / 过期 stop 动作不残留后台服务」两项修复待真机验证：前者覆盖背靠背 remove→start 不误判 STALE（对应第 6/13/14 行场景），后者覆盖点击过期停止动作不残留后台服务。

| # | 用例（设计 §15） | 前置条件 | 状态 | 结果 / 缺失前置条件 |
|---|---|---|---|---|
| 1 | 首次通知权限允许：发送不中断，通知进入 ongoing | Android 13+ 真机 + `POST_NOTIFICATIONS` 复位 | PENDING | 无 Android 13+ 真机接入 |
| 2 | 首次通知权限拒绝：发送仍继续，应用不重复弹权限 | Android 13+ 真机 + `pm revoke POST_NOTIFICATIONS` | PENDING | 无 Android 13+ 真机接入 |
| 3 | 前台长流：正文/推理字符数约每秒更新且不重复响铃 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 4 | 切换到其他应用后完成流式请求 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 5 | 锁屏后继续并在解锁后看到正确状态 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 6 | 通知“停止生成”保存已有部分内容，重复点击无副作用 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 7 | 自动重试显示正确 attempt，停止重试走 durable stop | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 8 | 401、429、超时、空回复与持久化失败只显示允许名单摘要 | Android 13+ 真机 + 可控故障注入（错误服务端/代理） | PENDING | 无 Android 13+ 真机接入 |
| 9 | 点击 ongoing/error 通知进入正确 conversation | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 10 | 最近任务划掉后 Service 与 ongoing 通知消失且不自启 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 11 | `adb shell cmd activity stop-app yuzu.shiki.oh_my_llm` 后不自启 | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 12 | 强制 Doze/锁屏场景退出后应用状态能够正常恢复 | Android 13+ 真机（`adb shell dumpsys deviceidle force-idle`） | PENDING | 无 Android 13+ 真机接入 |
| 13 | `dumpsys activity services` 能看到 active generation 期间的 `dataSync` foreground service | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 14 | terminal 后 `dumpsys` 不再存在该 Service | Android 13+ 真机 | PENDING | 无 Android 13+ 真机接入 |
| 15 | Windows 运行路径无通知权限请求、MethodChannel 调用或行为变化 | Windows 桌面 + 交互式会话 | 部分 PASS / 部分 PENDING | 见下方 §3：构建/启动/无 channel 与权限错误已 PASS；真实生成与 inline UI 视觉确认 PENDING |

### Android 15+ 专用测试设备附加用例（可选）

| # | 用例 | 前置条件 | 状态 | 结果 / 缺失前置条件 |
|---|---|---|---|---|
| A | Android 15 dataSync 超时：`onTimeout` 及时 stopSelf，token 标记无保护，后台不重启 Service | 专用 Android 15+ 测试设备 + §1.4 超时流程 | PENDING | 无 Android 15+ 专用测试设备接入 |

---

## 3. Windows 路径验证记录（第 15 行）

**方法：** 在 Windows 桌面运行应用，发起一次聊天生成并停止，检查无通知权限请求、无 MethodChannel 调用报错、生成成功/停止/错误行为正常、页面内 inline 错误卡与消息树语义与改动前一致。

| 子项 | 状态 | 结果 |
|---|---|---|
| Windows Debug 目标可构建 | PASS | `flutter build windows --debug` 成功，`build\windows\x64\runner\Debug\oh_my_llm.exe` 产出（2026-08-18，日志 `logs/chat-fgs-build-windows-debug.log`） |
| 应用可正常启动、窗口出现、进程存活 | PASS | 以 `oh_my_llm.exe` 直接启动，窗口标题 `oh_my_llm`，12s 后进程仍存活，Dart VM service 正常监听；随后正常终止、无残留进程 |
| 无通知权限请求 | PASS | Windows 绑定 `NoopChatGenerationForegroundService`（`lib/app/platform/noop_chat_generation_foreground_service.dart`），不存在 POST_NOTIFICATIONS 概念，不发起权限请求；运行日志无权限相关输出 |
| 无 MethodChannel 调用报错 | PASS | no-op adapter 不创建 MethodChannel；运行 stdout/stderr 无 `MissingPluginException` / `PlatformException` / 其他 channel 异常 |
| 生成成功 / 停止 / 错误路径正常 | PENDING | 需配置 LLM API key 并在交互界面实际发送/停止/触发错误；本环境无 API key 且无法进行视觉交互验证 |
| 页面 inline UI 与消息树语义不变 | PENDING | 需在可交互会话中视觉确认页面 inline 错误卡与消息树行为；已有自动化覆盖（chat/app 套件 814 例全绿）作为间接证据 |

> **执行说明：** 2026-08-18 在 Active console 会话（admin）中以 Debug exe 实际启动应用，验证了构建、启动、无 channel/权限错误的子项；「生成成功/停止/错误」与「inline UI 视觉确认」两个子项需要真实 LLM 请求与视觉观察，本环境无法完成，标 `PENDING` 并注明原因。

---

## 4. 复现性说明

1. **构建 APK**（Debug / Release 均以 `JAVA_HOME=C:\tools\JDK\jdk-21.0.11` 执行）：

   ```powershell
   $env:JAVA_HOME = "C:\tools\JDK\jdk-21.0.11"
   flutter build apk --debug     # 日志 -> logs/chat-fgs-build-debug-final.log
   flutter build apk --release   # 日志 -> logs/build-android.log
   ```

2. **安装与启动**：

   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-debug.apk
   adb shell am start -n yuzu.shiki.oh_my_llm/.MainActivity
   ```

3. **触发生成**：在聊天页发起一次 LLM 生成，按 §1.2 复位后再验证各用例；每次权限用例前后按 §1.1 复位权限。

4. **超时用例（仅专用测试设备）**：严格按 §1.4 执行，`finally` 恢复系统配置，并记录恢复后的 `device_config get activity_manager data_sync_fgs_timeout_duration` 确认恢复成功。

---

## 5. 风险与限制（诚实声明）

- 前台服务只**降低**进程被系统回收的概率，不保证不杀进程；用户强停（Force stop）、极端内存回收或 OEM 附加策略下，进程与 SSE 仍可能被终止，此时没有回调保证。
- 本手册所有 Android 真机行当前均为 `PENDING`（无设备接入），不代表行为验证通过，也不代表发现缺陷；需在接入 Android 13+ 真机后逐行执行并更新状态。
- Android 15 超时参数修改只能在专用测试设备上进行，用户日常设备不得触碰。

---

## 6. 生成终态通知最小原生 gate（计划 2026-08-22 Task 11，2026-08-24 追加）

本节属于计划 `docs/plans/2026-08-22-cross-platform-generation-terminal-notifications.md` 第 11 节「Ready 前最小原生 gate」的 Android 半边，与 §2 的旧前台服务矩阵**相互独立、互不替代**：§2 验证 ongoing 前台服务生命周期；本节验证生成**终态通知**（HIGH channel、激活与抑制）。诚实记录原则同前：未在真机上实际执行的行保持 `PENDING`，自动化证据只能支撑其标注的那一行，不得外推为真机 PASS。

**执行状态（2026-08-24 第二次更新）：** 用户已在 Android Studio 模拟器（emulator-5554）上人工执行计划「Android 最小原生 gate」四项核心（A1/A8/A10/A11），全部 PASS；执行包为 debug build（覆盖安装保留数据），证据口径为用户行为级确认，未留存 logcat/dumpsys 级明细（G2 缺陷诊断期间曾采集 45868 行 logcat 作为缺陷证据，见下方记录）。其余条目仍为 `PENDING`。

| # | gate 场景 | 结果 | 证据 / 缺失前置条件 |
|---|---|---|---|
| A1 | 生成成功后出现 `chat_generation_result` HIGH 终态通知 | **PASS** | 2026-08-24 用户模拟器人工确认：生成完成后 HIGH 终态通知出现并可点击。自动化佐证：Dart 收据→通知映射单测全绿（`logs/fltest.log` EXIT=0，2026-08-24） |
| A2 | HIGH channel 配置正确：`IMPORTANCE_HIGH` + 默认声音 + 振动启用，且与 ongoing LOW channel 分离 | **PASS** | 源码 `ChatGenerationTerminalNotification.kt`（`CHANNEL_IMPORTANCE = IMPORTANCE_HIGH`、`setSound` / `enableVibration`）；Kotlin 单测 40/40 当日重跑 EXIT=0（`logs/task11-kotlin-unittest.log`，JAVA_HOME 用 Android Studio JBR）；范围审计确认 `ONGOING_CHANNEL_IMPORTANCE = IMPORTANCE_LOW` 与 terminal channel 分离 |
| A3 | 默认声音实际表现（横幅/响铃由系统通知音量、静音模式等设备设置控制） | PENDING | 未在受控声音开关组合下执行；允许记录「channel 配置正确但设备静音」，不得把设备静音判成实现 FAIL |
| A4 | 空回复终态通知（`emptyReply` 固定分类摘要） | PENDING | 未构造空回复场景 |
| A5 | 最终失败终态通知（network/timeout/authentication/rateLimited/server 等固定分类摘要，无原始异常） | PENDING | 未注入故障服务端 |
| A6 | 持久化失败终态通知 | PENDING | 未构造持久化失败场景 |
| A7 | 保护超时 fallback（`foregroundProtectionTimedOut` 收据 + Kotlin 固定 fallback） | PENDING | 超时注入仅限专用测试设备并按 §1.4 流程执行；本次未执行 |
| A8 | 精确会话抑制：应用前台正在查看同一会话时不弹终态通知 | **PASS** | 2026-08-24 用户模拟器人工确认抑制行为符合预期。自动化佐证：`app_attention_observer_test.dart` 与深模块单测覆盖注意力判定逻辑 |
| A9 | 其他会话 / 其他页面时展示终态通知 | PENDING | 未单独执行（与 A1 同路径但未独立观察） |
| A10 | 点击终态通知打开精确会话 | **PASS** | 2026-08-24 用户模拟器复验通过：点击 HIGH 终态通知直达对应会话、无异常页面闪现（含 G2 缺陷修复后的 green 复验，见下节）。自动化佐证：激活链路单测/集成测试全绿 |
| A11 | 现有 ongoing 通知点击仍打开对应会话（旧契约保留，只有旧 LOW 终态点击路径被替换） | **PASS** | 2026-08-24 用户模拟器确认 LOW ongoing 通知点击正常直达会话（G2 诊断对照项）。自动化佐证：coordinator 生产调用 `takePendingOpenConversation` + 回归测试全绿 |
| A12 | warm 点击（应用进程存活时点终态通知） | PENDING | 未单独区分 warm/cold 执行（用户验证的 HIGH 点击发生在进程存活的 DELIVERED_TO_TOP 投递路径，logcat 已证实） |
| A13 | cold 点击（进程不在时点通知拉起应用并直达会话） | PENDING | 本次未执行 cold 路径 |
| A14 | 已删除会话回退（点击指向已删除会话的通知回退根页，不崩溃） | PENDING | 未执行 |
| A15 | 权限拒绝：revoke `POST_NOTIFICATIONS` 后发送不中断、不重复弹权限 | PENDING | 未执行；复位命令见 §1.1 |
| A16 | 设置入口：设置页显示系统通知状态卡并可打开系统通知设置 | PENDING | 未执行。自动化佐证：`system_notification_status_controller_test.dart`（3 例）+ `settings_screen_test.dart` 全绿 |

**统计：PASS 5（A1/A2/A8/A10/A11）/ PENDING 11 / FAIL 0。**

### G2 缺陷记录（2026-08-24 发现并修复，red/green 完整）

- **现象（red）**：debug 包上点击 HIGH 终态通知跳转应用时，先闪现 GoRouter「未找到页面：oh-my-llm://generation-notification/&lt;id&gt;」页面再正常渲染目标会话；LOW ongoing 通知点击无此现象。
- **根因**：终态通知 PendingIntent 携带 data URI（`oh-my-llm://generation-notification/<id>`）；Flutter embedding 对带 data 的启动/onNewIntent intent 自动把 dataString 转发为 Flutter 路由 → GoRouter 无匹配路由渲染 404 页 → 随后自有 payload 链路（KEY_PAYLOAD extra → method channel）接管导航。消费链路全程无人读 intent.data。
- **修复**：commit `9476862` 移除 data URI（对计划 §7.4/:595、§7.5/:619 的有意偏离，偏离裁决记录于 SDD ledger）；PendingIntent 区分性由 request code 同源于通知 ID 单独保证；JVM 定向测试 EXIT=0（`logs/android-jvm-data-uri-fix-green.log`）。已知残留：升级安装前发出的旧通知点击仍带旧 data URI 闪现一次 404，一次性自愈。
- **green**：3.81.2 debug 包覆盖安装后用户复验——HIGH 终态通知点击直接进入对应会话，无任何异常页闪现；LOW ongoing 对照正常。本缺陷关闭。

### 判定规则（与计划第 11/14 节一致）

- A1/A8/A10/A11 四项即计划「Android 最小原生 gate」核心：任一 FAIL 停止 Ready 并修复；无法执行（无设备）则 PR 保持 draft。
- 只有扩展矩阵（其他 ROM/厂商策略、专注助手组合、多声音设备等）允许保持 `PENDING`。
- 自动化佐证只证明 Dart/Kotlin 层契约，永远不能替代表格中真机行的 PASS。
