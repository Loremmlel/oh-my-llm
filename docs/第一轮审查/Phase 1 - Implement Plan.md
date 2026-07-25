# Phase 1 - 可信工程基线 Implement Plan

> 本 Plan 基于 `Phase 1 - 可信工程基线.md` 细化，不改变 Phase 的结论或技术选型。
> 遵守 Refactor Scope / Out Of Scope / Phase 依赖，不提前实现其他 Phase。

## 一、现状验证结论（已实测）

| 验证项 | 命令 | 结果 | 判定 |
|---|---|---|---|
| 静态分析 | `flutter analyze` | `No issues found!` EXIT=0 | 干净，符合 Phase 既定事实 |
| 全量测试 | `flutter test --reporter compact`（重定向） | `All tests passed!` EXIT=0，1262 用例 | 4 个历史失败已修复，TD-32 稳定性确认 |
| 媒体路径测试 | 单文件 + 全量并发 | 通过 | 已用 `resolveSymbolicLinksSync().toLowerCase()` 归一化，跨 Windows 短名/长名稳定 |
| UDP 测试 | 单文件 + 全量并发 | 通过 | 已打 `@Tags(['udp'])`，停止广播用例已过滤并发源噪声（只断言 `Gone-PC`） |
| format | `dart format --set-exit-if-changed lib test` | EXIT=1，大量文件 Changed | **未格式化**，启用 format 门禁前必须先全量格式化 |
| CI | `.github/workflows/` | 不存在 | TD-36 从零建立 |
| coverage | `coverage/lcov.info` | 过期快照 | `.gitignore` 已忽略 `/coverage/`，不入库；CI 生成新产物 |
| 分层结构 | find | application:37 / data:36 / domain:35 / presentation:110 | coverage 过滤模式清晰 |

**关键事实**：`dart format` 80 与 120 行宽均报 Changed，差异是真实格式问题（如多行 `Stack(children:[...])` 应折叠为单行），非行宽/行尾配置问题。这是启用 format 门禁的前置阻塞项。

**生产文件结论**：`media_directory_scanner.dart` 与 `sync_udp_discovery.dart` 实现健壮（符号链接二次校验、MulticastLock 生命周期、资源清理可观察），测试已稳定，**不进入修改范围**（符合 File Scope "仅当测试揭示真实缺口时"的限定）。

## 二、关键实现决策（不改变 Phase 结论）

1. **CI runner = ubuntu-latest**。测试是 Dart 层，媒体扫描测试已用 `Platform.pathSeparator` 适配，Linux 上路径为 `/tmp/...`、分隔符 `/`，断言用 `resolveSymbolicLinksSync` 归一化，跨平台稳定。成本低、反馈快。
2. **CI 测试集排除 UDP**：`flutter test --exclude-tags=udp --coverage`。UDP 测试文件自身注释明确"CI/虚拟化环境可能不可用"，Phase Risks 也点名"CI 网络权限差异"。UDP 的稳定性由本地 Windows 验证覆盖（对应 Verification Requirements 第一条"对应平台 + 全量并发上下文"）。CI 的"全量 test"语境 = 可靠集。
3. **format 前置全量格式化**。项目从未跑过 `dart format`，必须先 `dart format lib test` 建立格式基线，CI format 门禁才有效。这是建立门禁的前提，属 Refactor Scope；不属于 Out Of Scope 的"pumpAndSettle/Key/真实时间清理"（那是 Phase 15）。
4. **coverage 聚焦 application/data**。用 `lcov --remove` 剔除 `presentation/**`（行为清单验证，不追覆盖率）与 `domain/**`（Equatable/getter 噪声），保留 `application/**`+`data/**`，生成 HTML 与摘要。初始门禁阈值设为 `COVERAGE_MIN=0`（不阻塞现状），首次 CI 产出基线后上调为基线值防回退。变更行用 `diff-cover` 出报告（非阻塞），避免"单一总百分比替代关键路径判断"。
5. **固定 Flutter 版本 = 3.44.6 stable**（当前开发版本，满足 pubspec `^3.11.5`）。
6. **`.gitattributes` 规范行尾为 LF**（可选但推荐）。当前 `core.autocrlf=true`，跨平台贡献易混入 CRLF 导致 CI format 假失败。服务于"跨环境测试稳定性"（TD-32 精神）。

## 三、文件修改清单

