# Phase 14 - 关键交互可访问性

## Phase Name

关键自绘交互的 Semantics、焦点与键盘契约。

## Why this Phase exists

TD-30 包含两个时机不同的议题：关键控件 a11y 应渐进处理；全量 l10n 仅在产品需求出现时处理。本 Phase 只交付报告明确的关键控件可访问性，不把“未启用本地化”转化为无需求的全量迁移，因此能保持中等范围、独立验证和回滚。

## Included Technical Debts

- **TD-30（P3）**：显式 Semantics 与语义测试稀少；关键自绘手势/状态组件的屏幕阅读器和键盘可达性不足。全量 l10n 暂缓至产品需求。

## Dependencies

- 前置 Phase：Phase 10、12、13 已稳定 workspace、路由和 viewport 行为。
- 后续依赖：Phase 16 的设备 smoke 可纳入键盘/平台基本可访问性检查。
- 顺序理由：先稳定组件结构与响应式行为，再为关键交互建立语义，避免把 Semantics 绑定到即将变化的 Widget 组合。

## Expected Benefits

- 视频手势、通知气泡、消息锚点和其他关键状态控件可被屏幕阅读器识别。
- 桌面键盘与焦点用户能够触发关键操作并理解状态变化。
- A11y 成为外部行为契约，而不是依赖 Flutter 自动推断。
- 不在缺乏产品需求时承担全量文案本地化成本。

## File Scope

- 报告点名的关键控件：`lib/features/media/presentation/pages/video_player_gesture.dart`、`widgets/video_player_controls.dart`、`lib/core/widgets/notification_bubble*.dart`、`lib/features/chat/presentation/widgets/message_anchor_rail.dart`。
- 其他同类自绘 `GestureDetector`/状态组件，仅限盘点后被认定为关键用户路径者。
- 焦点/快捷键所需的 app/theme/widget 边界，仅限上述控件。
- 对应 semantics/focus/widget tests。

## Refactor Scope

- 为关键自绘操作提供可理解的 label、role/action、enabled/selected/live 状态语义。
- 为 Windows 键盘用户建立合理的焦点顺序、可见焦点与等价触发路径。
- 为通知与动态状态变化提供不过度重复的可感知反馈。
- 建立 SemanticsTester/焦点行为测试，验证用户可达性而非具体 widget 实现。
- 明确 l10n 不在当前产品需求范围，不新增全量 arb/intl 迁移。

## Out Of Scope

- 不启用全量 localization，不翻译现有文案。
- 不进行全应用视觉重设计或 WCAG 全量认证。
- 不改变视频播放、通知、消息锚点的业务行为。
- 不为普通 Material 控件重复添加无价值 Semantics。

## Risks

- 重复或嵌套 Semantics 可能让屏幕阅读器播报冗余。
- 快捷键可能与文本输入或平台默认键冲突。
- 测试若断言 Widget tree 类型而非语义节点，会形成新的脆弱契约。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- Semantics tests 覆盖视频关键手势/控制、通知状态、消息锚点操作。
- Focus tests 覆盖键盘遍历、触发、disabled 状态和焦点可恢复性。
- 在至少 compact 与 desktop viewport 验证关键语义路径。

## Completion Criteria

- 报告点名的关键自绘控件具有可用、非重复的语义与焦点契约。
- 屏幕阅读器/键盘核心路径有自动化保护。
- 全量 l10n 明确未触发且未被偷偷引入。
- Phase 不改变产品行为或视觉架构。

## Implement Context For Next Agent

报告只要求 a11y 渐进治理，点名视频手势、通知、锚点等关键控件；“本地化未启用”不是立即做全量 l10n 的结论。盘点自绘交互并限制到关键路径，规划 Semantics、focus 和 keyboard 行为测试。保持现有中文产品与 Material 控件，避免重复语义和快捷键冲突。不要新增 localization 架构或把范围扩大到全应用审计。
