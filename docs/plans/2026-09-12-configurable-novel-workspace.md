# 可配置的小说工作区实施计划

日期：2026-09-12。基线：`master@75c30ba`。实施分支：`feat/configurable-novel-workspace`。

用户最初授权先写计划、随后实施；完成并精简后，又明确授权更新交接文档、提交并发起 PR。本计划只交付可配置的小说工作区，不包含剧情数据库、剧本触发或发布。

## 1. 目标与范围

同一部作品可以维护世界书、人物卡和普通文档，保存不同的主／子 Agent 提示词和模型方案，使用新方案开启独立会话，查看实际请求包含的文本、资料版本及用量。保留已有工作区、文档历史、原生上下文和运行记录的迁移；本阶段尚未发布的手工角色知情配置按用户授权直接移除，不另做兼容。

用户最终明确的产品目标是自由 roleplay 推进剧情，并按故事内时间、阶段或条件触发预写剧本；大纲流只是此前的使用方式，不是后续默认工作流。本阶段是这一目标的配置基建，下一阶段待设计边界见 [Agent 交接文档](../agent/README.md#产品目标与下一阶段交接)，不因目标澄清扩大本次实现范围。

已知实际规模约为一万字设定、九名主要人物。本阶段四种职责默认完整持有会话采用的世界书和人物卡；character 的扮演对象、场景和信息限制通过本次任务及提示词说明。资料仍以自然语言编辑，不设计性格字段系统。

### 范围内

1. 作品内的世界书／人物卡／普通文档，稳定 ID、类型、修订号；每份资料只维护一份作者设定正文。
2. 四种既有职责的可编辑提示词与独立模型；未覆盖模型的子职责继承主模型；共享预设文本可选择适用职责。
3. 命名配置方案的版本保存、另存、恢复默认、历史载入；复用既有预设的内容入口，不继承 Chat 的检查点与重试规则。
4. 作品与会话分离；新会话共享作品资料、不复制旧原生历史。旧会话可选择和继续。
5. 配置与设定在开始运行前冻结。已有历史不改首段；更换配置／采用新版设定通过新会话完成。
6. 主／子实际输入查看：角色、模型、提示词、资料版本、文本及工具结果；工具定义可展开；原生签名、认证信息不作为产品内容显示。
7. 最近一棵任务树的已报告用量统计，主／子详情显示各自实际模型。未知用量不伪装为完整统计。

### 范围外

- 自动剧情状态抽取、人物知识推断、正式正文与事实的原子接受、旧剧情依赖回滚。
- 手工角色视角正文、资料向人物开放名单及按角色过滤；动态状态和知情边界留待剧情数据库阶段统一设计。
- 剧本触发、Skills 框架、搜索／向量库、自动压缩、按楼层隐藏、子任务跨场景续接。
- 任意角色／工具插件、Shell、外部执行、OS 沙箱、自动模型路由。
- Agent Sync、导入导出整个作品、Android 前台保护、关闭应用后继续运行。
- 真实小说质量和长期缓存命中率的承诺；自动测试与构建不替代真实模型评估。

## 2. 产品合同

### 作品、会话与配置

- 保留 `AgentWorkspace` 作为 application 返回的当前作品／会话视图，作品 ID 仍是文档及现有路由的归属 ID。
- 每部作品有多个会话。每个会话独立拥有标题、输入草稿、原生历史、配置快照和资料快照。
- 新建作品产生首个空会话。会话切换只加载目标会话的主／子运行，不改变资料，也不启动模型。
- “保存方案”写入作品内配置版本；“应用配置”在空会话采用该配置，有历史时创建新会话。新建会话不继承旧聊天，但保留作品文档可读。
- 编辑配置不即时修改正在执行的任务。运行时禁用作品／会话切换、配置应用及资料修改；查看配置与上下文可用。
- 配置保存失败保留表单输入并显示 inline 错误；关闭有未保存改动的编辑器时使用既有 `AppConfirmDialog`。
- 方案正文记录当前有效的四角色提示词。恢复默认只修改编辑稿；保存后生成新版本，不覆盖旧版本。
- 模型与 API key 继续由 Settings 拥有；配置只引用模型 ID。每次运行捕获实际 target/options，子任务按职责选择，任务中不热切换。
- 已有原生历史的模型、协议或解析 endpoint 改变时继续拒绝发送，并明确提示在同一作品新建会话。

### 世界书、人物卡与版本

- 扩展既有文档修订存储，新增稳定文档 ID 和版本化元数据，不另建重复的正文存储系统。
- 类型为 `document/worldBook/characterCard`。旧文档全部迁为普通文档；不能仅凭名称自动判断人物身份或公开秘密。
- 人物卡只维护作者设定；四种职责使用相同的会话冻结世界书／人物卡版本，普通文档按需读取最新版本。
- character 保留为角色推演职责，主 Agent 在派发任务时明确角色、场景和信息限制；不要求额外的角色 ID 参数，也不宣称提供硬性的角色知情隔离。
- Agent 的通用 `write_document` 只操作普通文档，不能覆盖世界书、人物卡。资料维护归用户编辑器。
- 手动更新资料保留历史；旧会话的固定设定不静默改变。UI 提示新会话采用最新资料。普通文档更新仍通过追加通知告知当前会话。

### 上下文与用量

- 使用一个 application 上下文组装入口：角色说明及执行合同 → 适用预设 → 稳定排序的设定资料 → 本次任务；Tools 仍走三协议原生工具定义。
- 资料包含 ID、类型、名称、revision，排序以稳定 ID 为准，不依赖最近更新时间。
- 每个模型步骤记录输入项边界；主输入从所属会话的追加历史读取，子输入从子运行自己的历史读取，避免为每轮复制一份完整上下文。
- 运行记录保存模型显示名、模型 ID 和当时工具目录，用于重启后查看；不保存 API key、HTTP Header。
- 实际上下文查看复用该记录，不能用当前配置重新拼接后冒充过去请求。发送前预览只称为“下一次输入预览”。
- 展示字符／字节规模，不把字节数当作模型 Token 数。Token 用量仅使用供应商已报告字段，缺失时注明。
- 主页面统计最新主任务及其子任务；不能将主任务用量称为全树用量。

## 3. 数据与迁移

继续使用 `AppDatabase` 与 `AgentStore`，不增加依赖。

1. schema v17 追加 `agent_sessions` 与 `agent_configurations`，给 `agent_runs` 增加 session 归属，给文档版本增加稳定 ID 与类型字段。
2. `agent_workspaces` 只保存作品标题和当前会话指针；会话表是草稿／原生历史的唯一持久 owner。application 返回的工作区视图从两者组装。
3. v16→v17 在事务内把每个旧工作区迁为一个作品和初始会话，旧运行归属初始会话，保留旧 history 与 draft 的完整 JSON 值；旧文档每个逻辑名称获得稳定 ID。
4. v13→v14→v15→v16 已发布迁移与 fixture 全部保留。v17 作为未发布迁移仅增加本阶段保留的字段；从最低支持版本顺序到达 v17，不新增用于移除实验字段的 v18 迁移。
5. 冻结完整 v16 schema fixture，测试带旧运行、文档多版本、原生历史的合法升级；malformed 记录使事务回滚，不能只改 user_version。
6. 新会话保存与作品活动指针切换原子完成；检查点原子保存 run 与所属 session，不让后台子任务切换活动会话。
7. 恢复中断时按 run 所属 session 收尾，不误写另一个当前会话，不重放工具。
8. 继续现有资源上限；每作品最多 100 个会话、200 个配置版本，列表有明确上限；不增加删除功能。

## 4. 文件与职责

| 文件 | 责任 |
| --- | --- |
| `lib/features/agent/domain/agent_configuration.dart` | 不可变配置／角色设置、职责及资料类型 |
| `lib/features/agent/domain/agent_models.dart` | 当前会话视图、资料修订、运行上下文元数据 |
| `lib/features/agent/application/agent_harness.dart` | 默认提示词和工具目录，用户提示词外保留执行合同说明 |
| `lib/features/agent/application/agent_context.dart` | 固定资料组装、可读上下文与用量汇总 |
| `lib/features/agent/application/agent_runtime.dart` | 分角色 target/options、输入记录、资料工具权限 |
| `lib/features/agent/application/agent_workspace_controller.dart` | 方案保存应用、会话选择新建、输入预览、失败恢复 |
| `lib/features/agent/application/ports/agent_store.dart` | 会话与配置持久接口 |
| `lib/features/agent/data/agent_record_codec.dart`、`sqlite_agent_store.dart` | 编解码、事务、版本与范围验证 |
| `lib/core/persistence/app_database.dart` | v17 schema 与顺序迁移 |
| `lib/app/composition/agent_bindings.dart` | 现有模型及预设的 application 注入 |
| `lib/features/agent/presentation/agent_configuration_dialog.dart` | 四角色配置、共享预设、版本保存载入和应用 |
| `lib/features/agent/presentation/agent_context_dialog.dart` | 下一次输入预览与实际运行输入检查 |
| 既有 Agent screen/document editor/panel/run screen/transcript | 作品／会话入口、资料类型及正文、模型与全树用量 |
| `DESIGN.md`、`docs/agent/README.md` | 更新本阶段用户操作及验证边界 |

必要时按完整职责拆文件；不引入通用插件框架、不修改 Chat generation。

## 5. 顺序实施与验收

### 步骤一：持久模型与迁移

- 先增加合法 v16 升级的数据保留测试，运行得到缺少 v17 能力的 RED。
- 实现领域模型、codec、store 和 schema；GREEN 验证旧正文／草稿／原生历史、两个会话独立、配置历史、文档元数据版本、跨作品隔离和冲突拒绝。
- 拒绝未来 codec 版本的测试随 canonical 版本更新，不能把刚引入的版本继续当未来版本。

### 步骤二：上下文与运行

- 最低 owner 测试四种职责都包含完整的会话设定、子任务只读、通用写工具不能覆盖世界书／人物卡，作品文档读取仍受所属工作区约束。
- 同一任务不同职责走不同 target；每个职责内部原生续接保持自己的协议／模型／endpoint。
- 保存完整输入边界后核对预览／实际输入和工具目录；资料编辑不改变旧会话前缀，新会话采用新版。
- 现有取消、后台收取、预算、持久化失败测试继续通过。

### 步骤三：controller 与配置入口

- 覆盖保存方案后应用、同作品新会话、返回旧会话草稿与记录、未保存结果先补存再切换。
- 模型缺失、旧 target 改变、资料／方案保存冲突返回可理解错误且保留输入。
- 配置修改不改变旧会话；重建上下文不会复制旧原生回放。

### 步骤四：界面

- 延续 Material 3、现有 tokens、中文名称、DropdownButtonFormField、AppConfirmDialog、inline 错误。
- 顶部作品／会话选择和资料／配置／上下文入口；窄屏采用独立行或 Wrap，禁止横向挤压导致停止不可达。
- 编辑资料区分类型，只维护一份正文；历史版本整体载入且保护未保存输入。
- 配置四职责使用角色选择器，只显示当前角色表单；支持保存、恢复默认、方案历史和应用。
- 运行详情显示实际模型，并能打开模型步骤对应的实际输入；保留实时推理、工具和导航。
- 页面只保留关键用户流程测试，不重复下层权限／协议矩阵。

### 步骤五：集成、检查与交付

- 三协议集成继续通过，并通过生产 composition 验证模型／预设注入；模拟 HTTP 不宣称真实模型验证。
- `dart format` 变更 Dart 文件；`dart format --output=none --set-exit-if-changed ...`。
- `flutter analyze --no-pub`；`dart run tool/check_import_boundaries.dart`。
- 全量 `flutter test --no-pub --reporter compact`。
- Windows、Android release 构建；可用的页面渲染／交互检查覆盖桌面、窄屏、长内容、键盘和打开的下拉菜单。
- 执行 frontend premium 静态审计；其结果不能代替 Dart 测试和实际渲染。
- 自审完整 diff，更新本计划执行记录和 Agent 交接文档，列明真实模型／设备未执行项。

## 6. 命令与故障诊断

所有诊断日志写根目录 ignored `logs/`。已有 `logs/run-agent-check.py` 在命令层提供 timeout 并杀进程树，超时后调用 `scripts/kill-stale-test-processes.ps1`；复用它，测试不使用无期限后台进程。

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
python logs/run-agent-check.py 60 logs/novel-migration-red.log 'flutter test test/core/persistence/agent_workspace_migration_test.dart --no-pub --reporter compact'
python logs/run-agent-check.py 60 logs/novel-store-green.log 'flutter test test/features/agent/data/sqlite_agent_store_test.dart --no-pub --reporter compact'
python logs/run-agent-check.py 60 logs/novel-runtime-green.log 'flutter test test/features/agent/application/agent_runtime_test.dart --no-pub --reporter compact'
python logs/run-agent-check.py 60 logs/novel-widget-green.log 'flutter test test/features/agent/presentation/agent_screen_test.dart --no-pub --reporter compact'
python logs/run-agent-check.py 240 logs/fltest.log 'flutter test --no-pub --reporter compact'
```

- migration 失败：检查事务和旧记录合法性，禁止删除 fixture 或提高最低支持版本。
- native replay 失败：检查每个 Agent 的实际 target 与输入 owner，禁止把历史重编码为伪造文本续接。
- 资料越权：检查所属工作区、会话冻结版本和写权限；提示词中的角色信息限制不是硬性权限保障。
- 旧会话资料变化：检查会话冻结版本，不通过修改旧工具结果修补。
- UI 测试等待：使用可观察状态、受控 stream、有限动画 helper；不加任意 sleep。
- 测试进程级挂起：先清理残留进程，再诊断日志和重跑。

## 7. 初次实现记录（精简前的历史证据）

- 在 `master@75c30ba` 的干净工作树创建实施分支，先完成本计划，再修改实现；未提交或推送。
- 持久化：schema v17、完整 v16 fixture、配置版本、作品／会话归属和资料元数据已实现。迁移 RED 确认旧版本仍为 16；实现后 GREEN，最终全量同时覆盖原生历史保留及损坏记录回滚。
- 运行：四职责模型配置、固定设定前缀、角色视角／显式开放名单，以及预注入／list／read／write 权限已实现；主子实际输入边界及工具目录随运行保存。
- 界面：资料分类、配置保存载入及应用、预设文本导入、同作品会话切换、输入查看、主子已报告用量已实现。配置及资料编辑失败保留输入，未保存关闭需确认。
- 关键验证：既有运行器 14 项、控制器 3 项、页面 4 项通过；新增配置运行器与上下文测试纳入全量。最终 `flutter test --no-pub --reporter compact` 为 **1849 项通过**（106 秒，进程树硬超时 240 秒）。
- `flutter analyze --no-pub`：0 issues；架构门禁：417 个文件、0 违规；变更 Dart 文件完成格式化。
- 桌面 1280×900／窄屏 390×844 的离线 Flutter 渲染和交互通过，并补充桌面深色主题；使用真实中文字体检查资料列表、人物卡作者／角色视角、配置、共享预设、角色／模型打开的菜单及输入预览。图片留在 ignored `logs/novel-*.png`。这不是 Windows 原生启动或 Android 真机验证。
- frontend premium strict 静态审计：0 findings；该脚本不解析 Dart，不能代替上述测试与渲染。
- 最终自审补充开放名单引用保护：先以实际允许错误转换的行为取得 RED，再要求解除引用后才能改变人物卡类型；store 全部 7 项 GREEN，确认失败不生成修订、解除后可转换且保留历史。
- 最终 Windows：`flutter build windows --release --no-pub --no-tree-shake-icons` 通过（79.4 秒）；产物 `build/windows/x64/runner/Release/oh_my_llm.exe`。沿用上一阶段的完整图标字体构建方式。
- 最终 Android：`flutter build apk --release --no-pub` 通过（93.4 秒）；产物 `build/app/outputs/flutter-apk/app-release.apk`（86.5 MB）。日志仍提示缺少被引用的 CupertinoIcons 字体；本阶段界面使用 Material Icons，未修改全局字体配置。
- 最终 27 个变更 Dart 文件格式检查通过；`git diff --check` 通过。范围为 Agent、必要的 composition／SQLite 迁移、对应测试及文档，无新增依赖或协议客户端变更。
- 本阶段已完成，未调用真实模型，未验证长期小说质量或缓存命中率，未做 Windows 新版原生启动及 Android 真机验证。未提交、推送或发布。

## 8. 删除手工知情配置

用户确认目前只有测试会话，授权直接删除与未来剧情数据库重叠的手工配置，不做实验格式兼容。删除人物卡的第二份角色视角正文、资料开放名单、角色绑定参数、上下文过滤和对应引用保护，以及未发布 v17 中的两个存储列。世界书／人物卡、稳定 ID、修订历史、角色推演职责、分角色模型和提示词均保留。已发布迁移链和其他功能的数据合同保持原样。

相关测试改为验证各职责共用完整作者设定、角色模型独立、子任务只读及设定写保护；删除一项仅保护开放名单引用的测试。未实现或调查剧情数据库。

- 全量 `flutter test --no-pub --reporter compact`：1848 项通过（89 秒，240 秒进程树硬超时）；减少的一项测试仅覆盖已删除的开放名单引用保护，其余相关测试按新合同更新。
- `flutter analyze --no-pub`：0 issues；`dart run tool/check_import_boundaries.dart`：417 个文件、0 违规；27 个变更 Dart 文件格式检查通过。
- 离线 Flutter 渲染与交互：桌面 1280×900、窄屏 390×844、桌面深色主题均通过，复查人物卡单正文编辑、资料列表、配置和上下文入口；图片位于 ignored `logs/novel-prune-*.png`。
- frontend premium strict 静态审计：0 findings；脚本不解析 Dart，仅辅助检查设计约定。
- 逐文件对照精简前的本地快照，删除项没有残留在源码和测试；未新增依赖、工具权限或数据库功能。
- Windows `flutter build windows --release --no-pub --no-tree-shake-icons`：通过（78.4 秒），产物 `build/windows/x64/runner/Release/oh_my_llm.exe`。
- Android `flutter build apk --release --no-pub`：通过（91.9 秒），产物 `build/app/outputs/flutter-apk/app-release.apk`（86.5 MB）；仍有此前的 CupertinoIcons 字体缺失提示，本次未修改全局字体配置。
- `git diff --check`：通过；本轮变更仅涉及上述清理及对应测试、文档，之前已实现的工作区配置改动保留。
- 未调用真实模型，未启动新版应用操作用户数据库，未做 Android 真机验证；未提交或推送。
