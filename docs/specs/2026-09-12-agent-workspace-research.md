# 独立 Agent 工作区：调研、范围与运行契约

日期：2026-09-12。基线：`master@d568d81`。实施分支：`feat/agent-workspace-runtime`。

本文保留开发期间的调研与阶段记录，其中的后续设想不是已确定的开发安排。当前实现、最终验证和已知缺陷以 [Agent 基础设施交接](../agent/README.md) 为准；后续范围由用户决定。

用户已确认：一层主 Agent → SubAgent，支持等待结果和后台执行后收取；先提供工作区文档读写与列举，文档和运行记录持久化。世界书、角色卡、剧情状态库、剧本触发系统不在这一阶段。

## 1. 既有基建评估

`feat/shared-llm-infrastructure` 已作为 `6929855` 通过 PR #40 合入当前 master。

| 能力 | 当前证据与判断 |
| --- | --- |
| 三协议单次调用 | `core/llm` 契约、三个协议 client/parser 与 app composition 已具备；可以直接复用 |
| 原生函数工具 | typed 定义、选择、增量参数、完成调用及工具结果已经实现；每轮 32 调用、单参数/结果 1 MiB 上限 |
| 原生续接 | `LlmAssistantTurn` / `LlmReplayEnvelope` 保留协议输出并校验协议、解析后的 endpoint、模型及 call ID 关联；不能只拼接显示正文 |
| 请求取消 | `LlmCallControl` 和请求级 abort 已有；上层仍需管理整棵任务树，不能关闭共享 HTTP client |
| 缓存与统计 | 支持稳定输入顺序、Responses/CC cache key、Messages 自动缓存选项、缓存读写 Token 统计；没有真实服务命中率保证 |
| Agent 执行 | 基建只提出工具调用，没有生产工具执行器、循环、预算或 SubAgent 调度 |
| Agent 产品 | 基建没有独立工作区页面、数据、文档版本及崩溃恢复机制 |

结论：协议和单次调用层足以作为此次起点；还不能称为可运行的 Agent。历史基建验证记录在 `docs/plans/2026-09-11-shared-llm-infrastructure.md`，本轮的检查单独记录，不将历史 PASS 当作当前验证。

