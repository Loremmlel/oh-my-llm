# Task 6B 人工验收指南（runner-owned spike，最小行为集 A–E）

预计总操作 **≤15 分钟**。所有验证的机制一句话：runner 在 Flutter 之前持有 Toast COM activator；Toast 点击要么直接进运行中的 primary，要么由短命 relay 经 named pipe 转交，任何情况下同一用户会话内只有一个 Flutter/storage owner。

## 开始前 2 分钟准备

1. Windows 设置 → 系统 → 通知总开关打开；专注助手/勿扰暂时关闭。
2. 确认没有残留进程（输出 0 即可）：
   ```powershell
   @(Get-Process omll_runner_spike -ErrorAction SilentlyContinue).Count
   ```
3. 三个变体产物都在：
   ```powershell
   Get-ChildItem E:\Code\omll-runner-spike\variants -Directory
   # 应有 normal、pre-com、post-com 三项
   ```
4. 记住机制：**每次手工启动 exe 都会把 Toast 注册指向当次启动的这个 exe**，所以每个 case 先启动对应变体再发 Toast。

**UI 速览**：窗口上半部分是状态卡（大号 PID、mode、COM/ready/注册状态、变体延迟、待取队列），中间三个按钮「发 Toast：ASCII / 中文 / 1024 字节」，下方列表显示收到的 payload（新→旧，附 hash 和字节数）。点击 Toast 后 1 秒内列表应出现对应条目。

