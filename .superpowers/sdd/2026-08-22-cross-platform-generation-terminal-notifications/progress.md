# SDD ledger - plan: docs/plans/2026-08-22-cross-platform-generation-terminal-notifications.md

## Setup

- Workspace: `.superpowers/sdd/2026-08-22-cross-platform-generation-terminal-notifications/`
- Branch: `feat/cross-platform-generation-notifications`（计划指定的目标分支，非 master，无需额外 worktree）
- Base HEAD at start: `3cf0360`（计划文档已单独提交，产品实施从本 HEAD 起）
- 无独立 spec 文件：本计划自身包含产品契约（第 1-10 节为 spec 内容，第 11 节起为实施步骤）。计划是唯一权威；本 ledger 中无 spec 佐证的 ruling 均为 provisional。

## Pre-flight scan

| 检查项 | 结果 |
| --- | --- |
| Task 1 → Task 3（`projectChatGenerationTerminalReceipt` + `ChatGenerationTerminalNotifications` port 的产出/消费） | 一致 |
| Task 2 → Task 3（provider 接口；5.5 节明确 adapter 默认 no-op，中间提交可编译） | 一致 |
| Task 2 → Task 9（adapter provider 默认 no-op，Task 9 composition override） | 一致 |
| Task 3 → Task 4（同文件 `android_chat_generation_foreground_service.dart` 先删 `fail()` 再迁 bridge） | 顺序衔接；Task 4 dispatch 需携带「fail 已在 Task 3 删除」 |
| Task 4 → Task 5（channel 名：Task 4 暂用旧名 `.../chat_generation_foreground`，Task 5 原子切换，无双写/双 handler） | 一致（第 13 节明确） |
| Task 6 → Task 7-11（spike 阻塞 Windows 产品实现） | 一致；但 spike 需要真实人机交互 + 仓库外副作用（HKCU 注册表/临时工程），届时停止询问用户 |
| Task 7 → Task 8（registration decoder 产出 → Windows adapter 消费） | 一致 |
| Task 9 → Task 10（settings provider 装配 → UI 消费；port 由 Task 2 提前创建） | 一致（10.1 节明确时序） |
| Task 5 (Kotlin) ↔ Task 9 (composition)：Android adapter Task 4 创建、Task 9 才接线 | 一致（中间提交可编译） |
| 测试文件重命名时序（`chat_generation_foreground_service_bindings_test.dart` Task 3 修改、Task 9 重命名） | 一致 |
| 5.2 节 FNV-1a 预核对向量 | 已独立复算（PowerShell 按 UTF-8/32-bit 公式）：`succeeded`→1672833428、`foregroundProtectionTimedOut`→937742124，均与计划一致 |
| 计划引用的现有文件（coordinator / bindings / android+noop adapter / Kotlin 4 文件 / windows/runner） | 全部存在 |
| Task 11 最小原生 gate（人工 smoke） | 计划允许保留 draft；届时如实汇报，不得把 PENDING 写成 PASS |

Ruling: Task 6 spike 由人工执行后才能解锁 Task 7-11 - spike 的阻塞验收清单要求点击系统 Toast、观察进程列表等真实 Shell/COM 人机交互，且写 HKCU 注册表与开始菜单快捷方式（worktree 外副作用）- 若错误成本是整条 Windows 链路基于未验证假设实现后返工。

扫描结论：计划内部无矛盾，未发现任务间冲突或与全局约束冲突的强制要求。开始执行。

## Task 1

Task 1: complete (commits 3cf0360..46c2b95, review clean)
Task 1: minor (deferred): pubspec 版本行 3.76.17+0 -> 3.76.18+0 混入提交（post-commit hook 自动 bump，已披露，非偏离）
Task 1: minor (deferred): succeeded 缺 outcome 返回 null 与 failed 缺 outcome 降级 unknown 的防御路径不对称（受 snapshot invariant 保护，生产不可达，fail-open 取向合理）
Ruling: 计划 5.1 节示意 `const` 构造器，实现改为非 const - invariant 校验（RegExp/函数调用）无法在 const 上下文编译，计划内部「const 示意」与「运行时 invariant」互相矛盾时以 invariant 为准；全项目无 const 实例化点，无下游成本 - reviewer 独立确认偏离成立且无害。
Ruling: 后续 dispatch 携带环境提示 - 工具层会把 Write/Edit 参数中的反斜杠-u 转义解释成真实 NUL 字节；写含控制字符的测试/源码时用 `String.fromCharCode(0)` 或 `codeUnitAt`+十六进制字面量 - Task 1 已两次踩坑并字节级扫描确认干净 - 成本为零，只是提示。

