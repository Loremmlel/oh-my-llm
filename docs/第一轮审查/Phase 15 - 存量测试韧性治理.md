# Phase 15 - 存量测试韧性治理

## Phase Name

存量 Widget/异步测试等待、Finder 与真实时间治理。

## Why this Phase exists

TD-31 是横跨测试目录的存量治理，不应与任何单一生产 Phase 一次性捆绑。Phase 4 已提供 writer ACK，Phase 5～14 已稳定主要 workflow 和 UI 边界；此时可优先清理 setup helper、5 秒 settle、真实 debounce delay 和内部 Key，而不会为即将变化的实现重复劳动。新测试从 Phase 1 起已遵守规范，本 Phase 专门偿还剩余存量。

## Included Technical Debts

- **TD-31（P2）**：大量 `pumpAndSettle()`、内部 `find.byKey`、真实 200/300ms delay 与 timing-dependent tests 违反项目测试规范。

## Dependencies

- 前置 Phase：Phase 4 的持久化 ACK/flush；Phase 5～14 的稳定 public contracts；Phase 1 的 CI 门禁。
- 后续依赖：Phase 16 的 device/release smoke 应继承此处的稳定等待原则。
- 顺序理由：新测试规范立即生效，但机械清理存量放在业务边界稳定后，按风险热点处理，避免测试 churn 阻塞 P0/P1 修复。

## Expected Benefits

- Widget tests 不因未结束动画、pending timer 或实现 Key 重命名产生非行为性失败。
- 后台/节流测试不依赖机器速度和微秒级余量。
- Setup 使用单帧或明确条件，测试执行时间和失败定位改善。
- 测试继续验证外部契约，允许内部重构。

## File Scope

- 共享 harness/helpers：`test/helpers/test_harness.dart`、`fixtures.dart`、各 feature `*_test_helpers.dart`。
- 通过盘点确认含 setup settle、5s settle、内部 Key、200/300ms delay 或微秒 timing 的 `test/**` 文件。
- 为可控 clock/debouncer/completion signal 所必需的 production seams，仅限相关 application/core 边界；优先复用 Phase 4 已有 ACK 和现有 fake。
- `dart_test.yaml` 仅在隔离特定平台资源的稳定策略确有需要时进入范围。

## Refactor Scope

- 新增测试继续强制 setup 用 `pump()`、行为 finder、明确动画等待与可观察完成条件。
- 优先清理共享 setup helper 与超长 settle，因为它们影响最多用例。
- 将内部 Key finder 改为用户可见文本、语义、角色或公开行为结果；不以 widget 类型不存在来测试实现。
- 将真实 debounce/节流/后台 delay 改为可控 clock、debouncer、ACK 或明确事件完成。
- 按风险热点渐进处理存量，不要求单个提交机械改完全部 301 次 settle；但 Phase 结束时报告指出的类别必须有完成清单和剩余零例外或明确、审查过的合理例外。

## Out Of Scope

- 不改变产品动画时长或 debounce 业务值来迁就测试。
- 不重写 production architecture；仅允许建立最小可观测测试 seam。
- 不机械替换每个 `pumpAndSettle`，真实需要等待完整动画的用例可保留并说明行为理由。
- 不重复 Phase 9 的测试文件契约分解或 Phase 1 中 TD-32 的环境隔离。

## Risks

- 机械替换 settle 为 pump 可能让真实动画行为测试失去等待条件。
- 为测试加入生产 seam 若过度设计，会形成新的 abstraction debt。
- Finder 从 Key 改为文本时需考虑同文案多个实例，应该以用户语义而非巧合唯一性定位。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`，并在 CI 并发设置下重复运行高风险文件。
- 统计并审核 `pumpAndSettle`、`find.byKey`、固定 delay 的剩余用例；每个保留项必须有真实行为理由。
- 关键异步 tests 不再以 `delay + 2ms` 等微小时序余量判断成功。
- 测试总耗时和 flaky 重试情况至少不劣于 Phase 前基线。

## Completion Criteria

- Setup helper、5 秒 settle、真实 debounce delay 与内部实现 Key 的高风险用法已清理。
- 所有保留的 settle/Key/delay 都有稳定行为理由，不是默认习惯。
- 新测试规范被 CI/评审清单持续执行。
- 生产行为与时序参数未为测试妥协。

## Implement Context For Next Agent

报告统计约 301 次 `pumpAndSettle()`、32 次 `find.byKey`，部分 setup helper 也 settle，后台测试有 200/300ms delay。项目规范要求 setup 用 pump、行为 finder、避免真实 timing。Phase 4 应已提供后台 ACK，其他 Phase 已形成新的公开边界。你的计划先用搜索建立清单，按共享 helper→超长 settle→真实 delay→内部 Key 的收益排序处理；不要机械删除所有合理动画等待，也不要修改产品时长来让测试变绿。
