# Phase 11 - Ports 所有权与依赖门禁

## Phase Name

Application-owned ports 与可执行 import boundary。

## Why this Phase exists

本 Phase 聚合 TD-05 与 TD-39。仅搬迁 port 而没有门禁，边界会继续漂移；仅增加 import 检查而不处理已知 application→data port ownership，会把当前债务永久合法化。前序 Phase 已建立一批真实 facade/contract，本 Phase 以这些边界为样板，渐进调整旧 port 并把项目既有分层规则变为可执行约束。

## Included Technical Debts

- **TD-05（P2）**：application 依赖的抽象接口由 data 层拥有，port、binding 与实现选择混在 data。
- **TD-39（P1）**：没有可执行架构边界检查，presentation→data/persistence、core→feature 穿透只能靠 review 发现。

## Dependencies

- 前置 Phase：Phase 4、5、7、9 已分别建立 chat data ownership、settings workflow、cross-feature facade 与 generation boundary。
- 后续依赖：所有更晚 Phase 和未来新代码都受本 Phase 门禁保护；Phase 17 的 migration ownership 必须满足相同依赖方向。
- 顺序理由：先完成报告明确的高风险边界修复，再启用检查，可避免为通过 lint 而一次性搬迁整个代码库。

## Expected Benefits

- 上层需要的抽象由 application/中性 contract 所有，data 只实现并由 composition root 绑定。
- presentation→data/persistence 与 core→feature 等高风险穿透在提交时自动失败。
- 新 port 从本 Phase 起遵循一致规则，旧代码按触及范围渐进迁移。
- 架构文档不再是唯一防线，且不会因开启大量低信号 lint 制造噪声。

## File Scope

- 已知 port：`lib/features/chat/data/chat_completion_client.dart`、`chat_conversation_repository.dart` 及其 application consumers/provider bindings；其他 feature 仅限确实被上层消费的现有抽象。
- 目标 ownership：对应 `lib/features/*/application/ports/**` 或报告允许的中性 domain contract 位置。
- Composition：`lib/bootstrap.dart`、`lib/app/**`、各 feature provider binding 文件。
- Boundary tooling：`analysis_options.yaml`、`pubspec.yaml`、`tool/**` 或 `test/architecture/**`（新增），以及 CI 对该检查的调用。
- Boundary tests 与受迁移 import 影响的现有 unit/integration tests。

## Refactor Scope

- 识别 application 实际消费的 port，将 ownership 与具体 data implementation/binding 分开；仅迁移能形成完整闭环的旧 port。
- 将新 port 必须由 application 或中性 contract 层拥有的规则固化。
- 建立高信号 import boundary 检查，至少覆盖 presentation 不直接依赖 data/core persistence、core 不依赖 feature、domain 零 Flutter/Riverpod/sqlite3。
- 将架构检查纳入 Phase 1 的 CI 门禁，并允许为报告明确保留的组合边界提供窄而有理由的规则。
- 分批启用 lint；仅引入与已确认问题直接相关、可自动修复或高价值的规则。

## Out Of Scope

- 不一次性搬迁所有 repository/client 接口。
- 不为每个按钮、纯函数或简单 controller 创建 port/use case。
- 不引入新的状态管理、Clean Architecture 全套层级或 riverpod_lint 大规模规则集。
- 不以门禁为理由重排所有 feature 目录。

## Risks

- 规则过宽会漏掉真实穿透，过窄会把合法 app composition 判为违规。
- 大批 import 迁移容易造成无行为收益的 churn，必须限定为 application 所需 ports。
- Provider binding 若仍留在 data-owned port 文件中，ownership 只完成了表面移动。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- Architecture tests 对合法与非法示例均有验证，并在 CI 中执行。
- 检查当前仓库不再含报告已要求修复的 presentation→data/persistence 与 core→feature 穿透。
- 迁移后的 port 可由 fake override，具体 data implementation 仍由 composition root 选择。

## Completion Criteria

- 已触及的 application ports 不再由 data implementation 层拥有。
- 高信号依赖方向成为 CI 可执行门禁。
- 新代码规则明确，旧代码没有被迫进行无边界收益的全量搬迁。
- Phase 不引入新架构体系或低价值 lint 洪水。

## Implement Context For Next Agent

报告发现 `chat_sessions_controller.dart` 从 `data/chat_completion_client.dart` 和 `data/chat_conversation_repository.dart` 导入其所需抽象；当前没有 import cycle，但 presentation→data/persistence 与 core→feature 已存在。前序 Phase 应已修复最重要穿透并创造真实 facade。本 Phase 要把上层 port ownership 与 data binding 分开，并增加可执行 boundary test/script。坚持渐进：新 port 立即遵循，旧 port 只按完整闭环迁移，不做全仓大搬家，不开启大量低价值 lint。
