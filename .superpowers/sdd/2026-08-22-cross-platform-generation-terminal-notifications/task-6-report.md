# Task 6 实现报告：Windows 未打包 Toast 激活机制 spike

状态：**DONE_WITH_CONCERNS**（工程与构建验证全部完成；人工验收未执行，属任务设计内；concerns 见末节）

## 工程路径与身份

- throwaway 工程：`E:\Code\omll-notification-spike`（仓库外，永不进仓库）
- 项目名 / exe：`omll_notification_spike`
- spike AUMID：`YuzuShiki.OmllNotificationSpike`
- spike GUID（无花括号 36 字符）：`1546BAD8-62DA-4F70-BA10-AA3F8708DE3E`（本次新生成）
- CLSID 注册文本：`{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}`
- 快捷方式：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\OmllNotificationSpike.lnk`
- 固定 payload：主 `生成终态通知激活验证-Payload-Ω-20260823`（29 chars）；第二条 `连续冷启动第二条-Payload-β-98765`（24 chars）
- 依赖：`flutter_local_notifications_windows: 3.1.1`（pubspec 精确固定，lockfile 回读确认 3.1.1）；另显式声明平台接口 `^12.0.0`（解析到 12.2.0，回调类型来源）；未添加 flutter_local_notifications 主包
- Flutter 3.44.8 stable / Dart 3.12.2；OS Windows 11 Pro 25H2 build 26200（NT 10.0.26200）

## 交付物结构

```
E:\Code\omll-notification-spike\
  pubspec.yaml                          # 3.1.1 精确固定
  lib\main.dart                         # PID/参数回显、延迟倒计时、双按钮固定 Toast、
                                        # callback+launch-details 双通道回显、event key(=payload)去重
  windows\runner\windows_notification_registration.{h,cpp}   # Task 7 简化预演
  windows\runner\main.cpp               # CoInitializeEx 后调用注册，结果经 entrypoint 参数带给 Dart
  windows\runner\CMakeLists.txt         # 新增源文件、ole32/shell32/advapi32/propsys/uuid、/utf-8
  cleanup-spike.ps1                     # 断言式清理（UTF-8 带 BOM）
  dist\normal\…   dist\delayed\…        # 两套可执行快照
