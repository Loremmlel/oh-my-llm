# Agent 基础设施交接

更新日期：2026-09-12。适用分支：`feat/agent-workspace-runtime`，起点为 `master@d568d81`。

本文记录当前实现、已验证的流程和已知限制，不安排后续开发。当前已经能够运行独立的 Agent 工作区，完成原生工具往返、一层同步／后台 SubAgent、文档修订和运行记录持久化；尚不能完整承载最初设想的长期小说工作流。

## 1. 代码入口与职责

所有路径均相对仓库根目录。

| 入口 | 当前职责 |
| --- | --- |
| `lib/features/agent/application/agent_runtime.dart` | 每次用户任务的 Loop、工具执行、子任务、预算、取消、流式更新与检查点 |
| `lib/features/agent/application/agent_harness.dart` | 主／子 Agent 的内置提示词、固定工具目录和参数 schema |
| `lib/features/agent/application/agent_workspace_controller.dart` | 工作区选择、模型与规则、草稿、发送／停止、文档操作和持久化失败后的补存 |
| `lib/features/agent/application/ports/agent_store.dart` | 工作区、运行和文档版本的存储接口 |
| `lib/features/agent/domain/agent_models.dart` | 工作区、文档、步骤、运行终态及未完成工具的收尾规则 |
| `lib/features/agent/data/sqlite_agent_store.dart` | SQLite 查询、检查点事务、文档版本冲突校验、中断恢复 |
| `lib/features/agent/data/agent_record_codec.dart` | JSON v1 编解码，保存 typed native history；拒绝未知版本 |
| `lib/features/agent/presentation/agent_screen.dart` | 独立工作区页面，顶部元信息、中间执行流、底部输入 |
| `lib/features/agent/presentation/agent_transcript.dart` | 主／子共用的正文、推理、工具步骤、子任务链接与滚动跟随 |
| `lib/features/agent/presentation/agent_run_screen.dart` | 子 Agent 的运行中／历史详情 |
| `lib/features/agent/presentation/agent_documents_panel.dart`、`agent_document_editor.dart` | 文档新建、编辑、历史版本查看和保存新版本 |
| `lib/app/composition/agent_bindings.dart` | 注入共享 LLM client、已有模型配置和 Agent store |
| `lib/core/persistence/app_database.dart` | schema v16 及 v15→v16 迁移 |

Agent 通过独立 `/agent` 入口使用，不借用 Chat 会话、消息树或生成状态机。子详情路由为 `/agent/workspaces/:workspaceId/runs/:runId`。共享的是已有三协议 LLM 客户端、HTTP 客户端、模型配置、主题和应用导航。

本次另外修复了 `lib/core/llm/protocols/llm_input_encoder.dart` 中 Responses 原生 assistant message 续接丢失 `phase` 的问题。只保留服务返回的该字段，不给用户消息添加阶段。

## 2. Harness 与上下文

Harness 的运行行为由提示词和应用代码共同决定：模型提出行动，运行器校验权限、执行工具、保存结果并决定是否允许继续。

### 主 Agent

内置提示词要求：明确目标与约束，按需读取资料、委派、审查和保存；区分事实、推断和候选剧情；不能把文档内容当作权限；审查要有证据，主 Agent 需判断子 Agent 意见；委派时提供目标、文档名、限制和交付要求；保存正文必须调用工具并遵守版本校验；没有实际保存不能宣称已保存；达到目标后结束。

首次运行创建 `system = 内置主提示词 + 工作区写作规则`，随后追加用户任务。之后沿用持久化上下文，继续追加模型原生 turn、工具结果和新的用户任务。原有 Chat 的预设 Prompt、模板、检查点和自动重试流程没有自动接入。

### 子 Agent

| 角色 | 内置要求 |
| --- | --- |
| `writer` | 根据设定和文风写作／重写候选正文，不擅自改变既定事件，不宣称已保存 |
| `reviewer` | 在委派范围内检查矛盾、OOC、因果、文风或禁用词；引用短小证据，区分确定问题与推测 |
| `character` | 根据角色已知信息、动机、关系和场景推演行动与台词，不使用全知视角；结果只是候选方案 |

子上下文为 `角色提示词 + 工作区写作规则 + 明确委派的任务`，不继承主 Agent 全部历史。子 Agent 与主 Agent 使用同一个模型，只能读当前工作区的文档。子任务不能再派发子任务，也不能写文档。其正文、推理和工具过程保存为独立运行记录；主 Agent 收取的是状态、正文和错误，不是完整子上下文。

三个角色的区别主要来自提示词，尚没有角色专属持久记忆、不同模型配置或人物知识可见性控制。

## 3. 现有工具

参数 schema 中列出的字段全部必填；执行端再次检查字段集合、类型和权限，拒绝额外字段。

