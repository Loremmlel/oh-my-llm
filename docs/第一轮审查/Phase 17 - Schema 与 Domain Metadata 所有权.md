# Phase 17 - Schema 与 Domain Metadata 所有权

## Phase Name

Feature migration ownership 与持久化 metadata 解耦。

## Why this Phase exists

本 Phase 聚合 TD-07 与 TD-10。两项均是 P3、由下一轮模块化或大 schema 扩张触发：AppDatabase 集中所有 feature migration，settings domain 又被 core persistence mixin 塑形。单独做 domain metadata 只能局部移动概念，单独做 migration registry 仍会让 feature entity 携带 persistence contract；在真实扩张触发时一起建立 ownership，收益才完整。

## Included Technical Debts

- **TD-07（P3）**：AppDatabase 集中所有 feature schema/migration，ownership 全落在 core。
- **TD-10（P3）**：settings domain 模型依赖 `core/persistence/has_id_and_updated_at.dart`，持久化需求反向塑造 domain。

## Dependencies

- 触发条件：下一次大 schema 扩张、feature 模块化或更换存储的真实需求出现。未触发时不做全面重构。
- 前置 Phase：Phase 4 已将 chat mapper ownership 归还 feature；Phase 11 已建立 import boundary。
- 后续依赖：未来 schema feature 化与模块抽取。
- 顺序理由：先用 Phase 4/11 建立低成本所有权样板，再在真实扩张时迁移 migration 和 metadata，避免当前单体应用承担高成本抽象。

## Expected Benefits

- Feature 拥有自身 migration/mapper 声明，`AppDatabase` 只负责统一顺序、事务和执行。
- Settings domain 不再 import persistence 概念，存储 adapter 负责提取 metadata。
- 新增 schema 字段或抽取 feature 时，修改范围与 ownership 更明确。
- 保留单一 AppDatabase 与 `PRAGMA user_version` 的简单可靠性，不演变为多个数据库。

## File Scope

- Core persistence：`lib/core/persistence/app_database.dart`、`has_id_and_updated_at.dart`、`sqlite_entity_repository.dart`、`sqlite_replace_all.dart`。
- Feature data repositories/mappers：`lib/features/chat/data/**`、`favorites/data/**`、`settings/data/**` 及触发 schema 扩张的 feature。
- Settings domain models：`memory_prompt.dart`、`preset_prompt.dart`、`template_prompt.dart`、`fixed_prompt_sequence.dart` 等实际使用 metadata mixin 的模型。
- Migration/schema tests：`test/core/persistence/app_database_migration_test.dart`、各 feature repository round-trip tests、`test/test_database.dart`。
- Phase 11 architecture boundary tests。

## Refactor Scope

- 将 feature schema/migration 声明与 mapper ownership逐步归还对应 feature，由 `AppDatabase` 保持统一迁移执行和事务边界。
- 保持 `PRAGMA user_version` 单调及现有数据升级路径，不改变 schema 兼容事实。
- 将 entity metadata 从 persistence-specific mixin 移到中性 contract 或 data repository adapter，避免 domain 依赖 core/persistence。
- 以触发扩张涉及的 feature 为首个渐进样板，不一次性迁移所有 migration。
- 更新 boundary tests，防止 domain 再次导入 Flutter/Riverpod/sqlite3/persistence。

## Out Of Scope

- 未触发真实 schema 扩张时，不为架构整齐全面实施。
- 不拆成多个 SQLite 数据库，不引入 drift/sqflite。
- 不改变现有数据模型的业务含义或 ID/updatedAt 语义。
- 不一次性搬迁所有历史 migration 或重置 `user_version`。

## Risks

- Migration 顺序或事务边界变化可能破坏已有用户数据，风险高于普通重构。
- Metadata 解耦若改变序列化/排序含义，会影响 settings round-trip 与同步。
- 多 feature registry 若缺少全局版本协调，会比当前集中模式更复杂。
- 无真实触发条件时实施会增加抽象而没有收益，构成新技术债。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 从所有受支持历史 schema 到当前版本的 migration tests 通过，断言 `user_version >=` 目标而非 `==`。
- 各 feature repository round-trip 与现有数据 fixture 兼容。
- Architecture tests 证明 domain 不依赖 core/persistence，core 不依赖 feature。
- 真实文件数据库升级验证不能仅依赖 in-memory 新建 schema。

## Completion Criteria

- 触发 feature 的 migration/mapper ownership 清晰，AppDatabase 仍统一执行。
- Settings domain 不再携带 persistence-specific dependency。
- 旧数据库可无损升级，所有 schema/version tests 遵守 `>=` 约定。
- 未发生全量 migration 搬迁或存储技术替换。

## Implement Context For Next Agent

这是条件 Phase：只有下一次大 schema 扩张、模块化或换存储需求出现才实施。当前 AppDatabase 集中所有 feature migration，报告认为单体应用下仍简单有效；settings domain 的多个实体则 import `core/persistence/has_id_and_updated_at.dart`。Phase 4 应已把 chat SQL/mapper 从 core 移回 chat，Phase 11 应有 boundary tests。以真实扩张 feature 为渐进样板，让 feature 声明 migration/mapper、AppDatabase 统一执行，并把 metadata 适配放到中性 contract/data adapter。禁止多数据库、重置版本或全迁历史 migration。
