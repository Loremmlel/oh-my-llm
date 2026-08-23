# Task 7 完成报告：Windows runner 通知宿主与 Dart host client

- 分支：`feat/cross-platform-generation-notifications`（BASE `7e1bf4e`）
- Commit：`a32e0d5` `feat(windows): 增加 runner 通知宿主与单实例协调`（post-commit hook 自动 bump 3.77.2+0 → 3.78.0+0 并 amend 回本次提交，属正常行为；20 文件 +5273/-12）
- 结论：**DONE**（完成定义 1–6 全部达成，均有日志证据）

## 做了什么

前任留下 6 对头文件（设计完整）、CMakeLists、测试脚本与一份 1598 行但语法损坏、且依赖 RPCSS 真实路由驱动 COM 回调的测试文件；6 个 `.cpp` 实现全部为空 stub，main.cpp/flutter_window 未接线。本次接管：

1. **补齐 6 个模块实现**（约 2400 行 C++）：
   - `windows_notification_protocol.cpp`：v1 帧/ACK 编解码、严格 UTF-8 校验（拒 overlong/代理半区/截断）、UTF-16↔UTF-8、XML 集中转义。
   - `windows_notification_instance_coordinator.cpp`：`-Embedding` 独立 token 解析、`CreateMutexW`+`ERROR_ALREADY_EXISTS` 原子选主、manual-reset ready event（owner 打开即 reset 上一任遗留 signaled）、lease mutex 切片竞争（WAIT_ABANDONED 视为取得）、pipe DACL（当前 user SID + LocalSystem 各一条完全访问 ACE，构造失败即拒绝）、单实例 message pipe server（DACL + overlapped IO + `Start` 返回时 pipe 可达性已确定，读缓冲 max+1 显式暴露超长）与一次性 client（connect 2s / ACK 3s 有界）。
   - `windows_notification_activator.cpp`：`INotificationActivationCallback` + `IClassFactory`（COM 引用计数；注册期工厂引用保留到 revoke 之后——沿用 spike 已验证的不释放策略）、FIFO 32 队列（单项 ≤1024、不逐出旧 payload）、focus 合并标志、worker「入队 + PostMessage」投递、primary 后台 STA 线程（独立 apartment 注册/revoke/pump；ready 只在 pump 开始 dispatch 后 Set）、relay 短命 STA loop（drain grace 1000ms 从注册时刻起算、max lifetime 15s 绝对上界、每次 Activate 收尾重挂 grace）、`CreateActivatorForTest` 进程内直接构造接缝。Shutdown 顺序固定：stopping → reset ready → 注册线程 revoke+join → 有界等待 in-flight 归零 → 释放 shared state（防 use-after-free；activator 通过自身 shared_ptr 保活，shutdown 后调用安全 drop）。
   - `windows_notification_registration.cpp`：产品固定身份（AUMID `YuzuShiki.OhMyLlm`、CLSID `{7E4B2C91-...E751}`）+ 纯构造 helper + 幂等注册（shortcut target/workdir/`PKEY_AppUserModel_ID`/`VT_CLSID` ToastActivatorCLSID、LocalServer32 quoted default + unquoted ServerExecutable、AUMID 键 DisplayName REG_EXPAND_SZ / CustomActivator REG_SZ），只写 HKCU，失败只回固定 stage token。
   - `windows_notification_toast.cpp`：show 参数 native 再校验（id 10000..2147483646、title ≤128 / body ≤512 / payload ≤1024 UTF-8 非空约束）、ToastGeneric XML（launch=转义 payload、双 text、无 audio/scenario/图片）、WRL ABI Toast 展示（`CreateToastNotifierWithId` + `IXmlDocumentIO::LoadXml`、`IToastNotification2::put_Tag` 十进制 ID），最外层 catch-all。
   - `windows_notification_host.cpp`：`Core` 编排——名字/身份持有拷贝（overrides 裸指针指向的调用方字符串可能在 host 存活期销毁）；primary bootstrap 顺序 = dispatch 窗口 → ready event → pipe server（先于 pre-COM delay 与注册）→ 幂等注册（失败仅禁用冷启动）→ pre-COM delay → lease（30s 总上界）→ STA ready（10s 上界）；pipe/STA handler 共用「入队+post」路径；channel 胶水（`getNotificationHostStatus` / `showTerminalNotification`（结构错→固定错误码，数值越界→false）/ `takePendingNotificationActivations`（原子清空，首次调用 armed）/ `notificationActivated` 直推，armed 前留队列避免 pending+live 双通道重复）；relay 有界竞争 lease（ready 已亮且 lease 被持有即无工作退出），投递失败捕获 payload，drain 后仅在 mutex 确认消失时晋升 primary；manualSecondary 只发 activateWindow，失败同样按 mutex 判定晋升或有界退出；`WindowsNotificationRunProcess` 与 wWinMain 同序的测试 seam；shutdown 幂等且顺序固定。