## Task 2

- 首任实现者于「RED 已捕获、GREEN 未完成」时被用户手动停止；工作区遗留全部计划内新文件的未提交骨架。
- 用户指示重新派发接管（非 fix loop）：第二任实现者以 sdd-implementer 类型派出，先盘点遗留文件再续写，以自己跑出的测试结果为准。

Task 2: complete (commits 46c2b95..4512203, review clean)
Task 2: minor (deferred): `default_chat_generation_terminal_notifications.dart` start() 缺 `_disposed` 守卫——经端口接口不可达，仅装配误用才触发；建议加一行守卫 → 指向 Task 9 dispatch
Task 2: minor (deferred): 生产诊断出口为 debugPrint 固定分类前缀，release 不剥离；Task 9 装配时应改接 core/logging 统一 logger 或按需静默 → 指向 Task 9 dispatch
Task 2: minor (deferred): 多处注释嵌入计划章节编号（指向 docs/plans/ 持久文档，AGENTS.md 红线灰色地带）；建议合并前改写为自含表述 → 留最终 review triage
Task 2: minor (deferred): payload decode 对重复 JSON 键 last-wins 折叠后放行（生产 payload 自家 encode 产生，不可达）
Task 2: minor (deferred): app_attention_observer_test 用例顺序依赖 binding lifecycle 全局状态（Flutter 按声明顺序执行稳定）
⚠️ 已解决：import boundary「403 文件 0 违规」由 controller 直接复跑确认属实。
⚠️ 已解决：unawaited 订阅取消的生产行为由 Task 9 根部装配集成测试覆盖；Task 9 dispatch 携带「勿依赖 dispose 返回后流必然静默」提示。
Ruling: 深模块 dispose 内 subscription.cancel 改为 unawaited - await 版在 fake-async 测试驱动下永久挂死且计划第 10 条只要求「取消 subscription」，不要求等待取消完成；disposed 后事件由回调入口 _disposed 检查兜住 - 若 Task 9 依赖「dispose 返回后流必然静默」强时序则会暴露，成本为零到一行改动。

## Task 3

Task 3: complete (commits 4512203..ccd70c2, review clean)
Task 3: minor (deferred): `test/integration/chat_generation_notification_integration_test.dart` harness 未 override `chatGenerationNotificationSessionIdProvider`（当前断言不读 session 无影响）→ 指向 Task 9 dispatch
Task 3: minor (deferred): `chat_generation_notification.dart:6` feature→app 反向 import 共享 codec——边界门禁无此方向禁令（0 违规）、计划 6.4 强制共享单一 codec、实现者已披露；最终 whole-branch review 确认这是有意取舍而非新惯例起点
Task 3: minor (deferred): coordinator 已入队 start/update 在 context.tokenUnavailable 时跳过执行，与「一旦入队必须执行」字面张力——系沿用既有通道判死 fail-open 语义，评审判定合规，仅记录备查
Ruling: Task 3 不把 `timeoutActivationPayload` 加入 Android adapter start/update wire 编码 - 计划 6.4 对 Task 3 的要求止于 payload 字段+共享 codec 预编码，wire 传输由 Task 4 RED 用例明确承接；旧 Kotlin runtime 不消费该键时不传是正确中间态，避免双写 - reviewer 独立确认与计划一致；若 Task 4 忘记补 wire 编码则 Android timeout fallback 收不到 payload，成本是一个修复轮次。

## Task 4

