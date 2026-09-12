# Agent 小说工作区交接

更新日期：2026-09-12。当前阶段分支：`feat/configurable-novel-workspace`，起点为 `master@75c30ba`。实施计划见 [可配置的小说工作区](../plans/2026-09-12-configurable-novel-workspace.md)。

本文记录当前实现、已验证的流程和已知限制。已有原生工具循环、一层同步／后台 SubAgent 和文档修订；本阶段增加世界书／人物卡、可保存的角色提示词与独立模型方案、同作品多会话，以及输入查看。尚不能完整承载最初设想的长期小说工作流。

## 产品目标与下一阶段交接

用户已明确：开发 Agent 的目标是自由 roleplay 推进剧情。过去的“先写剧本、生成大纲、逐 Part 写作”是现有聊天能力下的工作方式，不应作为后续产品的默认流程或验收目标。

期望的长期流程是：自由互动并推进剧情 → 剧情时间、阶段或前置条件满足 → 触发预写剧本 → 在后续若干轮自然演绎 → 标记完成并保留人物与事件影响 → 继续自由互动。预写剧本是离散的待触发事件，例如预科班、高中各年及后续阶段的剧情；无需每轮沿剧本大纲逐 Part 写作。这里的时间首先指故事内的时间与阶段，触发规则的具体表达尚待设计。

当前可以通过明确任务和提示词试验单场景角色推演、续写、审查及修订，但没有自动剧情时钟、状态维护或剧本触发。推演／写作／审稿／保存的顺序由主 Agent 决定，程序不强制完整流水线，也没有正式接受正文并同时更新剧情事实的事务。

下一阶段应先围绕“每轮 roleplay 如何形成可靠的剧情状态，以及状态如何触发和推进剧本”确定合同。以下是待设计事项，不是已实现能力或已批准的实施计划：

- 剧情状态：剧情时间、人物状态、事件、经历和人物知情；用户希望由专门的 SubAgent 根据每轮正文提出更新，避免逐人物手工维护。
- 剧本触发与执行：先提供 description，满足时机后按需加载完整剧本，跟踪执行中的目标、后续轮次和完成状态，避免重复触发。
- 正文接受与修订：明确候选正文何时成为已发生剧情，重写后如何处理已经提取的状态和事件影响。
- 上下文交接：主／子 Agent 从状态和必要前文取得续写依据，控制历史膨胀，同时验证缓存与信息保留效果。

本阶段只提供可配置的工作区基建，不提前实现上述剧情数据库和触发系统。手填角色视角、逐角色资料开放名单及过滤已按用户要求移除；人物卡只维护一份作者设定。后续不要重新引入一套与剧情状态库平行的手工知情配置。

使用顺序：新建作品 → 从“工作文档”添加世界书和人物卡 → 从“模型与规则”配置四种职责、共享预设并保存／应用 → 查看下一次输入预览 → 开始任务。已有上下文后更换配置会创建同作品的新会话；修改设定后也通过新会话采用最新资料。旧会话和普通文档仍保留，旧历史不会复制到新会话。

## 1. 代码入口与职责

所有路径均相对仓库根目录。

