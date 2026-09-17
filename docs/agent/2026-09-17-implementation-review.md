# Agent 小说工作区实现核对与状态表调查

核对日期：2026-09-17。依据当前代码、`docs/agent/README.md` 最新交接及三份领域规格；交接中较早日期的限制不代表当前行为。本次只修改导航、重命名和表单布局，不改写 Agent 工作流或数据库结构。

## 与原始设想的契合程度

主要写作闭环已经成立，Skill 式剧本也已实现，不需要再从头建设剧本触发功能。

| 设想 | 当前实现与边界 |
| --- | --- |
| 世界书、人物卡在固定前缀注入 | 每轮按当前资料重建前缀；`worldbook` / `character_cards` XML 区域，内部 Markdown 标题。覆盖修改下一轮生效，没有资料版本浏览。 |
| 主 Agent 调度，writer 自行审稿和更新状态 | coordinator → writer → reviewer / state。writer 保存候选稿，审查拒绝后可以改稿重审，通过后调用 `update_story_state`。审查结论绑定完整当前稿，改稿会使旧结论失效。 |
| 正文直接交付并结束整轮 | state 成功提交后应用结束 writer 和主任务，无额外模型结束语。主任务与 writer 展示采用正文，过程默认折叠；reviewer、character、state 仍保留各自结果与日志，并不是所有职责都生成正文。 |
| 主 Agent 掌控全局 | 主 Agent 接收用户意图、发现/读取剧本、判断时机、组织本轮约束、选择角色推演。正常写作交付由 writer/reviewer 完成，主 Agent 不再对交付稿多做一次最终审查。 |
| 角色推演只看自己的资料 | `spawn_character` 绑定一张人物卡和显式状态行，后续读取也受限；世界书仍完整提供。角色卡、共享状态行或委派文字里的秘密仍可能泄露，所以不是严格的语义知情隔离。 |
| 新角色没有人物卡也能参与 | 已支持空 `card_id` 加已有的人物状态行。全新角色还没登记状态时，需要先通过正式正文落地，或由用户创建人物卡。 |
| 最近 n 轮正文控制上下文 | 当前是手动选连续正文楼层隐藏、总结替代、编辑摘要、恢复；没有自动固定 n 轮滑窗。原文留在数据库。 |
| 类 Skill 剧本 | Markdown YAML `name` / `description` 目录追加到主会话；`read_script` 按需取全文；`record_script_progress` 保存 planned/active/completed 备忘与正文来源。新会话重新发现，进度不跨会话继承。 |
| 剧本在 n 轮内完成 | 未做硬性轮数调度。当前按故事时间和自然语言约束判断，可以跨周/月并穿插自由 RP。主 Agent 要将具体大纲与限制传给 writer，writer 再转交 reviewer；是否遗漏仍取决于模型。 |
| 沙箱与权限 | 按职责提供受限工具，限定当前作品，不提供 Shell、代码执行、任意路径、外部网络。参数、归属、状态时效和预算由程序校验；没有另外启动 OS 沙箱进程。 |
| 状态栏与预算 | 显示运行状态、子任务、已报告用量及停止入口。默认整轮 24 次模型调用、64 次工具、10 个子任务、2 个执行并发、10 分钟；审查修改受此预算约束，不是无限重试。 |

代码入口：[上下文组装](../../lib/features/agent/application/agent_context.dart)、[Harness 与工具](../../lib/features/agent/application/agent_harness.dart)、[运行器](../../lib/features/agent/application/agent_runtime.dart)、[剧本上下文](../../lib/features/agent/application/agent_script_context.dart)。

## 上下文与缓存的实际情况

主 Agent 实际输入为：职责 Harness → 预设 → 当前世界书/人物卡 → 生效摘要 → 连续主历史 → 本轮剧本目录更新 → 最新状态快照 → 用户输入。工具定义随请求按职责提供。

其中“连续主历史”还包含历史用户指令、原生工具往返、服务商要求保留的 reasoning、已读剧本与旧状态快照，并非仅有 n 轮正文。隐藏只过滤可定位的正式正文块，不会全文搜索清理工具参数或旧 reasoning 中的副本。已读剧本也不会被普通正文总结移除；输入累计达到 4 MiB 时显式停止。

writer/reviewer 每次启动新上下文，获得各自 Harness、预设、完整作者资料、生效摘要、保留正文、当前状态及委派任务；reviewer 额外得到绑定候选稿。character 获得世界书、单卡、局部状态和委派文字，不自动获得正文历史。state 获得设定、预设、维护规则、原指令、更新前状态和绑定正文，不继承改稿日志。

追加最新状态保留前面的历史前缀，但旧快照会累计。修改资料、应用新摘要或恢复/隐藏正文会改变相应前缀。子任务虽有相似资料，职责提示词和工具集合不同，不能假设主子会话直接共用整段缓存。当前实现有缓存用量记录，尚无真实长篇连续写作实验能证明收益或状态遗漏率。