2. **修复测试文件并去 RPCSS 化**（按协调方既定方向）：
   - 修复 `#if 0` 脚手架断点（`clicker.join()` 悬垂引用）。
   - `TestInflightShutdownRace` / `TestRelayStaLoop` / `TestProcessSeamModes` relay 晋升用例 / `TestHostChannelGlue` 冷启动+live push+detach 用例全部改为直接驱动模块接缝：`CreateActivatorForTest`（共享状态同源的进程内真实 `Activate`，不依赖 RPCSS 路由）、宿主自身 pipe server 的 v1 帧、native 队列/标志直接操作；COM 注册/revoke/状态机保持真实调用（hermetic 断言 `class_registered`/ready event）。
   - 修复测试自身三处 bug：dispatch 窗口 `GWLP_USERDATA` 未设置（lpParam 不会自动进入）、`FakeBinaryMessenger::SetMessageHandler` 先 `std::move` 后判空导致事件误记 "remove"、空回复 envelope 误读（`reply == nullptr` 即 NotImplemented 的线上形态）。
   - `HostFixture` 持有名字字符串（overrides 裸指针不再指向 ctor 临时对象）。
3. **接线**：`main.cpp` 在任何 `DartProject` 之前 `WindowsNotificationHost::Start`（宽字符命令行保留 `-Embedding` token 判定；kFatal 直接退出；secondary 路径先于任何 Flutter 构造 return；post-COM delay 编译期钩子只延迟 DartProject）；`FlutterWindow` 增加 host 参数，OnCreate 在 engine 就绪后 `AttachMessenger` + `AttachWindowActivation`（RestoreAndFocus：不可见→show、最小化→restore、最后 focus，逐步 best-effort），OnDestroy 先 `DetachMessenger`。
4. **Dart host client**：`lib/app/platform/windows_notification_host_client.dart`（接口 + 生产 `MethodChannelWindowsNotificationHostClient`：构造同步安装唯一 handler、malformed/异常固定映射 false/空列表、dispose 幂等且不触发 native 调用）+ 5 条单测。

## 文件清单

新增：`windows/runner/windows_notification_{host,registration,activator,instance_coordinator,protocol,toast}.h/.cpp`（12 个）、`windows/runner/tests/windows_notification_host_test.cpp`、`scripts/test-windows-notification-host.ps1`、`lib/app/platform/windows_notification_host_client.dart`、`test/app/platform/windows_notification_host_client_test.dart`。
修改：`windows/runner/CMakeLists.txt`、`windows/runner/main.cpp`、`windows/runner/flutter_window.h/.cpp`。
（前任的 CMakeLists 与脚本基本保留；CMakeLists 仅消费其原有结构，未改语义。）

## GREEN 证据摘要（日志均在仓库根 `logs/`，不入库）

| 验证 | 命令/方式 | 结果 |
| --- | --- | --- |
| 原生测试 + configure 矩阵 | `scripts/test-windows-notification-host.ps1` → `logs/windows-notification-host-native-green.log` | EXIT=0；矩阵 4 项 PASS（testing=OFF+非零 delay 被拒、两个 delay 仅进 Debug 定义、默认全 0 可配置）；125/125 checks |
| 产品构建 | `flutter build windows` → `logs/build-windows-notification-host.log` | EXIT=0，Built Release\oh_my_llm.exe |
| Dart client 单测 | `flutter test test/app/platform/windows_notification_host_client_test.dart` → `logs/windows-notification-host-client-green.log` | EXIT=0，5/5（先装 handler、pending 一次取走、live 单一流、malformed/PlatformException 固定映射、dispose 幂等无 native 调用） |
| flutter analyze | → `logs/analyze-task7.log` | EXIT=0，No issues |
| import boundaries | `dart run tool/check_import_boundaries.dart` → `logs/import-boundaries-task7.log` | EXIT=0，407 文件 0 违规 |
| 全量测试 | `flutter test` → `logs/fltest.log` | EXIT=0，2228 全过 |
| 产品注册回读 | 启动 Release 构建一次正常关闭后 `windows_notification_host_test.exe --verify-product-registration <exe>` → `logs/windows-notification-registration-readback.log` | VERIFY_EXIT=0，7/7 全 MATCH |