| 入口 | 当前职责 |
| --- | --- |
| `lib/features/agent/application/agent_runtime.dart` | 每次用户任务的 Loop、工具执行、子任务、预算、取消、流式更新与检查点 |
| `lib/features/agent/application/agent_harness.dart` | 主／子 Agent 的内置提示词、固定工具目录和参数 schema |
| `lib/features/agent/application/agent_workspace_controller.dart` | 作品／会话选择、配置方案、输入查看、草稿、发送／停止、资料操作和持久化失败后的补存 |
| `lib/features/agent/application/agent_context.dart` | 配置默认值、资料快照、会话可读文档、上下文组装和已报告用量汇总 |
| `lib/features/agent/domain/agent_configuration.dart` | 配置方案、各职责模型与提示词、资料类型 |
| `lib/features/agent/application/ports/agent_store.dart` | 作品、会话、配置、运行和文档版本的存储接口 |
| `lib/features/agent/domain/agent_models.dart` | 工作区、文档、步骤、运行终态及未完成工具的收尾规则 |
| `lib/features/agent/data/sqlite_agent_store.dart` | SQLite 查询、检查点事务、文档版本冲突校验、中断恢复 |
| `lib/features/agent/data/agent_record_codec.dart` | 会话 JSON v2、运行 JSON v1 的编解码；保存 typed native history，拒绝未知版本 |
| `lib/features/agent/presentation/agent_screen.dart` | 独立工作区页面，顶部元信息、中间执行流、底部输入 |
| `lib/features/agent/presentation/agent_transcript.dart` | 主／子共用的正文、推理、工具步骤、子任务链接与滚动跟随 |
| `lib/features/agent/presentation/agent_run_screen.dart` | 子 Agent 的运行中／历史详情 |
| `lib/features/agent/presentation/agent_documents_panel.dart`、`agent_document_editor.dart` | 文档新建、编辑、历史版本查看和保存新版本 |
| `lib/features/agent/presentation/agent_configuration_dialog.dart`、`agent_context_dialog.dart` | 配置方案编辑保存／应用，以及预览／实际输入查看 |
| `lib/app/composition/agent_bindings.dart` | 注入共享 LLM client、已有模型与预设文本、Agent store |
| `lib/core/persistence/app_database.dart` | schema v17，追加 v16→v17 并保留此前迁移链 |

Agent 通过独立 `/agent` 入口使用，不借用 Chat 会话、消息树或生成状态机。子详情路由为 `/agent/workspaces/:workspaceId/runs/:runId`。共享的是已有三协议 LLM 客户端、HTTP 客户端、模型配置、主题和应用导航。

前一阶段修复的 Responses 原生 assistant message `phase` 保留逻辑继续沿用，本阶段未修改共享协议客户端。

## 2. Harness 与上下文

Harness 的运行行为由提示词和应用代码共同决定：模型提出行动，运行器校验权限、执行工具、保存结果并决定是否允许继续。

### 主 Agent

内置提示词要求：明确目标与约束，按需读取资料、委派、审查和保存；区分事实、推断和候选剧情；不能把文档内容当作权限；审查要有证据，主 Agent 需判断子 Agent 意见；委派时提供目标、文档名、限制和交付要求；保存正文必须调用工具并遵守版本校验；没有实际保存不能宣称已保存；达到目标后结束。

新会话首次运行依次组装：该职责的提示词及固定执行合同 → 适用的共享预设 → 按稳定 ID 排序的世界书／人物卡 → 用户任务。四种职责共用完整作者设定，约一万字设定无需先建立检索系统。之后主会话继续追加原生 turn、工具结果和用户任务。

四种职责的提示词都可编辑、恢复默认、命名保存并载入历史版本；子职责模型未覆盖时继承主模型。共享预设可勾选适用职责；“追加现有预设文本”只复制原预设已启用的文本内容，作为前置预设使用，不继承 Chat placement、模板、检查点或重试语义。保存方案保留旧版本；应用到已有历史时新建会话。

资料在首次运行时冻结为会话快照。设定编辑不会修改旧前缀；新会话采用最新版。旧版迁移的已有历史原样保留，不补写其前置设定；要采用第一公民资料需新建会话。普通文档仍按需读取。

### 子 Agent

| 角色 | 内置要求 |
| --- | --- |
| `writer` | 根据设定和文风写作／重写候选正文，不擅自改变既定事件，不宣称已保存 |
| `reviewer` | 在委派范围内检查矛盾、OOC、因果、文风或禁用词；引用短小证据，区分确定问题与推测 |
| `character` | 根据角色已知信息、动机、关系和场景推演行动与台词，不使用全知视角；结果只是候选方案 |

