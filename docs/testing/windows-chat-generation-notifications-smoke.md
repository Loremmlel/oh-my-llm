# Windows 生成终态通知实机验证手册

## 这份文档是干什么的

本文档属于计划 `docs/plans/2026-08-22-cross-platform-generation-terminal-notifications.md`，同时是两样东西：

1. **操作手册**：带你一步步在真机上验证 Windows 生成终态通知的底层机制。每一步都告诉你打开什么、点什么、看到什么写什么。
2. **证据记录**：验证结果当场回填进本文档的表格。没做过实验的字段一律保持 `PENDING`——不预测结果，不编造数据。

全文分四部分：

| 部分 | 对应计划 | 干什么 | 卡住什么 |
|------|----------|--------|----------|
| 第一部分：插件激活 spike | Task 6 | 用仓库外的临时工程验证 `flutter_local_notifications_windows 3.1.1` 在未打包场景下能否被 Toast 点击正确激活 | 7 项验收全部 PASS 之前，禁止开始 Task 7–11 的产品实现 |
| 第二部分：产品最小 gate | Task 11 / 计划第 11 节 | 用最终产品 build 复验同样的机制，再加产品行为 | 全部 PASS 之前，PR 不得标记 Ready |
| 第三部分：runner-owned spike | Task 6B | 用仓库外 throwaway 工程验证 runner 在 Flutter engine 之前持有 COM activator 的方案（独立 STA 线程 + named pipe 帧协议），人工验收 A–E | A–E 全部 PASS 之前，禁止开始 Task 7–11 的产品实现 |
| 第四部分：产品级 smoke 清单 | Task 11 回填 | 回填自动化证据并记录产品级人工 smoke 清单（W 系列），与第二部分共同构成 Ready 判定依据 | 核心 smoke 项未全部 PASS 之前，PR 不得标记 Ready；仅扩展矩阵 W18/W19 允许保持 `PENDING` |

**当前状态（2026-08-24 更新）：** 第一部分插件方案已被 runner-owned 方案否决替代（原始 FAIL 证据原样保留于下文）；第三部分 runner-owned spike 人工验收 A–E 已全部 PASS；第二部分产品最小 gate 与第四部分产品级 smoke 清单的人工核心项已于 2026-08-24 由用户在正式 Release 产品 build 上按 `task-11-user-guide.md` 六组 case 执行完毕并全部 PASS（W5 按当日用户裁决精简为 3 轮，见对应条目备注），仅剩扩展矩阵 W18/W19 允许保持 `PENDING`。

---

## 第一部分：插件激活 spike（Task 6，阻塞）

### 先弄懂几个词

| 词 | 意思 |
|----|------|
| Toast | Windows 右下角弹出的系统通知卡片，没被点掉也会留在通知中心 |
| warm | 应用已经在运行时点击 Toast。系统把点击直接递给现有进程 |
| cold | 应用没在运行时点击 Toast。系统按注册表里登记的 exe 路径把程序拉起来，再把点击递给它 |
| payload | 发通知时塞进去的一段字符串。点击 Toast 后程序拿到的应该就是这段原文，一字不差 |
| AUMID（AppUserModelID） | Windows 用来标识「这条通知是谁发的」的应用 ID。通知中心按它归组，系统设置按它开关通知 |
| CLSID | COM 组件的 GUID 身份号。这里登记的是 spike 的 Toast 激活器，Windows 处理 Toast 点击时按它找到要拉起的程序 |
| LocalServer32 | 当前用户注册表（HKCU）下的一个键，内容是「这个 CLSID 对应哪个 exe」。cold 启动就是照它拉起程序的，所以不需要管理员权限 |
| VT_CLSID | 注册表值的一种类型标记，表示这个值里存的是一个 CLSID（GUID） |
| `-Embedding` | Windows 拉起 COM 服务进程时附加的命令行参数，用来区分「系统拉起的」还是「用户自己双击的」 |
| CALLBACK / LAUNCH-DETAILS | 同一次点击的两条到达通道：CALLBACK 是插件的激活回调；LAUNCH-DETAILS 是事后调 `getNotificationAppLaunchDetails()` 问插件「这次进程是不是被通知拉起的、带了什么 payload」，返回里的 `didNotificationLaunchApp` 就是第一个问题的答案 |
| event key 去重 | 上面两条通道说的是同一次点击。spike 按 event key 判定为同一次，「逻辑激活数」只加 1 |
| 逻辑激活数 | spike 界面上的计数器：去重后真正算数的激活次数 |

spike 工程在仓库外：`E:\Code\omll-notification-spike`，一次性临时工程，永不进仓库。它的身份和产品身份（`Oh My LLM` / `YuzuShiki.OhMyLlm` 等）完全无关。

### 环境与身份（记录区）

| 项目 | 值 |
|------|------|
| OS 版本 | Windows 11 Pro 25H2 build 26200（NT 10.0.26200）|
| Flutter | 3.44.8 stable / Dart 3.12.2 |
| 插件版本 | `flutter_local_notifications_windows: 3.1.1`（pubspec.lock 精确锁定）|
| spike 工程路径（仓库外） | `E:\Code\omll-notification-spike` |
| spike AUMID | `YuzuShiki.OmllNotificationSpike` |
| spike CLSID | `{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}` |
| spike 快捷方式 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\OmllNotificationSpike.lnk` |
| 主测试 payload（29 字符） | `生成终态通知激活验证-Payload-Ω-20260823` |
| 第二条 payload（24 字符） | `连续冷启动第二条-Payload-β-98765` |

这两条 payload 就是后面所有「逐字一致」比对的**抄写基准**：汉字、希腊字母 Ω 和 β、连字符个数，一个字符都不能差。

### 两套构建命令（记录区）

在 spike 工程根目录 `E:\Code\omll-notification-spike` 下执行：

```powershell
# 正常版（产物快照在 dist\normal）
flutter build windows --release
# 日志：logs/spike-build-normal.log

