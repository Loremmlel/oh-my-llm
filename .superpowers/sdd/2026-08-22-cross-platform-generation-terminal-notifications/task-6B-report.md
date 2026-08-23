# Task 6B 报告：Windows runner-owned 激活 spike（throwaway）

日期：2026-08-23　状态：实现者自检全部通过，人工验收（最小行为集 A–E）待用户执行（见 task-6B-user-guide.md）。

## 做了什么

在产品仓库外新建 throwaway Flutter Windows 工程 `E:\Code\omll-runner-spike`（`flutter create --platforms=windows`，无任何通知插件），在 runner 原生层实现了 brief 8.1–8.6 的最小版本并验证协调机制：

- **进程模式分发**（8.1）：`wWinMain` 解析命令行（`-Embedding`/`/Embedding` 独立 token、大小写不敏感、无 substring 误匹配）+ instance mutex `ERROR_ALREADY_EXISTS` 原子判定 → `primary` / `activationRelay` / `manualSecondary` 三模式；无进程名/PID 枚举。
- **primary 时序**：ready event（manual-reset，选主后先 reset 陈旧 signaled）→ pipe server（独立线程，不依赖 Flutter/UI）→ 身份注册（8.4 全格式）→ [`SPIKE_PRE_COM_DELAY_MS` 延迟] → activator lease（250ms 切片、总上界 30s）→ notification STA 线程（CoInitializeEx(APARTMENTTHREADED) + CoRegisterClassObject(CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE)，pump 开始 dispatch 后才 SetEvent ready）→ [`SPIKE_POST_COM_PRE_FLUTTER_DELAY_MS` 延迟] → DartProject/Flutter engine。两个延迟是独立 CMake compile definition 变体，不阻塞 pipe 线程与 STA pump。
- **relay**（COM 拉起且 mutex 已存在）：竞争 lease 成功且 primary 未 ready 时注册**短命** class object，pump；每个 Activate 有界 pipe 转发（kind=1 帧 + ACK 等待 ≤3s）；`relayDrainGrace` 静默期后退出，`relayMaxLifetime` 绝对上界兜底；revoke 与 release 都在退出前完成。primary ready 且持有 lease 时 relay `relay_abort_primary_ready` 有界放弃；lease 可取但 ready signaled 判定为陈旧事件继续注册（`relay_stale_ready_ignored`）。
- **secondary**（无 `-Embedding` 且 mutex 已存在）：只发一帧 `activateWindow`（kind=2，payload 必须为 0 字节），等 ACK 后退出；primary 侧合并为 pending focus flag，STA 恢复/前置窗口。
- **pipe v1 帧协议**（8.3）：`OMLN` + u16 version + u16 kind + u32 len，payload ≤1024；ACK `OMLA` 8 字节 4 状态；一条连接一帧一 ACK；`PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS`；未知 version/kind、超长、截断、focus 带 payload、header 与消息长度不一致、`ERROR_MORE_DATA`、非法 UTF-8 一律 invalidFrame；primary 侧 32 项 FIFO native 队列（满→queueFull ACK）。
- **COM activator**（8.5）：`INotificationActivationCallback::Activate` noexcept + catch-all，只验证 AUMID/nullable/长度/UTF-16→UTF-8；primary 只入队，relay 只做有界 IPC；shutdown 先 stopping、reset ready、由注册线程 `CoRevokeClassObject` 再退 pump。
- **Toast**（8.6）：固定 ToastGeneric XML，root `launch` = payload（XML 转义实现），无 audio/scenario/图片；WinRT 经 `RoGetActivationFactory` + `CreateToastNotifierWithId(AUMID)`。
- **Dart UI 极简**：显示 mode/PID/host 状态/收到的 opaque payload 列表（hash+bytes），三个按钮发测试 Toast（ASCII/中文/1024 字节边界）。

## 身份值（与产品 8.1、旧 spike 均不同，集中定义于 `windows/runner/spike_identity.h`）

| 项 | 值 |
|----|----|
| AUMID | `YuzuShiki.OmllRunnerSpike` |
| CLSID | `{9E60E9C6-0CD2-4727-A762-A18DD8079E80}`（[guid]::NewGuid() 现生成）|
| 快捷方式 | `FOLDERID_Programs\Omll Runner Spike.lnk` |
| instance mutex | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.Instance` |
| lease mutex | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.ActivatorLease` |
| ready event | `Local\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.Ready`（manual-reset）|
| pipe | `\\.\pipe\OmllRunnerSpike.9e60e9c60cd24727a762a18dd8079e80.v1` |

## 选定常量（spike 实测依据见自检证据；产品回写第 8 节前还需 case C/D 人工数据）

