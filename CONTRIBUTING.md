# 开发与交付

## 环境与常用命令

仓库示例使用 PowerShell 7。Windows 用 `pwsh.exe`，其他系统用 `pwsh`；Claude Code 可启用原生 PowerShell tool（`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`）。SDK 版本以 [CI](.github/workflows/ci.yml) 和 [pubspec.yaml](pubspec.yaml) 为准，Windows 构建需要 Visual Studio 2022 的 C++ 桌面开发工作负载，Android 构建需要 Android SDK、JDK / `keytool`。

```powershell
flutter pub get
New-Item -ItemType Directory -Force logs | Out-Null
flutter analyze *> logs/analyze.log
$AnalyzeExit = $LASTEXITCODE; Get-Content -Tail 80 logs/analyze.log; Write-Host "EXIT=$AnalyzeExit"
dart run tool/check_import_boundaries.dart *> logs/import-boundaries.log
$BoundaryExit = $LASTEXITCODE; Get-Content -Tail 80 logs/import-boundaries.log; Write-Host "EXIT=$BoundaryExit"
flutter run -d windows
```

升级 Flutter 后先 `flutter clean` 再测试，避免旧 shader 缓存造成 Asset manifest 假失败。

## 测试执行与日志

测试约定见 [test/AGENTS.md](test/AGENTS.md)。全量测试使用 `flutter test --reporter compact`；单文件追加文件路径，单用例再追加 `--plain-name "用例名称"`。并发与 per-test timeout 以 [dart_test.yaml](dart_test.yaml) 为准。

所有测试（包括单文件）都必须重定向到日志并保留退出码，例如：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log
$TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

执行上述命令还必须有进程级硬超时：单文件 60 秒、全量 240 秒，到点杀整棵子进程树。使用工具的硬超时能力，或 PowerShell 7 的 `Process.WaitForExit` / `Kill(true)`；工具仅返回 session ID 或后台运行不等于设置了超时。per-test timeout 不覆盖编译、启动、setup/teardown、DLL 锁或进程退出阶段，不得用无超时后台任务等待同步测试结果。

- `EXIT=0` 才表示通过；非零时查看完整日志，不能只凭 tail 判断失败原因。详情用 `Select-String -Pattern "关键词" -Path logs/fltest.log -Context 0,30`。
- 不直接输出全量测试或使用 `tee`。测试、分析、构建和诊断日志统一放在 ignored 的 `logs/`；全量测试用 `logs/fltest.log`，回归证据用 `logs/<任务>-red.log` / `logs/<任务>-green.log`。
- 超时或测试启动卡住时，先排查残留 Dart / `flutter_tester` 对 `build/native_assets/windows/sqlite3.dll` 的锁；确认是本仓库残留进程后运行 `.\scripts\kill-stale-test-processes.ps1`，再诊断重跑。该脚本是异常退出后的缓解措施，会结束非 IDE 的 Dart 测试进程，不在正常测试前例行运行。
- `logs/` 可覆盖或清理。CI runner 的根目录 `fltest.log` 上传流程和应用 AppData 的 `network.log` 不受本地日志规则影响。

## 构建与版本

| 命令 | 结果 |
| --- | --- |
| `.\build-windows-release.ps1` | `artifacts/windows/oh_my_llm-windows-{version}.zip` |
| `.\build-android-apk.ps1` | APK 写入 `artifacts/android/`；首次自动生成 `android/app/self-use-release.jks` |
| `.\scripts\bump-version.ps1 -Minor` / `-Major` | 手动升 minor / major |

脚本日志分别写入 `logs/build-windows.log`、`logs/build-android.log`；直接执行 `flutter build windows --release` / `flutter build apk --release` 时同样落盘日志。产物前缀固定为 `oh_my_llm-{platform}-{version}`，版本从 `pubspec.yaml` 读取；品牌与持久化身份约束见 [AGENTS.md](AGENTS.md)。

安装 hooks：`git config core.hooksPath .githooks`。日常版本由 [post-commit](.githooks/post-commit) 根据 commit 第一行自动 bump 并 amend 回本次提交：

| 前缀 | 版本变化 |
| --- | --- |
| `type!:` / `type(scope)!:` | major + 1，minor / patch 归零 |
| `feat:` / `feat(scope):` | minor + 1，patch 归零 |
| 其他（fix / docs / refactor / test / chore 等） | patch + 1 |

hook 对已 bump 的 amend 幂等，跳过 merge / rebase / cherry-pick，以 `OMLL_BUMPING` 防递归；必要时可设置 `$env:OMLL_SKIP_BUMP = '1'` 跳过一次提交，之后移除该变量。`pre-commit` 仅提醒大改动，不管理版本。hook 的实现背景和边界以脚本为准，不要另建版本流程。

## 提交与 Pull Request

使用根 [AGENTS.md](AGENTS.md) 规定的新分支与中文 Conventional Commit。在 PowerShell 中直接提交，常规多段消息用多个 `-m`：

```powershell
git commit -m "fix(chat): 修复具体行为" -m "说明触发条件与修复结果"
```

复杂消息可先存入 PowerShell here-string 变量，再传给 `git commit -m $Message`；不要把 here-string 交给 Bash 解释。

每次提交前，对本次所有改动的 Dart 文件执行 `dart format`；暂存后以 `dart format --output=none --set-exit-if-changed <暂存的 Dart 文件列表>` 再检查，非零不得提交。通过静态分析、导入门禁及相关测试；纯文档变更只需检查 diff、链接和文档一致性，并如实说明免测原因。提交后检查最终 HEAD、变更文件与工作区，确保 hook 的版本变化已并入。

PR 保持单一目标、规模可审查，正文使用 [三段模板](.github/pull_request_template.md)：为什么改、改了什么、改后效果。简短变更每段一句即可，不复制 commit 列表。标题为 `type(scope): 简短结果`，scope 可省略，不以句号结尾，前缀与分支及核心提交语义一致。

- 只记录当前 PR head 已实现的行为，改后效果中写实际验证命令和结果；手工验收注明平台、设备与操作。未执行项及影响判断的兼容性、数据、安全或性能风险也在此说明，不要求额外章节或空泛的“无”。新增 commit 改变范围或证据时同步正文。
- 提请审查前自审完整 `base...head` diff，排除意外文件、调试代码、敏感信息和无关变更，确认正文与 diff 一致。
- 正文存为可回读的 UTF-8 Markdown 文件（本地临时文件可放 `logs/`），使用 `gh pr create --body-file <path>`，不要手工拼接 PowerShell 多行 `--body`。
- 创建后用 `gh pr view --json title,body,baseRefName,headRefName,isDraft,url` 回读；尚未准备好接受人工审查时用 draft，验证和正文齐备后再标记 Ready for review。发布后如实报告实际存在的 CI 检查状态。
- 审查意见先核对需求、代码与可复现证据；成立则修改并回归验证，不成立则说明证据，处理完再 resolve。每条意见保留可追踪结果，超出范围的建议不要顺手扩大当前 PR。
