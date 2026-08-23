# Task 6 用户操作手册：Windows 未打包 Toast 激活 spike

本手册带你完成 Task 6 的全部人工验收。工程已由实现者搭好并通过构建验证；你只需要按步骤启动 exe、点 Toast、把看到的东西记下来（或直接回填 smoke 文档）。

**预计耗时**：约 30–45 分钟（其中冷启动循环 20 轮占大头）。

---

## 准备

1. **确认系统通知可用**：Windows 设置 → 系统 → 通知 已开启；专注助手/勿扰模式建议暂时关闭，否则 Toast 可能不弹出或静默进通知中心。
2. **确认没有残留 spike 进程**：
   ```powershell
   Get-Process omll_notification_spike -ErrorAction SilentlyContinue
   ```
   有输出就先关掉对应窗口。
3. **两个构建都在** `E:\Code\omll-notification-spike\dist\` 下：
   - `dist\normal\omll_notification_spike.exe` —— 正常版
   - `dist\delayed\omll_notification_spike.exe` —— 延迟版（插件初始化推迟 10 秒）
4. **重要机制**：每次手工启动 exe 都会把快捷方式和 LocalServer32 注册“修复”为当次启动的 exe。所以**做哪一步就用哪个 exe 启动一次**，注册就会指向它。

## spike 界面速览

- **PID 大数字**：当前进程 PID。任何时刻它变了 = 出现了第二个实例。
- **命令行参数行**：COM 冷启动拉起的进程会显示 `-Embedding`；同时会显示 `SPIKE_REG_OK`（C++ 注册成功）。这两个都在 = 验收项 1 的关键证据。
- **插件状态条**：灰色等待 / 红色延迟倒计时 / 绿色已初始化 / 红色失败。
- **计数器行**：callback 次数、launch-details 回读、去重抑制、仅 launch-details 收到、逻辑激活数。
- **日志列表**：每次激活的原始 payload 全文回显（CALLBACK 与 LAUNCH-DETAILS 两条通道都显示）。

**判定核心口诀**：点击一次 Toast 后，「逻辑激活数」应恰好 +1；payload 必须与界面下方参照卡里的原文逐字一致（含中文与希腊字母）；进程列表里永远只有一个 `omll_notification_spike` 进程。

---

## 步骤 0：首次启动 + 注册回读（验收项 1）

1. 双击启动 `dist\normal\omll_notification_spike.exe`。
2. **记录窗口里的大号 PID**（下称 PID-A）。
3. 观察命令行参数行：应为空或只有 `SPIKE_REG_OK`。**看到 SPIKE_REG_OK = C++ 注册成功**；若显示 `SPIKE_REG_FAIL@stageN@hr...`，记下原文，这是 FAIL 证据。
4. 可选回读核对（PowerShell，直接复制运行）：
   ```powershell
   Get-ItemProperty 'HKCU:\Software\Classes\CLSID\{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}\LocalServer32' | Select-Object '(default)', ServerExecutable
   ```
   预期：`(default)` 是带双引号的 spike exe 路径，`ServerExecutable` 不带引号同路径。
5. 点击「发送主测试 Toast」。屏幕右下角应弹出标题为 “OMLL Notification Spike” 的通知。
6. **点击这个 Toast**（不要点 X 关闭，要真正点通知本体）。
7. 观察：
   - 日志出现一行 `[CALLBACK] type=selectedNotification payload=生成终态通知激活验证-Payload-Ω-20260823`
   - 随后出现 `[LAUNCH-DETAILS] ... payload=同一字符串` + 一行 `[DEDUP] ... 只计一次`
   - 「逻辑激活数」= 1，PID 仍是 PID-A
   - **以上全中 = warm 路径正常**（验收项 2 的主证据 + 验收项 6 的 warm 半边）。

**什么算什么**：callback 行 payload 与参照卡逐字一致 → 记 PASS 证据；payload 缺字/乱码/为 null → 记 FAIL 并截图。

---

## 步骤 1：warm 复核（验收项 2 完整证据）

应用保持运行（PID-A 不变）：

1. 再点两次「发送主测试 Toast」，依次各点击弹出的 Toast。
2. 每次点击后：「逻辑激活数」应精确递增到 2、3；PID 始终是 PID-A。
3. 打开任务管理器（或 PowerShell `Get-Process omll_notification_spike`），**确认始终只有一个 spike 进程**。

**什么算什么**：任何一次 warm 点击后进程数变 2 或 PID 变了 → 命中硬停止条件「warm 点击启动第二个实例」，立即停止并报告。

---

## 步骤 2：冷启动循环 ×20（验收项 3 主证据）

每一轮流程（约 1 分钟/轮）：

1. **完全退出**：关闭 spike 窗口，然后确认：
   ```powershell
   @(Get-Process omll_notification_spike -ErrorAction SilentlyContinue).Count
   ```
   输出必须是 `0`。
2. **重新发送 Toast**：重新双击 exe → 点「发送主测试 Toast」→ **直接关闭窗口并再次确认进程数为 0**。此时 Toast 留在通知中心。
3. **点击通知中心的 Toast**：按 `Win+N` 打开通知中心，点击刚才那条 spike 通知。
4. COM 会冷启动一个新进程。观察新窗口：
   - **记录新 PID**（每轮应不同）
   - 命令行参数行应显示 `-Embedding` 和 `SPIKE_REG_OK`
   - 日志应有 `[CALLBACK] payload=生成终态通知激活验证-Payload-Ω-20260823`
   - 应有 `[LAUNCH-DETAILS] didNotificationLaunchApp=True ... 同一 payload` + `[DEDUP] 只计一次`
   - 「逻辑激活数」= 1
5. 回填 smoke 文档第 N 轮那一行，然后回到第 1 步。

> 小技巧：第 3 步也可以不等通知中心，Toast 弹出的几秒内直接点屏幕上的浮层，效果相同。20 轮里建议至少 5 轮走纯通知中心路径、其余走浮层直点，两种都算 cold。

**什么算什么**：
- 20 轮全部「callback+launch-details 同 payload、逻辑激活数=1、单进程、有 -Embedding」→ 验收项 3 PASS。
- 出现一次「窗口起来了但 CALLBACK 无行且 launch-details 为 null」→ payload 丢失，硬停止。
- 出现一次「点了没反应 / 没有进程起来」（等足 60 秒）→ 冷启动失败，硬停止。
- callback 行数 ≥2 但逻辑激活数仍=1 属于正常的去重行为，不是失败；但如果 launch-details 显示 `didNotificationLaunchApp=False` 或 payload 不同，记下来作为异常证据。

---

## 步骤 3：快速连续 cold / 两条 Toast（验收项 4）

1. 启动 normal exe → 依次点「发送主测试 Toast」和「发送第二条 Toast」→ 完全退出并确认进程数为 0。
2. `Win+N` 打开通知中心，**尽可能快地连续点击两条 spike 通知**（先点旧的那条）。
3. 等待约 15 秒让一切尘埃落定，然后：
   ```powershell
   Get-Process omll_notification_spike | Select-Object Id, StartTime
   ```
4. 判定：
   - **只有一个进程** → 本项 PASS。查看该进程日志：应有对应 payload 的交付记录（一条或两条，取决于 Windows 是否合并激活；两条都到则逻辑激活数=2）。
   - **两个进程并行** → 硬停止「快速连续 cold 激活产生两个进程」。
5. 用另一条作第一条再重复一遍（可选但推荐）。

---

## 步骤 4：10 秒延迟版手工启动窗口（验收项 5）

> 这是和步骤 3 不能互相替代的关键 case：重现「进程已手工启动但 COM class object 还没注册」的窗口期。

1. 先确保有一条待点的 spike Toast 在通知中心（用 normal 版发一条然后完全退出）。
2. 双击启动 `dist\delayed\omll_notification_spike.exe`。
3. **立刻记录红色横幅下方的大号 PID（PID-B）**。此时插件状态条显示红色倒计时（≈10 秒）。
4. **在倒计时结束前**（前 8 秒内最佳）去通知中心点击那条 Toast。
5. 观察接下来 60 秒内发生了什么，逐项记录：
   - 是否出现了**第二个** spike 窗口？（任务管理器看进程数）
   - PID-B 的窗口在倒计时变绿后是否收到 `[CALLBACK]`？
   - 如果有第二个窗口：它的 PID、参数行内容、日志里有没有 payload？
6. 判定：
   - **最终全程只有 PID-B 一个进程，且原 payload 在初始化完成后由 callback/LAUNCH-DETAILS 交付恰好一次（逻辑激活数=1）** → PASS。
   - 出现第二进程 / payload 丢失 / 60 秒内未交付 → 硬停止。
7. 无论结果如何，这一步的完整现象（含时间线）写进 smoke 文档验收项 5 的备注列——即使 PASS，也把「点击时倒计时还剩几秒」「payload 在几秒后才到达」记上。

---

## 步骤 5：非 ASCII 校验（验收项 6）

其实你在步骤 0–4 里一直在校验它：

- 主 payload 参照原文：`生成终态通知激活验证-Payload-Ω-20260823`（29 字符）
- 第二条参照原文：`连续冷启动第二条-Payload-β-98765`（24 字符）

对照规则：日志里 CALLBACK 行与 LAUNCH-DETAILS 行的 payload 必须**逐字符**等于上面原文（汉字、希腊字母 Ω/β、连字符个数都不能差）。warm（步骤 0/1）与 cold（步骤 2 至少一轮）都要各自核对一遍并在表格备注里写「一致」。

---

## 步骤 6：native 生存性观察（验收项 7）

贯穿所有步骤：

1. **崩溃对话框**：全程不应出现 “omll_notification_spike.exe 已停止工作” / WER 红叉 / `std::terminate` / access violation 弹窗。
2. **退出码**：每轮正常关闭窗口后跑：
   ```powershell
   @(Get-Process omll_notification_spike -ErrorAction SilentlyContinue).Count
   ```
   为 0 即干净退出（Flutter runner 正常关闭返回 EXIT_SUCCESS）。
3. **事件查看器抽查**（可选但推荐）：`eventvwr` → Windows 日志 → 应用程序，来源筛选 `.NET Runtime`/`Application Error`，确认测试期间没有 spike 相关的错误条目。
4. 注意：Dart 侧 catch 到的异常会在日志里以 `INIT-FAIL`/`SHOW-FAIL` 行显示——那**不算**通过本项的证据；本项要求的是没有任何 native 层终止。

---

## 收尾

### 1. 回填 smoke 文档

编辑 `E:\Code\oh-my-llm\docs\testing\windows-chat-generation-notifications-smoke.md`：

- 把 7 行验收表的 PENDING 改成 PASS/FAIL，填入你记录的 PID、payload 原文片段、进程数；
- 逐轮填冷启动 20 轮表格；
- 任一 FAIL 时在备注写清现场（哪个步骤、第几轮、看到了什么）。

### 2. 运行清理脚本

```powershell
# 先干跑一遍断言（不删除任何东西），确认全部 OK：
E:\Code\omll-notification-spike\cleanup-spike.ps1 -ReportOnly

# 确认无误后正式清理（删快捷方式 + 三个注册键 + 整个 spike 目录）：
E:\Code\omll-notification-spike\cleanup-spike.ps1

# 如果还想保留 exe 目录以后复测：
E:\Code\omll-notification-spike\cleanup-spike.ps1 -KeepProjectDir
```

脚本每项删除前都会回读并断言仍是 spike 身份；如果它报「断言失败」并中止，说明某个值被别的程序改写了——**不要强行删除**，把输出交给 controller。

### 3. 把结果告诉 controller

按以下格式发一段总结即可：

```
Task 6 spike 结果：<7 项全 PASS / 第 N 项 FAIL>
- 各项一句话结论（或直接说已回填 smoke 文档）
- 冷启动实际完成轮数：<N>/20
- 异常现场：<无 / 具体描述>
- 清理脚本：<已执行 / ReportOnly 未清理 / 断言中止>
```

controller 会据此决定放行 Task 7–11 还是触发硬停止。