Task 4: complete (commits ccd70c2..d21717b, review clean)
Ruling: `takePendingNotificationActivation` 应答 wire 形状 = `{payload: <严格 v1 JSON 字符串>}`，`notificationActivated` 回调参数 = JSON 字符串本身（计划「nullable activation map」/「payload」留有解释空间，Dart 侧单方定义并固化于 bridge doc 注释）- Task 5 Kotlin 实现必须按此对齐 - 若 Kotlin 定义不一致则激活链路断裂，评审/测试会立即暴露。
Ruling: pending 激活单槽「后一次覆盖前一次」接受 - 与计划 timeout fallback 覆盖哲学一致且 wire 契约本就是单个 nullable activation - 多条终态并存连点时可能丢一次点击，属已知限制。
Task 4: minor (deferred): 本地槽与 live 流的交付顺序由深模块初始化顺序决定——深模块已有 hot/pending 去重，接线时留意即可
Task 4: minor (deferred): terminal adapter 测试用 last-wins handler 替换语义重建 bridge，正确但可读性一般
⚠️ 已解决：通道名一致性由 reviewer 对照 Dart 改动前后与 Kotlin `ChatGenerationForegroundProtocol.kt:15` 核实为 `yuzu.shiki.oh_my_llm/chat_generation_foreground_service`（实现者报告里写的名字正确，controller 此前记忆的短名有误）。

## Task 5

Task 5: complete (commits d21717b..e5acd58, review clean)
Ruling: Kotlin 收敛旧 LOW 终态 openConversation 动作解析（parseActionKind 返回 null + loud-fail）- 被拒对象恰为计划 12 节删除清单中的普通错误通知 action；ongoing 点击路径（content intent→handleOpenConversationIntent→pendingOpenConversation 槽→emitOpenConversation/takePendingOpenConversation/4104 request code）经 reviewer 逐项核实完好 - 若误伤 ongoing 点击则 Android 回归测试会立即暴露。
Ruling: remove() 超时后返回 serviceUnavailable（删除超时瞬态记录）- coordinator 三次 ACK 重试语义不变且 fail-open 有界；唯一触达场景（终态先入队、Kotlin 随后超时）经推演无用户可见影响 - 成本为零。
Task 5: minor (deferred): `chat_generation_foreground_service.dart:200` doc 注释仍引用已改名旧类 ChatGenerationForegroundChannel，应同步为 ChatGenerationNotificationChannel（纯注释失配）
Task 5: minor (deferred): `android/.gitignore` 加 `+/.kotlin/` 超出 brief 文件清单（构建产物卫生修正，已披露，可接受）
Task 5: minor (deferred): Kotlin 两处注释嵌入计划章节编号（沿袭被删文件既有写法，指向持久需求文档）→ 并入 Task 2 同类项，留最终 review triage
Task 5: minor (deferred): GREEN 日志含 `:app:testDebugUnitTest UP-TO-DATE` 重放段（JUnit XML 时间戳证明 40/40 为真实执行；UP-TO-DATE 本身即输入未变的 Gradle 证明）；报告措辞透明度略有折扣
环境事实（供 Task 11）：本机 Gradle 测试需 JAVA_HOME 指向 Android Studio JBR (JDK 21)；系统 JDK 25 不被内嵌 Kotlin 解析支持。冷 daemon 曾停滞一次，kill-stale 清理后重试稳定。

## Task 6（搭台阶段完成，人工验收进行中）

- 搭台 DONE_WITH_CONCERNS：spike 工程 `E:\Code\omll-notification-spike`（独立身份 YuzuShiki.OmllNotificationSpike / {1546BAD8-62DA-4F70-BA10-AA3F8708DE3E} / OmllNotificationSpike.lnk）；两版本构建 EXIT=0；注册链自测通过（shortcut AUMID/VT_CLSID、LocalServer32 quoted default + unquoted ServerExecutable、幂等修复、延迟模式注册时机 +4s 无键/+13s 有键）；cleanup-spike.ps1 -ReportOnly 断言 13/13；仓库内仅 docs/testing/windows-chat-generation-notifications-smoke.md 骨架未跟踪（按计划暂不提交）。
- 用户选择「subagent 搭台 + 用户人工验收」模式执行本 Task。
环境事实（供 Task 7）：CP936 代码页环境下 runner C++ 含中文注释必须加 /utf-8 编译选项（否则 C4819 当错误）；产品现有 runner 全 ASCII 注释，Task 7 二选一：加 /utf-8 或保持 ASCII 注释。
Task 6: pending 人工验收 —— 等待用户回报 7 项阻塞验收结果后决定放行 Task 7-11 或硬停止。