子上下文为对应职责提示词、适用预设、会话设定和明确委派的任务，不继承主 Agent 全部历史。每个职责选择自己的模型，单个子任务的工具往返沿用同一 target。子任务不能再派发子任务，也不能写文档。原生历史、正文、推理和工具过程保存为独立运行记录；主 Agent 收取状态、正文和错误。

人物卡只保存一份完整作者设定。主 Agent 在委派任务中明确要推演的人物、场景和信息限制；character 与其他职责共用会话资料，不设手填视角或逐人物文档开放名单。人物动态状态、事件与知情管理留待剧情数据库统一设计；目前角色推演依靠提示词和委派信息，不提供代码级人物知情隔离。子任务仍是一次性委派，没有跨场景续接或自动记忆整理。

## 3. 现有工具

下表参数全部必填；执行端再次检查字段集合、类型和权限，拒绝额外字段。

| 工具 | 参数 | 行为与权限 |
| --- | --- | --- |
| `list_documents` | 无 | 列当前会话的文档 ID、类型、名称和版本；设定为会话快照，普通文档为最新版本 |
| `read_document` | `name: string` | 返回会话采用的正文与版本；不存在于当前会话时返回工具错误 |
| `write_document` | `name: string`、`content: string`、`expected_revision: integer` | 仅主 Agent 保存普通文档新版本；新建为 0，更新必须匹配最新版本；不能覆盖世界书或人物卡 |
| `spawn_subagent` | `role`、`task`、`background` | 角色仍限 writer/reviewer/character；`false` 等待终态，`true` 立即返回 `task_id`；仅主 Agent |
| `collect_subagent` | `task_id: string`、`wait: boolean` | `true` 等待终态，`false` 查询状态；只能访问本次主任务派发的子任务，重复收取不重跑；仅主 Agent |

文档是 SQLite 内的逻辑文档，不是磁盘文件。工具不能选择任意工作区 ID。名称限定 1–120 个字符，不允许首尾空白、路径分隔符、控制字符或 `.`／`..`。SQL 使用参数绑定。

当前没有 Shell、任意文件路径、网络请求、设置读取、任意 SQL、动态代码、搜索、局部补丁、删除文档、Skills 加载或上下文压缩工具。这是应用能力限制，工具仍与应用同进程，不能称为操作系统沙箱。

## 4. Loop、预算与失败语义

正常流程：

1. 持久化用户任务及运行开始状态，向共享 LLM client 发起请求。
2. 页面接收分离的正文和推理；约 60 ms 合并一次 UI 更新，不逐 token 写数据库。
3. 等待权威 `LlmCompleted`。只有完整、可可靠回放的原生工具调用才进入执行；拒绝、未完成、缺少可靠原生 turn 等情况停止。
4. 同一模型回复提出的工具依次执行，每个结果追加到原生历史并保存检查点，然后继续模型调用。后台子任务可以与主任务重叠运行。
5. 主 Agent 若准备结束但仍有未收取的子任务，运行器等待并追加完成通知，再给主 Agent 一轮综合机会，不伪造重复的同 ID 工具结果。
6. 模型正常完成、用户停止、失败或达到预算后，记录明确终态。主任务退出时收尾其所有子任务，不遗留后台任务。

| 限制 | 默认值／口径 |
| --- | --- |
| 模型调用 | 每次用户任务全树合计 24 次；主最多 12 轮，每个子最多 6 轮 |
| 工具调用 | 每次用户任务全树合计 64 次；共享协议层每个模型回复最多 32 个调用 |
| 子任务 | 每次用户任务累计最多 6 个，同时最多 2 个；只允许一层 |
| 总时长 | 每次用户任务全树 10 分钟 |
| 单次模型请求 | 最多 8192 输出 Token；响应头等待、SSE idle 各 60 秒 |
| 输入／输出 | 主任务或委派任务 64 KiB；一次文本加推理输出 512 KiB |
| 上下文 | 本地历史与单个原生回复有 4 MiB 防护；不是模型 Token 窗口估算 |
| 文档 | 单份正文 256 KiB；每工作区最多 100 份逻辑文档 |
| 工作区 | 当前控制器最多创建 100 个 |
| 会话／配置 | 每部作品最多 100 个会话、200 个配置版本；每个职责提示词／共享预设最多 64 KiB |

