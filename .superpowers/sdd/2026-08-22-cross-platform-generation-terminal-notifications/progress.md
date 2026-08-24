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

## 会话恢复（2026-08-24，第三接管会话）

- 按 ledger 恢复：Tasks 1–6B complete；Task 7 产品 commit `a32e0d5` 已存在且 `task-7-report.md` 完整（DONE，GREEN 证据齐全），上个会话中断于实现完成后、任务评审之前。`77d74ab` 为 SDD 过程文件入库提交（chore，非产品 commit，不进入 Task 7 评审范围）。
- 本次恢复点：Task 7 任务级评审。BASE=`7e1bf4e`，HEAD=`a32e0d5`，评审包 `review-7e1bf4e..a32e0d5.diff` 已生成（1 commit，约 227KB）。
- 后续待办：Task 7 评审 → （视结果 fix loop）→ Task 8/9/10/11 → final whole-branch review。
- Task 7 dispatch 时携带的环境事实继续有效：产品 runner 中文注释需 /utf-8；SetForegroundWindow 前台锁退化行为带入 Task 8。

## Task 7 任务级评审（2026-08-24，第三接管会话）

- Reviewer（opus）：spec ❌（1 缺失）+ quality Needs fixes；无 Critical；架构与安全核心获正面评价（模式隔离/DACL/shutdown 顺序/协议校验均有真实行为测试背书）。
- Important 1（plan-mandated）：`native_activation_queue_full` 固定诊断 token 全 diff 不存在——队列满只在 `windows_notification_host.cpp:217-234` 返回 AckQueueFull、`windows_notification_activator.cpp:334-344` 返回 false，无任何固定 token 记录；拒绝语义本身正确（不逐出旧 payload）→ 进入 fix loop。
- Important 2：brief「产品注册回读」四项中仅注册表/属性存储回读有日志（VERIFY_EXIT=0 7/7 MATCH）；live available=true 回读、同目录覆盖 exe 幂等修复、移动目录修复、固定 Toast smoke 四项无证据但报告宣称「完成定义 1–6 全部达成」→ 经 controller 核对为真实缺口，进入 fix loop。
- ⚠️ 已解决：CMake 链接集少 oleaut32/windowsapp——计划明文允许「以 spike 实际 link set 为准」，native test 与 flutter build 均 EXIT=0，实证足够，仅记录备查。
- ⚠️ 已解决：真实 RPCSS 封送路径由 `CreateActivatorForTest` 进程内接缝替代——既定方向（去 RPCSS 化），真实路径由 Task 6B spike 实测 + Task 11 产品 smoke 承接，报告已知风险 #3 已主动披露。
- Ruling: Important 2 补证口径 - 同目录覆盖 exe 幂等修复与移动目录修复两项必须实际执行并留 logs/ 证据；live available=true 若无法在不改生产代码前提下直接取得，允许等价组合证据（既有注册回读 7/7 MATCH + 对运行中 primary 的 pipe activateWindow ACK status=0 live probe），报告须显式标注替代口径；固定 Toast 点击 smoke 维持 brief 第四条的能力声明口径，不强制本轮执行 - 若替代口径被最终 review 认定不足，成本是补一次真实回读。
- Task 7: minor (deferred): CMakeLists 删除 apply_standard_settings 时丢 `_UNICODE`/`UNICODE` 定义未补回（现全显式 W API 无害，未来泛型宏会静默落 ANSI）
- Task 7: minor (deferred): 测试残留两处 `Sleep(150)` 等待 pipe 实例创建（Start 已确定性可达化，冗余且与报告自述矛盾）
- Task 7: minor (deferred): `CreateActivatorForTest` 无条件编入 release 二进制（可用 OMLL_NOTIFICATION_HOST_TESTING ifdef 收紧）
- Task 7: minor (deferred): `ActivatorImpl::Activate` stopping 检查与 `in_flight.fetch_add` 非原子 TOCTOU（revoke 后 pump 已退，生产不可达，可在 in_flight 区间内复查 stopping 封死）
- Task 7: minor (deferred): `CLSIDFromString` 失败映射 `"exePath"` stage 语义错位（分支实际不可达，改 token 即可）
- Task 7: minor (deferred): `XmlEscape` 不处理 C0 控制字符（LoadXml 失败→show 优雅 false，无注入风险；可在 ValidateShowParams 拒绝控制字符收紧契约）
- Task 7: minor (deferred): DACL 构造失败时 BootstrapPrimary 标 unavailable/stage="pipe" 的分支无宿主级断言（现有测试停在 pipe-server 层）
- Task 7: fix round 1/5 派发：fresh implementer（原实现者 agent 跨会话不可达，report file 为持久记忆），scope 仅限两个 Important，minors 不入 loop。
- 派发波折：第一派（sonnet）因 harness API 模型路由错误早夭（无产物）；第二派（opus）因本机未装 cmake 中止（用户随后安装 cmake 4.4.2，无产物）；第三派（opus）接管完成。环境事实：本机仅 VS 18 2026 无 VS 17 2022，`scripts/test-windows-notification-host.ps1:26` 硬编码 `-G 'Visual Studio 17 2022'` 需适配；logs/ 中 Task 7 旧日志已被清理，本轮证据全部重新落盘。
- 首任早夭前留下的半成品经协调方核可后由第三任沿用：activator.cpp 的 `PendingQueue::Push` 满分支单点 `OutputDebugStringW(kNativeActivationQueueFullToken)`（两条拒绝路径收敛单点）+ test exe 新增 `--probe-live-primary` 探测模式。
- Task 7: fix round 1/5 (2 addressed 待 re-review 确认, 0 open — queue-full token 单点记录 + 注册回读 STEP1-4 补证; commit 5ad80f0)
- Fix round 1 报告要点：原生 127/127 EXIT=0（新增「队列满拒绝留固定 token」用例 red/green 已验证）；flutter build EXIT=0；产品回读 STEP1 live probe 替代口径（已显式声明）+ STEP2 同目录覆盖幂等 + STEP3 移动目录修复 + STEP4 现场恢复全 PASS；generator 适配为探测式选择。
- Fix round 1 concerns（待 re-review 分类）：host.cpp 晋升回填路径调 Push 忽略返回值（relay ≤15s 窗口积压 >32 条溢出丢弃无 token，极端边角）；本机调试通道 OutputDebugStringW 宽字符降级 ANSI 形态（回归测试三种形态兼容并记录实测结论）。
- Scoped re-review（opus）结论：两个 Important 均 ADDRESSED——Important 1 的「两路收敛单点」经独立枚举核实（生产入队唯一封装 EnqueueActivationForUi、调用方恰好两处：pipe handler 与 STA sink；超长 payload 分支提前返回不发 token 属正确）、黑盒子进程调试事件捕获测试真实有效、red/green 日志逐字核验一致；Important 2 的 STEP1-4 全部核实（①替代口径显式标注合规、②③实际执行、现场恢复义务履行完毕）。无新 Critical/Important 破坏。
- Task 7: fix round 1/5 (2 addressed, 0 open — queue-full token 单点记录; 注册回读 STEP1-4 补证; commits a32e0d5..5ad80f0)
- Task 7: minor (deferred): test-windows-notification-host.ps1 退化探测把 CMake 主版本号当 VS 安装目录名拼接（VS2019/2022 按年份命名会探不到；fail-safe 显式 FAIL 不错配 generator，vswhere 主路径正常时不触发）
- Task 7: minor (deferred): 原生测试调试循环对 CREATE_THREAD_DEBUG_EVENT 未关闭 u.CreateThread.hThread（子进程不创建额外线程、句柄随进程退出回收，调试协议完整性瑕疵，无可观察影响）
- Task 7: minor (deferred): host.cpp:402-409 relay 晋升回填循环 `queue.Push(payload)` 忽略返回值——relay ≤15s 寿命窗口内积压 >32 条时溢出丢弃无任何诊断 token（计划 :747「队列满记录固定 token」严格读法的残余缺口；触发需 15s 内 >32 次点击且 pipe 投递持续失败）→ 最终 review triage：在该循环补同一 token 输出或明确接受静默丢弃并说明理由