## Task 6（人工验收结果：硬停止）

用户冒烟测试回报：验收项 1-4、6-7 PASS；**验收项 5 FAIL —— delayed 版手工启动窗口期内点击 Toast 出现第二个 spike 进程**（COM RPCSS 在 class object 未注册时按 LocalServer32 直接拉起第二实例）。smoke 文档已由用户回填现场记录。

Ruling: 计划 Task 6 / 第 15 节硬停止条件触发（「手工启动尚未注册 COM 时点击产生第二进程」）——立即停止 Task 7-11 的 dispatch；不得把双实例风险标成「接受」，不得在本 SDD 会话内顺手扩大范围实现单实例协调 - 这是计划 2.2 节预留的「另行设计 notification-specific runner 协调」场景，属新计划范畴 - 若强行继续 Windows 链路，成本是双 Flutter 实例并发写存储的数据损坏风险。
收尾：cleanup-spike.ps1 ReportOnly 断言通过后正式执行（-KeepProjectDir）；快捷方式 + CLSID + AppUserModelId + PushNotifications Backup 四处 spike 身份全部删除，产品 oh-my-llm 身份未触碰；spike 工程保留于 E:\Code\omll-notification-spike 备将来复测。
状态：等待用户决定 PR 处理方式（draft 收尾 / 先规划单实例协调 / 缩小范围）。

## 会话结束（2026-08-23）

用户决定：今天收工；draft PR 与「通知级单实例协调」新计划均延后。

**分支遗留状态（供恢复会话使用）：**
- 分支 `feat/cross-platform-generation-notifications`，HEAD = e5acd58，共 5 个产品提交（46c2b95 / 4512203 / ccd70c2 / d21717b / e5acd58），全部通过任务级评审；无 final whole-branch review。
- 工作区未跟踪文件：`docs/testing/windows-chat-generation-notifications-smoke.md`（含 Task 6 FAIL 现场，属计划第 13 节第 6 条 commit 的内容，未提交）；无其他未提交改动。
- Task 7-11 未开始。恢复前提：先完成「notification-specific runner 协调」的重新设计（计划 2.2 节预留方向），新 spike 验证协调方案后再回来做 Task 7-9 + 10 + 11。
- spike 工程保留于 `E:\Code\omll-notification-spike`（注册表已清理，工程与 dist 构建产物完整可复用）。
- 本 workspace 目录保留（未做 final clean，不删除）。

## Recovery

Ruling: 恢复 Task 2 时继续使用当前功能分支工作目录，不迁移到新 linked worktree - 中断现场包含尚未提交的 Task 2 新文件，且当前分支正是计划指定的非 master 专用分支；新建 worktree 无法自动携带这些 untracked 文件，会破坏恢复现场 - 若判断错误，成本是缺少 harness 级隔离，但不会污染 master，且后续仍由任务审查与全分支审查约束范围。
Task 2: recovery resumed from existing brief and untracked partial implementation; prior implementer unreachable and no report exists, so a fresh implementer owns completion from current filesystem state.
Ruling: SDD 专用 agent 派发在本 harness 的 `Agent` schema 中必须填写 `model`，无法按仓库记忆真正省略该字段；填写与 agent 定义一致的 `sonnet`，不改变既定模型层级 - 若 harness 将同值仍视为 override，成本仅是元数据层偏离，实际模型与 effort 策略不变。

## Windows runner-owned 方案恢复（2026-08-23）