这些是代码中的固定默认值，页面没有预算编辑器。达到上限不会标记为完成。错误在页面内显示；当前没有自动网络重试。

**停止与崩溃不同。** 用户停止会取消全树请求，保存已收到的部分文本、推理和取消状态。进程意外退出时，只能恢复最近持久化检查点，正在流式生成但尚未检查点保存的部分可能丢失。下次初始化 Agent 控制器时，把遗留 `running` 改为 `interrupted`，补齐未确认工具的错误结果，并告知模型核实当前文档；不会自动续跑或重新执行写入。

## 5. 持久化与缓存

### 存在哪里

沿用 `AppDatabase.open()` 的应用支持目录，不由构建脚本或 EXE 所在目录决定。当前 Windows 测试安装的路径为 `%APPDATA%\yuzu.shiki\oh_my_llm\chat_history.sqlite`；普通构建／启动不会自动创建隔离测试库。

schema v17 的 Agent 表：

| 表 | 数据 |
| --- | --- |
| `agent_workspaces` | 作品标题与当前会话指针 |
| `agent_sessions` | 每个会话的配置、资料快照、输入草稿、主 Agent typed native history |
| `agent_configurations` | 作品内命名配置方案的不可变修订 |
| `agent_runs` | 会话／主子归属、任务、状态、步骤、正文、分离推理、工具及用量；实际模型、工具目录、输入边界和子历史 |
| `agent_document_revisions` | 作品 ID、稳定文档 ID、名称、类型、版本与完整正文；历史保留 |

追加 v16→v17 迁移，保留已发布 v13→v14→v15→v16 迁移。每个旧工作区产生初始会话，原 history/draft JSON 值不重写，旧运行归属初始会话，旧文档统一为普通文档且多版本共享稳定 ID；不从名称猜测类型。顶层旧工作区记录不合法时事务回滚。Agent 表不引用 Chat 会话或消息。模型与凭据仍由 Settings 管理，Agent 记录不额外序列化 API key 或 HTTP Header。上下文、正文和推理作为本地内容保存，不等于加密存储。

升级后的 v17 数据库不能交给仅支持 v16 的旧版应用打开；仅回退 EXE 不会回退数据库版本。

主运行检查点和工作区上下文在同一事务保存。文档写入是单独的版本事务，因此存在“文档已保存、工具结果尚未保存”的崩溃窗口，恢复时不会盲目重放。终态保存失败会保留内存记录并提示；下次操作先补存，不重新执行旧工具。

草稿 300 ms 防抖保存。运行器与控制器由应用持有，离开页面或进入子详情不会停止任务。关闭应用后不能继续运行；Android 的 Chat 前台服务没有接管 Agent。Agent 数据目前没有接入 Sync 或设置导入导出。

### 当前缓存做法

- 每个 Agent 的工具目录、顺序和会话前缀固定；已有历史后更换配置通过新会话完成。发送前检查协议、解析后的 endpoint 和模型是否仍匹配原生历史。
- 世界书与人物卡按会话冻结；普通文档按需读取。不每轮重复插入完整设定或状态栏。
- 手动编辑普通文档后追加“使用前重新读取”的消息，保留旧工具结果。保存新版本也不会删除历史里的旧正文。
- 子任务使用独立短上下文，不复制完整父历史。Anthropic 装配启用已有自动缓存选项；其他缓存行为由共享协议层及服务端决定。
- 顶部统计最近主任务及其子任务的已报告输入／输出／缓存读写量；缺失时标注不完整，子详情显示自身用量。不同厂商缓存统计口径不同，不计算统一费用或跨模型命中率。
- “下一次输入预览”与运行时共用组装函数；每个模型步骤可查看当时输入的可读部分和工具目录。旧记录未保存边界时说明无法恢复，不用当前配置伪造历史输入。协议签名等私有字段不显示；字符数不等于 Token。