## Task 7

Task 7: complete (commits 7e1bf4e..5ad80f0, review clean after 1 fix round；区间含协调方过程文档提交 77d74ab，产品改动为 a32e0d5 + 5ad80f0 两个 commit)

## Task 8 dispatch（2026-08-24）

- 实现者已派出（opus；BASE = 5ad80f0）。dispatch 携带跨任务上下文：WindowsNotificationHostClient 五成员接口、ChatGenerationNotificationPayloadCodec 位置（lib/features/chat/application/generation/chat_generation_notification.dart）、默认深模块去重职责归属、SetForegroundWindow 前台锁退化事实（Task 6B）、测试超时约定（单文件 180s/全量 600s 工具硬超时）。
- 实现 DONE：commit 7c35c41；RED 15/15 留证 → 定向 GREEN 9+4+2 → analyze/import-boundaries EXIT=0 → 全量 All tests passed。报告 task-8-report.md。
- Concerns（措辞级澄清，非阻塞）：①「host unavailable no-op」实现为不触达通道但抛固定异常保留深模块重试语义；② window_restore_or_focus_failed 由 WindowsAppWindow 自身上报、restoreAndFocus 永不抛出；③ 初版 Future.delayed 刷流被仓库韧性门禁拒绝，已改 emitsInOrder/emitsDone 真实信号未放宽 allowlist。待评审独立判断。

