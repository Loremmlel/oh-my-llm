# Phase 2 - 仓库与版本事实源

## Phase Name

仓库卫生与版本流程单一事实源。

## Why this Phase exists

本 Phase 聚合 TD-17 与 TD-38。两项债务都源于“仓库内存在相互冲突或不应跟踪的事实源”：本地配置、诊断产物和陈旧元数据造成源码噪声；hook、AGENTS、CLAUDE 与脚本对版本流程描述不一致。它们属于同一低风险 housekeeping 边界，适合在业务重构前独立清理。

## Included Technical Debts

- **TD-17（P3）**：跟踪本地配置、异常诊断文件，README/pubspec 元数据陈旧。
- **TD-38（P2）**：版本 hook 与文档存在多个事实源，实际 `post-commit` 自动 amend 带来版本与提交历史语义不一致。

## Dependencies

- 前置 Phase：Phase 1。版本机制与 CI 的最终关系应建立在已有门禁之上。
- 后续依赖：Phase 16 依赖本 Phase 已明确的本地版本流程，并负责将可分发版本、versionCode 与 provenance 收敛到 release 流程。
- 顺序理由：先清理并记录当前真实行为，再在发布 Phase 调整正式分发机制，避免一边迁移一边依赖冲突文档。

## Expected Benefits

- clone 后不再出现个人配置与诊断垃圾。
- 维护者可从一个一致来源理解当前版本策略、hook 安装与限制。
- 日常提交与未来 release 版本生成之间的边界清晰。

## File Scope

- 仓库元数据：`.gitignore`、`.claude/settings.local.json`、报告指出的异常命名 `E…gitfull_diff.txt`、`README.md`、`pubspec.yaml`。
- 版本流程：`.githooks/post-commit`、`.githooks/pre-commit`、`.githooks/commit-msg`（若存在或作为迁移目标）、`scripts/bump-version.ps1`、构建脚本、`AGENTS.md`、`CLAUDE.md`（若存在）。
- 针对 hook/版本契约的测试或校验脚本，仅限上述流程。

## Refactor Scope

- 移除不应由仓库跟踪的本地设置与诊断产物，并补足忽略规则。
- 清理或改为不易过期的项目描述、测试数字和默认元数据。
- 统一文档、hook 与脚本对“当前版本何时变化、由谁变化、是否改写提交”的陈述。
- 为当前版本流程建立可验证契约，同时明确它与 Phase 16 正式 release 版本策略的交接边界。

## Out Of Scope

- 不在本 Phase 配置正式 Android 签名、secret、release provenance 或设备 smoke。
- 不以个人偏好更换 Conventional Commits 语义。
- 不修改 Review Report 的审查基线或结论。
- 不清理与报告未指出且与事实源无关的用户文件。

## Risks

- 删除已跟踪文件是有意的仓库变更，必须精确确认目标，避免影响用户未提交内容。
- 版本 hook 变更可能改变提交 hash 或版本 bump 行为，需用隔离测试验证。
- 文档若同时保留“当前机制”和“未来目标”而未标注时机，仍会形成歧义。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 验证被移除的本地/诊断文件已由 ignore 规则覆盖。
- 用隔离仓库或等效测试验证 fix/feat/breaking 类型的版本行为与文档一致，不污染当前工作树历史。

## Completion Criteria

- TD-17 指出的仓库噪声和陈旧元数据已处理。
- TD-38 指出的所有冲突描述已统一，当前 hook 语义可验证。
- 文档明确正式分发版本机制仍由 Phase 16 处理，没有提前实现发布功能。
- 变更是独立 housekeeping 提交，可独立回滚。

## Implement Context For Next Agent

本 Phase 只处理仓库卫生和版本事实源。Review Report 认定实际机制是 `post-commit` 自动 amend，但 AGENTS、CLAUDE、pre-commit/脚本注释有冲突；同时仓库跟踪了 `.claude/settings.local.json`、异常诊断文件，并含陈旧 README/pubspec 信息。先确认文件当前存在与是否有用户改动，再规划精确变更。不要实现 Phase 16 的正式签名、tag release 或 provenance，也不要把 Review Report 改成适配代码现状。
