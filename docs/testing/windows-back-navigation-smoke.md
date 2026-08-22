# Windows 鼠标侧键返回导航 — 真机 Smoke 手册

**目的：** 按计划 `docs/plans/2026-08-22-windows-back-navigation.md` 第 7 节，在真实 Windows 桌面 + 真实鼠标上验证返回侧键 / browserBack 键进入应用返回链的最终行为，并如实记录 PASS / FAIL / PENDING。

**对应任务：** Task 4。Task 1–3（adapter 单测、根部组合集成、视频差异回归）已完成，自动化证据见 `logs/windows-back-task1-red.log`、`logs/windows-back-task1-green.log`、`logs/windows-back-task2-red.log`、`logs/windows-back-task2-green.log`、`logs/windows-back-video-green.log`。

> **诚实记录原则：** 未在真实硬件上实际执行的行必须标 `PENDING`，并注明缺失的前置条件。任何行不得把 `PENDING` 当作通过。Widget 测试通过不等于硬件验证通过。

---

## 0. 被测对象与环境

| 项 | 值 |
|---|---|
| 被测行为 | Windows 宿主内 `kBackMouseButton` pointer down 与首次 `browserBack` KeyDown → `BackButtonDispatcher.invokeCallback` → 既有返回链（Dialog → busy PopScope → 页面 PopScope → Shell 本地目标 → 子路由 → 顶层回 `/chat` → Chat 根无动作） |
| 代码基线 | `2e6e9bd`（`feat/desktop-back-navigation`，本文档撰写时 HEAD；执行时以实际运行版本为准） |
| Windows 版本 | Windows 11（10.0.26200） |
| Flutter | 3.44.8 stable（CI 固定 3.44.6） |
| 鼠标型号 | 待补填（用户 2026-08-22 已完成验证，型号未提供） |
| 驱动 / 厂商软件 | 待补填（同上） |
| 侧键映射 | 待补填（同上） |
| Smoke 执行时间 | 2026-08-22（用户真实鼠标验证，本表最后更新：2026-08-22） |

### 运行被测构建

```powershell
flutter run -d windows                     # 开发调试
flutter build windows --release            # 或用 Release 产物验证
```

---

## 1. 验证矩阵（10 项）

> **当前执行状态：** 用户已于 2026-08-22 在真实 Windows 桌面 + 真实鼠标上执行第 1–9 项，全部通过（用户报告，硬件型号/驱动待补填）。第 10 项依赖把侧键映射为 Browser Back 键的设备，未见对应硬件报告，保持 `PENDING`。

| # | 用例 | 前置条件 | 状态 | 结果 / 缺失前置条件 |
|---|---|---|---|---|
| 1 | 普通侧键在历史 / 收藏 / 设置 / Sync 顶层页回 Chat | 真实鼠标 + 上述各顶层页 | PASS | 2026-08-22 用户真机验证通过 |
| 2 | 收藏夹内容、收藏详情、图片、视频子路由只退一层 | 真实鼠标 + 已进入上述子路由 | PASS | 2026-08-22 用户真机验证通过 |
| 3 | Dialog、菜单、Drawer 先关闭自身；busy Dialog（如生成中检查点）不关闭 | 真实鼠标 + 可触发的 Dialog/菜单/Drawer/busy 场景 | PASS | 2026-08-22 用户真机验证通过 |
| 4 | History / 收藏选择态先清选择再离开 | 真实鼠标 + 已进入选择态 | PASS | 2026-08-22 用户真机验证通过 |
| 5 | Chat 根侧键无动作、不关窗口、不退出进程 | 真实鼠标 + 停在 `/chat` 根 | PASS | 2026-08-22 用户真机验证通过 |
| 6 | TextField 聚焦时侧键仍返回；`Alt+Left` 只移动光标不返回 | 真实鼠标 + 聊天输入框聚焦 | PASS | 2026-08-22 用户真机验证通过 |
| 7 | 视频全屏中侧键关闭视频页；Escape 只退出全屏、留在视频页 | 真实鼠标 + 可播放视频资源 | PASS | 2026-08-22 用户真机验证通过 |
| 8 | 快速连续点击按物理点击次数逐层返回（如 详情 → 总览 → Chat） | 真实鼠标 + 位于多层栈内 | PASS | 2026-08-22 用户真机验证通过 |
| 9 | 单次点击不产生双退；若出现，记录驱动映射与事件来源并保持 `FAIL` | 真实鼠标 + 观察 | PASS | 2026-08-22 用户真机验证：无单次点击双退 |
| 10 | browserBack 映射设备走键盘路径同样返回 | 驱动把侧键映射为 Browser Back 键的设备（若有） | PENDING | 无对应硬件/驱动映射报告；有此类设备时补验 |

---

## 2. 结果记录区（执行后填写）

| # | 实际结果 | 备注 |
|---|---|---|
| 1 | PASS | 2026-08-22 用户真机验证 |
| 2 | PASS | 2026-08-22 用户真机验证 |
| 3 | PASS | 2026-08-22 用户真机验证 |
| 4 | PASS | 2026-08-22 用户真机验证 |
| 5 | PASS | 2026-08-22 用户真机验证 |
| 6 | PASS | 2026-08-22 用户真机验证 |
| 7 | PASS | 2026-08-22 用户真机验证 |
| 8 | PASS | 2026-08-22 用户真机验证 |
| 9 | PASS | 2026-08-22 用户真机验证；未出现双退 |
| 10 | PENDING | 无 browserBack 映射设备报告 |

---

## 3. 复现性说明

1. 用 `flutter run -d windows` 或 Release 产物启动应用，先在 §0 环境栏补全鼠标型号、驱动与侧键映射。
2. 逐行执行 §1 用例：每行记录实际结果到 §2；任何与「返回链优先级」不符的表现记 `FAIL` 并附复现步骤。
3. 第 9 行如出现一次点击双退：不要添加 debounce 掩盖问题；先记录驱动型号、映射设置，并在应用侧捕获 pointer/key 事件来源（临时日志可加在 `WindowsNavigationInputAdapter`），据此设计窄去重后再复测。
4. 第 10 行仅在设备驱动把侧键映射成 Browser Back 键时执行；没有此类设备时保持 `PENDING` 并注明。

---

## 4. 风险与限制（诚实声明）

- 侧键事件形态因驱动而异：多数直接产生 XButton2 pointer 事件，部分厂商驱动会改发 `browserBack` 键甚至浏览器唤起。本实现同时覆盖两条路径，但无法在无真实硬件的环境下替用户验证。
- 应用失焦（焦点在其他窗口）时 Flutter 收不到 pointer/key 事件，侧键不生效属于预期，不是缺陷。
- Android 端行为不在本手册范围；`defaultTargetPlatform != windows` 的宿主不挂载 adapter。