## 6. 已跑通的流程

### 自动验证覆盖

| 测试入口 | 验证内容 |
| --- | --- |
| `test/features/agent/application/agent_runtime_test.dart` | Loop、原生前缀、用量、工具权限、只读子任务、同步／后台收取、并发和次数预算、取消、活动步骤与部分输出 |
| `test/features/agent/application/agent_workspace_controller_test.dart` | 补存不重跑工具、超限输入、方案应用与旧会话恢复、设定冻结、预览与历史实际输入 |
| `test/features/agent/application/agent_context_test.dart`、`agent_configuration_runtime_test.dart` | 稳定前缀、各职责完整设定、工具写保护、独立角色模型及工具续接、输入边界持久化 |
| `test/features/agent/data/sqlite_agent_store_test.dart` | 文档版本与作品隔离、重开恢复、codec、会话／配置版本及资料类型修订 |
| `test/features/agent/presentation/agent_screen_test.dart` | 生产路由、子详情、Markdown、资料修订／历史、配置保存应用、输入查看、会话切换、窄屏键盘下停止可达 |
| `test/integration/agent_workspace_integration_test.dart` | 三种协议通过生产装配和模拟 HTTP 响应完成工具写入、续接与重载，检查前缀保持 |
| `test/core/persistence/app_database_migration_test.dart` | 合法历史 schema 升级；完整 v15 fixture 升级后保留旧聊天并新增 Agent 表 |
| `test/core/persistence/agent_workspace_migration_test.dart` | 完整 v16 fixture 升级保留旧资料、原生历史、草稿和运行；损坏记录回滚 |
| `test/core/llm/protocols/llm_input_encoder_test.dart` | Responses 原生阶段字段保留，不污染用户消息 |

协议集成测试是离线 wire fixture，不等于三家真实 API 均已测试。真实供应商试用如下。

以下真实供应商试用属于上一阶段（`feat/agent-workspace-runtime`），不能作为本次配置与设定快照功能的线上验证。

### 上一阶段 Windows + DeepSeek Flash

2026-09-12 使用已有配置“官方DeepSeek / deepseek-flash”，在新工作区中创建自行编写的雾港世界书和人物卡。没有把用户已有小说、预设或剧本作为素材。

| 流程 | 观察结果 |
| --- | --- |
| 建立参考文档 | 两次模型调用、约 7.4 秒，两份参考文档保存为 revision 1，与测试原文一致 |
| 同步角色推演 | `character`，`background=false`；两次模型调用，读取人物卡并返回行动／对白 |
| 后台审稿 | `reviewer`，`background=true`；两次模型调用，主 Agent 用 collect 等待结果 |
| 运行中导航 | 审稿运行时进入其详情，看到实时推理和工具参数／结果；返回主页面后继续完成 |
| 写作与修订 | 该轮主 Agent 六次模型调用，整轮约 38.9 秒；保存正文 revision 1，补上时间锚点后保存 revision 2；两份参考文档未变 |
| 停止 | 主任务等待 writer 时点击停止，主／子均保存为 cancelled，子任务部分推理保留；没有额外文档版本 |
| 重开与继续 | 退出应用后重新启动 Release，工作区、记录和文档可回读；新任务两次调用确认 revision 2，没有恢复旧子任务或重复写入；Markdown 加粗正常 |

这次试用最终保存七条主／子运行记录：五条完成、两条取消。

停止专项测试之前的 **12 次已完成调用**（建立文档、写作主任务及其两个子任务）：累计输入 51,719 Token，输出 8,178 Token，缓存读取 44,160 Token，读取占输入 **85.4%**。其中写作主 Agent 为 39,424 / 41,733，约 **94.5%**；两个首次启动的短子上下文分别约 34.4%、28.6%。口径为供应商报告的缓存读取 Token 除以输入 Token，不包含之后的停止／继续测试，不将未报告用量计成零；这只是一个短样例。