RED 清单逐项覆盖位置：token 解析/模式决策/ready 语义/DACL+失败仍持 mutex/v1 round-trip 与拒绝/FIFO 32 与 focus 合并（含 8 线程并发）/UTF-8 上限/XML escaping/show 参数校验/固定身份与时序常量/STA 状态机幂等/in-flight 竞态/worker 只 post UI dispatch/CMake delay 拒绝规则（脚本矩阵）/relay 与 secondary 的 `flutterStartCount==0`（`WindowsNotificationRunProcess` 注入计数器 + relay 晋升用例断言 starts==1 仅发生于晋升后）。

## 注册回读结果

启动当前 Release 构建一次、`CloseMainWindow` 正常关闭（Exited=True，无残留进程），回读全部 MATCH：shortcut target=exe、shortcut AUMID、ToastActivatorCLSID 为 VT_CLSID、LocalServer32 默认值带引号无参数、ServerExecutable 同路径不带引号、AUMID 键 DisplayName=REG_EXPAND_SZ、CustomActivator=REG_SZ。绝对路径未写入任何文档。

## 对前任产物的处置说明

- **6 对头文件**：保留并修复。有效改动：`FocusFlag::Request` 返回是否首次置位（post 合并依据）；activator shared state 持有身份字符串拷贝（COM 对象可超越宿主生命周期）并增加 `class_registered`/`notify_hwnd`；`StaHost` 增加 `shared_for_test`、shutdown 自带 reset ready；`RunRelayStaLoop` 第三参改为共享状态回调；`PipeServer` 增加 Start 可达性确定化（ready event）与 DACL 成员；host 增加 `CreateActivatorForTest` 测试入口、私有构造改为接收 overrides（前任 `Start` 从未把 overrides 传给 Core，导致所有宿主都用产品身份运行——测试误判 primary 并与真实环境互踩，本次修复）。
- **CMakeLists / 测试脚本**：整体保留（设计正确），仅由编译验证间接确认。
- **测试文件**：保留主体结构（用例矩阵完整），修复语法断点、三处测试自身 bug，并按既定方向把 4 处 RPCSS 依赖的 COM clicker 改为接缝驱动。删除了失去调用方的 `TestClsid()` 辅助。
- **6 个 .cpp stub**：全部由本次实现补齐（前任未开始）。

## 已知风险 / 取舍

1. **`BuildPipeSecurity` 的 ACL 尺寸按 `SECURITY_MAX_SID_SIZE` 预算两条 ACE**，比精确尺寸略大（LocalAlloc 一次性分配），无功能影响。
2. **relay drain grace 从注册时刻起算**（spike 只在首次 callback 后 arm）：无点击的 relay 约 1s 退出而非等到 15s 上界，语义收紧、更快回收；与计划「drain 静默期」描述一致。
3. **测试中 `WindowsNotificationRunRelayStaLoop`/`CreateActivatorForTest` 的进程内直接 `Activate` 跑在调用线程而非 STA 线程**（生产为 COM 封送回 STA）：in-flight 计数、sink、drain 语义完全同路径；真实封送路径已由 Task 6B spike 实测覆盖，产品 smoke（真实 Toast 点击）属 Task 11。
4. **`showTerminalNotification` 参数 map 严格四键**：多键/少键返回 `badArguments` 错误码，数值越界返回 false——Dart 侧 client 不区分两种失败（统一 false），错误码供未来诊断。
5. **pipe `Start` 的可达性等待**引入最多 5s 的启动上界（仅当 CreateNamedPipeW 卡死才触界）；正常毫秒级，测试不再需要固定 sleep。
6. main.cpp 的 kFatal 路径直接退出进程（无法判定唯一 owner 时不冒险启动第二个 Flutter），与计划一致；这是产品层面的取舍而非缺陷。
7. 本机曾以前任损坏状态运行过一次 Release 构建（注册可能写过旧路径），本次回读已由当前构建重新覆盖为全 MATCH。