```

仓库内新增（未提交）：`docs/testing/windows-chat-generation-notifications-smoke.md`（骨架，全 PENDING）。
工作区新增：本报告 + `task-6-user-guide.md`。
构建日志：`logs/spike-build-normal.log`、`logs/spike-build-delayed.log`。

## runner 注册实现要点（对照 brief）

- `GetModuleFileNameW`（缓冲不足自动翻倍）取 exe → `SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE)` 取 Programs → `IShellLinkW`+`IPropertyStore`+`IPersistFile::Save` 写快捷方式：
  - target=exe、workdir=exe 目录；
  - `PKEY_AppUserModel_ID` = AUMID 字符串（InitPropVariantFromString）；
  - `PKEY_AppUserModel_ToastActivatorCLSID` = 手工构造 `PROPVARIANT{vt=VT_CLSID, puuid=CoTaskMemAlloc 的 CLSID}`，CLSID 由 `CLSIDFromString` 解析带花括号文本。
- `HKCU\Software\Classes\CLSID\{clsid}\LocalServer32` 默认值 = `"带引号 exe 绝对路径"`；同键 `ServerExecutable` REG_SZ = 不带引号同路径。无自定义 activation 参数。
- 幂等：快捷方式覆盖保存、注册表值覆盖写入；任一步失败置 stage(1..4)/hr 返回 available=false，不阻断启动。失败时 Dart 收到 `SPIKE_REG_FAIL@stageN@hr...` 参数。
- 不写 HKLM、不需要管理员权限、不删除旧注册。

## Dart 侧实现要点

- `main(List<String> args)` 接收真实命令行参数并显示——COM 冷启动可见 `-Embedding`；同时显示 `SPIKE_REG_OK/FAIL`。
- PID 用 `dart:io pid` 在 initState 同步显示，先于一切延迟逻辑。
- 延迟模式：`const int.fromEnvironment('SPIKE_INIT_DELAY_MS', defaultValue: 0)`；>0 时仅对 plugin.initialize 做一次 `Future.delayed`（事件循环定时器，不阻塞 runner message loop / COM apartment），UI 有 200ms 刷新的红色倒计时横幅。
- 激活记录：callback 行与 LAUNCH-DETAILS 行都全文回显 payload；以 payload 原文为进程级 event key 去重——launch-details 与 callback 同 payload 时计「去重抑制」，仅 launch-details 有而 callback 无则计「仅 launch-details 收到」（_isReady 窗口丢失告警）；计数器含「逻辑激活数」。
- 插件初始化异常与 show 异常分别落日志行，不崩溃。

## 构建验证证据

| 构建 | 命令 | 结果 | 日志 |
|------|------|------|------|
| 正常版 | `flutter build windows --release` | EXIT=0 | `logs/spike-build-normal.log` |
| 延迟版 | `flutter build windows --release --dart-define=SPIKE_INIT_DELAY_MS=10000` | EXIT=0 | `logs/spike-build-delayed.log` |

- exe 本体两版 SHA256 相同（runner 层不变），Dart AOT `data/app.so` SHA256 不同（`DCBD574B…` vs `3A64AC29…`），确认 dart-define 生效。
- 两版分别快照到 `dist\normal`、`dist\delayed`，互不覆盖。
- 中途失败轮次：首轮因 MSVC 按 CP936 解码 UTF-8 中文注释报 C4819（warning-as-error）；次轮缺显式 include（propkey.h 等）与误用不存在的 `CoTaskFree`。修复：CMakeLists 增加 `/utf-8`，补 `<knownfolders.h> <objbase.h> <propkey.h> <propsys.h> <propvarutil.h> <shlobj.h>`，改用 `CoTaskMemFree`。最终 analyze 与构建干净。

## 自查回读值（非人工验收）

启动 `dist\normal\omll_notification_spike.exe`（PID 3480）后：

- `HKCU\...\CLSID\{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}\LocalServer32`
  - `(default)` = `"E:\Code\omll-notification-spike\dist\normal\omll_notification_spike.exe"`（带引号）
  - `ServerExecutable` = `E:\Code\omll-notification-spike\dist\normal\omll_notification_spike.exe`（不带引号）
- 快捷方式属性（Shell.Application ExtendedProperty）：
  - `System.AppUserModel.ID` = `YuzuShiki.OmllNotificationSpike`
  - `System.AppUserModel.ToastActivatorCLSID` = `{1546BAD8-62DA-4F70-BA10-AA3F8708DE3E}`（VT_CLSID 可正确回读）
  - WScript target/workdir = exe 路径 / exe 目录
- 插件 initialize 写入（源码审计预言全部命中）：`AppUserModelId\<AUMID>` DisplayName=`Omll Notification Spike`、CustomActivator=花括号 CLSID；PushNotifications Backup 键 appType=`app:desktop`、Setting=`s:banner,s:toast,s:audio,c:toast,c:ringing`、wnsId 存在。
- 幂等性实测：随后启动 delayed 版把 LocalServer32 重写为 delayed 路径，再启动 normal 版又重写回 normal——「最后启动者接管」成立。
- 进程均正常启动/关闭，无残留（REMAINING=0）。

## 延迟模式功能验证（无 UI 旁证）

清空插件写的两个注册键后启动 delayed 版：

- +4 秒（仍在延迟窗内）：`AppUserModelId\<AUMID>` 键不存在 → initialize 确实未执行；
- +13 秒：该键与 Backup 键均已重建 → 延迟到期后 initialize 执行。

## 清理脚本验证

- `cleanup-spike.ps1 -ReportOnly`（只断言不删除）：13 项断言全过（shortcut 存在性/target 指向 spike 根/文件名精确匹配；LocalServer32 存在/默认值带引号/ServerExecutable 无引号/两值同源；AUMID CustomActivator/DisplayName；Backup appType）。当前注册保留给用户测试，未做删除。
- 安全设计：检测到运行中 spike 进程拒绝执行（exit 2）；任一断言失败整体中止不删任何东西（exit 3）；逐项断言天然保证产品身份与其他注册项不可触碰；正式删除阶段若工程目录被占用给出明确指引（exit 4）。
- 注意：脚本必须保持 UTF-8 带 BOM（PS 5.1 对无 BOM 文件按 ANSI 解析会把中文注释读碎导致解析错误）；文件已内置 BOM。

## 用户操作手册

`E:\Code\oh-my-llm\.superpowers\sdd\2026-08-22-cross-platform-generation-terminal-notifications\task-6-user-guide.md`
覆盖：首次启动+注册回读 → warm 复核 → 冷启动 20 轮循环 → 快速连续两条 cold → 延迟版手工启动窗口 → 非 ASCII 对照 → native 生存性观察法 → smoke 文档回填 → 清理脚本三档用法 → 向 controller 汇报格式。每步含「看到什么算什么结果」。

## 遗留风险 / concerns

1. **验收项 5（手工启动窗口）存在真实的第二进程可能性**：COM RPCSS 在点击时若无已注册 class object，会直接按 LocalServer32 拉起新进程（`-Embedding`），不会等待手工启动中的进程完成注册。这正是 spike 要暴露的对象——若发生即命中硬停止条件，须由人工验收如实记录，不得人为规避。实现严格未加任何单实例 IPC/守护（计划明令禁止作为通过手段）。
2. **Task 7 编码情报**：CP936 环境下 runner C++ 源文件含中文注释必须配 `/utf-8`（否则 C4819 视为错误）；产品现有 runner 全 ASCII 注释。Task 7 要么同样加 `/utf-8`，要么保持 ASCII 注释（AGENTS.md 注释语言要求对 C++ 的适用性需 controller 裁量）。
3. 计划 8.0 已知限制原样存在：FFI `init` 无 catch-all，Dart try/catch 不能证明 native 异常 fail-open；插件无 `CoRevokeClassObject`。spike 未（也无法）缓解，只能靠验收项 7 观察。
4. `_isReady` 丢失的表现形式是「冷启动窗口出现但 CALLBACK/LAUNCH-DETAILS 均无行且计数为 0」——静默缺失，只能靠人眼对照点击次数发现，手册已明确写出该判据。
5. dart-define 仅影响 `data/app.so`，exe 哈希两版一致属预期；分发/取证时勿以 exe 哈希区分两版。
6. 系统通知设置（专注助手、通知权限）可能让 Toast 不弹出或静默入库，属环境噪声而非链路失败；手册准备节有提示，若误判会在多步骤间自相矛盾（其他步骤能弹出）。
7. spike UI 去重键为 payload 原文（进程生命周期内有效）；同一进程内重复 warm 点击靠 callback 计数而非 event key 区分——与产品 JSON event key 语义不同但满足本 spike 观测目的（每轮冷启动都是新进程，无跨轮污染）。