- 用户明确要求评估并把后续 Windows Tasks 改为新方案；原 Task 6 硬停止结论对插件方案仍然有效，但“不在本 SDD 扩大范围”的旧 ruling 已被本次明确授权取代。
- 架构决策：删除 `flutter_local_notifications_windows` 路径；Windows runner 在 `DartProject`、Flutter engine 与存储初始化前启动独立 notification STA thread，由该线程拥有并持续 pump `INotificationActivationCallback` COM server；runner UI STA 用 C++/WinRT 负责本 PR 所需的窄 Toast show，pipe IO 同样不依赖 Dart/UI message loop。
- 唯一 owner 决策：instance named mutex 只允许一个 Flutter/storage owner；activator lease mutex 串行长期 primary 与短命 relay 的 COM class object；ready event + versioned named pipe 交付 activation/窗口恢复。禁止进程名、PID 枚举、窗口标题或固定 sleep 作为身份判断。
- 允许 RPCSS 在极早竞态创建第二个 native OS 进程，但该进程只能是 `activationRelay`，不得构造 `DartProject`、窗口、SharedPreferences、SQLite 或 network logger，且必须在有界 IPC/COM 生命周期后退出。第二次手工启动为 `manualSecondary`，只恢复/聚焦 primary。
- 计划第 8、9、11–16 节与 Tasks 6–9 已同步修订：Task 6A 永久保留插件 FAIL 证据；Task 6B 是新的 runner-owned 外部 spike；Task 7 增加 runner 深模块、原生 test executable 与 Dart host client；Task 8/9 共享唯一 client并完成 adapter/composition。
- `docs/testing/windows-chat-generation-notifications-smoke.md` 的既有插件 FAIL 现场保持未跟踪且未修改；Task 6B 后在新章节追加证据，不覆盖历史。
- 当前恢复点：Tasks 1–5 及其 commits 状态不变；Task 6A complete/FAIL（历史反例）；Task 6B pending。只有 Task 6B 的 warm、20 轮 cold、快速 cold、pre-COM、post-COM/pre-Flutter、第二次手工启动、边界输入、失效恢复与 native 生存性全部 PASS，才解锁产品 Task 7–11。

## 会话恢复（2026-08-23，第二接管会话）

- 计划修订已提交：`docs(chat): 修订 Windows 通知为 runner 托管激活方案`（a9eb8aa；post-commit hook 自动 bump 3.77.0+0 → 3.77.1+0 并 amend 回提交）。工作区仅余未跟踪 smoke 文档。
Ruling: 用户授权精简 Task 6B 人工验收 - 最小行为集 = (A) 正常版 warm 点击；(B) 正常版完全退出后 cold 点击 ×2~3 轮（计划原文 20 轮缩减）；(C) pre-COM 延迟版窗口期点击（上次 FAIL 的回归重点）；(D) post-COM/pre-Flutter 延迟版窗口期点击；(E) primary warm 时第二次手工双击 exe - 边界输入（中文/1024/1025/坏帧）、时限测量（registration/handoff/pipe ACK p50/max）与崩溃监测改由 spike 结构化日志 + 自测模式自动完成，不占用户操作；快速连续 cold 与失效恢复降级为顺手观察项，未做标 PENDING 不判 FAIL - 代价是 Task 6B 证据覆盖低于计划第 14 节原文，PR 正文与 smoke 文档必须如实记录实际执行范围，不得声称 20 轮 cold 等未执行项；已执行的最小集仍按 PASS/FAIL 严格判定，任一 FAIL 仍触发硬停止。
- Task 6B 搭台 dispatch（subagent 搭台 + 用户人工验收模式，沿用用户在上轮 Task 6 的选择）。BASE = a9eb8aa；本 task 仓库内预期改动仅未跟踪 smoke 文档的追加章节，任务评审需直读 spike 工程目录（E:\Code\omll-runner-spike）。

## Task 6B 搭台（2026-08-23，第二接管会话）

