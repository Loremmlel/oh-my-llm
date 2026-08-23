# Task 6B 评审包（runner-owned spike 搭台）

## 评审范围说明

本 task 无 git diff：spike 是仓库外 throwaway 工程（未提交任何 commit），产品仓库内唯一改动是未跟踪 smoke 文档的文末追加章节。因此「diff」= 下列新文件全集，直接 Read 即为评审对象。

- spike 工程：`E:\Code\omll-runner-spike`
- smoke 文档新章节：`E:\Code\oh-my-llm\docs\testing\windows-chat-generation-notifications-smoke.md` 第 393–520 行（「第三部分：runner-owned spike（Task 6B）」）；第 1–392 行是既有内容（Task 6A 插件 FAIL 现场 + 产品最小 gate），实现者声称原样未动——无 git 基线可 diff，若发现结构异常按 ⚠️ 报告。
- 实现者报告：`E:\Code\oh-my-llm\.superpowers\sdd\2026-08-22-cross-platform-generation-terminal-notifications\task-6B-report.md`
- 用户验收指南（同为交付物，一并评审）：同目录 `task-6B-user-guide.md`

## 评审面（Read 这些文件；build/、variants/、.dart_tool/、.idea/ 为产物，不属评审面）

原生源码（windows/runner/）：
- spike_identity.h（72 行）— 身份常量集中处
- spike_runtime.cpp/.h（682/53）— 进程模式决策、instance/activator mutex、ready event、生命周期编排
- spike_com.cpp/.h（556/79）— INotificationActivationCallback、IClassFactory、notification STA thread
- spike_pipe.cpp/.h（251/61）— pipe server/client
- spike_protocol.cpp/.h（126/72）— OMLN/OMLA 帧编解码与校验
- spike_registration.cpp/.h（358/33）— shortcut/HKCU 注册与回读
- spike_text.cpp/.h（133/29）— UTF-16→UTF-8、XML escaping 等文本工具
- spike_evidence.cpp/.h（118/27）— 结构化证据日志
- main.cpp（57）、flutter_window.cpp/.h（162/37）— 入口顺序与 messenger attach
- win32_window.cpp/.h、utils.cpp/.h、Runner.rc、CMakeLists.txt — Flutter 模板 + 变体开关

Dart UI：
- lib/main.dart — mode/host 状态/payload 列表显示 + 测试 Toast 按钮

脚本与证据：
- scripts/build-variants.ps1、selfcheck-variants.ps1、selfcheck-relay.ps1、summarize-evidence.ps1、verify-registration.ps1、cleanup-spike.ps1（工程根）
- evidence/*.log（11 份，按进程分文件）— 对照报告的自检声明抽查

## 实现者报告的关键声明（对照源码与证据核实，勿轻信）

- 三变体构建 EXIT=0 且 exe 哈希互异；delay 由 CMake compile definition 注入。
- normal 版全链路 com_register/toast_show/com_revoke hr=0、exit 0；注册回读 8 项 MATCH。
- selftest 12+1 case 全 PASS：1024B 接受；1025B/坏帧/未知 version/kind 拒收；第 33 帧 queueFull。
- pre-COM 窗口 relay 短命 owner 全生命周期自动验证：lease 串行、无双注册、15s 有界退出、primary 7.5s 接棒。
- pipe ACK p50=0ms/max=110ms；注册→ready 44–52ms；11 份 evidence 全有 process_exit。
- cleanup-spike.ps1 -ReportOnly 4 项身份断言全过。
- 身份：CLSID {9E60E9C6-0CD2-4727-A762-A18DD8079E80} / AUMID YuzuShiki.OmllRunnerSpike；relayDrainGrace=1000ms、relayMaxLifetime=15000ms。

## 已知未覆盖（不属本评审判 FAIL，控制器已裁决）

- 真实 SCM 拉起路径（RPCSS 因真实 Toast 点击启动 -Embedding relay）无法自动触发，属用户人工验收 case C/D 的核心目的。
- relay handoff p50/max 真实数据待 case C 点击后由 summarize-evidence.ps1 计算。
- 快速连点双 relay、primary 崩溃残留（WAIT_ABANDONED）按用户精简裁决为顺手观察项/PENDING。
- SetForegroundWindow 前台锁限制为产品 Task 8 关注点。