### 新增
- **`.github/workflows/ci.yml`**：CI 主流水线。
- **`scripts/coverage-report.sh`**：coverage 过滤 + 报告（bash，CI 与本地 Git Bash 复用）。
- **`.gitattributes`**：行尾规范（`* text=auto eol=lf`，`*.dart/*.yaml/*.md/*.json` 强制 LF）。

### 修改
- **大量 `lib/**/*.dart` 与 `test/**/*.dart`**：仅由 `dart format` 产生的格式改动，零逻辑变更。
- **`fltest.log` / `analyze.log`**：本地验证产物，已在 `.gitignore`（`*.log`），不入库。

### 不修改
- `dart_test.yaml`：当前 `concurrency:4 / timeout:120s / tags.udp:` 已满足需求，CI 通过命令行 `--exclude-tags=udp` 排除，无需改配置。
- `analysis_options.yaml`：`flutter_lints` 默认配置，analyze 已干净，无需改。
- `pubspec.yaml`：`flutter test --coverage` 内置 coverage，无需加依赖。
- `media_directory_scanner.dart` / `sync_udp_discovery.dart`：测试已稳定，无契约缺口。

## 四、`ci.yml` 关键结构

```yaml
name: ci
on:
  push:
    branches: [master]
  pull_request:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  gate:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.6'
          channel: stable
          cache: true
      - run: flutter pub get
      # 1) format 门禁
      - run: dart format --set-exit-if-changed lib test
      # 2) analyze 门禁
      - run: flutter analyze
      # 3) test 门禁（排除 UDP，重定向完整日志）
      - name: test
        run: |
          flutter test --exclude-tags=udp --coverage --reporter compact > fltest.log 2>&1
          echo "EXIT=$?" >> fltest.log
          tail -n 150 fltest.log
          grep -q "EXIT=0" fltest.log
      - name: upload test log
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-log
          path: fltest.log
      # 4) coverage 过滤与报告
      - name: coverage report
        if: always()
        run: bash scripts/coverage-report.sh
      - name: upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: |
            coverage/lcov.info
            coverage/lcov.filtered.info
            coverage/html/
            coverage/diff-report.html
```

## 五、`scripts/coverage-report.sh` 关键逻辑

```bash
#!/usr/bin/env bash
# 聚焦 application/data 覆盖率，剔除 presentation（行为清单）与 domain（model getter 噪声）
set -euo pipefail
sudo apt-get install -y lcov >/dev/null 2>&1 || true

# 过滤：保留 application + data，剔除 presentation/domain
lcov --remove coverage/lcov.info \
  'lib/features/*/presentation/*' \
  'lib/features/*/domain/*' \
  -o coverage/lcov.filtered.info

genhtml coverage/lcov.filtered.info -o coverage/html

# 摘要输出（CI 日志可见，非单一总%）
lcov --summary coverage/lcov.filtered.info 2>&1 | tee coverage/summary.txt

# 变更行报告（非阻塞，仅信息性，PR 时对比 origin/master）
pip install diff-cover --quiet 2>/dev/null || true
diff-cover coverage/lcov.info --compare-branch origin/master \
  --html-report coverage/diff-report.html 2>/dev/null || true
```

> 门禁阈值：初始不设硬门禁（`COVERAGE_MIN` 概念保留，值为 0）。首次 CI 运行产出 application/data 基线后，在后续小提交里把基线写入 workflow env 作为防回退线。这样既"定义了保护目标"，又规避 Risks"初始门槛阻塞合理重构"。

## 六、测试策略

### 本地验证（对应 Verification Requirements 第一、三条）
- 全量：`flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log` -> 期望 `EXIT=0`（含 UDP）。
- 媒体单文件：`flutter test test/features/media/data/media_directory_scanner_test.dart` -> 通过。
- UDP 单文件：`flutter test test/features/sync/data/sync_udp_discovery_test.dart` -> 通过。
- format：`dart format --set-exit-if-changed lib test` -> EXIT=0。
- analyze：`flutter analyze` -> No issues found。

### CI 验证（对应 Verification Requirements 第四、五条）
- push 到 master / PR 触发，ubuntu 上跑 format check + analyze + `--exclude-tags=udp` 全量 test。
- 失败时上传 `fltest.log` 完整日志（不因终端截断丢失）。
- coverage artifact 含 `lcov.info`（全量）+ `lcov.filtered.info`（application/data 聚焦）+ `html/` + `diff-report.html`。
- **"对 CI 配置本身完成一次成功运行验证"**：需 push 后观察 GitHub Actions 首次运行全绿。若 media scanner 在 Linux 暴露路径差异（当前测试已用 `Platform.pathSeparator` 适配，预期稳定），则在 Phase 1 范围内修复（属 TD-32 跨环境稳定性）。