因此主/子区别主要是权限、任务寿命和职责，而非是否重复读世界书。保留 coordinator 负责跨轮计划与剧本，把 writer 作为单轮交付负责人是合理的；不必为了体现“主”身份再加一次重复审稿。下一步更有价值的是用真实写作样本检查剧本漏触发、委派约束遗漏、状态缺项及实际输入增长，再决定是否加固定正文窗口或状态检索。

## 当前“数据库”是什么

底层仍为同一 SQLite 的 `agent_story_states`，按作品保存一个含 revision、稳定行 ID 和 cells 的 JSON 状态快照。`agent_story_rounds` 记录正式正文、增量操作、前后状态和撤回依据。它是三张有固定列的逻辑表，不是三张可由模型任意改 schema 的 SQL 表。

| 逻辑表 | 列 |
| --- | --- |
| 场景状态 scene | 剧情时间/阶段、地点、在场人物、其他世界状态；最多一行 |
| 人物动态 characters | 人物、位置、目标、身体与情绪、关系、所知与判断 |
| 重要经历 events | 参与人物、事件简述、时间/地点、持续影响 |

单元格是自然语言。`commit_story_state` 使用类型化 insert/update/delete：应用生成新行 ID，更新用稳定 ID，缺省列保留，空字符串清空。整批先验证，再原子提交；任何非法操作均不部分落地。内部 revision 防迟到提交，不是作者资料版本系统。状态有 512 KiB 上限。

界面按表分组、按行展开字段，适合长文本；每表先显示 20 行，用户可加载更多。目前只读，没有电子表格式单元格编辑或用户自定义表结构。状态按作品共享，多个会话不会产生独立剧情时间线。

代码入口：[逻辑表及校验](../../lib/features/agent/domain/agent_story_state.dart)、[SQLite 事务](../../lib/features/agent/data/sqlite_agent_store.dart)、[状态视图](../../lib/features/agent/presentation/agent_story_panel.dart)。

## 参考插件与填表提示词

原规格指向 **muyoou/st-memory-enhancement（记忆增强表格）**。以下按原规格固定提交 `321571958b28c75af7a83487fb20794aa11c7912` 核对，不声称覆盖所有分支或用户自定义模板。

它的提示由全局模板、每表说明/维护条件和当前表内容组合，并不是一段通用 system prompt。表内容包括带索引的 CSV、用途及初始化/新增/更新/删除条件。[表提示组装源码](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/core/table/sheet.js#L238)

三个相关入口的任务语义如下（概述，完整原文见链接）：

- `message_template`：供写作模型参考数据，并在产出后给出增删改函数文本；规定表/列/行索引和输出标签。[随正文填表模板](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/data/pluginSetting.js#L153)
- `step_by_step_user_prompt`：独立请求读取所选聊天与操作规则，只做表更新，不生成故事正文。调用方可替换当前表、聊天、总结、完整规则、世界书等占位符。[独立填表默认模板](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/data/pluginSetting.js#L329)、[运行时组装](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/scripts/runtime/absoluteRefresh.js#L883)
- `refresh_system_message_template` / `refresh_user_message_template`：针对给定聊天、旧表与表头，输出 `<tableEdit>` 中的 `insertRow` / `updateRow` / `deleteRow`，无变更时返回空标签；强调依据已知内容，并对分隔符和引号施加格式限制。[增量整理模板](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/data/pluginSetting.js#L264)

默认表还覆盖稳定特征、与用户的社交关系、约定和重要物品；它们不全适合群像写作。本应用将稳定设定交给人物卡，关系可指向任意人物，暂用三表保存动态事实。[默认表定义](https://github.com/muyoou/st-memory-enhancement/blob/321571958b28c75af7a83487fb20794aa11c7912/data/pluginSetting.js#L352)

值得对齐的是按表讲清“记录什么、何时变化、何时保留”，这已进入本应用的 `agentStateInstructions`，可在“模型与规则 → 状态 Agent”调整。值得后续评估的是重要物品与正式约定是否常被三表遗漏，以及用户是否需要手动纠正状态；这些应由实际故事决定。

不建议复制 CSV/行号/函数文本协议：当前 JSON 工具与稳定 ID 不需要禁止逗号和引号，事务及撤回也更贴合交付流程。表格外观可以作为宽屏阅读/编辑方式单独讨论，不要求替换存储。外部模板还混有与状态维护无关的权限覆盖措辞，不应作为本应用 Harness 的组成部分。

## 临时人物怎么处理

先按需记入人物动态表，并保留重要经历。常驻、重要且需要稳定性格/背景或反复角色推演的人物，再由用户整理成角色卡。现有 `write_document` 不允许 Agent 自动修改世界书或人物卡，避免把模型临时发挥悄悄提升为作者设定。当前人物表没有完整的外貌/职业/性格专列；如果角色需要长期保留这些信息，人物卡比塞进动态状态更合适。