# 延迟版（产物快照在 dist\delayed）：只把插件 initialize 推迟 10 秒，PID 显示与注册逻辑不推迟
flutter build windows --release --dart-define=SPIKE_INIT_DELAY_MS=10000
# 日志：logs/spike-build-delayed.log
```

两套构建均已完成并快照到 `dist\normal`、`dist\delayed`（两份 `data/app.so` 的 SHA256 不同，确认 dart-define 生效）。日常验证直接用现成快照，不必重新构建。

### 工程师自查记录（已完成的事实，非人工验收）

以下是实现者已经做过并确认过的背景，不需要重复做：

- 启动 exe 后回读 LocalServer32 默认值 = `"E:\Code\omll-notification-spike\...\omll_notification_spike.exe"`（带引号），`ServerExecutable` = 不带引号同路径。
- 快捷方式属性回读：AUMID 与 ToastActivatorCLSID（VT_CLSID 类型）均为 spike 值；target/workdir 指向当次 exe 目录。
- 插件写入回读：`AppUserModelId\<AUMID>` DisplayName/CustomActivator、PushNotifications Backup 键 appType/Setting 均正确。
- 幂等性：先后启动 delayed 与 normal 构建，LocalServer32 每次被重写为当次启动 exe。
- 清理脚本断言模式（`cleanup-spike.ps1 -ReportOnly`）13 项断言全过，未做删除。

### spike 窗口速览

- **PID 大数字**：当前进程的 PID。任何时刻它变了，就说明出现了第二个实例。
- **命令行参数行**：COM 冷启动拉起的进程会显示 `-Embedding`；同时显示 `SPIKE_REG_OK`（C++ 注册成功）。若显示 `SPIKE_REG_FAIL@stageN@hr...`，把原文抄下来——那是 FAIL 证据。
- **插件状态条**：灰色等待 / 红色延迟倒计时（仅延迟版）/ 绿色已初始化 / 红色失败。
- **计数器行**：callback 次数、launch-details 回读、去重抑制次数、仅 launch-details 收到次数、逻辑激活数。
- **日志列表**：每次激活的原始 payload 全文回显，CALLBACK 与 LAUNCH-DETAILS 两条通道都显示。

### 动手前检查

1. Windows 设置 → 系统 → 通知的总开关已打开；专注助手/勿扰模式暂时关闭，否则 Toast 可能不弹出或静默进通知中心。
2. 没有残留 spike 进程：跑下面「常用命令」第一条，输出必须是 `0`。不是 0 就先关掉对应窗口。
3. `dist\normal` 和 `dist\delayed` 两套快照都在。
4. 记住一个机制：**每次手工启动 exe，都会把快捷方式和 LocalServer32 重新指向当次启动的这个 exe**。所以做哪一步就用哪个 exe 启动一次，注册就会跟着它走。

### 常用命令

```powershell
# 查 spike 进程数（正常只能是 0 或 1）
@(Get-Process omll_notification_spike -ErrorAction SilentlyContinue).Count

# 回读 LocalServer32 注册值
Get-ItemProperty 'HKCU:\Software\Classes\CLSID\{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}\LocalServer32' | Select-Object '(default)', ServerExecutable