| 常量 | 值 | 依据 |
|------|----|----|
| lease 切片等待 | 250ms | 任意值，足够细且日志可读 |
| primary lease 总上界 | 30000ms | relay 最长持有 15s（max lifetime），30s 覆盖两代 relay |
| relay lease 总上界 | 3000ms | primary 正常 lease-acquire→ready 为 0–5ms，3s 远超正常窗口 |
| pipe 连接上界 | 2000ms | primary 先建 pipe 再做一切，窗口极小 |
| pipe ACK 上界 | 3000ms | 实测 ACK p50=0ms/max=110ms |
| relayDrainGrace | 1000ms | 静默期判定；连续点击间隔实测场景下足够 |
| relayMaxLifetime | 15000ms | 无回调兜底；SCM 激活到达在秒级以内 |
| primary ready 等待 | 10000ms | 实测注册→ready 全程 <10ms |

## 文件清单

spike 工程 `E:\Code\omll-runner-spike`（新增，仓库外）：

- `windows/runner/spike_identity.h` — 身份与常量单一来源。
- `windows/runner/spike_runtime.{h,cpp}` — 模式分发、primary/relay/secondary 流程、selftest、verify。
- `windows/runner/spike_com.{h,cpp}` — activator/factory/STA 线程/Toast/队列。
- `windows/runner/spike_pipe.{h,cpp}` — pipe server（overlapped，分片可停）+ 一次性客户端。
- `windows/runner/spike_protocol.{h,cpp}` — v1 帧编解码与全量校验。
- `windows/runner/spike_registration.{h,cpp}` — 8.4 注册 + 8 项回读断言。
- `windows/runner/spike_evidence.{h,cpp}`、`spike_text.{h,cpp}` — 结构化日志；FNV-1a/UTF-8 校验/XML 转义。
- `windows/runner/main.cpp`、`flutter_window.{h,cpp}`、`lib/main.dart` — 入口重写、方法通道、极简 UI。
- `windows/runner/CMakeLists.txt` — 新源文件、链接库（propsys/runtimeobject/shell32/advapi32/ole32）、`_WIN32_WINNT=0x0A00`、两个延迟 cache 变量（模板 `_HAS_EXCEPTIONS=0` 被显式设置替换，模板注释允许）。
- `scripts/build-variants.ps1`（三变体构建+快照）、`scripts/verify-registration.ps1`、`scripts/summarize-evidence.ps1`、`scripts/selfcheck-variants.ps1`、`scripts/selfcheck-relay.ps1`（后两个为实现者一次性自检脚本，可删）。
- `cleanup-spike.ps1`（`-ReportOnly` / `-KeepProjectDir`）、`omll-runner-spike.marker`（evidence 目录定位）、`variants\{normal,pre-com,post-com}\`（自包含产物）、`evidence\`（全部结构化日志）、`logs\`（构建日志）。

产品仓库内改动（唯一允许的文件，追加新章节，未动第一部分 Task 6A 内容）：

- `docs/testing/windows-chat-generation-notifications-smoke.md` — 文末追加「第三部分：runner-owned spike（Task 6B）」（环境身份、构建命令、自检记录、A–E 记录区、自动证据说明、清理说明）。

其他交付物（.superpowers/sdd 同目录）：本报告、`task-6B-user-guide.md`。未做任何 git commit；smoke 文档保持未跟踪。

## 实现者自检证据摘要（全部完成，无需用户操作的部分）

1. **三变体构建 EXIT=0**：`scripts\build-variants.ps1`，产物快照 `variants\{normal,pre-com,post-com}`，三份 exe MD5 互不相同（延迟 compile definition 生效）；构建后 CMake cache 复位为 0/0。
2. **正常版全链路**（`--auto-toast` 自动发 Toast，无需点击）：evidence `proc-30144-primary.log` 等 5 份 primary 日志均为 `registration_ok hr=0 → lease_acquired 0ms → com_register hr=0 → sta_pump_started → ready_set → flutter_started → toast_show stage=7 hr=0 → （关闭）ready_reset → com_revoke hr=0 → pipe_server_stopped → lease_released → process_exit code=0`。WinRT `Show()` 在真实 Shell 返回 S_OK。
3. **注册回读**：`scripts\verify-registration.ps1` 8 项全 MATCH（shortcut AUMID / ToastActivatorCLSID 为 VT_CLSID、LocalServer32 quoted default + 无参数 + unquoted ServerExecutable 同路径、AppUserModelId DisplayName REG_EXPAND_SZ / CustomActivator REG_SZ）。
4. **自测模式**（`--selftest`，12+1 case 全 PASS，exit 0）：1024-byte 接受；1025-byte/未知 version/未知 kind/截断帧/focus 带 payload/坏 UTF-8/超长消息(1512B)/坏 magic 全部 invalidFrame；空 focus 帧接受；33 帧序列 32 accepted + 第 33 帧 queueFull。
5. **warm 协调**：primary ready 时 `-Embedding` 启动 → `relay_abort_primary_ready`（0ms 退出）；普通再启动 → secondary `kind=2 ack=0 delivered=1`、primary `focus_applied`、secondary exit 0。
6. **pre-COM 窗口 relay 生命周期**（`selfcheck-relay.ps1`，模拟 SCM 在延迟窗口拉起 relay）：relay `lease_acquired 0ms → com_register owner=relay hr=0 → relay_pump_started →（无回调）relay_max_lifetime_reached 15s → com_revoke hr=0 → lease_released → exit 0`；同期 primary 以 250ms 切片重试 7.5s 后接棒注册——时间线上 relay register(21:51:49.060) 与 primary register(21:52:04.073) 严格被 lease 串行，任何时刻只有一个 class object owner，全程零崩溃、双方 exit 0。
7. **时限实测**（`scripts\summarize-evidence.ps1`）：pipe ACK n=20 p50=0ms max=110ms；normal 变体 process_start→ready_set 44–52ms（summary 中的 17.6s 离群值是 pre-com+relay 故意构造的场景：10s 延迟 + 7.5s lease 等待，非注册本身开销）；11 份日志全部有 `process_exit` 行（无崩溃/无挂起信号）。
8. **清理断言**：`cleanup-spike.ps1 -ReportOnly` 4 项（shortcut / HKCU CLSID / AppUserModelId / Toast backup）全部 present+identity-ok，exit 0，未删除任何东西。

## 已知风险与不确定点

1. **SCM 真实拉起路径未由实现者触发**：本机自检覆盖了 relay 的全部内部生命周期（lease 串行、注册、pump、有界退出），但「RPCSS 因真实 Toast 点击拉起 `-Embedding` 进程并把 Activate 编组进来」这一段只能由人工验收 case C/D 验证——这正是 spike 的目的。已有证据（cold 变体二进制存在、LocalServer32 格式与旧 spike 被验证可 cold 拉起的格式一致）降低了风险但不是证明。
2. **relay handoff p50/max 尚无数据**：需要 case C 点击产生真实 activation→pipe 交付对；summarize 脚本已支持计算，做完验收即可得出，供产品第 8 节回写。
3. **SetForegroundWindow 可能被前台锁拒绝**：primary 侧 `focus_applied foreground=0` 在后台进程调用时可能失败（Windows 前台权限）；ShowWindow/SW_RESTORE 已生效，spike 只记录值不重试。产品实现 focus 行为时需另行处理（如 AllowSetForegroundWindow 或最小化到托盘场景）。
4. **双 relay 极端并发**：快速连点两条 Toast 且 primary 未注册时可能拉起两个 relay；协议上第二个 relay 会等 lease（3s 上界），若等待超时且 primary 仍无 ready 则该次点击的 Activate 由 SCM 决定重试或失败——brief 允许（快速连续 cold 是用户顺手观察项），但产品实现时应考虑 relay 等待期间收到 SCM 取消的优雅路径。
5. **primary 崩溃残留场景**：primary 持 lease 崩溃后 relay 对 mutex 的 WAIT_ABANDONED 按"取得"处理并继续短命注册；pipe 不存在时 relay 2s 连接失败后退出，payload 丢失（primary 已死，属 brief case 9 的产品层选主恢复范畴，spike 不展开）。
6. **selftest 的 33 帧队列容量测试与 20 帧 timing 之间 Sleep(150) 启动等待**：依赖 pipe 线程先建实例，若极端调度延迟可能首连失败重试（客户端有 2s 重试，未观察到失败）。
7. **Windows PowerShell 5.1 怪癖（已在脚本内规避并注释）**：反引号续行后的裸参数 `$var` 不展开（构建脚本首跑曾把字面 `$PreComDelayMs` 写进 CMake cache 导致一次构建失败，已通过给 `-D` 参数加引号修复并清除 cache）。
8. **toast settings backup 键**：`HKCU\...\Notifications\Settings\<AUMID>` 由系统在首次发 Toast 后创建；cleanup 的 ReportOnly 对该键只断言存在性（值内容系统自管）。

## 对产品实现的直接可迁移结论（待 case A–E 证实后回写第 8 节）

- runner 在 DartProject 之前持有 COM activator 的结构可行：正常路径注册→ready 实测 <60ms，对启动时长影响可忽略。
- lease 串行化足以保证「任何时刻至多一个 class object owner」：pre-COM 10s 窗口的极端场景下 primary 以 250ms 切片等待 7.5s 平滑接棒，无 RPCSS 竞态。
- pipe ACK 本机回环 p50=0ms/max=110ms；3s ACK 上界有 ~27 倍余量。
- 建议产品沿用：ready event reset-on-create（防陈旧 signaled）、relay 对「ready signaled 但 lease 可取」按陈旧事件处理、STA 线程独占 register/revoke。
