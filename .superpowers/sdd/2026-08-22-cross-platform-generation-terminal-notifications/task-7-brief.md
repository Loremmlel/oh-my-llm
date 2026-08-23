### Task 7：Windows runner 通知宿主与 Dart host client

**文件**

- 新增 `windows/runner/windows_notification_host.h/.cpp`
- 新增 `windows/runner/windows_notification_registration.h/.cpp`
- 新增 `windows/runner/windows_notification_activator.h/.cpp`
- 新增 `windows/runner/windows_notification_instance_coordinator.h/.cpp`
- 新增 `windows/runner/windows_notification_protocol.h/.cpp`
- 新增 `windows/runner/windows_notification_toast.h/.cpp`
- 新增 `windows/runner/tests/windows_notification_host_test.cpp`
- 修改 `windows/runner/main.cpp`
- 修改 `windows/runner/flutter_window.h/.cpp`
- 修改 `windows/runner/CMakeLists.txt`
- 新增 `scripts/test-windows-notification-host.ps1`
- 新增 `lib/app/platform/windows_notification_host_client.dart`
- 新增 `test/app/platform/windows_notification_host_client_test.dart`

本 Task 不修改 `pubspec.yaml`/`pubspec.lock`，不添加 Windows 通知插件或 Windows App SDK。仅使用仓库 Flutter Windows embedder、当前 Windows SDK、WRL/C++/WinRT 与 Win32。

**RED 测试/编译契约**

- 原生 test executable 覆盖：精确 `-Embedding` token 解析；primary/relay/manual secondary 模式决策；manual-reset ready event 的新 owner reset/长期 owner set/shutdown reset；当前 user SID + LocalSystem 的 pipe DACL 构造及失败时 host unavailable/instance mutex 仍持有；v1 frame round-trip 与未知/超长/截断拒绝；并发入队下的 FIFO 32 queue 与 focus 合并；UTF-8 byte 上限；XML escaping；notification ID/title/body/payload validation；固定 AUMID/CLSID/shortcut/registry value 构造；notification STA ready/register/revoke/shutdown 状态机幂等；in-flight callback 与 shutdown 竞态不发生 use-after-free；worker 只能 post UI dispatch、不能直接调用 messenger/window。
- CMake configure test 覆盖默认 delay 为 0、testing=OFF/Release 拒绝非零 delay、testing=ON Debug 才能生成两个 race 变体；不得把 runtime delay 开关暴露给 Dart 或最终 release。
- `main.cpp` 的可审计 control flow 保证 `ShouldStartFlutter()==false` 分支在任何 `DartProject` 构造之前 return；native test 用注入的 process-actions seam 断言 relay/manual secondary 的 `flutterStartCount==0`。
- Dart tests：`host client 先安装唯一 handler 再查询状态`、`pending activation 一次取走完整列表`、`live callback 原样进入单一 stream`、`malformed 返回与 PlatformException 固定映射为 unavailable 或 false`、`dispose 幂等且不调用 native shutdown`。
- 真实 shortcut/registry/COM/Toast OS 行为不伪装成纯测试已覆盖，沿用 Task 6B 与下方产品回读/smoke。

**GREEN**

- 严格实现第 8.1–8.7 节 runner host 与 Dart client；`main.cpp` 只依赖 `windows_notification_host.h`，内部 helpers 不泄漏到 Flutter/app composition。
- runner 和 native test target 显式启用 C++17 与 MSVC `/utf-8`；notification STA、pipe IO thread 与 runner UI thread 的 ownership 写成类级中文 doc；所有 COM/WinRT/pipe callback 最外层 catch-all，日志只写固定 stage/token。
- `windows/runner/CMakeLists.txt` 显式链接 Task 6B 已验证的最小 Windows SDK libraries（预计包含 Toast/WinRT、shell property store、HKCU 与 COM 所需的 `runtimeobject`/`windowsapp`、`shell32`、`propsys`、`advapi32`、`ole32`、`oleaut32`、`uuid`；以 spike 实际 link set 为准）。不得照抄官方 sample 中与本实现无关的 ODBC/GDI 库，也不得靠机器隐式 linker state。
- `scripts/test-windows-notification-host.ps1` 负责构建并运行原生 test executable，非零立即退出；不得引入 gtest 或另一个测试框架。
- 运行 Dart client 单测并写 `logs/windows-notification-host-client-green.log`，工具超时 60000ms。
- 运行原生测试与 Windows build：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
.\scripts\test-windows-notification-host.ps1 2>&1 | Out-File -Encoding utf8 logs/windows-notification-host-native-green.log; $NativeExit = $LASTEXITCODE; Write-Host "EXIT=$NativeExit"; Get-Content -Tail 150 logs/windows-notification-host-native-green.log
flutter build windows 2>&1 | Out-File -Encoding utf8 logs/build-windows-notification-host.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows-notification-host.log
```

两个命令级硬超时各 600000ms。

**产品注册回读**

- 启动当前 build 一次，通过 host status 回读 `available=true` 与固定 failureStage 为空。
- 用 Windows 属性存储 API 回读 `Oh My LLM.lnk` target/AUMID/`VT_CLSID`，再回读 LocalServer32 default 与 `ServerExecutable`；记录匹配结果，不把绝对路径提交到文档。
- 覆盖同目录 exe 后重新启动，确认 primary 幂等修复；移动目录后先完全退出旧 primary，再手工启动新目录并确认修复。
- 本 Task 已能用 runner channel 显示固定测试 Toast 与取得 native activation，但尚未接 terminal/domain adapter；不得把固定测试 payload 冒充端到端会话导航验收。

**硬停止条件**

- native tests、build 或产品回读证明模式隔离、注册、COM/pipe queue、Toast show 或 shutdown 链不成立。
- relay/manual secondary 的任一路径能够构造 Flutter engine/窗口/存储。
- 必须把 HWND、runner 对象或原始 HRESULT/异常暴露给 Dart 才能实现。
- 可靠实现必须引入第三方插件、MSIX、安装器或管理员权限。

发生硬停止时不继续 Task 8–11；保留 Task 6B 与 native 日志，不降级成“只支持应用运行时 Toast”。