## Task 8 任务级评审（2026-08-24）

- Reviewer（opus）：spec ✅ + quality **Approved**，无 Critical/Important；RED 15/15 证据抽查属实。
- 两处对计划文本的解释经评审独立核实为正确选择：① unavailable 时 show() 抛固定异常保留深模块重试——字面静默 no-op 会使收据进入 _completeReport 永久去重，宿主晚启动时通知全丢；② brief 所给 codec 路径有误（controller grep 未区分定义与引用），实现者自行定位真实定义处并主动申报偏离，消费接口逐一吻合。
- ⚠️ 已解决：native runner takePending 原子清空契约已由 Task 7 原生测试覆盖（FIFO 32 / 原子取走用例），adapter 层只证「无本地缓存/不二次投递」，分层正确，无需动作。
- ⚠️ 指向 Task 9（dispatch 必带）：broadcast 流无 listener 时 pending 多余合法项会丢——composition 必须保证深模块先订阅 adapter activation stream 再 initialize/takePending。
- ⚠️ 指向 Task 9（dispatch 必带）：WindowsAppWindow 默认诊断 sink 为 debugPrint（release 不可回读），composition 应注入接结构化 logger 的 reporter（与 Task 2 debugPrint minor 同类，合并处理）。
- Task 8: minor (deferred): test :857「同一 pending payload 只取一次」手动置空 Fake 模拟原子清空，本层实为验证无本地缓存（真契约在 Task 7 runner 侧且已被覆盖）；merge review 抽查即可
- Task 8: complete (commits 5ad80f0..7c35c41, review clean)

## Task 9 dispatch（2026-08-24）

- 实现者已派出（opus；BASE = 7c35c41）。dispatch 携带五项遗留处置：a 装配顺序契约（深模块先订阅 adapter 流再 initialize/takePending）、b 诊断 reporter 注入结构化 logger、c 深模块 start() _disposed 守卫（顺手补或说明理由）、d integration harness 补 session override、e unawaited dispose 时序提示。
- Windows/Android 可装配件接口、第 9.1-9.3 节行号范围（:864-997）、测试超时约定均已写入派发词。
- 实现 DONE_WITH_CONCERNS：commit 3fe8a8c；RED 留证（编译期 EXIT=1）→ 定向 140 全过 → 全量 2253 全过 → analyze EXIT=0 → boundaries 0 违规。报告 task-9-report.md。
- 自述偏离 4 处（待评审核实）：① 深模块 start 移入 provider build（端口无 start 方法，沿用协调器先例）；② 清单外 history_page_query_bindings_test 仅同步一个标识符改名；③ RED 为编译期形态、中间三轮断言级修复未单独留日志（已如实描述）；④ Ubuntu CI 生产默认路径会构造真实 Dart client 但全部 fail-open。
- 评审包已生成 review-7c35c41..3fe8a8c.diff，task reviewer（opus）已派发；重点核实 ① eager 启动契约、④ 构造源头隔离语义。

