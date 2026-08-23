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

> 注：Task 6A 已完成（插件方案 FAIL 证据已归档），本 brief 的执行对象只有 Task 6B。以下为计划第 8 节中 spike 需要遵循的协议/注册/COM 细节摘录（spike 实现的是其最小版本，身份值必须换成 spike 自己的临时身份）。

**8.1 身份参考（spike 不得复用这些值）**

- 产品：appName `Oh My LLM`、AUMID `YuzuShiki.OhMyLlm`、CLSID `{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}`、shortcut `FOLDERID_Programs\Oh My LLM.lnk`、mutex `Local\YuzuShiki.OhMyLlm.NotificationHost...`、pipe `\\.\pipe\YuzuShiki.OhMyLlm.NotificationHost.v1`。
- 旧插件 spike：AUMID `YuzuShiki.OmllNotificationSpike`、CLSID `{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}`，工程保留在 `E:\Code\omll-notification-spike`（只读参考）。
- spike 的三种进程模式：`primary`（唯一可创建 Flutter engine/窗口/存储，持有长期 COM class object、pipe server、Toast notifier）；`activationRelay`（命令行含 COM 传入的 `-Embedding`（大小写不敏感、只匹配独立 token，不做 substring）且 instance mutex 已存在；只跑原生 COM/message loop，交付 payload 后退出）；`manualSecondary`（非 `-Embedding` 且 mutex 已存在；只向 primary 发 `activateWindow`，等 ACK 后退出）。

**8.3 唯一 owner 与 relay 协议（spike 最小实现要点）**

- `CreateMutexW(nullptr, FALSE, fixedName)` + `GetLastError()==ERROR_ALREADY_EXISTS` 原子判断是否已有 primary；`Local\` namespace 限定当前 logon session；禁止进程名/PID 枚举/exe 路径猜测。
- ready event 为 manual-reset：新 primary 选主成功后先 `ResetEvent`，长期 owner ready 后 `SetEvent`，shutdown 在 revoke 前再次 reset；relay 不得设置它。不得把上一任遗留 signaled handle 当作当前 ready。
- 长期 COM owner 与短命 relay 通过 activator lease mutex 串行：primary 创建 pipe 后立即竞争 lease，成功后注册长期 class object 并持有到 shutdown；relay 只有在 primary 尚未 ready 且成功取得 lease 时才注册短命 class object。任何时刻不得有两个 class object owner。
- pipe：`PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS`；一条 request 一个完整 pipe message，最大 1036 bytes；header 固定 12 bytes：ASCII magic `OMLN`（4）、LE `uint16 version=1`、LE `uint16 kind`（1=`notificationActivation`，2=`activateWindow`）、LE `uint32 payloadByteLength`；随后恰好 payload bytes。activation payload 必须合法 UTF-8 且 ≤1024 bytes；focus length 必须为 0。未知 version/kind、超长、截断、focus 带 payload、header 与 message 长度不一致、`ERROR_MORE_DATA` 一律拒绝。
- ACK 固定 8 bytes：ASCII magic `OMLA`、LE `uint16 version=1`、LE `uint16 status`（0=`accepted`、1=`invalidFrame`、2=`queueFull`、3=`shuttingDown`）；只有 0 视为交付；一个 connection 串行一条 request/ACK 后关闭。
- primary 收 `notificationActivation` 先写入上限 32、FIFO 的 native pending queue 再 ACK；收 `activateWindow` 只合并一个 pending focus flag。relay 每次 callback 建独立 pipe request 并等 ACK；有 `relayDrainGrace`（无在途 callback 才退出）与 `relayMaxLifetime` 防永驻，具体值由 spike 实测选定并记录。primary 若发现 lease 暂由 relay 持有，只等待固定上界后重试。
- relay/secondary 执行 `DartProject`、出现 Flutter window、打开存储，或退出后残留，均为硬 FAIL。

**8.4 身份注册格式（spike 按此格式写自己的临时身份）**

1. `GetModuleFileNameW` 取 exe 绝对路径；`SHGetKnownFolderPath(FOLDERID_Programs)` 取当前用户 Programs。
2. 创建/重写 shortcut（spike 名）：target 指向 exe，working directory 指 exe 目录，`PKEY_AppUserModel_ID` 写 spike AUMID。
3. `CLSIDFromString` 解析带花括号 CLSID；`PKEY_AppUserModel_ToastActivatorCLSID` 写 `PROPVARIANT{vt=VT_CLSID, puuid=<parsed>}`，不得写 REG_SZ。
4. 写 `HKCU\Software\Classes\CLSID\{spike CLSID}\LocalServer32`：默认值为带双引号、无参数的 exe 绝对路径；`ServerExecutable` REG_SZ 为不带引号、无参数同一路径。注册值不自创参数，只接受 COM 自动附加的 `-Embedding`。
5. 幂等写 `HKCU\Software\Classes\AppUserModelId\<spike AUMID>`：`DisplayName`（REG_EXPAND_SZ）、`CustomActivator`（REG_SZ 带花括号 CLSID）。
6. 失败只返回固定 failureStage；不记录绝对路径/HRESULT 文本。只写 HKCU，不请求管理员。

**8.5 COM activator 与队列（spike 最小实现要点）**

- notification STA thread：独立 `CoInitializeEx(COINIT_APARTMENTTHREADED)`、`CoRegisterClassObject(CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE)`、保存 cookie、持续 pump native message loop；注册成功且 pump 开始后才标记 ready。
- `Activate(appUserModelId, invokedArgs, data, count)` 为 `noexcept`、内部 catch-all；只验证 AUMID、nullable/长度、UTF-16→UTF-8；不解析 JSON、不判断业务、不记录 payload。
- callback 不等待 Flutter/路由/窗口；primary 只入队（上限 32 项、每项 ≤1024 UTF-8 bytes）；relay 只做有界 IPC。
- shutdown：先标记 stopping、reset ready、由注册 cookie 的同一 STA thread `CoRevokeClassObject` 后退出 pump；多次 shutdown 幂等。

**8.6 Toast XML（spike 用）**

- 固定 `toast/visual/binding template="ToastGeneric"/text+text`，root `launch` 为 payload 字符串；XML escaping 必须实现；不包含 `<audio>`/`scenario`/图片。

