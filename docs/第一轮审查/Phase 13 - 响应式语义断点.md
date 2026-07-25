# Phase 13 - 响应式语义断点

## Phase Name

跨页面响应式语义断点与 viewport 行为矩阵。

## Why this Phase exists

TD-29 是独立、低到中风险的 UI 契约债务：项目已有响应式布局，但 560/600/640/680/720/840 等数值散落，Settings/Sync 缺 compact 测试矩阵。将它与 Chat/Settings 大型工作流重构合并会扩大 review 面；在前序边界稳定后单独收敛语义 token 和行为测试，可获得清晰、可回滚的交付。

## Included Technical Debts

- **TD-29（P2）**：断点散落、缺少 shell/content/form/bubble 语义，测试偏向超宽桌面且缺 compact 边界矩阵。

## Dependencies

- 前置 Phase：Phase 5、7、10、12 已稳定 Settings、Sync、Chat workspace 与路由组合边界。
- 后续依赖：Phase 14 可访问性验证可复用同一 viewport matrix；Phase 16 设备 smoke 覆盖代表性实际尺寸。
- 顺序理由：先减少业务/组合变化，再冻结布局断点契约，避免对即将拆分的参数和页面重复测试。

## Expected Benefits

- 断点按 shell/content/form/bubble 的业务语义命名，而不是由各 Widget 复制魔法数。
- 390、600、719/720/721、1024、1440 等代表性视口能系统覆盖移动、临界值、桌面。
- 平板、窄桌面与横屏 Android 的布局夹缝更早暴露。
- 测试验证布局行为而非像素位置或 widget 私有属性。

## File Scope

- Breakpoint contract：`lib/core/constants/app_breakpoints.dart`。
- 直接使用散落断点的 app shell 与 feature presentation 文件，重点为 `lib/app/shell/**`、`lib/features/chat/presentation/**`、`settings/presentation/**`、`sync/presentation/**`、`media/presentation/**`。
- Responsive widgets：`lib/core/widgets/adaptive_master_detail_layout.dart` 等直接消费者。
- Tests：对应 app/chat/settings/sync/media Widget tests 与共享 viewport helper（若已有则复用）。

## Refactor Scope

- 盘点报告指出的散落断点并按布局职责归并为语义 token；保留确属局部设计约束的值，不追求一个全局断点。
- 让主要页面与通用 responsive widget 使用同一语义定义，消除同义魔法数。
- 建立参数化 viewport 行为矩阵，覆盖报告列出的临界尺寸和桌面宽度。
- 测试可见组件、导航模式、内容可达性与 overflow 等稳定外部契约，不测试像素坐标、内部 Key、maxLines 等实现细节。

## Out Of Scope

- 不重新设计视觉系统或改变产品信息架构。
- 不以统一 token 为由删除所有局部布局值。
- 不修改业务 Controller、持久化或协议。
- 不在本 Phase处理 Semantics/焦点；属于 Phase 14。

## Risks

- 语义名称过于抽象会让不同布局职责错误共用一个阈值。
- 临界值测试若断言具体坐标，会重现报告禁止的脆弱测试。
- 大范围机械替换数字可能改变原本有意不同的组件行为。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 参数化 tests 至少覆盖 390、600、719、720、721、1024、1440，Settings/Sync 必须包含 compact 场景。
- 测试确认无 RenderFlex overflow/unbounded constraint，并验证关键内容在各尺寸可达。
- 不新增基于 `getTopLeft`、`getRect` 或内部 Key 的布局断言。

## Completion Criteria

- Shell/content/form/bubble 等布局职责有清晰断点语义，主要重复魔法数已收敛。
- 临界与代表性 viewport 形成稳定行为矩阵。
- UI 视觉与业务行为保持一致，Phase 可独立回滚。

## Implement Context For Next Agent

项目已有 `lib/core/constants/app_breakpoints.dart`，但报告观察到 720/840/680/640/600/560 等散落值，且 Widget tests 主要覆盖 1440 宽桌面，Settings/Sync 缺 compact matrix。你的计划应先区分 shell/content/form/bubble 的语义，不能机械统一所有数值；测试尺寸必须包含 390、600、719/720/721、1024、1440，并遵守项目禁止像素定位、内部 Key 和 widget 属性断言的规则。不要借机改 UI 设计或业务状态。
