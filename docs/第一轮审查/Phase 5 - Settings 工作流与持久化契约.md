# Phase 5 - Settings 工作流与持久化契约

## Phase Name

Settings 工作流边界与持久化完成契约。

## Why this Phase exists

本 Phase 聚合 TD-03、TD-22、TD-23、TD-26。`SettingsScreen` 之所以穿透 SharedPreferences、ModelListClient 并承担 import/export，是因为设置依赖和持久化完成语义尚未形成 application 契约；`dynamic ref` 与未传递 `_commit()` Future 又让工作流无法被类型和测试可靠约束。四项共享 settings application/presentation 边界，必须先统一依赖与提交语义，再让 Screen 退回组合 UI 的职责。

## Included Technical Debts

- **TD-03（P1）**：`SettingsImportExecutor.executeImport(dynamic ref, ...)` 以动态 ref 充当 service locator。
- **TD-22（P2）**：多个设置 Controller 直接使用 JSON + SharedPreferences，版本、fallback、错误和 commit policy 分散。
- **TD-23（P2）**：`SettingsEntityController` 的公开 async 方法未传递 `_commit()` Future；replace-all 策略边界不清。
- **TD-26（P1）**：`SettingsScreen` 直接读取 persistence/data，并编排 tab、导入导出、模型获取、去重和 dialogs。

## Dependencies

- 前置 Phase：Phase 1；Phase 3 已统一 ModelListClient 的 HTTP 观测边界。
- 后续依赖：Phase 7 的 `SettingsSnapshot`/Importer 跨 feature facade 依赖本 Phase 已建立的类型化 settings application 边界；Phase 8 的同步协议通过该 facade 处理设置数据。
- 顺序理由：先使单个 settings feature 内部依赖显式、提交语义一致，再让 sync 通过稳定 facade 消费，避免把现有 service locator 暴露成跨 feature API。

## Expected Benefits

- Import/export 与模型目录工作流可脱离 Widget 和动态 ref 进行纯 application 测试。
- 调用方 `await` 设置更新时，能获得一致的提交完成或失败语义。
- SharedPreferences 设置具有统一的 key、codec、version、fallback 与 commit policy，而无需为每个小设置建立独立接口。
- `SettingsScreen` 只负责展示、用户 intent 与 dialog 组合，不直接依赖 persistence 或 data client。

## File Scope

- Settings application：`lib/features/settings/application/settings_import_executor.dart`、`settings_entity_controller.dart`、所有直接 SharedPreferences 的 settings controllers，以及与 tab、transfer、model catalog 相关的 application 文件。
- Settings data/domain：`lib/features/settings/data/model_list_client.dart`、现有 repositories、`lib/features/settings/domain/models/settings_export_data.dart`，仅限定义稳定工作流输入输出。
- Settings presentation：`lib/features/settings/presentation/settings_screen.dart`、`widgets/import_confirm_dialog.dart`、`widgets/tab/**`、`widgets/form/model_fetch_section.dart`。
- Core persistence：`lib/core/persistence/versioned_json_storage.dart`、`shared_preferences_provider.dart`，仅限轻量通用 settings store 契约。
- 对应 tests：`test/features/settings/**` 与直接验证版本化 storage 的 `test/core/persistence/**`。

## Refactor Scope

- 将设置导入目标和所需依赖变为显式、类型安全的 application 契约。
- 统一小型 SharedPreferences 设置的版本化编解码、fallback、错误与提交策略；按设置被修改时渐进迁移，不要求一次创造大量 repository。
- 使所有公开设置 mutation 的 Future 与实际 commit 完成语义一致。
- 保留小集合 replace-all 策略；仅为报告所述高频或大集合明确增量 CRUD 的触发边界，不因形式全面迁移。
- 将 tab preference、import/export 与 model catalog 工作流移出 Screen 的直接 persistence/data 访问范围。

## Out Of Scope

- 不实现 sync 的跨 feature snapshot facade、协议版本或认证；属于 Phase 7、Phase 8。
- 不全面搬迁 application ports；属于 Phase 11。
- 不引入新状态管理方案、代码生成或每按钮一个 UseCase。
- 不为仍属小集合的数据强制改为增量 CRUD。

## Risks

- 统一 Future 语义可能暴露此前被吞掉的存储失败，UI 必须保持现有错误展示约定。
- 设置格式迁移若破坏 fallback 或版本兼容，会影响已有本地配置。
- `SettingsScreen` 边界调整涉及多个 dialogs/tabs，需防止把视觉行为和 workflow 重构混为一谈。
- 聚合 store 若承载业务逻辑会成为新的 God Service，必须保持其职责为轻量持久化契约。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 导入、去重、取消、失败与成功路径由不依赖 dynamic ref 的 application tests 覆盖。
- 所有公开 async mutation 测试证明 Future 在实际 commit 成功/失败后完成。
- 旧版本、损坏 JSON 与 fallback 行为有回归保护。
- Settings widget tests 保持现有用户行为，且不通过 presentation 直接装配 persistence/data 来验证核心工作流。

## Completion Criteria

- Settings import 不再接受 `dynamic ref`，依赖列表可被编译器检查。
- 小设置的持久化与 Future 契约一致，未要求无收益的全量 repository 化。
- `SettingsScreen` 不再直接读取 SharedPreferences 或编排 ModelListClient/transfer 的业务流程。
- 本 Phase 独立提交，不包含 sync facade、协议或认证实现。

## Implement Context For Next Agent

当前 Settings 同时存在 repository 与 Controller 直接 JSON/SharedPreferences 两套持久化方式；更新顺序和错误语义不同。`SettingsEntityController` 的公开 async 方法没有把 `_commit()` Future 返回给调用方。`SettingsImportExecutor` 接收 `dynamic ref` 并读取多个 Provider。`SettingsScreen` 直接访问 SharedPreferences、ModelListClient、Clipboard import/export 与去重。你的计划应先定义 settings 内部可测试的 application 边界，再迁移 Screen；保留 Riverpod 3、现有数据模型、VersionedJsonStorage 和小集合 replace-all 的合理部分。不要提前创建 Sync facade 或协议。