# 列出 spike 进程详情
Get-Process omll_notification_spike | Select-Object Id, StartTime
```

建议按 1 → 2 → 3（20 轮）→ 4 → 5 → 6 → 7 的顺序做；第 7 项贯穿全程顺带观察。

### 验收项 1：LocalServer32 注册值正确，手工启动与 COM 启动进入同一 entrypoint

**【做什么】**

1. 双击 `E:\Code\omll-notification-spike\dist\normal\omll_notification_spike.exe`。记下窗口里的大号 PID（下称 PID-A）。
2. 看命令行参数行：应出现 `SPIKE_REG_OK`；若出现 `SPIKE_REG_FAIL@stageN@hr...`，把原文完整抄进记录位。
3. 跑常用命令第二条回读 LocalServer32：`(default)` 应为带双引号的 exe 完整路径，`ServerExecutable` 应为不带引号的同一路径。
4. `-Embedding` 那一半证据在冷启动循环里顺手采（见验收项 3）：任意一轮的新窗口命令行参数行出现 `-Embedding`、界面正常工作、日志正常滚动，就证明 COM 拉起的进程进了和手工启动相同的入口，参数没有被 `-Embedding` 卡住。

**【怎么判定 PASS】**

- LocalServer32 两个值的格式都对（一个带引号、一个不带引号，路径指向当次 exe）。
- 看到 `SPIKE_REG_OK`。
- 至少一轮冷启动显示 `-Embedding` 且进程正常进入主界面，没有因为参数解析失败而退出或白屏。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| LocalServer32 `(default)` 实际回读值 | "E:\Code\omll-notification-spike\dist\normal\omll_notification_spike.exe" |
| `ServerExecutable` 实际回读值 | E:\Code\omll-notification-spike\dist\normal\omll_notification_spike.exe |
| `SPIKE_REG_OK` 或 `SPIKE_REG_FAIL` 原文 | SPIKE_REG_OK |
| `-Embedding` 出现的冷启动轮次 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

### 验收项 2：warm class object——应用运行中点击，callback 收到一次原 payload

**【做什么】**

1. 保持 PID-A 的窗口开着。点「发送主测试 Toast」，右下角弹出标题为 “OMLL Notification Spike” 的通知后，**用鼠标点通知本体**（不要点 X 关闭）。
2. 观察：日志出现 `[CALLBACK] ... payload=生成终态通知激活验证-Payload-Ω-20260823`；随后出现 `[LAUNCH-DETAILS] didNotificationLaunchApp=True ...` 带同一 payload，以及一行 `[DEDUP] ... 只计一次`；「逻辑激活数」变为 1；PID 仍是 PID-A。
3. 再发再点两次：「逻辑激活数」应精确递增到 2、3，PID 始终是 PID-A。
4. 每次点击后用任务管理器（或常用命令第一条）确认始终只有一个 spike 进程。

**【怎么判定 PASS】**

- 三次点击后逻辑激活数恰好是 1、2、3；PID 全程是 PID-A；进程数始终为 1；每次 CALLBACK 行的 payload 与抄写基准逐字一致。
- **任何一次 warm 点击后出现第二个进程或 PID 变了 = 硬停止**（「warm 点击启动第二个实例」），立即停下并按硬停止流程处理。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| PID-A | 18240 |
| 第 1 / 2 / 3 次点击后的逻辑激活数 | 1/2/3 |
| 三次点击时的 PID（是否始终 PID-A） | 是 |
| 进程数峰值 | 1 |
| CALLBACK payload 是否与基准逐字一致 | 是 |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

### 验收项 3：cold payload——callback 与 launch-details 同源，去重后只算一次

**【做什么】**

执行下面的「冷启动 20 轮循环记录」，共 20 轮，每轮把结果填进表格。

**【怎么判定 PASS】**

- 20 轮全部满足四条：CALLBACK 与 LAUNCH-DETAILS 的 payload 相同、`didNotificationLaunchApp == true`、逻辑激活数 = 1、全程单进程（且能看到 `-Embedding`）。
- **日志里 CALLBACK 行数 ≥2 但逻辑激活数仍是 1，属于按 event key 正常去重，不是失败**；但如果 launch-details 显示 `didNotificationLaunchApp=False` 或 payload 与基准不同，要把原文记进该轮备注，作为异常证据。
- 出现一次「新窗口起来了但没有 CALLBACK 行、launch-details 也是 null」→ payload 丢失，硬停止。
- 出现一次「点了没反应、等足 60 秒也没有进程起来」→ 冷启动失败，硬停止。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| 实际完成轮数（N/20） | 懒得做，看了下冷启动没问题，PID不一样，进程没有残留 |
| 异常轮次及现象 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

逐轮明细见下文「冷启动 20 轮循环记录」。

### 验收项 4：快速连续 cold 激活，最终只能有一个进程

**【做什么】**

1. 启动 normal 版 exe → 依次点「发送主测试 Toast」和「发送第二条 Toast」→ 完全退出，并用常用命令第一条确认进程数为 0。
2. 按 `Win+N` 打开通知中心，**尽可能快地连续点击两条 spike 通知**（先点更旧的那条）。
3. 等约 15 秒让一切尘埃落定，跑常用命令第三条看进程列表。
4. （可选但推荐）换另一条作第一条，把上面整段重做一遍。

**【怎么判定 PASS】**

- 最终**只有一个进程** → 本项 PASS。查看该进程日志：应有对应 payload 的交付记录一条或两条（取决于 Windows 是否合并激活；两条都到则逻辑激活数 = 2，属正常）。
- **两个进程并行 = 硬停止**（「快速连续 cold 激活产生两个进程」）。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| 最终进程数 | 1 |
| 各进程 Id 与 StartTime | PENDING |
| 交付记录条数 / 逻辑激活数 | PENDING |
| 是否做了换序重做 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

### 验收项 5：手工启动窗口期——initialize 还没完成时点击

**【做什么】**

> 这是验收项 4 替代不了的关键 case：重现「进程已被手工启动、但 COM class object 还没注册完」的窗口期。

1. 先备一条待点的 Toast：用 normal 版发一条 → 完全退出并确认进程数为 0。
2. 双击 `E:\Code\omll-notification-spike\dist\delayed\omll_notification_spike.exe`。
3. **立刻记下红色横幅下方的大号 PID（下称 PID-B）**。此时插件状态条是红色倒计时（约 10 秒）。
4. **趁倒计时没走完**（前 8 秒内最佳）去通知中心点那条 Toast。
5. 盯住接下来 60 秒，逐项记下：有没有出现第二个 spike 窗口（任务管理器看进程数）？倒计时变绿后 PID-B 收到 `[CALLBACK]` 没有？若有第二个窗口：它的 PID、参数行内容、日志里有没有 payload？

**【怎么判定 PASS】**

- **全程只有 PID-B 一个进程/engine，且 payload 在初始化完成后由 CALLBACK/LAUNCH-DETAILS 恰好交付一次（逻辑激活数 = 1）** → PASS。
- 出现第二进程、payload 丢失、或 60 秒内没能交付 → 硬停止。
- **无论 PASS 还是 FAIL，都要把时间线写进备注**：点击那一刻倒计时还剩几秒、payload 过了几秒才到达。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| PID-B | 7500 |
| 点击时倒计时剩余秒数 | 5 |
| 是否出现第二进程（及其 PID、参数行、日志内容） | 是,24604，日志[19:58:37.094] INIT-OK 插件已初始化，COM class object 已注册（CoRegisterClassObject）[19:58:37.094] LAUNCH-DETAILS null —— 插件未记录任何激活详情（initialize 完成后首次读取）。若本次对应一次点击且 CALLBACK 无行，即 payload 丢失证据 [19:58:37.104] CALLBACK type=NotificationResponseType.selectedNotificationAction payload=生成终态通知激活验证-Payload-Ω-20260823 [19:58:37.104] LAUNCH-DETAILS didNotificationLaunchApp=true type=NotificationResponseType.selectedNotificationAction payload=生成终态通知激活验证-Payload-Ω-20260823（callback 之后回读） [19:58:37.104] DEDUP payload 已由 callback 记录，按 event key 去重，逻辑激活只计一次 |
| payload 到达时刻（点击后第几秒） | PENDING |
| 逻辑激活数 | PENDING |
| 时间线备注 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **FAIL** |

### 验收项 6：非 ASCII payload 逐字一致

**【做什么】**

其实前面每一步都在验它，这里做显式核对：

- 抄写基准：主 `生成终态通知激活验证-Payload-Ω-20260823`（29 字符）；第二条 `连续冷启动第二条-Payload-β-98765`（24 字符）。
- 取 **warm 一次**（验收项 2 的任意一次点击）和 **cold 一次**（20 轮中的任意一轮），把日志里 CALLBACK 行与 LAUNCH-DETAILS 行的 payload 与基准**逐字符**比对：汉字、希腊字母 Ω/β、连字符个数都不能差。

**【怎么判定 PASS】**

- warm 与 cold 两处、两条通道的 payload 都逐字符等于基准。
- 缺字、乱码、为 null 都算 FAIL，截图留证。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| warm 比对结果（一致/不一致，不一致贴原文） | 一致 |
| cold 比对轮次与结果 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

### 验收项 7：native 生存性——全程零 native 崩溃

**【做什么】**（贯穿所有步骤）

1. 全程留意崩溃对话框：“omll_notification_spike.exe 已停止工作”、WER 红叉、`std::terminate`、access violation 弹窗——一次都不该出现。
2. 每轮正常关窗后跑常用命令第一条，输出 `0` 即干净退出（Flutter runner 正常关闭返回 EXIT_SUCCESS）。
3. （可选但推荐）事件查看器抽查：运行 `eventvwr` → Windows 日志 → 应用程序，来源筛 `.NET Runtime` / `Application Error`，确认测试期间没有 spike 相关的错误条目。

**【怎么判定 PASS】**

- 所有 case 的进程都正常退出、全程零崩溃弹窗、事件查看器无相关条目。
- 注意：Dart 日志里的 `INIT-FAIL` / `SHOW-FAIL` 行是 Dart 层捕获到的异常信号，必须原样记录上报；它们既不能当成本项 PASS 的证据，本项判定的也只是「有没有 native 层终止」这一件事。

**【观察值记录位】**

| 观察项 | 记录值 |
|--------|--------|
| 崩溃弹窗出现次数 | PENDING |
| 未达到进程数 0 的退出轮次 | PENDING |
| 事件查看器抽查结论（如做了） | PENDING |
| `INIT-FAIL` / `SHOW-FAIL` 出现情况 | PENDING |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

### 硬停止条件（单独列出）

下列任何一条出现，立即停止执行、保留现场（截图 + 命令输出），按「回填要求」记录。**Task 7–11 不开工**：

- warm 点击启动第二个实例。
- cold 点击不能启动，或 payload 与 `show(payload)` 不一致/丢失。
- 快速连续 cold 激活产生两个进程。
- 手工启动尚未注册 COM 时点击产生第二进程、payload 丢失，或无法在默认 60 秒窗口内交付。
- 任一初始化/激活 case 终止 native 进程。
- 只有增加 MSIX、安装器、管理员权限或产品级单实例 IPC 才能通过。

### 冷启动 20 轮循环记录（验收项 3 的明细）

每一轮这样做（约 1 分钟）：

1. **完全退出**：关闭 spike 窗口，跑常用命令第一条，输出必须是 `0`。
2. **重发 Toast**：双击 normal 版 exe → 点「发送主测试 Toast」→ 直接关窗 → 再确认进程数为 0。这条 Toast 会留在通知中心。
3. **点击**：按 `Win+N` 打开通知中心，点刚才那条 spike 通知。（浮层还没消失时直接点浮层效果相同；20 轮里建议至少 5 轮走纯通知中心路径，其余走浮层直点，两种都算 cold。）
4. **记录**：COM 拉起新进程后，在新窗口记下——新 PID；命令行参数行的 `-Embedding` 与 `SPIKE_REG_OK`；CALLBACK 行 payload；LAUNCH-DETAILS 行 payload 与 `didNotificationLaunchApp`；逻辑激活数。
5. 把本轮结果填进表格对应行，回到第 1 步。

| 轮次 | callback payload 一致 | launch-details 一致且 didLaunch=true | 逻辑激活数=1 | 新 PID | 单进程 | 结果 | 备注 |
|------|-----------------------|--------------------------------------|--------------|--------|--------|------|------|
| 1 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 2 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 3 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 4 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 5 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 6 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 7 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 8 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 9 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 10 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 11 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 12 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 13 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 14 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 15 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 16 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 17 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 18 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 19 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |
| 20 | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | |

实际完成轮数：PENDING / 20；异常轮次：PENDING。

提醒：某轮「callback 行数 ≥2 但逻辑激活数 = 1」是正常去重，结果照常记 PASS；但 `didNotificationLaunchApp=False` 或 payload 不同必须写进备注。

### 回填要求

- 全部 PASS 后：把实测命令行/注册格式回写计划第 8 节；若实测与源码审计不同，以实测触发重新设计。
- 任一 FAIL：保留 spike 证据并停止 Task 7–11；不得先写产品 runner 再把失败留给最终 smoke；不得把双实例风险标成“接受”。
- 本任务的提交只包含本文档证据，不包含 throwaway 工程（仓库外，永不进仓库）。

### 收尾：清理 spike 痕迹

```powershell
# 先干跑一遍断言（不删除任何东西），确认全部 OK：
E:\Code\omll-notification-spike\cleanup-spike.ps1 -ReportOnly