**证据文件位置**：`E:\Code\omll-runner-spike\evidence\proc-<PID>-<mode>.log`（primary / relay / secondary 分文件）。跑完所有 case 后用一条命令看汇总：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Code\omll-runner-spike\scripts\summarize-evidence.ps1
```

---

## Case A：正常版 warm 点击（约 2 分钟）

1. 双击 `E:\Code\omll-runner-spike\variants\normal\omll_runner_spike.exe`，等窗口出现。记下大号 **PID-A**。状态卡应显示：COM activator=是、ready=是、注册=是、变体延迟 0/0。
2. 点按钮「发 Toast：ASCII」→ 右下角弹出 Toast（标题 Omll Runner Spike）→ **点 Toast 本体**（不要点 X）。
3. 预期：1 秒内 UI payload 列表出现 `spike|ascii|activation-test|0123456789`（bytes=38 附近）；PID 仍是 PID-A；任务管理器里始终只有 1 个 `omll_runner_spike` 进程。
4. （可选 30 秒）再点「发 Toast：中文」并点 Toast，列表出现 `spike|zh|中文载荷|通知点击测试` 且汉字不乱码。
5. **回填**：smoke 文档第三部分 Case A 表格（PID、payload 是否到达、进程数峰值、PASS/FAIL）。

**判定 PASS**：payload 一次到达、PID 不变、进程数峰值 1。出现第二个带窗口的进程或 PID 变化 = 硬停止，保留现场记录。

## Case B：正常版完全退出后 cold 点击 ×2~3 轮（约 5 分钟）

每一轮（第 1 轮可直接接着 Case A 做）：

1. 保持窗口开着 → 点「发 Toast：ASCII」→ Toast 弹出（或留在通知中心）→ **关闭 spike 窗口** → 用准备第 2 步的命令确认进程数 = 0。
2. 按 `Win+N` 打开通知中心，点刚才那条 spike Toast。
3. 预期：spike 窗口被系统拉起（这是 RPCSS 按 LocalServer32 启动的同一个 exe）；新窗口 PID 与上一轮不同；UI 状态卡正常（COM=是）；1 秒内 payload 列表出现 `spike|ascii|...`。
4. 顺手看任务管理器：**只有刚拉起的这一个进程**，没有第二个。
5. 回填 smoke 文档 Case B 表格该轮行，回到第 1 步。至少 2 轮，3 轮更稳。

**判定 PASS（每轮）**：恰一个新窗口、payload 一次到达、进程数 1。点了没进程起来（等 60 秒）或 payload 丢失 = 硬停止。

## Case C：pre-COM 延迟版窗口期点击（约 3 分钟，重点回归）

这是上次插件方案 FAIL 的同款窗口期：primary 进程已存在但 COM activator 尚未注册。

1. **先备一条待点 Toast**：如果 Case B 结束后通知中心还有一条未点过的 spike Toast，直接用；否则：双击 `variants\normal\omll_runner_spike.exe` → 点「发 Toast：ASCII」→ 关窗 → 确认进程数 0。
2. 双击 `E:\Code\omll-runner-spike\variants\pre-com\omll_runner_spike.exe`。
3. **立刻记下大号 PID-C**。此时窗口还没出现（primary 正在 pipe 就绪后的 10 秒 pre-COM 延迟里，COM 未注册、lease 空闲）。变体延迟状态卡要等窗口出现才能看到（pre_com_delay_ms=10000）。
4. **趁 10 秒窗口内**（越早越好）去通知中心点那条备好的 Toast。
5. 观察 60 秒，预期：
   - 可能短暂出现**第二个** `omll_runner_spike` 进程（relay，无窗口），几秒内自行消失；
   - 约 10~12 秒后 primary 窗口出现，PID 仍是 PID-C；
   - payload `spike|ascii|...` 在窗口出现后 1 秒内**恰好一次**出现在列表里；
   - 最终任务管理器只剩 PID-C 一个进程。
6. **回填**：smoke 文档 Case C 表格。另外看一眼 relay 证据（把下面的 PID 换成任务管理器里看到的短命进程 PID，或直接看时间戳最新的 relay 文件）：
   ```powershell
   Get-Content E:\Code\omll-runner-spike\evidence\proc-*-relay.log | Select-String 'activation_received|pipe_request|process_exit'
   # 期望：activation_received 有 payload hash；pipe_request ... delivered=1；process_exit code=0
   ```

**判定 PASS**：payload 经 relay 一次转交到 primary、relay 有界退出且不开窗、primary 延迟结束后接棒成为唯一 COM owner。payload 丢失、relay 开出窗口、出现两个带窗口进程 = 硬停止。

## Case D：post-COM/pre-Flutter 延迟版窗口期点击（约 3 分钟）

这次 primary 的 COM activator 已注册并在 pump，但 Flutter 还没启动——验证 callback 不等 Flutter。

1. 备一条待点 Toast（同 Case C 第 1 步）。
2. 双击 `E:\Code\omll-runner-spike\variants\post-com\omll_runner_spike.exe`，记下 **PID-D**。窗口约 10 秒后才会出现。
3. **10 秒内**去通知中心点备好的 Toast。
4. 预期：
   - 点击瞬间**没有任何新进程**（COM 已注册，点击直接进 primary 的 notification STA 线程并进 native 队列）；
   - 约 10 秒后 primary 窗口出现（PID-D），payload 已在列表里等它（延迟结束 Flutter attach 后一次取出）；
   - 全程任务管理器只有 PID-D 一个进程。
5. **回填**：smoke 文档 Case D 表格。可核对 primary 证据：`activation_received` 的时间戳应早于 `flutter_started`：
   ```powershell
   Get-Content E:\Code\omll-runner-spike\evidence\proc-<PID-D>-primary.log | Select-String 'activation_received|post_com_delay|flutter_started|process_exit'
   ```

**判定 PASS**：activation_received 先于 flutter_started、payload 一次到达、无第二进程。若 payload 只有等 Flutter 起来后才收到（activation_received 时间戳晚于 flutter_started）= FAIL。

## Case E：primary warm 时第二次手工双击（约 1 分钟）

1. 保持 Case D 的窗口开着（或重新启动 normal 版），记下 PID。
2. **再双击一次同一个 exe**。
3. 预期：不出现第二个窗口；原 spike 窗口被恢复/置前（如果最小化则还原）；那个二次启动的进程一闪而过（它是 secondary，只发了一条 activateWindow）。
4. 核对证据：
   ```powershell
   # 最新的 secondary 日志应为：pipe_request kind=2 ... ack=0 delivered=1 + process_exit code=0
   Get-Content E:\Code\omll-runner-spike\evidence\proc-*-secondary.log -Tail 4
   ```
5. **回填**：smoke 文档 Case E 表格。

**判定 PASS**：无第二窗口、原窗口被聚焦、secondary 干净退出。

---

## 全部做完后（约 1 分钟）

1. 关闭 spike 窗口，确认进程数 0。
2. 跑汇总，把输出贴到回填备注或发给任务负责人：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File E:\Code\omll-runner-spike\scripts\summarize-evidence.ps1
   ```
   重点看：`relay handoff n>0 p50/max`（来自 Case C）、`every log has a process_exit line`（无崩溃/无挂起）。
3. 按 smoke 文档第三部分「收尾」清理（先 `-ReportOnly` 断言，再决定是否 `-KeepProjectDir`）。**清理会删除 evidence 目录**（若选整目录删除），需要保留证据就先备份或用 `-KeepProjectDir`。

## 硬停止条件（任一出现即停，保留现场）

- 任何 case 出现两个带窗口的 spike 进程，或 payload 丢失/重复/乱序。
- relay 打开了窗口（它必须是无窗口短命进程）。
- 点击后 60 秒无进程起来或 payload 未到达。
- 出现崩溃弹窗 / 进程不退出（evidence 缺 process_exit 行）。