## Task 9 任务级评审（2026-08-24）

- Reviewer（opus）：spec 基本符合 + quality **Needs fixes**；装配本体（typedef、惰性工厂、共享 owner 单次释放、session 单例、eager 启动、锁序契约）全部按规格落地且测试证据形态强。
- 自述偏离 4 处独立判定：① start 移入 provider build 成立且可接受（根部双 watch + 幂等 start 满足 eager 契约，锁序用例证明订阅先于一切 await）；② history_page_query_bindings_test 一处标识符跟随改名属实合理；③ 注释修订属顺带合规；④ **属实且是唯一实质问题** → Important 1。
- Important 1（plan-mandated）：bootstrap_integration_test 的 `_pumpBootstrappedApp` factory 参数默认 null，四个用例以 TargetPlatform.windows 走生产默认路径构造并驱动真实 MethodChannel client（app.dart eager 启动实际发起通道调用，靠 Task 7/8 fail-open 收敛），违反 §9.1「从构造源头阻止真实 MethodChannel client」。→ 进入 fix loop。
- 协调方裁决：不采用评审备选「文档化例外保留单条」——计划原文无例外余地；按主方案修：_pumpBootstrappedApp 默认注入 no-op/fake 工厂恢复全文件隔离 + 生产默认类型断言改为纯构造级单元断言（只构造不触发生命周期调用）。
- ⚠️ 已解决：「git mv 保持历史」经 controller 用 git log --follow 核实——rename 检测因内容差异过大（22 行→134 行）天然失效，操作层无法验证亦无实际影响，历史追溯由 commit message 承担，非缺陷。
- Task 9: minor (deferred): createAppWindow 默认 Windows 分支与生产 composition 双默认分歧——裸调得到 debugPrint sink 版本，建议委托同一结构化 logger reporter
- Task 9: minor (deferred): _productionWindowsAppWindowFactory 把信息性分类经 logError 写 Error 级别，回读污染严重度过滤（可接受，值得注释取舍）
- Task 9: minor (deferred): CI 用例 root eager start 断言对懒加载 provider 恒真（isNotNull），零通道断言才是承重部分；bindings 测试组的 initializeCount==1 形态更强可对齐
- Task 9: minor (deferred): RED 为编译期形态 + 中间三轮断言级修复未留独立日志（过程缺口，GREEN 与全量已验证，不阻塞）
- Task 9: minor (deferred): settings/terminal 共享同一 client 无直接行为证据（公开面无 accessor、final 类不可包装；靠装配函数结构保证，实现者已披露）
- Task 9: fix round 1/5 派发：SendMessage 续派原实现者（上下文保留），scope 仅 Important 1。
- Fix round 1 过程波折：续派后实现者两次中途停止（一次 API 错误断线、一次停在定向测试完成后），均 SendMessage 原地恢复，未重做已完成步骤；最终 DONE。
- Task 9: fix round 1/5 (1 addressed 待 re-review 确认, 0 open — _pumpBootstrappedApp 默认注入隔离工厂 + 生产默认用例改纯构造级断言; commit 1ef7ba7)
- Fix round 1 验证：bootstrap_integration_test 8 全过（logs/notification-composition-fix1-green.log EXIT=0）、analyze EXIT=0、全量 2253 全过（logs/fltest.log EXIT=0）、format EXIT=0；报告已追加「## Fix round 1」章节。
- Scoped re-review（opus）：Important 1 **ADDRESSED**（三点裁决逐点核验：隔离工厂与 test_harness 同源、生产默认用例改纯构造级四类型断言零生命周期调用且被构造类构造函数均无通道触达、三个既有用例相对 base 用例体零改动语义不变）；无新 Critical/Important。
- 过程备注：本轮评审包 review-3fe8a8c..1ef7ba7.diff 在 hunk 中途物理截断（止于 :195），re-reviewer 经比对 base 完整状态确认截断部分仅为未改动上下文、不影响裁定；后续生成评审包时应校验完整性（对比 git diff 字节数）。
- Task 9: minor (deferred): createAppWindow 的 Windows 生产默认分支在全测试目录已无直接断言（旧断言随用例转换被丢弃），dispatcher 平台选择契约该分支失去验证；可后续以纯构造级断言补回
- Task 9: complete (commits 7c35c41..1ef7ba7, review clean after 1 fix round)

