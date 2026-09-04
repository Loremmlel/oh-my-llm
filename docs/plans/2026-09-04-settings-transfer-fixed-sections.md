# Settings Transfer 固定 section 实施记录

**候选**：全仓 ponytail audit #9

**分支**：`refactor/settings-transfer-fixed-sections`

**状态**：已实施，待 PR 合入

## 目标

把只有九项固定注册的 Settings Transfer 从 participant hierarchy、类型擦除 box 和 catalog 压平为一个 closure-backed `SettingsTransferSection` 与一个 Coordinator，同时保持 Settings Transfer v9、Sync v4、SQLite schema、本地偏好格式及所有安全和执行语义不变。

不在范围内：新增可传输设置、改变 wire key/JSON、引入 runtime plugin、调整 Sync transport、修改数据库或设置 controller 的持久化格式。

## 实施前基线

记录时间：2026-09-04，基于 `master` `709d63d`。

- `lib/features/settings/application/transfer/`：12 个 Dart 文件，约 1,892 行。
- Transfer application 定向测试：5 个文件，约 1,952 行。
- 稳定设计文档：751 个物理行，混有大量历史方案比较、迁移步骤和动态扩展性说明。
- 生产注册：九个 participant、六个 group；只有 `settings_transfer_catalog_provider.dart` 一个固定注册点，没有 runtime 注册消费者。
- 旧生产路径：`participant → strategy base → JSON base → concrete participant → erased view → box → catalog → provider → coordinator`。
- 定向 Transfer 基线：40 tests，通过，约 39 秒（冷启动与依赖解析包含在内）。
- 必须保留的测试节点：v9 codec/canonical snapshot、九项 typed fixture、服务商合并、四类提示词去重、模板校验、replacement clear、敏感确认、allowed groups、prepare 零写入、stale、串行 writer、failure/partial failure、一次性 batch、SettingsScreen 和 Sync 集成。

## 最终设计

- `SettingsTransferSection` 提供 `replacing<T>`、`merging<T>` 和 `custom<T>` 三个静态泛型构造器，在注册处捕获 reader、codec、prepare、summary 与 writer。
- `SettingsTransferCoordinator` 接收固定 section iterable，独占 key 校验、重复拒绝、确定性排序、查找、group 敏感性聚合、export、decode、prepare、revalidate 和串行 execute。
- `settingsTransferCoordinatorProvider` 直接注册固定九项；旧 participant、策略基类、box、catalog、具体 participant 类和 catalog provider 全部删除。
- section 与摘要直接使用已验证的 `String key`；不再保留一层 `SettingsTransferKey` 包装。
- 单预设导出收口为 `coordinator.exportPreset`，Settings presentation 不再知道 section key 或 typed lookup。
- `RiverpodSettingsSyncFacade` 只依赖 Coordinator，并从 `coordinator.groups` 投影 Sync descriptor。

## 测试重组

- 新增 section 局部策略测试，只覆盖 metadata、重复 key、group 敏感性以及 replacing/merging 行为。
- Coordinator 测试使用 closure-backed fake section，保留安全与四阶段执行契约。
- 生产契约改为只经过 Coordinator 的外部接口：固定 key/group、跨容器全量 typed fixture 往返、v9 secret-safe canonical snapshot、本地专属设置排除及领域冲突规则。
- 删除 catalog 动态扩展性、typed lookup、box 类型擦除和具体 participant 类身份测试。
- SettingsScreen、导入确认对话框和 Sync 测试继续验证真实入口与结果。

## 实施结果

- `lib/`：`+646/-1072`，净减 **426 行**。
- `test/`：`+1165/-1757`，净减 **592 行**。
- 稳定 spec：由 751 行收敛到 144 行，只保留现行 wire、安全、执行和测试所有权约束。
- 最终生产路径对旧 `SettingsTransferParticipant`、`SettingsTransferCatalog`、`SettingsTransferKey` 和 catalog provider 的引用为零。
- 保持九个 section key、六个 group、顺序、label、敏感性与 canonical v9 JSON 不变。
- SQLite schema、Settings Transfer format version 9、Sync protocol version 4、本地设置格式均未修改。

## 验证记录

- Transfer 定向 44 tests：通过，7.7 秒，日志 `logs/settings-transfer-green.log`。
- SettingsScreen、导入确认与 Sync 定向 77 tests：通过，24.1 秒，日志 `logs/settings-transfer-ui-sync-green.log`。
- `flutter analyze`：通过，0 issue，日志 `logs/settings-transfer-analyze.log`。
- `dart run tool/check_import_boundaries.dart`：通过，检查 388 个文件、0 违规，日志 `logs/settings-transfer-boundaries.log`。
- 全量测试：1,722 tests 通过，约 44 秒，日志 `logs/fltest.log`。
- Dart format：所有改动 Dart 文件已格式化；staged format gate 通过，0 个文件需要修改。

## 审查重点

- 固定九项的 closure 是否仍复用原 controller/repository 写入边界，并保留服务商专用合并和提示词内容去重。
- prepare/revalidate 是否仍在任何写入前拒绝未知、越组或非法 payload。
- stale preview、敏感确认与 partial failure 的一次性 batch 语义是否保持。
- Settings 与 Sync presentation 是否只依赖 Coordinator/facade 的稳定外部接口。
