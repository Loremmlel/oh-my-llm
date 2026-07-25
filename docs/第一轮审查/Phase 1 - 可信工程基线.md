# Phase 1 - 可信工程基线

## Phase Name

可信工程基线：稳定测试、CI 门禁与覆盖率事实源。

## Why this Phase exists

本 Phase 聚合 TD-32、TD-34、TD-36。跨环境测试稳定性是 CI 可用的前提，CI 又是持续生成可信覆盖率数据的载体；三者分开交付会出现“自动化稳定复现红灯”或“覆盖率仍是过期本地快照”的中间状态。它们修改范围集中在测试与工程配置，风险低于业务重构，且会为所有后续 Phase 提供统一门禁，因此必须最先完成。

Review Report 已说明审查时发现的 4 个失败测试后来已修复。本 Phase 不改变这一结论；其职责是确认修复在并发和跨环境条件下稳定，并把当前可通过的质量要求固化为仓库门禁。

## Included Technical Debts

- **TD-32（P0）**：媒体路径测试依赖 Windows 路径表示，UDP 测试依赖共享广播环境。
- **TD-34（P2）**：coverage 仅有过期本地快照，没有可信的持续覆盖数据与门禁。
- **TD-36（P0）**：仓库没有 CI，format、analyze、test 和日志留存只依赖本地约定。

## Dependencies

- 前置 Phase：无。
- 后续依赖：所有后续 Phase 均依赖本 Phase 的分析与测试门禁；Phase 16 的发布任务依赖本 Phase 的测试 job 与产物追溯基础。
- 顺序理由：先消除环境与并发噪声，再启用强制门禁，最后以同一流水线产生覆盖率事实；否则失败信号不可被信任。

## Expected Benefits

- 主分支与每个重构提交都有一致的 format、analyze、test 反馈。
- Windows 路径表示和 UDP 并发不再导致环境相关假失败。
- 测试日志可完整留存，失败不因终端截断而丢失。
- coverage 成为当前提交的可审计产物，并聚焦 application/data 与变更行，而不是被模型 Getter 的总量稀释。

## File Scope

- CI 与测试配置：`.github/workflows/**`（新增）、`dart_test.yaml`、`analysis_options.yaml`、`pubspec.yaml`（仅 CI/coverage 所需配置）。
- 稳定性测试：`test/features/media/data/media_directory_scanner_test.dart`、`test/features/sync/data/sync_udp_discovery_test.dart`。
- 必要时用于稳定契约的对应生产文件：`lib/features/media/data/media_directory_scanner.dart`、`lib/features/sync/data/sync_udp_discovery.dart`；仅当测试揭示真实生命周期契约缺口时进入范围。
- CI 日志与 coverage 规则相关脚本或配置：仓库根目录及 `scripts/` 下与上述门禁直接相关的文件。

## Refactor Scope

- 将媒体路径断言从字符串表示一致，收敛为跨 Windows 路径形式仍成立的同一目录契约。
- 将 UDP 测试从共享广播残留中隔离，并明确资源清理完成的可观察条件。
- 建立固定 Flutter 版本的 format、analyze、按项目重定向规则执行的全量 test 门禁，并保留完整失败日志。
- 由 CI 生成当前 coverage 产物，定义核心 application/data 与变更行的保护目标；presentation 继续以行为清单验证，不追求无意义总行覆盖率。

## Out Of Scope

- 不修复任何与 TD-32 无关的产品行为或测试失败。
- 不在本 Phase 建立 Windows/Android 设备 E2E 或 release 构建；它们属于 Phase 16。
- 不大规模清理 `pumpAndSettle`、内部 Key 或真实时间等待；它们属于 Phase 15。
- 不改变 Flutter、Riverpod、sqlite3、http 或 go_router 技术选型。

## Risks

- CI 环境与本地 Windows 环境的网络权限差异可能暴露新的非确定性。
- 初始 coverage 门槛若错误使用总覆盖率，可能奖励低价值测试或阻塞合理重构。
- 未遵循仓库要求重定向测试输出会让失败摘要不完整。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试必须使用 AGENTS.md 指定的重定向命令执行并得到 `EXIT=0`。
- 媒体扫描与 UDP 单文件测试需在其对应平台和全量并发上下文均通过。
- CI 必须执行 format check、analyze、全量 test，上传完整测试日志和当前 coverage 产物。
- 对 CI 配置本身完成一次成功运行验证。

## Completion Criteria

- TD-32 的两个不稳定来源都有稳定、行为导向的回归保护。
- 新提交无法在 format、analyze 或 test 失败时通过门禁。
- coverage 不再依赖仓库中的过期快照，且质量目标不以单一总百分比替代关键路径判断。
- 本 Phase 可独立 Commit、Review、回滚，且不包含后续业务重构。

## Implement Context For Next Agent

你只需处理测试可信度与自动化门禁。Review Report 的既定事实是：静态分析干净；审查时全量测试曾因 3 个 Windows 路径断言和 1 个 UDP 并发用例失败，报告随后注明这 4 个失败已修复；旧 `coverage/lcov.info` 不是当前覆盖率。你的 Implement Plan 必须先验证现状，再把稳定契约放进 CI。不要借机修改业务架构、生产功能或发布签名。完成后的仓库应具备可供其余 Phase 复用的统一绿灯基线。