- 首次派发被取消（无产物）；重派后台执行，DONE_WITH_CONCERNS，耗时约 38 分钟。实现者 agentId：agent_25d9397b-3224-4cd8-8a05-cbbfe0e64683（fix round 1-3 续派用）。
- 产物：E:\Code\omll-runner-spike（CLSID {9E60E9C6-0CD2-4727-A762-A18DD8079E80} / AUMID YuzuShiki.OmllRunnerSpike，relayDrainGrace=1000ms / relayMaxLifetime=15000ms）；smoke 文档第 393-520 行追加第三部分；task-6B-report.md / task-6B-user-guide.md；无 git commit（符合预期）。
- Concerns 处置：SCM 真实拉起与 handoff 实测数据属用户验收目的（不阻塞）；快速连点双 relay 与 primary 崩溃残留属精简裁决的 PENDING 项（记录）；SetForegroundWindow 前台锁 → 带入 Task 8 dispatch（产品 8.8 节 focus 实现注意）。
Ruling: 用户裁决跳过 Task 6B 搭台的任务级评审、直接人工验收 - 用户是流程所有者，明确表示「这个就别 review 了，我直接测试」- 代价：spike 源码规范符合性未经独立评审席位检查，代码级缺陷将延后到人工验收（行为层）或 Task 7 原生测试 / final whole-branch review 暴露；若验收暴露代码级问题仍进入 fix loop。评审包已生成（task-6B-review-package.md）未派发，保留备查。
- 用户人工验收进行中（A-E 最小集，指南 task-6B-user-guide.md）；等待用户回报各 case PASS/FAIL。

## Task 6B: complete（2026-08-23）

Task 6B: complete (人工验收 A–E 全部 PASS + 自动证据；证据 commit 7e1bf4e，含 smoke 文档首次入库与计划 8.3 回写)
- 用户验收（22:00–22:07）：A warm（PID 30060，3 次激活含中文 40B×2）；B cold×2（28896/16080，均 RPCSS `-Embedding` 拉起、单 Flutter owner、启动→activation 4ms）；C pre-COM×2（relay 10000→primary 28712 ASCII 38B、relay 28732→primary 26904 中文 40B；primary `pipe_served` 先于自身 com_register，relay ~1s drain 退出）；D post-COM（primary 29804：activation_received 22:05:56.436 < flutter_started 22:06:04.102，点击瞬间无新进程）；E 二次双击×4（secondary 20880/27260/17284/18240 全部 ack=0 delivered=1 + exit 0；primary 24896 4 次 focus_applied 一一对应）。
- PENDING（精简裁决允许）：快速连续 cold 未执行；失效恢复显式用例未执行（间接证据：cold 轮次间 instance_mutex 重新 created）。
- 实测锁定（已回写计划 8.3）：lease 切片 250ms / primary lease 30s / relay lease 3s / pipe 连接 2s / pipe ACK 3s / relayDrainGrace 1000ms / relayMaxLifetime 15000ms；pipe ACK p50=0/max=110ms（n=20）、relay handoff p50=0/max=1ms（n=2）、start→ready p50=49ms。
- spike 注册身份已清理（-ReportOnly 4 项断言全过后 -KeepProjectDir）；工程与 evidence 保留于 E:\Code\omll-runner-spike 备 Task 7 参考/复测。
- 环境事实（供 Task 7/8）：产品 runner 中文注释必须加 /utf-8；SetForegroundWindow 后台调用被前台锁拒绝时退化为任务栏闪烁（spike 实测 foreground=0），Task 8 窗口恢复实现需知晓（不构成 FAIL：激活仍导航）。
- Tasks 7–11 解锁。下一 task：Task 7 产品 runner 通知宿主与 Dart host client。

## Task 7 dispatch 与中断事故（2026-08-23）

- Task 7 实现者已派出（agent_8e93a2c7-953d-41e8-8e6c-34fda5117943；BASE = 7e1bf4e；brief = task-7-brief.md；single commit `feat(windows): 增加 runner 通知宿主与单实例协调`；产品身份 + Task 6B 锁定常量 + /utf-8 + logs/ 纪律 + 挂起处理均写入 prompt）。
- 事故：运行 ~15 分钟后协调方误判挂起（依据=agent 目录无 transcript.jsonl + 无构建进程）并 TaskStop；实际 agent 正常工作中（transcript 为缓冲写入，外部不可见；停止时已落盘 3 个头文件 instance_coordinator/protocol/registration）。已 SendMessage 原地恢复，保留其上下文。教训：运行中 agent 的 transcript 文件不实时可见，不得作为存活判据；判断挂起前必须先问用户或等更明确信号。
Ruling: 用户裁决今后实现者一律前台同步派发、不用 background agent - 轮询 TaskOutput 每 10 分钟一轮浪费 token - 例外：本次恢复沿用了后台通道（保留上下文的唯一途径），恢复后不轮询、纯等完成通知。