## 七、实施顺序与独立提交节点

> 全部在 Bash 执行 `git commit`（CLAUDE.md/AGENTS.md 均要求，避免 PowerShell here-string）。版本 bump 由仓库 hook 按 `style/chore/ci` 前缀自动 patch+1。

### Commit 1 - `style: 全量 dart format 建立格式基线`
- 执行 `dart format lib test`。
- 验证：`flutter analyze` 仍 EXIT=0；全量测试仍 EXIT=0（format 不改逻辑）。
- 提交：仅格式变更，零逻辑改动。pre-commit 会因 >500 行提醒但不阻塞。

### Commit 2 - `chore: 新增 .gitattributes 规范跨平台行尾`
- 新增 `.gitattributes`（LF 规范）。
- 执行 `git add --renormalize .` 归一化已跟踪文件（Commit 1 后文件已 LF，预期无额外差异）。
- 验证：`git status` 干净，`dart format --set-exit-if-changed` 仍 EXIT=0。

### Commit 3 - `ci: 新增 GitHub Actions format/analyze/test 门禁`
- 新增 `.github/workflows/ci.yml`（不含 coverage step，或 coverage step 占位）。
- 验证：本地 `act` 干跑不可行（项目无 act 依赖），靠 Commit 4 后首次 push 统一验证。
- **此提交后 push 触发首次 CI 运行**，观察 format/analyze/test 三门禁全绿。

### Commit 4 - `ci: 新增 coverage 聚焦报告与 application/data 基线`
- 新增 `scripts/coverage-report.sh`，ci.yml 接入 coverage step + artifact 上传。
- 验证：CI 产出 coverage artifact，`lcov.filtered.info` 仅含 application/data，HTML 可读，`diff-report.html` 存在。
- 记录首次 application/data 覆盖率基线值（写入 commit body 或 PR 描述），作为后续防回退线依据。

> 每个提交独立可 review、可回滚。Commit 1/2 纯工程基线，Commit 3/4 是 CI 门禁主体。若 CI 首次运行暴露跨环境问题，修复作为 Commit 3 的 amend 或新增 `fix(test):` 提交（视改动性质）。

## 八、验证清单（对照 Verification Requirements）

- [x] `flutter analyze` 必须通过 -> CI step 2 + 本地已验证 EXIT=0。
- [x] 全量测试用重定向命令得 EXIT=0 -> 本地已验证（含 UDP）；CI 用同模式重定向排除 UDP 得 EXIT=0。
- [x] 媒体扫描与 UDP 单文件在对应平台 + 全量并发均通过 -> 本地已验证。
- [x] CI 执行 format check / analyze / 全量 test，上传完整日志 + coverage 产物 -> ci.yml 设计覆盖。
- [ ] 对 CI 配置本身完成一次成功运行验证 -> 待 push 后观察（plan 阶段无法本地完成）。

## 九、风险与缓解

| 风险 | 缓解 |
|---|---|
| CI 网络差异暴露 UDP 非确定性 | CI `--exclude-tags=udp`，UDP 由本地 Windows 验证 |
| media scanner 在 Linux 路径差异失败 | 测试已用 `Platform.pathSeparator`+`resolveSymbolicLinksSync` 适配，预期稳定；若失败属 TD-32，本 Phase 范围内修 |
| 初始 coverage 门槛阻塞重构 | `COVERAGE_MIN` 初始为 0，首次基线后再设防回退线，且只看 application/data 不看总% |
| format 全量大 diff 淹没 review | 单独 Commit 1，message 明确"格式基线，无逻辑变更" |
| 行尾混入致 CI format 假失败 | `.gitattributes` + `git add --renormalize` |
| 未重定向致失败摘要丢失 | ci.yml 用 `> fltest.log 2>&1` + artifact 上传 |

## 十、Out Of Scope 确认

- 不修复与 TD-32 无关的产品行为/测试失败。
- 不建 Windows/Android 设备 E2E 或 release 构建（Phase 16）。
- 不清理 `pumpAndSettle`/内部 Key/真实时间等待（Phase 15）。
- 不改 Flutter/Riverpod/sqlite3/http/go_router 选型。
- 不改业务架构、生产功能、发布签名。
- 不碰 AGENTS.md 与 CLAUDE.md 的版本号 hook 描述差异（commit-msg vs post-commit），那是 Phase 2 仓库事实源范畴。