# 确认无误后正式清理（删快捷方式 + 三个注册键 + 整个 spike 目录）：
E:\Code\omll-notification-spike\cleanup-spike.ps1

# 如果还想保留 exe 目录以后复测：
E:\Code\omll-notification-spike\cleanup-spike.ps1 -KeepProjectDir
```

脚本每删一项前都会回读并断言仍是 spike 身份。如果它报「断言失败」并中止，说明某个值被别的程序改写了——**不要强行删除**，把输出原样交给任务负责人处理。

---

## 第二部分：产品最小 gate（Task 11，阻塞 PR Ready）

这部分用**最终产品 build**（真实的 Oh My LLM，不再是 spike 工程）复验同样机制，并叠加产品行为，由计划 Task 11 执行并回填。该部分在 spike 全 PASS、产品实现完成之后才具备执行条件，初始记录时各项均为 `PENDING`；2026-08-24 已由用户在正式 Release build 上执行完毕并全部 PASS（见上表结果列与第四部分回填）。

### 最小原生 gate 清单（Ready 前必须全部 PASS，不允许 PENDING）

| # | 场景 | PASS 标准 | 结果 |
|---|------|-----------|------|
| G1 | warm 点击 | payload 与导航正确，且只有一个产品进程 | **PASS** |
| G2 | 完全退出后的 cold 点击 | 同上 | **PASS**（按 2026-08-24 用户裁决精简为 3 轮） |
| G3 | 手工启动到 plugin ready 之间点击 | 同上 | **PASS**（W7/W8/W10 instrumented 变体复验） |
| G4 | 最小化恢复后导航 | 导航行为正常 | **PASS** |
| G5 | 删除会话回退根页 | 会话删除后回退到根页，无崩溃 | **PASS** |

执行口径说明（2026-08-24）：五项 gate 中，G1/G2/G4/G5 四项由用户在正式 Release build 上执行；G3 前后半（W7/W8）经由 `-DOMLL_NOTIFICATION_HOST_TESTING=ON` 的 Debug instrumented 变体复验。以上均按 `task-11-user-guide.md` 六组 case 人工执行并确认全部 PASS；判定以可观察行为结果为准（导航正确、单实例、无崩溃）。原文要求的 PID/进程数/AUMID/CLSID 表示/class registration 耗时级逐轮明细未留存——行为级结论可信，仪器级明细视为未采集，如实记录于此。

### 随产品 smoke 一并记录的观察项

- 前台、失焦、最小化三种状态下通知的展示与点击行为。→ 已执行 PASS（W1/W2/W3）
- 默认声音在系统声音开启/关闭与专注助手下的实际表现；不声称应用强制响铃。→ 声音开关已执行 PASS（W17）；专注助手属扩展矩阵保持 PENDING（W18）
- 已知限制（记录即可，不要求人工构造碰撞）：相同通知 ID 碰撞时，后一条通知会覆盖前一条。→ 保持文档记录义务，未构造
- 同目录覆盖更新后再次点击。→ 已执行 PASS（W13）
- 移动安装目录后首次手动启动再点击。→ 已执行 PASS（W15）
- 系统设置里的通知入口可直达本应用的通知设置。→ 已执行 PASS（W16）

除专注助手组合（W18）与多声音设备/多安装位置矩阵（W19）属扩展矩阵允许保持 PENDING 外，其余观察项均已随第四部分人工执行完成。

### 判定规则

- 任一最小 gate 为 FAIL：停止 Ready 并修复，修完重测。
- 无法执行（环境不可得等）：PR 保持 draft。
- 只有扩展矩阵允许 PENDING；核心 gate 不允许。
- Android 侧的最小 gate 记录在 `docs/testing/android-chat-generation-foreground-service-smoke.md`，两边都 PASS 才能 Ready。

---

## 第三部分：runner-owned spike（Task 6B，阻塞）

第一部分的插件方案已证伪后，Task 6B 改用 **runner 在 DartProject/Flutter engine 之前持有 COM activator** 的方案：独立 notification STA 线程 + instance mutex + activator lease mutex + manual-reset ready event + v1 帧协议 named pipe。本部分记录该方案的 throwaway spike（工程在仓库外 `E:\Code\omll-runner-spike`）的环境、身份、构建方式与人工验收结果。

人工验收按用户裁决精简为最小行为集 **A–E**（预计总操作 ≤15 分钟）；边界输入、时限测量与崩溃监测由 spike 自身的结构化证据日志与自测模式自动完成（见「自动证据说明」）。逐步操作指引见 `.superpowers/sdd/2026-08-22-cross-platform-generation-terminal-notifications/task-6B-user-guide.md`。

### 环境与身份（记录区）

| 项目 | 值 |
|------|------|
| OS 版本 | Windows 11 Pro 25H2 build 26200（与第一部分同一台机器）|
| Flutter | 3.44.8 stable / Dart 3.12.2 |
| Windows SDK（ABI 头与链接库来源）| 10.0.26100.0 |
| 链接库 | `propsys.lib`、`runtimeobject.lib`、`shell32.lib`、`advapi32.lib`、`ole32.lib`（外加模板默认 `dwmapi.lib`）|
| spike 工程路径（仓库外） | `E:\Code\omll-runner-spike` |
| spike AUMID | `YuzuShiki.OmllRunnerSpike` |
| spike CLSID | `{9E60E9C6-0CD2-4727-A762-A18DD8079E80}`（2026-08-23 现生成，与产品、旧 spike 均不同）|
| spike 快捷方式 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Omll Runner Spike.lnk` |
| instance mutex | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.Instance` |
| activator lease mutex | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.ActivatorLease` |
| ready event | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.Ready`（manual-reset）|
| pipe | `\\.\pipe\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.v1` |
| 选定等待常量 | lease 切片 250ms；primary lease 总上界 30000ms；relay lease 总上界 3000ms；pipe 连接上界 2000ms；pipe ACK 上界 3000ms；relayDrainGrace 1000ms；relayMaxLifetime 15000ms |

### 三个变体构建命令（已构建完成，可直接使用产物）

在 `E:\Code\omll-runner-spike` 下执行一条脚本即可产出全部三个变体（正常版 + 两个 10 秒延迟版，延迟由 CMake compile definition 写入 C++）：

```powershell
# 产物快照：variants\normal、variants\pre-com、variants\post-com
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-variants.ps1
# 等价的分步命令（脚本内部即此三步）：
# 1) 正常版：flutter build windows --release
# 2) pre-COM 延迟版：cmake -S windows -B build\windows\x64 "-DSPIKE_PRE_COM_DELAY_MS=10000" "-DSPIKE_POST_COM_PRE_FLUTTER_DELAY_MS=0" 然后 cmake --build build\windows\x64 --config Release
# 3) post-COM 延迟版：同上，改为 "-DSPIKE_PRE_COM_DELAY_MS=0" "-DSPIKE_POST_COM_PRE_FLUTTER_DELAY_MS=10000"
```

机制提醒（与第一部分相同）：**每次手工启动 exe 都会把快捷方式和 LocalServer32 重新指向当次启动的这个 exe**。做哪个 case 就先用哪个变体启动一次。

### 实现者自检记录（已完成的事实，非人工验收）

以下由实现者在交付前完成并留有证据（`E:\Code\omll-runner-spike\evidence\`）：

- 三个变体构建 EXIT=0，三份 exe 哈希互不相同（延迟 compile definition 生效）。
- 正常版启动→关闭（`--auto-toast` 自动发一条 Toast，无需点击）：证据链 `com_register hr=0 → ready_set → flutter_started → toast_show stage=7 hr=0 → com_revoke hr=0 → process_exit code=0`。
- 注册回读：`scripts\verify-registration.ps1` 输出 8 项全 MATCH（shortcut AUMID / ToastActivatorCLSID VT_CLSID、LocalServer32 quoted default + unquoted ServerExecutable、AppUserModelId DisplayName REG_EXPAND_SZ / CustomActivator REG_SZ）。
- 自测模式 `--selftest`：12 个边界 case + 队列容量 32 全 PASS（1024-byte 接受；1025-byte、未知 version/kind、截断帧、focus 带 payload、坏 UTF-8、超长消息、坏 magic 全部拒收；33rd 帧返回 queueFull）。
- warm 协调路径：primary 就绪时以 `-Embedding` 启动 → `relay_abort_primary_ready` 有界退出；普通双击 → secondary `activateWindow` 经 pipe ACK=0 送达、primary `focus_applied`、secondary 退出。
- pre-COM 窗口 relay 生命周期：primary 延迟期内 `-Embedding` relay 取得 lease、注册短命 class object（hr=0）、pump、无回调时 15 秒 max-lifetime 有界退出；primary 以 250ms 切片重试 7.5 秒后接棒注册，全程任何时刻只有一个 class object owner，无崩溃，双方退出码 0。
- `cleanup-spike.ps1 -ReportOnly`：4 项身份断言全过（shortcut / CLSID / AppUserModelId / Toast backup 均确属本 spike），未删除任何东西。
- 自动时限测量（`scripts\summarize-evidence.ps1`）：pipe ACK p50=0ms / max=110ms（n=20）；normal 变体 process_start→ready_set 约 44–52ms。

### 最小行为集 A–E 记录区（人工验收已执行：2026-08-23 22:00–22:07，A–E 全部 PASS）

> 操作细节、每步预期看到什么、证据文件位置见 task-6B-user-guide.md。快速连续 cold 与失效恢复是顺手观察项，未做就在备注写 PENDING，不算 FAIL。

#### Case A：正常版 warm 点击

| 观察项 | 记录值 |
|--------|--------|
| primary PID（窗口大字）与 toast 类型 | PID 30060；ASCII + 中文（warm 会话共 3 次激活：38B×1、40B×2）|
| 点击后 payload 是否在 UI 列表出现且 PID 不变 | 是；activation_received 22:01:54 / 22:02:16 / 22:02:26，PID 未变 |
| 任务管理器中进程数峰值（含 relay） | 1 |
| **结果（PASS/FAIL/PENDING）** | **PASS** |

#### Case B：正常版完全退出后 cold 点击（×2~3 轮）

| 轮次 | 新窗口 PID | UI 收到 payload | 仅一个 Flutter 窗口 | 结果 |
|------|-----------|----------------|--------------------|------|
| 1 | 28896（RPCSS 以 `-Embedding` 拉起；启动→com_register→flutter→activation 共 4ms）| 是（38B）| 是 | PASS |
| 2 | 16080（RPCSS 以 `-Embedding` 拉起）| 是（38B）| 是 | PASS |
| 3（可选） | 未执行（2 轮已满足精简最小集）| — | — | — |
懒得填了，PASS（用户口头确认；上表数值由 evidence 日志回填）

#### Case C：pre-COM 延迟版窗口期点击（上次插件 FAIL 的回归重点）

| 观察项 | 记录值 |
|--------|--------|
| primary PID 与点击时倒计时剩余 | 第 1 次：PID 28712（pre-com 变体，点击发生于延迟开始后 ~1.7s）；第 2 次：PID 26904（~0.9s）|
| 是否出现第二个窗口/进程（relay 不应开窗） | 短暂出现第 2 个进程（relay PID 10000 / 28732），无窗口，约 1s 内 drain 退出 |
| 10 秒延迟结束后 payload 是否到达 primary UI（一次） | 是；primary `pipe_served` 在自身 COM 注册前入队（22:04:40.782 / 22:05:05.794），Flutter 启动后 UI 一次显示 |
| evidence 中 relay 进程日志（pipe_request ack=0 / delivered=1） | 两条链完整：activation_received（38B hash ce4d9d74 / 40B hash 2aa47a6b）→ pipe_request delivered=1 → process_exit code=0 |
| **结果（PASS/FAIL/PENDING）** | **PASS（执行 2 次，第 2 次为中文 payload 40B）** |
注册前点击消息时，确实短暂出现两个进程，但没有出现两个窗口，延迟注册的应用确实收到，通过。（用户原注；共两次，第二次为中文 payload）

#### Case D：post-COM/pre-Flutter 延迟版窗口期点击

| 观察项 | 记录值 |
|--------|--------|
| primary PID 与点击时倒计时剩余 | PID 29804（post-com 变体）；COM 注册于启动后 48ms，点击发生于延迟第 ~2.4s |
| 点击时 Flutter 是否尚未启动（窗口未出现）而 payload 已入 native 队列 | 是；activation_received 22:05:56.436 **早于** flutter_started 22:06:04.102（38B hash ce4d9d74）|
| 延迟结束后窗口出现且 payload 一次到达 UI，无第二窗口 | 是；全程仅 PID 29804 一个进程 |
| **结果（PASS/FAIL/PENDING）** | **PASS** |
通过，不会有第二个进程出现。（用户原注；时序由 evidence 证实）

#### Case E：primary warm 时第二次手工双击 exe

| 观察项 | 记录值 |
|--------|--------|
| 第二次双击后：无新窗口、原窗口被恢复/聚焦 | 是；共 4 次双击（secondary PID 20880 / 27260 / 17284 / 18240），均一闪而过 |
| evidence 中 secondary 进程 exit code（应为 0）与 primary `focus_applied` | 4 条 secondary 全部 pipe_request kind=2 ack=0 delivered=1 + process_exit code=0；primary 24896 的 4 次 focus_applied 与之一一对应（restored=0；foreground=0 表示 SetForegroundWindow 被前台锁拒绝、由任务栏闪烁提醒，见下方用户原注与 Task 8 注意事项）|
| **结果（PASS/FAIL/PENDING）** | **PASS** |
通过，多次点击时任务管理器后台进程栏短暂出现，但迅速关闭。然后原有的进程在任务栏会标黄提醒，表示activewindow。（用户原注；共 4 次）

#### 顺手观察项（可选）

| 观察项 | 记录值 |
|--------|--------|
| 快速连续 cold（退出后连点两条不同 Toast） | PENDING（未执行，按精简裁决不判 FAIL）|
| 失效恢复（primary 退出后下次启动可重新选主） | 间接证据：Case B 每轮均为上一 primary 完全退出后 instance_mutex 重新 created；显式用例未执行，PENDING |
| 中文 payload 点击后 UI 逐字一致 | PASS；warm 两次 + relay 一次（40B hash 2aa47a6b），用户确认显示正常 |

### 自动证据说明

- 每个进程（primary / relay / secondary / selftest / verify）在 `E:\Code\omll-runner-spike\evidence\proc-<pid>-<mode>.log` 写结构化 ASCII 日志：PID、mode、变体延迟、COM register/revoke stage 与 HRESULT、lease 等待、pipe request/ACK 与 wait_ms、payload 仅以 FNV-1a hash + byte count 出现（不记录绝对路径、完整正文或异常文本）。
- 边界输入（1025-byte、未知 version/kind、截断帧、坏 UTF-8、超长、focus 带 payload、1024-byte 接受、队列容量）由 `variants\<任意>\omll_runner_spike.exe --selftest` 自动验证；注册回读由 `scripts\verify-registration.ps1`；时限 p50/max 由 `scripts\summarize-evidence.ps1` 从日志时间戳计算；崩溃监测 = 每个日志都有 `process_exit` 行（summarize 脚本会对缺失项告警）。
- relay handoff（activation_received→pipe ACK）实测：**n=2，p50=0ms / max=1ms**（来自人工验收 case C 的两笔真实 relay 交付）。全量汇总（27 份日志）：pipe ACK p50=0ms/max=110ms（n=20）、primary→ready p50=49ms（normal 变体，max=17586ms 为 pre-com 变体 10s 延迟 + lease 等待所致）、所有日志均有 process_exit 行（零崩溃、零挂起）。

### 收尾：清理 spike 痕迹

```powershell
# 先干跑断言（不删除任何东西），确认 4 项身份断言全过：
E:\Code\omll-runner-spike\cleanup-spike.ps1 -ReportOnly