### 上一阶段 OpenCode Go + GLM 5.2

首次请求返回 MissingSessionID 400。用户增加临时自定义请求头后，Agent 成功完成一次模型调用及文档工具，下一次调用遇到 TLS 握手失败。成功调用报告输入 1,472、输出 3,996、缓存读取 50 Token。没有在该模型上跑通完整 SubAgent 写作流程。

此次确认主／子请求共用生产 HTTP client，能透传现有自定义 Header。临时全局 UUID 不等于按 Agent 会话管理 Session；没有把该 UUID 或认证信息写入仓库。

### 上一阶段本地检查与构建记录

- 最终全量测试：`flutter test --no-pub --reporter compact`，1,840 项通过。
- `flutter analyze --no-pub`：0 issues。
- `dart run tool/check_import_boundaries.dart`：412 个文件、0 违规。
- Windows 最终 CUI 测试构建：`flutter build windows --release --no-pub --no-tree-shake-icons`，通过，并完成上述原生界面试用。
- Android Release 在 CUI 改造前构建通过；最终 CUI 没有 Android 真机验证，不能据此宣称已验证后台运行或最终 Android 界面。

验证日志和自编测试素材保留在本机 ignored 的 `logs/`，不作为仓库附件发布。全量测试使用 240 秒进程树硬超时，单文件使用 60 秒；源码测试可通过上述入口复跑。

### 初次实现验证（精简前的记录）

- 最终全量 `flutter test --no-pub --reporter compact`：1849 项通过，106 秒；单文件／全量分别受 60／240 秒进程树硬超时保护。
- `flutter analyze --no-pub`：0 issues；`dart run tool/check_import_boundaries.dart`：417 个文件、0 违规。
- 关键测试验证旧版迁移和回滚、独立会话及配置版本、资料快照和角色读取权限、不同职责模型、实际输入重建，以及配置／文档／会话的页面操作。
- 使用真实中文字体完成 1280×900、390×844 离线渲染与交互检查，并补充桌面深色主题；包含打开的模型／角色菜单、人物卡作者／角色视角、共享预设和上下文预览，未发现溢出。另有窄屏键盘下提交／停止测试。
- frontend premium strict 审计 0 findings；该脚本不解析 Dart，结果仅作为设计约定静态检查。
- 最终 Windows `flutter build windows --release --no-pub --no-tree-shake-icons`：通过（79.4 秒），产物 `build/windows/x64/runner/Release/oh_my_llm.exe`。
- 最终 Android `flutter build apk --release --no-pub`：通过（93.4 秒），产物 `build/app/outputs/flutter-apk/app-release.apk`（86.5 MB）。日志有 CupertinoIcons 字体缺失提示，本阶段使用 Material Icons，未改全局字体配置。
- 27 个变更 Dart 文件格式检查及 `git diff --check` 通过；未新增依赖。实现保留在当前分支，未提交或推送。
- 本阶段未使用真实 API、未启动新版本操作用户数据库，也未做 Android 真机验证；上一阶段的线上试用和缓存数字不代表本阶段效果。

### 删除手工知情配置后的验证

用户确认没有非测试 Agent 会话，授权直接删除手工知情配置及实验字段；未发布 v17 schema 同步精简，不增加兼容层，已发布迁移链和普通聊天数据保持原样。正文与文档版本、独立模型、配置方案和会话能力保留。