## Task 10 dispatch（2026-08-24）

- 实现者已派出（opus；BASE = 1ef7ba7）。dispatch 携带：端口文件已由 Task 2 创建/Task 9 override 的事实、四态语义需先读现有 adapter 确认来源、settings 测试 case-file decomposition 模式、10.2 逐字文案要求、测试超时约定。
- 实现 DONE：commit 30c32c6；RED 12/12 先失败留证（logs/system-notifications-red.log）→ controller 单测 3 例 + settings_screen_test 50 例 + 全量 2265 全过 → analyze/import-boundaries/format 均 EXIT=0。
- 自述偏离 3 处（待评审核实）：① tab 种子需连同版本键写入否则 legacy 迁移把索引 5 换位成 4；② 生命周期模拟用合法 inactive→resumed 路径（框架拒绝 hidden 直跳 resumed）；③ 错误气泡收尾显式 dismiss 满足韧性门禁；loading 期间按钮取禁用而非隐藏属计划空白处决策。
- 评审包 review-1ef7ba7..30c32c6.diff（32749 bytes，与 +517/-4 改动量级吻合）；task reviewer（opus）已派发，重点核实③的按钮语义与六段文案逐字性。

## Task 10 任务级评审（2026-08-24）

- Reviewer（opus）：spec ✅ + quality **Approved**，无 Critical/Important；六段文案九处用户可见文本逐字命中一处不差。
- 三处自述偏离独立判定全部成立：① tab 版本键种子经真实迁移代码核对精确吻合（v1 双分支迁移确实把索引 5 换位成 4）；② inactive→resumed 为合法状态机路径且 addTearDown 保护；③ loading 期按钮 disabled 是计划空白的合理细化（status.value 为 null 时禁用比可点更安全）且有注释说明；显式 dismiss 符合仓库红线。
- ⚠️ 已解决：GREEN 日志与全量原始输出不在审查包内属正常（logs/ 不入 diff 包），按模板采信报告、不复跑，记录在案。
- Task 10: minor (deferred): _FakeSystemNotificationSettings 与 presentation helpers 的 Fake 结构近重复（分层取舍合理，出现第三个消费方时提取共享）
- Task 10: minor (deferred): refresh() 重叠调用完成顺序颠倒可能后写覆盖前者（平台查询近同步实际风险极低，严格语义需代次守卫）
- Task 10: minor (deferred): settings_screen_test_helpers.dart 两行 package import 字母序乱序（analyze 未启用该 lint，纯外观）
- Task 10: minor (deferred): 恢复前台计数断言 ==2 隐含单 Tab 实例存活假设（未来 TabBarView 预构建邻页会失败，方向无害）
- Task 10: complete (commits 1ef7ba7..30c32c6, review clean)

## Task 11 dispatch（2026-08-24）