| 工具 | 参数 | 行为与权限 |
| --- | --- | --- |
| `list_documents` | 无 | 列当前工作区文档名和最新 `revision`，不把正文返回给模型；主／子均可用 |
| `read_document` | `name: string` | 返回最新正文与版本；不存在返回工具错误；主／子均可用 |
| `write_document` | `name: string`、`content: string`、`expected_revision: integer` | 保存完整内容为新版本；新建为 0，更新必须匹配最新版本；仅主 Agent |
| `spawn_subagent` | `role: writer/reviewer/character`、`task: string`、`background: boolean` | `false` 等待终态；`true` 立即返回 `task_id`；仅主 Agent |
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
| 文档 | 单份 256 KiB；每工作区最多 100 份逻辑文档 |
| 工作区 | 当前控制器最多创建 100 个 |

这些是代码中的固定默认值，页面没有预算编辑器。达到上限不会标记为完成。错误在页面内显示；当前没有自动网络重试。

**停止与崩溃不同。** 用户停止会取消全树请求，保存已收到的部分文本、推理和取消状态。进程意外退出时，只能恢复最近持久化检查点，正在流式生成但尚未检查点保存的部分可能丢失。下次初始化 Agent 控制器时，把遗留 `running` 改为 `interrupted`，补齐未确认工具的错误结果，并告知模型核实当前文档；不会自动续跑或重新执行写入。

## 5. 持久化与缓存

### 存在哪里

沿用 `AppDatabase.open()` 的应用支持目录，不由构建脚本或 EXE 所在目录决定。当前 Windows 测试安装的路径为 `%APPDATA%\yuzu.shiki\oh_my_llm\chat_history.sqlite`；普通构建／启动不会自动创建隔离测试库。

schema v16 新增三个独立表：

| 表 | 数据 |
| --- | --- |
| `agent_workspaces` | 标题、模型配置 ID、工作区规则、输入草稿、主 Agent typed native history |
| `agent_runs` | 主子关系、任务文本、状态、步骤、正文、分离的推理、工具参数／结果和已报告用量 |
| `agent_document_revisions` | 工作区 ID、文档名、版本号和完整正文；历史版本保留 |

追加 v15→v16 迁移，保留已发布 v13→v14→v15 迁移。Agent 表不引用 Chat 会话或消息。模型和服务商配置仍由原有 Settings 管理，Agent 记录不额外序列化请求 API key 或 HTTP Header。上下文、正文和推理作为本地内容保存，不等于加密存储。

升级后的 v16 数据库不能直接交给仅支持 v15 的旧版应用打开；仅回退 EXE 不会回退数据库版本。

主运行检查点和工作区上下文在同一事务保存。文档写入是单独的版本事务，因此存在“文档已保存、工具结果尚未保存”的崩溃窗口，恢复时不会盲目重放。终态保存失败会保留内存记录并提示；下次操作先补存，不重新执行旧工具。

草稿 300 ms 防抖保存。运行器与控制器由应用持有，离开页面或进入子详情不会停止任务。关闭应用后不能继续运行；Android 的 Chat 前台服务没有接管 Agent。Agent 数据目前没有接入 Sync 或设置导入导出。

### 当前缓存做法

- 每个 Agent 的工具目录与顺序固定；主工作区首个 system 固定，已有历史后锁定模型和规则。发送前检查协议、解析后的 endpoint 和模型是否仍匹配原生历史。
- 文档按需读取，内容出现在工具结果所在的位置；不每轮注入完整世界书、数据库或状态栏。
- 手动编辑文档后追加“使用前重新读取”的消息，保留旧工具结果。保存新版本也不会删除历史里的旧正文。
- 子任务使用独立短上下文，不复制完整父历史。Anthropic 装配启用已有自动缓存选项；其他缓存行为由共享协议层及服务端决定。
- 页面展示供应商已报告用量；主页面顶部统计最近一次主任务自身，子详情展示该子任务自身。主页面数字不包含子任务，不能直接当成全树成本。没有统一费用估算。

## 6. 已跑通的流程

### 自动验证覆盖

| 测试入口 | 验证内容 |
| --- | --- |
| `test/features/agent/application/agent_runtime_test.dart` | Loop、原生前缀、用量、工具权限、只读子任务、同步／后台收取、并发和次数预算、取消、活动步骤与部分输出 |
| `test/features/agent/application/agent_workspace_controller_test.dart` | 持久化失败后的内存保留与补存、不重跑工具、超限任务输入 |
| `test/features/agent/data/sqlite_agent_store_test.dart` | 文档版本冲突与隔离、文件库重开和中断恢复、codec、按工作区读取运行详情 |
| `test/features/agent/presentation/agent_screen_test.dart` | 生产路由、运行中进入子详情和返回、Markdown、文档修订／历史、窄屏键盘出现后停止按钮可达 |
| `test/integration/agent_workspace_integration_test.dart` | 三种协议通过生产装配和模拟 HTTP 响应完成工具写入、续接与重载，检查前缀保持 |
| `test/core/persistence/app_database_migration_test.dart` | 合法历史 schema 升级；完整 v15 fixture 升级后保留旧聊天并新增 Agent 表 |
| `test/core/llm/protocols/llm_input_encoder_test.dart` | Responses 原生阶段字段保留，不污染用户消息 |