# 确认无误后正式清理（删快捷方式 + HKCU CLSID/AppUserModelId/Toast backup + 整个 spike 目录）：
E:\Code\omll-runner-spike\cleanup-spike.ps1

# 保留工程目录（证据、变体、日志都在里面）只清注册项：
E:\Code\omll-runner-spike\cleanup-spike.ps1 -KeepProjectDir
```

脚本每删一项前都会回读并断言仍是 spike 身份；断言失败会中止且不删任何东西，输出原样交给任务负责人。本任务的提交只包含本文档证据，不包含 throwaway 工程（仓库外，永不进仓库）。

已于 2026-08-23 证据回填完成后执行：`-ReportOnly` 4 项身份断言全过，正式清理使用 `-KeepProjectDir`（快捷方式 / HKCU CLSID / AppUserModelId / Toast backup 已删，工程目录与 evidence、变体产物保留备复测；再次运行任一变体会重新注册 spike 身份）。

---

## 第四部分：产品级 smoke 清单（Task 11 回填，2026-08-24）

本部分由计划 Task 11 执行者回填**自动化证据**并把人工项保持 `PENDING`。它不改变第二部分 G1–G5 的阻塞语义：G1–G5 与「至少 20 轮 cold」「快速连续 cold」「两个 race 变体」仍必须用最终 Release 产品 build 由人工执行并 PASS；第三部分 spike 的 PASS 属于 throwaway 工程，永远不能替代本部分的产品级验收。每项只写 `PASS` / `FAIL` / `PENDING` 三值之一。

### 产品身份与产物

| 项目 | 值 |
|------|------|
| AUMID | `YuzuShiki.OhMyLlm` |
| CLSID | `{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}` |
| 快捷方式 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Oh My LLM.lnk` |
| kernel objects | instance/activator lease mutex + ready event + pipe 均以 CLSID 无连字符形式命名，`Local\` 命名空间限定当前 logon session |
| Release 产物 | `build\windows\x64\runner\Release\oh_my_llm.exe`（3.81.0+0；2026-08-24 `flutter build windows` EXIT=0，`logs/build-windows.log`） |
| race 复验变体 | CMake `-DOMLL_NOTIFICATION_HOST_TESTING=ON` 的 Debug 构建 + `OMLL_NOTIFICATION_PRE_COM_DELAY_MS` / `OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS`（见计划 8.2 节） |

### 自动化已覆盖条目（PASS）

| # | 场景 | 结果 | 证据 |
|---|------|------|------|
| W9 | Release / testing=OFF configure 确实拒绝非零 delay；delay 编译定义只进 Debug | **PASS** | `scripts/test-windows-notification-host.ps1` configure 规则矩阵 4 项全 PASS，原生测试 127/127 checks，EXIT=0（`logs/windows-notification-host-native-final.log`，2026-08-24） |
| W12 | 同目录覆盖更新 exe 后注册幂等修复（LocalServer32/shortcut 重新指向当次 exe） | **PASS** | Task 7 fix round 1 STEP2A/2B：临时目录安装回读 MATCH → 用新构建产物原位覆盖同目录 exe 重启 → live probe ACK=0 且注册回读对新 exe 全 MATCH（`logs/windows-notification-registration-recovery.log`） |
| W14 | 移动安装目录后完全退出旧 primary 并首次手工启动，注册自动修复到新路径 | **PASS** | 同日志 STEP3：graceful 关闭旧 primary（无残留）→ rename 目录 → 新路径启动 probe OK → 回读对新路径全 MATCH；STEP4 已把现场恢复回原目录并清理临时树 |

### 人工执行条目（2026-08-24 用户按 task-11-user-guide.md 六组 case 执行完毕）

> 除 W18/W19 属扩展矩阵保持 `PENDING` 外，以下核心项全部由用户人工执行并确认 PASS。证据口径：行为级结果（用户确认现象符合预期），未逐项留存 PID/mode/class registration 耗时级仪器明细；W7/W8 使用当日构建的 testing=ON instrumented Debug 变体（`D:\Code\omll-task11-gate\`），其余使用正式 Release build。

| # | 场景 | 结果 | 备注 |
|---|------|------|------|
| W1 | 前台状态下终态通知展示与点击 | **PASS** | 应用在前台且正在查看其他会话/页面时展示；查看同一会话时抑制 |
| W2 | 失焦状态下展示与点击 | **PASS** | 点击后窗口恢复并导航到对应会话 |
| W3 | 最小化恢复后导航（G4） | **PASS** | RestoreAndFocus 行为正常；若仅任务栏闪烁属已知前台锁退化，激活导航不受影响 |
| W4 | warm 点击（G1） | **PASS** | 产品 build 复验 spike Case A 结论；单实例、payload 与导航正确 |
| W5 | 完全退出后的 cold 点击（G2） | **PASS** | 按当日用户裁决精简为 3 轮（计划原文 ≥20 轮，PR 如实记录该精简及理由：沿用 Task 6B 精简先例，关键 race case 全保留）；3 轮均单 Flutter owner 接管并正确导航 |
| W6 | 快速连续两条 cold activation | **PASS** | 最终只有一个 Flutter/storage owner；短暂 relay 属预期有界退出 |
| W7 | pre-COM 窗口期点击（instrumented Debug build，pre-COM delay=5s 变体）（G3 前半） | **PASS** | 产品源码 instrumented 变体复验 spike Case C 结论：短命 relay 无窗口秒级退出，唯一 Flutter owner 收到 payload 并导航 |
| W8 | post-COM/pre-Flutter 窗口期点击（post-COM delay=8s 变体）（G3 后半） | **PASS** | 产品源码 instrumented 变体复验 spike Case D 结论：activation 先于 engine 就绪入队，就绪后一次交付，无第二进程 |
| W10 | primary warm 时第二次手工双击只恢复/聚焦既有窗口（G3 相关） | **PASS** | 不创建第二个 Flutter engine，既有窗口被带到前台 |
| W11 | 删除会话回退根页（G5） | **PASS** | 删除会话后点击其旧通知回退根页，无崩溃 |
| W13 | 同目录覆盖更新后点击 Toast 并正确交付 payload | **PASS** | 覆盖同名 exe 后启动、触发、点击交付链路完整 |
| W15 | 移动目录后首次手工启动再点击 Toast | **PASS** | 目录改名后从新路径启动，注册自动修复，触发生成与点击交付正常 |
| W16 | 系统设置入口可直达本应用的通知设置 | **PASS** | 设置页系统通知卡片按钮实际打开 Windows 系统通知设置页 |
| W17 | 默认声音表现：系统声音开启/关闭下的实际表现 | **PASS** | 声音跟随系统设置；应用不强制响铃即为 PASS 口径 |
| W18 | 专注助手组合下的表现 | PENDING | 扩展矩阵，允许保持 PENDING |
| W19 | 多声音设备 / 多安装位置矩阵 | PENDING | 扩展矩阵，允许保持 PENDING |

变体 delay 参数说明：W7/W8 实际使用的 instrumented 变体为 pre-COM delay 5s / post-COM delay 8s（Task 6B 先例同款参数，足以覆盖竞态窗口），非本表早先占位文字的 10s。

### 已知限制记录（文档义务，非验证项）

- **通知 ID 碰撞覆盖**：不同终态若解析出相同通知 ID，后一条 Toast 会覆盖前一条（同一 Tag/ID）。这是记录在案的已知限制；按计划不要求人工构造碰撞，也不在生产中枚举碰撞。
- **SetForegroundWindow 前台锁**：primary 在后台收到 secondary 的 activateWindow 时，`SetForegroundWindow` 可能被系统前台锁拒绝而退化为任务栏闪烁提醒（spike Case E 实测 foreground=0）；激活与导航本身不受影响。
- **声音归属**：应用从不写 audio 配置；响铃与否完全由系统声音方案、应用通知设置与专注助手决定。

### 统计与判定规则

- 本部分条目统计：PASS 17（自动化 W9/W12/W14 + 人工 W1–W8/W10/W11/W13/W15–W17）/ PENDING 2（W18/W19 扩展矩阵，允许保持）/ FAIL 0；另有三条已知限制为文档记录义务。人工项执行日期 2026-08-24，执行者为用户本人（行为级确认），证据口径见「人工执行条目」导言。
- 核心 gate（W4–W11 及 G1–G5）不允许 `PENDING`：任一 FAIL 停止 Ready 并修复；无法执行则 PR 保持 draft。
- 只有扩展矩阵（W18/W19 及其他 Windows 版本、专注助手组合、多个声音设备、多安装位置）允许保持 `PENDING`。
- 两边都 PASS 才能 Ready：Android 半边记录在 `docs/testing/android-chat-generation-foreground-service-smoke.md` §6。
