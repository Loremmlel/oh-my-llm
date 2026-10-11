# AGENTS.md

四月（Siyue）：Windows / Android 本地 AI 聊天与创作客户端，支持 Chat Completions、Responses 和 Anthropic Messages。

技术栈：Flutter / Dart、Riverpod 3（`NotifierProvider`）、原始 `sqlite3`、原始 `package:http`、`go_router`。SDK 版本以 [CI](.github/workflows/ci.yml) 和 [pubspec.yaml](pubspec.yaml) 为准。

## 按任务读取

本文件适用于整个仓库。修改文件前读取其祖先目录中的 `AGENTS.md`；跨目录任务同时读取相关领域规则。不要假设 Agent 会自动加载所有子目录文件。

| 任务 | 先读 |
| --- | --- |
| 命令、环境、日志、构建、提交或 PR | [CONTRIBUTING.md](CONTRIBUTING.md) |
| `lib/` 代码、启动与跨 feature 组合 | [lib/AGENTS.md](lib/AGENTS.md) |
| Chat、Prompt、消息树、对话历史行为 | [Chat 规则](lib/features/chat/AGENTS.md) |
| LLM 协议、工具调用与原生续接 | [LLM 规则](lib/core/llm/AGENTS.md) |
| HTTP、SSE、取消、凭据与网络日志 | [HTTP 规则](lib/core/http/AGENTS.md) |
| SQLite、schema、迁移与持久化 | [持久化规则](lib/core/persistence/AGENTS.md) |
| Sync、配对授权、Settings 交换格式 | [Sync 规则](lib/features/sync/AGENTS.md) |
| 新增、修改、删除或优化测试 | [test/AGENTS.md](test/AGENTS.md)，以及被测领域的规则 |
| 页面、组件、导航、响应式与可访问性 | [DESIGN.md](DESIGN.md) |

仅运行测试时按贡献指南执行；测试性能治理规则仅在测试提速任务中适用。产品内 Agent 功能文档在 `docs/agent/`，不作为编码 Agent 的全局指令。

## 执行与交付

- Windows 显式使用 PowerShell 7（`pwsh.exe`），禁止 `powershell.exe`；其他系统需要 PowerShell 时用 `pwsh`。仅执行 `.sh`、Git hook 验证或 POSIX 工具链时显式调用 Git Bash，不混用 shell 语法。文本 I/O 使用 UTF-8。
- 编辑文件优先使用内置 Patch 工具；除必要的批处理或批量改名外，不用 Python、Bash、PowerShell、Node 脚本编辑文件。
- `master` 受保护，禁止直接提交或 push。使用 `feat/`、`fix/`、`refactor/`、`test/`、`chore/`、`docs/` 加简短 kebab-case 描述的新分支；每个功能或修复独立提交，通过 PR 合入。
- commit subject/body 与 PR 标题/正文使用简体中文，保留英文 Conventional Commit 前缀。PR 说明为什么改、改了什么、改后效果；模板见 [.github/pull_request_template.md](.github/pull_request_template.md)。
- 每次提交前格式化所有改动的 Dart 文件，暂存后再次执行格式检查。代码变更须通过 `flutter analyze`、导入边界门禁和相关测试；纯文档变更可免 Flutter 检查，并说明原因。
- 测试必须落盘日志、保留真实退出码，并设置能终止整棵子进程树的硬超时：单文件 60 秒，全量 240 秒。分析、构建和诊断日志也写入 ignored 的 `logs/`，不要在根目录生成日志或用 `tee` 输出全量测试。
- 只报告当前提交实际完成的验证；区分本地检查、设备/服务商验收、未执行项与实际 CI 状态。提交后检查最终 HEAD 和工作区，版本 hook 会 amend 本次提交。

## 通用代码约定

- 注释和测试名称使用简体中文；注释解释原因，测试名称描述触发条件与预期行为。禁止在代码或测试中留下临时 Issue、审查或阶段编号，历史背景放在 git history / `docs/`。
- 禁止 `part` / `part of`；大文件通过 `import` / `export` 拆分，大控制器可用 mixin。数据模型用 `Equatable`。
- 跨 feature、`core/`、`app/` 使用 `package:oh_my_llm/...`；同一 feature 内使用相对路径。`test/` 文件互引使用相对路径，package 根只解析到 `lib/`。
- 大类内部可用 `// ── 分类 ────────────────────────────────────────────` 组织方法块。

## 全仓库边界

- `presentation -> application -> domain`，`data -> domain`（可依赖 `core/`）；presentation 不直接访问 data 或 persistence，跨 feature 通过 application facade/command 与 app composition 组合。禁止用宽泛 allowlist 绕过导入门禁。
- 对外名称为 **四月 / Siyue**，Dart 使用 `AppIdentity`。仓库、包名、产物前缀 `oh_my_llm`、应用 ID、存储路径、通知身份和同步/交换标识保留原值，不做全局替换。
- Windows `Runner.rc` 的 `CompanyName=yuzu.shiki` 与 `ProductName=oh_my_llm` 决定持久化目录，禁止随品牌改名；窗口标题与 `FileDescription` 使用对外名称。
- 已发布数据库迁移及其合法旧版本 fixture、数据保留测试长期保留，新增版本只追加迁移。放弃历史版本支持须经用户明确授权并单独说明兼容性方案。
- 外部 LLM 使用 `httpClientProvider`；LAN Sync/Media 使用 `peerHttpClientProvider`，不得继承 API key、Cookie 或用户自定义 Header。敏感 Header 统一脱敏，请求正文日志默认关闭。
- 当前格式是唯一 canonical；退出支持的旧格式显式失败。临时兼容层须说明原因、边界、删除条件和保护测试，不能把一次性转换变成永久 fallback；已发布数据库迁移不属于临时 shim。