- 拆分裁决：Task 11 分「agent 搭台」（smoke 文档回填 + 定向/全量/构建/native final + 范围审计）与「用户人工最小原生 gate」两部分，沿用本计划 Task 6/6B 确立的「subagent 搭台 + 用户人工验收」模式；人工项一律 PENDING。
- 搭台 DONE_WITH_CONCERNS：commit a4df7fe；定向 47/47、全量 2265、analyze/boundaries/format 均 EXIT=0；Windows Release 与 APK Debug(JBR) 构建通过；native final 127/127；范围审计 13 项全 ✓（logs/task11-*.log）。smoke 文档：Android §6 PASS 1/PENDING 15，Windows 第四部分 PASS 3/PENDING 16，人工 gate 全部如实 PENDING。
- Concerns 处置：① 最小 gate 待用户人工执行（Android adb 当前无设备；Windows ≥20 轮 cold 等），PR 保持 draft 直至全部 PASS——预期内，待搭台评审后向用户请求验收；② Ruling: scripts/test-windows-notification-host.ps1 加 `#requires -Version 7` 的建议成立——PS 5.1 -File 调用会 ParserError，一行零风险改进 → 记 deferred minor 留 final review triage 顺手补；③ Ruling: 整仓 git diff --check exit=2 告警全部来自 77d74ab 特意入库的 .superpowers review-*.diff 过程产物空白，产品 diff 干净属实——PR 完成定义的 --check 以产品范围为口径并在 PR 正文如实说明，不声称整仓干净；是否移除过程文件属用户先前明确决定（跨机器续作用），留 finishing-a-development-branch 阶段由用户与 workspace 删除一并裁决。
- 评审包 review-30c32c6..a4df7fe.diff 已生成；task reviewer（opus）已派发，重点：PASS 条目证据可追溯性、PENDING 保守性、6A FAIL 现场原样保留、范围审计高风险声明抽查。
- Reviewer（opus）：spec ✅ + quality **Approved**，无 Critical/Important。核心红线「不得把未执行写成已通过」全量核对零违反；PASS 条目逐条实证可追溯（A2 Kotlin 配置级、W12/W14 编排日志逐字吻合）；6A FAIL 现场由 diff 结构性证明一字未动；范围审计抽查 7 项高风险声明全部与代码事实吻合。
- Task 11: minor (deferred): W9 configure 矩阵 PASS 行只打到控制台未入盘，证据指针措辞略夸大（证据链仍由脚本 EXIT=0 背书成立）；建议下次整体重定向或改措辞
- Task 11: minor (deferred): Windows smoke 导言「全文分两部分」表格与现状不符（一行修复）；报告转写漂移一处；判定规则时态张力可加半句回填期说明
- Task 11: minor (deferred): scripts/test-windows-notification-host.ps1 缺 `#requires -Version 7`（PS 5.1 -File 会 ParserError；协调方已裁决留 final review 顺手补）
- Task 11: complete (agent 部分 commits 30c32c6..a4df7fe, review clean)；剩余：用户人工最小原生 gate → final whole-branch review。

## 用户人工 gate 裁决（2026-08-24）

- Ruling: Windows 产品 cold 点击轮次 = 精简 3 轮 - 用户裁决（沿用 Task 6B 精简先例；关键 race case 全保留）；smoke 文档与 PR 必须如实记录实际执行 3 轮、低于计划原文 20 轮及理由，不得声称满足原文 - 若 final review 认为证据不足，成本是补跑至 20 轮。
- Ruling: Android 最小 gate 暂不执行，PR 保持 draft - 用户裁决（当前 adb 无设备）；Android §6 的 PENDING 保持原样，draft 状态直至补齐 - 若忘记补齐则 PR 无法 Ready，属流程内可见状态不会静默丢失。
- 已派出助手准备两个 testing=ON Debug instrumented build 变体（variant-A pre-COM delay 5s / variant-B post-COM delay 8s → E:\Code\omll-task11-gate\），供 W7/W8 竞态窗口人工验收使用；含冒烟自检与注册现场恢复义务。
- Instrumented builds 结果：本机无 E: 卷（Task 6B 时的盘符环境已变化），产物落在 D:\Code\omll-task11-gate\{variant-A-pre-com-delay, variant-B-post-com-delay}\，各 42 文件独立可运行；冒烟 A 窗口 6.7s/B 窗口 9.9s 出现、优雅退出零残留、注册回读全 MATCH、收尾已从 Release 启动修回正式注册路径。助手 concern「父会话并行提交 runner 文件」经 controller 核实为误判——HEAD 仍 a4df7fe 且 windows/runner/ 相对 HEAD 零 diff，变体即最新源码产物，无需重建。
- 用户人工 gate 材料就绪：正式 Release = build\windows\x64\runner\Release\oh_my_llm.exe；验收指南 = task-11-user-guide.md（六组 case，W5 按裁决 3 轮）。等待用户回报各条目 PASS/FAIL。

## Android gate G2 白屏缺陷诊断与 fix 派发（2026-08-24）