当前核查发现并修复一个续接遗漏：Responses 原生 message 虽然被 parser 完整保留，重新编码时却丢弃了 `phase`。手动回传 assistant items 必须保留原值，否则中间说明与最终答案的阶段信息会丢失；本轮在既有编码白名单中补回该字段，并用红/绿测试验证。没有向 user 消息添加 `phase`。[OpenAI Phase parameter](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.5#phase-parameter)

## 2. 对 Agent 理解的修正

Harness 包含提示词、工具说明，也包含开发者写出的运行控制、权限检查、上下文组装、预算、持久化与恢复。提示词无法替代执行端拒绝越权。模型决定下一步行动，应用执行并回传工具结果；这是基础循环。[OpenAI Function calling](https://developers.openai.com/api/docs/guides/function-calling)

SubAgent 的关键是上下文与职责隔离，未必需要另一个进程。同步/异步描述主任务是否等待子任务；异步任务仍要有归属、结果收取和取消语义。本实现用普通同步 function calling 实现“启动后立即返回 ID”与“后续收取”，不依赖某个新模型的原生 async tool 扩展。[Claude SDK Subagents](https://code.claude.com/docs/en/agent-sdk/subagents)

状态栏由代码状态派生。只有模型需要理解的状态变化进入上下文，不能每轮把 UI 状态和完整数据库重复追加。一个执行状态不能同时由提示词里的 flag 和应用 flag 各自维护。

Skills 式按需加载适合减少初始上下文；它并不天然保证剧本的合理触发和完成。剧本应有前置条件、可用阶段、互斥/依赖关系、激活状态与可检查的完成条件。“n 轮”应明确指已接受的剧情推进次数，不能用模型或工具调用轮数替代。

## 3. 小说问题的适用性与局限

- **矛盾和 OOC**：分角色推演和审稿可以分散检查负担，但多个 Agent 可能共享同一种误判。主 Agent 需要证据与验收标准，不能把子 Agent 多数意见当成事实。先积累小型评估集：原文证据、预期问题、误报、漏报、修订后的新矛盾，以及调用成本。
- **八股**：明确禁用词适合确定性检查；句式和文风需要有例子的审稿标准。用一次候选写作与一次聚焦审稿作为起点，是否再循环应由效果证据决定。
- **不能删除旧输出**：Agent 也无法撤销已经发生的 token 生成，但可以把正文作为版本化文档，重新生成或直接编辑内容。读者看到的接受版本和审查过程应分开管理。
- **压缩丢信息**：结构化数据库也是有损抽取，遗漏事实不会因为“存数据库”而消失。未来应保留原文与来源、事件记录、版本和按需检索；总结是索引，不能成为原文的唯一替代。

主 Agent + 工作者适合动态委派；写作 → 评估 → 修订适合有明确评价标准的任务。这些结构有额外延迟、成本和累积错误，需要实测。[Anthropic Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

未来剧情库建议区分：静态设定、角色所知、客观已发生事件、当前状态、未确认提案、已接受正文。事件应带来源与剧情时间；提案先审查再进入 canonical 状态。禁止把模型推测直接覆写成历史事实。这是后续设计方向，本轮没有创建相应表或业务协议。

## 4. 缓存策略

缓存复用依赖匹配的前缀和可用缓存条目；修改中间内容影响从首个变化点起的复用，前面的固定前缀仍可能命中。模型、工具定义与顺序、推理配置、缓存寿命也会影响结果。不能把“十几轮才隐藏一次”直接换算成高命中率。[OpenAI Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)

Messages 的工具、system、messages 有不同缓存失效范围，修改工具定义或调用配置可能影响缓存；thinking 块和签名需要按协议保留。[Claude Tool use with prompt caching](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching), [Claude Thinking](https://platform.claude.com/docs/en/build-with-claude/thinking)

本轮采用：

1. 工作区首个 system 消息固定；已有上下文后模型与规则在 UI 中锁定，避免混合不同 native replay。更换 endpoint/协议/模型时，在发送前拒绝原生续接。
2. 主/子工具目录各自固定，历史只追加。文档按需读取，在工具结果位置返回当前版本，不每轮塞入完整工作区。
3. 手动文档修改追加一条“重新读取”的消息；旧的工具结果保持原样。
4. 主/子共用已有服务商模型配置；子上下文由其角色规则、用户写作规则和明确委派任务组成，不全量继承父历史。
5. UI 显示供应商已报告的输入、输出、缓存读取 Token；字段缺失显示未知。跨调用用量相加，同一次调用的流事件与终态不重复计数。没有统一费用估算或虚构命中百分比。
6. 暂不自动压缩。4 MiB 上下文保护上限触发后要求新工作区与按需迁入文档；此值是本地资源上限，不代表模型 token 窗口。

## 5. 本轮模块与接口

`features/agent/application/agent_runtime.dart` 是一次主任务及其子任务的运行 owner。`run(prompt)` 返回最终主任务记录；`cancel()` 停止整树。每次模型调用有独立取消句柄；只有权威 `LlmCompleted` 的完整原生 turn 可以进入工具执行。`incomplete/refused/unknown` 或缺失可靠回放均停止，不猜补。

正常结束需完成待处理工具结果；后台子任务未收取时，运行器等待并追加明确完成通知，再给主 Agent 一次综合机会。重复 collect 不重跑子任务。主任务失败、停止或预算耗尽时取消剩余子任务，等它们进入终态后返回。

| 工具 | 参数及语义 |
| --- | --- |
| `list_documents` | 无参数，只列当前工作区的文档名与最新 revision |
| `read_document` | `name`，读取最新正文与 revision；不存在返回工具错误 |
| `write_document` | `name/content/expected_revision`，新建 expected=0，更新须匹配最新版本；每次成功新增版本 |
| `spawn_subagent` | `role/task/background`；writer、reviewer、character；后台模式返回 task_id |
| `collect_subagent` | `task_id/wait`；只能收取当前主任务创建的子任务；可等待或读取当前状态 |

子 Agent 只有前两个工具。工具 executor 同时校验字段集合、类型、角色权限与资源限制；未知字段不允许注入其他工作区 ID。没有 Shell、任意路径读写、HTTP 请求、动态代码、任意 SQL 或 Settings 读取工具。SQLite 查询使用参数绑定，工作区 ID 来自运行 owner。

这属于应用能力限制，不是 OS 进程沙箱；工具实现仍与应用同进程，不能声称已实现系统级隔离。文档版本可以缓解误改，但无法证明模型写入内容正确。

默认每次用户任务：全树最多 24 次模型调用、64 次工具调用；主循环最多 12 轮，子循环各 6 轮；最多派发 6 个子任务，同时最多 2 个；10 分钟全树时间上限；每次请求最多 8192 输出 token，响应头与 SSE idle 各 60 秒。达到上限产生独立终态，不声称完成。

单任务输入 64 KiB、单文档 256 KiB、单次文本加推理输出 512 KiB；每工作区最多 100 份逻辑文档、最多 100 个工作区。限制是第一版的明确产品边界，不是扩展插件框架。

## 6. 持久化与失败语义

SQLite schema v16 新增 `agent_workspaces`、`agent_runs`、`agent_document_revisions`。不引用 Chat 的 conversation/message，不修改 Settings 交换格式或 Sync 参与者。v13→v14→v15 的发布迁移保留，追加 v15→v16；固定的完整 v15 schema fixture 保护升级行为。

工作区保存模型配置 ID、用户规则、输入草稿和 typed native history；不会保存 `LlmRequestTarget.apiKey` 或 HTTP headers。运行记录保留父子关系、用户任务、终态、文本、分离的推理、工具参数与结果、已报告用量。原生 replay 仅作为上下文保存在本机；不是网络诊断日志。

模型终态、每次工具结果和运行终态产生检查点；流式显示节流，不按 token 写 SQLite。工作区上下文与主运行记录在一个事务中保存。文档保存另有版本事务：成功写文档后、记录结果前崩溃的窗口不能被当作安全重试。

重启把所有 running 记录改为 interrupted；补齐未确认工具的错误结果并提示读取当前版本。不会自动重新执行工具、自动续跑模型或把部分文本标记为完成。已保存文档不回滚，历史版本保留。正常停止遵循同一“不自动重放”的原则。

终态写入失败时，controller 保留内存中的失败记录与上下文，显示未保存提示；下次操作先尝试补存，不能从数据库重新加载旧 running 记录来覆盖失败状态，也不能重跑工具。单次网络流正常关闭也会释放 `LlmCallControl`，运行器仅在整树取消时把此回调视为用户停止，避免误判正常工具往返。

页面可新建与选择工作区，配置模型和写作规则，提交任务、查看执行过程和停止全部任务；文档可手动新建、编辑、查看旧版并保存为新版本。运行中锁定工作区切换和文档修改；离开页面仍由应用级 controller 持有运行。Android 前台服务尚只保护 Chat，Agent 后台执行与应用关闭后的继续运行未在本轮实现。

## 7. 验证与后续

测试归属：runtime 测循环、权限、子任务与取消；store 测版本冲突、文件重开与中断恢复；migration 测合法历史 schema 的升级；integration 测三个协议的真实生产装配往返；widget 测独立入口、文档修订与窄屏停止。共同的协议 wire fixture 被复用，不复制 parser 测试矩阵。

初版完成时的本地验证（2026-09-12，后续 CUI 改造结果见第 9 节）：

| 检查 | 结果与证据 |
| --- | --- |
| `flutter analyze --no-pub` | PASS，0 issues；`logs/agent-analyze.log` |
| `dart run tool/check_import_boundaries.dart` | PASS，409 个文件、0 违规；`logs/agent-import-boundaries.log` |
| `flutter test --no-pub --reporter compact` | PASS，1,837 个测试；`logs/fltest.log` |
| 最后页面调整后的单文件复验 | PASS，2 个页面场景；`logs/agent-widget-final.log` |
| Responses 阶段回传 | RED：`phase` 为 null；GREEN：18 个编码测试通过；`logs/agent-phase-red.log` / `logs/agent-phase-green.log` |
| 窄屏长输入与软键盘 | RED：底部溢出 42 px；GREEN：提交、停止与结果显示通过；`logs/agent-keyboard-red.log` / `logs/agent-keyboard-green.log` |
| 终态持久化故障 | RED：失败结果被旧 running 快照覆盖；GREEN：保留失败记录，恢复存储后补存且不重跑；`logs/agent-persistence-ui-red.log` / `logs/agent-persistence-ui-green.log`，补存扩展断言亦进入全量测试 |
| Dart 格式与 `git diff --check` | PASS，全部 25 个变更 Dart 文件已格式化 |
| `flutter build windows --release --no-pub` | PASS；`logs/build-windows.log` |
| `flutter build apk --release --no-pub` | PASS，86.1 MB；`logs/build-android.log`。构建另有 CupertinoIcons 缺失字体提示；Agent 使用 Material 图标，本轮未排查其他页面的该字体问题 |
| 页面离线视觉检查 | PASS，1280×900 与 390×844；`logs/agent-desktop.png` / `logs/agent-phone.png`，使用模拟数据、真实主题和字体 |
| DESIGN 合同审计 | 0 findings；审计脚本不解析 Dart，结果仅代表设计合同检查，页面另由 widget 测试和渲染核对 |
| 真实模型、缓存命中率、真实设备交互 | 未执行；三协议集成使用假 HTTP、真实 parser / runtime / controller / SQLite 装配 |

测试通过 `logs/run-agent-check.py` 设置进程树硬超时：单文件 60 秒、全量 240 秒；超时先清理残留测试进程再诊断。构建只生成本地产物，没有安装、发布、提交或推送。Windows 构建不能替代 Windows 原生交互检查；Android 编译不能证明后台保活或真机行为。

自动测试不构成小说质量提升、缓存命中率或所有兼容网关支持工具调用的证据。后续应以固定小型小说样本比较单模型、大纲流、单 Agent 和带审稿 SubAgent 四条路径，记录一致性、误报、改稿接受率、token 与延迟，再决定剧情库、自动压缩和更复杂的 Harness。

## 8. 第一版试用路径

1. 在原有设置中添加支持原生函数工具的模型；进入独立 **Agent** 页面，点击 **新建工作区**。
2. 在 **工作文档** 新建「设定」「剧本」「正文」等逻辑文档，直接粘贴内容。文档是 SQLite 中的版本记录，不是操作系统文件路径。
3. 从顶部 **模型与规则** 选择模型，按需填写写作规则。首次提交后模型和规则固定；其他配置实验使用新工作区。
4. 例如提交：“读取设定和正文，后台委派审稿子 Agent 检查人物已知信息；你先检查禁用词，收取审稿结果后修订正文并保存新版本。保留无法确定的问题。”
5. 在执行流查看思考和回复，展开工具查看参数及结果；点击子 Agent 进入独立详情，在文档页核对已保存版本。已有文档可手动编辑或查看历史，保存总是创建新版本。
6. **停止全部** 取消主任务及其子任务。关闭应用后的中断记录会在下次进入 Agent 时恢复为中断状态；已经保存的文档保留。


## 9. CUI 改造与实测

用户试用后要求对齐 Coding Agent 界面。页面现改为顶部工作区/模型/状态/用量，中间正序执行流，底部固定输入；工作文档从顶部文件夹入口切换。模型与规则在配置对话框查看，已有上下文时只读。Ctrl+Enter 可发送，Enter 保留换行，IME 组合输入期间不触发发送。

主会话和子会话复用同一执行流。活动推理显示末尾预览且可展开全文，正文分离，工具参数和结果单层展开。主视图顶部持续显示正在运行的子 Agent 入口；详情采用带工作区和运行 ID 的 GoRouter 子路由，可从持久记录恢复。页面返回不取消任务，停止仍作用于整树。滚动停留末尾时跟随输出，读历史时暂停并显示“回到最新”。

运行器在请求与工具开始时先发布活动步骤，流式更新同时传递正文和推理；60 ms 合并 UI 刷新，不增加 token 级 SQLite 写入。完成、停止或异常时保存步骤状态与部分文本；重启把遗留活动步骤终结为中断。JSON v1 的新增步骤字段可缺省，已有试用记录继续可读；没有额外 schema 迁移。

真实试用只使用自行编写的 `QA-雾港世界书` 与 `QA-人物卡`，模型为 OpenCode Go / GLM 5.2。最初请求因 MissingSessionID 返回 400；用户添加临时请求头后，同一 Agent 已能完成一次模型调用及 list/read 工具，下一轮遇到 TLS 握手失败。前一次成功调用报告输入 1472、输出 3996、缓存读取 50，冷启动样本不足以推断长期命中率。

Agent 主/子调用共用生产 HTTP client，用户自定义 Header 的更新会应用到后续请求。[OpenCode Go 官方说明](https://opencode.ai/docs/go/#where-can-i-use-it) 要求每个会话有稳定的 `x-opencode-session`；当前临时全局 UUID 能证明请求头透传，不代表已经实现按主/子会话分别管理 Session。本文不会保存其实际值。


### CUI 验证结果

- 全量测试：1,840 项通过（`logs/fltest.log`）；最终 Markdown 显示调整后，3 项页面场景再次通过（`logs/agent-cui-widget-markdown.log`）。
- 静态分析：0 issues（`logs/agent-cui-analyze.log`）；架构边界：412 个文件、0 违规（`logs/agent-import-boundaries.log`）。
- Windows 实际操作发现旧的裁剪字体缺少 tune/folder/send/pending 字形；使用 `flutter build windows --release --no-pub --no-tree-shake-icons` 重新生成测试产物，已核对字形和界面图标。该参数是本次构建方式，没有修改产品依赖。
- 模型输出复用现有 `flutter_smooth_markdown` 渲染；工具参数与结果保持可复制的原始结构，思考仍与正文分离。

### DeepSeek Flash 实测

用户指定更换为现有配置“官方DeepSeek / deepseek-flash”。为避免把已有 GLM 原生回放交给另一模型，在新建的工作区 2 内测试；只复用自行编写的 QA 内容，不读取现有小说、预设或剧本作为测试素材。

| 场景 | 实际结果 |
| --- | --- |
| 建立参考文档 | 2 次模型调用，约 7.4 秒；两份参考文档 revision 1，内容与本地 QA 原文一致 |
| 同步子 Agent | character，`background=false`，2 次模型调用，先读取人物卡再返回行动及对白 |
| 后台子 Agent | reviewer，`background=true`，2 次模型调用；主任务调用 collect 等待，真实 UI 可在运行中切换到其详情 |
| 执行流 | 实时推理、工具参数/结果、完成回复可见；返回主会话后任务继续完成 |
| 正文与修订 | 主任务 6 次模型调用，约 38.9 秒；保存 213 字符的 revision 1，随后补上时间锚点，保存 216 字符的 revision 2；参考文档不变 |
| 整树停止 | 主任务等待 collect 时点击停止；主任务与 writer 子任务均持久化为 cancelled，子任务部分推理保留；没有新增文档版本 |
| 重开与继续 | 退出应用并启动最终 Release 后，工作区、记录和文档恢复；新任务以 2 次模型调用核对 revision 2，不恢复旧子任务，不新增版本；Markdown 加粗正确显示 |

停止专项测试之前，12 次已完成模型调用累计输入 51,719、输出 8,178、缓存读取 44,160 Token，缓存读取占输入 **85.4%**。其中写作这一轮主 Agent 为 39,424 / 41,733，约 **94.5%**；角色和审稿子上下文较短且首次独立启动，累计分别约 34.4% 和 28.6%。这些是当前样例、当前供应商已报告字段的测量，不是长期命中率承诺；不把未完成调用的未报告用量算成零。证据为 `logs/agent-flash-records.json`、`logs/agent-flash-completions.json`、`logs/agent-flash-metrics.json`。

仍有 Harness 层的问题：审稿子 Agent 只被要求读取世界书，因而将人物卡明确给出的知情信息标成“缺乏依据”；主 Agent 虽保留了正确事实，却把来源分工误当成需要用户确认的规则。后续审稿提示词应要求读取相关来源、区分缺少证据与真实矛盾，并以具体证据支持违规判断。此问题不属于 Loop 或持久化失败，也说明多个 Agent 不自动等于更可靠的小说逻辑。

最终格式检查：28 个变更 Dart 文件、0 改动；`git diff --check` 通过。新版测试应用保持打开于工作区 2；未提交或推送代码。