- 全量 `flutter test --no-pub --reporter compact`：1848 项通过（89 秒，240 秒进程树硬超时）；减少的一项测试仅覆盖已删除的开放名单引用保护，其余相关测试按新合同更新。
- `flutter analyze --no-pub`：0 issues；`dart run tool/check_import_boundaries.dart`：417 个文件、0 违规；27 个变更 Dart 文件格式检查通过。
- 离线 Flutter 渲染与交互：桌面 1280×900、窄屏 390×844、桌面深色主题均通过，复查人物卡单正文编辑、资料列表、配置和上下文入口；图片位于 ignored `logs/novel-prune-*.png`。
- frontend premium strict 静态审计：0 findings；脚本不解析 Dart，仅辅助检查设计约定。
- 逐文件对照精简前的本地快照，删除项没有残留在源码和测试；未新增依赖、工具权限或数据库功能。
- Windows `flutter build windows --release --no-pub --no-tree-shake-icons`：通过（78.4 秒），产物 `build/windows/x64/runner/Release/oh_my_llm.exe`。
- Android `flutter build apk --release --no-pub`：通过（91.9 秒），产物 `build/app/outputs/flutter-apk/app-release.apk`（86.5 MB）；仍有此前的 CupertinoIcons 字体缺失提示，本次未修改全局字体配置。
- `git diff --check`：通过；本轮变更仅涉及上述清理及对应测试、文档，之前已实现的工作区配置改动保留。
- 未调用真实模型，未启动新版应用操作用户数据库，未做 Android 真机验证；未提交或推送。

## 7. 已知缺陷与能力边界

| 项目 | 当前事实与影响 |
| --- | --- |
| 审稿误报，真实试用已观察 | 主 Agent 只要求审稿读取世界书，审稿把人物卡已给出的知情信息标为缺乏依据；主 Agent 保留了正确事实，却向用户追问是否允许来源互补。Loop 成功不代表审稿可靠 |
| 没有强制审查后提交 | 写作／审稿／保存的次序由模型和用户任务决定；没有代码级 OOC、禁用词或因果检查，主 Agent 可直接写入文档 |
| 正文版本不能清除旧上下文 | 可以修改已保存正文，但旧草稿、写入参数和读取结果仍在历史里，模型仍可能受旧内容影响 |
| 没有长期上下文管理 | 没有隐藏历史、自动压缩、检索或 Token 窗口预算。4 MiB 只是字节防护，可能先遇到供应商上下文上限 |
| 资料库不是剧情状态库 | 世界书和人物卡已有类型与版本管理；没有自动更新的结构化时间线、人物状态、事件与人物知识关联，也没有正文与剧情状态的原子提交 |
| 没有剧本触发系统 | 无 description 目录／按需 Skill 加载、剧情前置条件、触发状态、完成标记或若干轮内完成的约束 |
| 子任务是一次性委派 | 保存原生历史供回看，不能继续已结束的子会话；各职责共用作品内的会话资料，人物知情依靠提示词与任务约束；不能直接更新数据库 |
| 配置实验需新会话 | 配置可编辑保存，已有历史时通过同作品新会话应用；模型被删除或其协议／endpoint／模型改变时旧会话发送被拒绝 |
| 历史浏览有限 | 默认加载最近 50 条运行记录，主／子一起计数；数据库保留更早记录，但没有分页浏览入口。没有工作区／文档删除 UI |
| 本地持久化仍有规模成本 | 检查点同步序列化／写入整份主历史与运行记录；文档列举在 store 内读取最新正文后再向工具返回名称。长期大上下文／大量版本的性能没有压测 |
| 运行连续性有限 | 不跨应用关闭自动续跑，无 Agent Android 前台保护；网络失败后需要新任务继续。记录持久化不等于后台执行服务 |
| 数据交换未接入 | Agent 文档与运行仅本机保存，没有 Sync／设置导入导出入口 |
| 增量 Windows 图标产物问题 | 实际发现旧裁剪字体缺少新图标；本次使用 `--no-tree-shake-icons` 重建并验证。构建脚本没有因此修改，普通增量构建的旧字体问题未作为通用构建修复处理 |

当前能试验“读取设定 → 按需委派角色／写作／审稿 → 保存与修订”的短流程。已有真实试用仅覆盖上一阶段的短场景写作与修订；自由 roleplay 的长期状态一致性、按剧情时间触发剧本及完成后继续互动，均尚未实现或验证。