- 用户回报：Android 四项最小 gate 功能均过，但 G2 有问题——LOW 通知点击正常，HIGH 终态通知点击后跳转应用闪过一个白屏（文字未看清）再正常渲染。
- logcat 取证（logs/task11-android-g2-logcat.log，45868 行）：HIGH 点击 `START u0 {act=...CHAT_GENERATION_NOTIFICATION_ACTIVATED dat=oh-my-llm://generation-notification/...}` result code=2 (DELIVERED_TO_TOP)，onNewIntent 复用正确、无 Activity 重复创建。
- 录屏 + 用户回读确认白屏内容 = 「未找到页面：oh-my-llm://generation-notification/<id>」，即 `lib/app/router/app_router.dart` errorBuilder 的 GoRouter 404 页。
- 根因定位（证据链闭合）：`ChatGenerationTerminalNotification.kt` `terminalActivationPendingIntent` 给 intent 设了 `data = oh-my-llm://generation-notification/<id>`；Flutter Android embedding 对带 data 的启动/onNewIntent intent 会自动把 dataString 转发为 Flutter 路由 → GoRouter 无匹配路由渲染 404 页 → 随后项目自有 payload 链路（KEY_PAYLOAD extra → method channel → Dart adapter 导航）接管跳到正确会话。消费链路全程无人读 intent.data，data URI 纯副作用源。LOW ongoing 通知 intent 不带 data 故无此现象，交叉印证。
- Ruling: 移除 data URI 属对计划 §7.4/:595 与 §7.5/:619 的有意偏离 - orchestrator 裁决采纳（计划规格盲点：未预见 embedding 自动 deep link 转发）；PendingIntent 区分性本就由 request code 同源于通知 ID 单独保证（terminalPendingRequestCode = notificationId），删除 data 不影响互不覆盖语义。PR 如实记录偏离理由。
- 缺陷回归证据口径：red = 用户手工 G2 复现白屏 404（已留档录屏与用户回读）；green = 修复后复验无 404 直接渲染（待用户复验后回填 smoke 文档）。不新增 JVM 伪回归测试（根因暴露层为 framework 真实投递路径，无 Robolectric 无法断言；恒真式常量断言违反测试清理原则）。
- fix brief 已写：task-11-fix-android-data-uri-brief.md（协议常量/函数删除、intent data 赋值删除、JVM 测试同步更新、Dart/Windows 零改动）；fix implementer（opus）已派发。
- 已知残留风险：升级安装场景下通知中心残留的旧终态 Toast 点击仍会带旧 data URI 闪一次 404；一次性自愈（被新终态替换或用户清除），记入 PR 风险说明。
- fix DONE：commit 9476862（3 Kotlin 文件 +12/-27，pubspec.yaml 为 hook 并入的版本 bump 3.81.1+0→3.81.2+0）；JVM 定向测试 EXIT=0（logs/android-jvm-data-uri-fix-green.log）；grep 残留（generation-notification/oh-my-llm:///dataUri/setData( 等）在 android/、lib/、test/ 全零匹配，计划原文未动；Dart/Windows 零改动。
- 评审包 review-a4df7fe..9476862.diff 已生成（6812 bytes）；task reviewer（opus）已派发，重点：diff 与 brief 一致性、PendingIntent 区分性回落 request code 的技术核实、测试唯一性契约保留、回报真实性抽查、public version/fallback 共用路径无新风险。
- Reviewer（opus）：spec ✅ + quality **Approved**，零 Critical/Important。自查证据：PendingIntent 身份键分析确认区分性语义不减（requestCode 恒等映射注入成立）；保留槽位隔离与 parseTerminalNotificationId 拒绝路径有测试覆盖；public version 与 fallback 4200 共用构造函数均无 data；消费链路全源码无 intent.data/dataString 读取；升级场景旧 PendingIntent 不跨包存活无交叉污染。
- Task 11: minor (deferred): ChatGenerationNotificationProtocol.kt:12 类头 KDoc「计划 Section 7 协议逐字节一致」指向持久设计文档而非临时审查阶段，是否按编号引用规则清理留 final review triage
- Task 11: minor (deferred): 计划 §7.4/:595、§7.5/:619 的 Intent data 描述与本实现永久不一致（brief 裁决计划不改）；final review 时确认 PR 正文已如实记录该偏离即可
- G2 缺陷修复闭环：commits a4df7fe..9476862 review clean；剩余 green 证据 = 用户在重建后的包上复验 G2（点击 HIGH 终态通知直接进会话、无 404 闪现），回填 Android smoke 文档后本缺陷关闭。