协议集成测试是离线 wire fixture，不等于三家真实 API 均已测试。真实供应商试用如下。

### Windows + DeepSeek Flash

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

### OpenCode Go + GLM 5.2

首次请求返回 MissingSessionID 400。用户增加临时自定义请求头后，Agent 成功完成一次模型调用及文档工具，下一次调用遇到 TLS 握手失败。成功调用报告输入 1,472、输出 3,996、缓存读取 50 Token。没有在该模型上跑通完整 SubAgent 写作流程。

此次确认主／子请求共用生产 HTTP client，能透传现有自定义 Header。临时全局 UUID 不等于按 Agent 会话管理 Session；没有把该 UUID 或认证信息写入仓库。

### 本地检查与构建记录

- 最终全量测试：`flutter test --no-pub --reporter compact`，1,840 项通过。
- `flutter analyze --no-pub`：0 issues。
- `dart run tool/check_import_boundaries.dart`：412 个文件、0 违规。
- Windows 最终 CUI 测试构建：`flutter build windows --release --no-pub --no-tree-shake-icons`，通过，并完成上述原生界面试用。
- Android Release 在 CUI 改造前构建通过；最终 CUI 没有 Android 真机验证，不能据此宣称已验证后台运行或最终 Android 界面。

验证日志和自编测试素材保留在本机 ignored 的 `logs/`，不作为仓库附件发布。全量测试使用 240 秒进程树硬超时，单文件使用 60 秒；源码测试可通过上述入口复跑。

## 7. 已知缺陷与能力边界

| 项目 | 当前事实与影响 |
| --- | --- |
| 审稿误报，真实试用已观察 | 主 Agent 只要求审稿读取世界书，审稿把人物卡已给出的知情信息标为缺乏依据；主 Agent 保留了正确事实，却向用户追问是否允许来源互补。Loop 成功不代表审稿可靠 |
| 没有强制审查后提交 | 写作／审稿／保存的次序由模型和用户任务决定；没有代码级 OOC、禁用词或因果检查，主 Agent 可直接写入文档 |
| 正文版本不能清除旧上下文 | 可以修改已保存正文，但旧草稿、写入参数和读取结果仍在历史里，模型仍可能受旧内容影响 |
| 没有长期上下文管理 | 没有隐藏历史、自动压缩、检索或 Token 窗口预算。4 MiB 只是字节防护，可能先遇到供应商上下文上限 |
| 文档库不是剧情状态库 | 世界书、人物卡、大纲和正文均可作为普通文档；没有结构化时间线、人物状态、客观事件、角色所知及其关联，也没有正文与剧情状态的原子提交 |
| 没有剧本触发系统 | 无 description 目录／按需 Skill 加载、剧情前置条件、触发状态、完成标记或若干轮内完成的约束 |
| 子任务是一次性委派 | 不保留可继续对话的角色会话；只能读文档，不能负责直接更新数据库；所有子角色都能读该工作区所有文档，人物知识隔离依赖提示词 |
| 配置实验受上下文约束 | 有历史后模型和规则固定；模型配置被删除或协议／endpoint／模型改变时，原工作区发送会被拒绝 |
| 历史浏览有限 | 默认加载最近 50 条运行记录，主／子一起计数；数据库保留更早记录，但没有分页浏览入口。没有工作区／文档删除 UI |
| 本地持久化仍有规模成本 | 检查点同步序列化／写入整份主历史与运行记录；文档列举在 store 内读取最新正文后再向工具返回名称。长期大上下文／大量版本的性能没有压测 |
| 运行连续性有限 | 不跨应用关闭自动续跑，无 Agent Android 前台保护；网络失败后需要新任务继续。记录持久化不等于后台执行服务 |
| 数据交换未接入 | Agent 文档与运行仅本机保存，没有 Sync／设置导入导出入口 |
| 增量 Windows 图标产物问题 | 实际发现旧裁剪字体缺少新图标；本次使用 `--no-tree-shake-icons` 重建并验证。构建脚本没有因此修改，普通增量构建的旧字体问题未作为通用构建修复处理 |

因此，当前能试验“读取设定 → 委派角色／审稿 → 写正文 → 保存与修订”的短流程，也能用明确任务要求模型从剧本生成大纲或逐 Part 写作；本次真实验证范围是短场景写作与修订，没有完成整部小说或多剧本长期续写验证。
