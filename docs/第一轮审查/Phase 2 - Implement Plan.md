# Phase 2 - 仓库与版本事实源 Implement Plan

> 本 Plan 基于 `Phase 2 - 仓库与版本事实源.md` 细化，不改变 Phase 的结论或技术选型。
> 遵守 Refactor Scope / Out Of Scope / Phase 依赖，不提前实现其他 Phase。
> 所有现状结论已对当前工作树实测（git status clean，无未提交改动）。

## 一、现状验证结论（已实测）

### 1.1 TD-17 - 仓库噪声与陈旧元数据

| 验证项 | 命令 | 结果 | 判定 |
|---|---|---|---|
| 异常诊断文件 | `git ls-files` | 跟踪中：`E：Codeoh-my-llm.gitfull_diff.txt`（文件名含私用区字符 U+F03A） | TD-17 点名目标，需删除 |
| 诊断文件性质 | `git cat-file blob <sha>` | 64KB，内容为 `warning: ... LF will be replaced by CRLF` 的 `git diff` 输出 | 确认是误提交诊断产物，误加于 `c4010b0`（F9 重构） |
| `.claude/settings.local.json` | `git ls-files .claude/` | 空（未跟踪） | **已自然消解**，见下文事实差异 |
| `.claude/` 忽略规则 | `git check-ignore -v .claude/settings.local.json` | `.gitignore:55:.claude/` 已覆盖 | ignore 已就位 |
| `.claude/` 删除史 | `git log --diff-filter=D -- '.claude/*'` | `c782d17 docs: 新增架构重构文档` 已删除跟踪 | 审查后已清理 |
| README 测试数字 | `Read README.md` | 第 268 行 `1016 个测试`、第 280 行 `共 1016 个测试（99 个测试文件）` | 陈旧（Phase 1 实测 1262） |
| AGENTS/CLAUDE 测试数字 | `Read` | 第 27 行 `全量测试 400+ 用例` | 陈旧 |
| pubspec description | `Read pubspec.yaml` | 第 2 行 `description: "A new Flutter project."` | Flutter 默认占位符，陈旧 |

**事实差异说明（非 Phase 内部矛盾）**：Phase 2 文档 File Scope 称"仓库跟踪了 `.claude/settings.local.json`"，但该文件已在历史提交 `c782d17` 中移除跟踪，且 `.gitignore:55` 的 `.claude/` 规则已覆盖。这是 Phase 文档基于审查快照、而仓库已在审查后自然消解该项--不构成 Phase 文档内部矛盾或关键事实缺失，无需回查 Review Report。本 Plan 对该项**不做重复变更**，仅在验收清单中确认 ignore 规则覆盖。

### 1.2 TD-38 - 版本事实源冲突

实际版本机制（**唯一真相源**）：`.githooks/post-commit` 按 commit message 第一行语义 bump `pubspec.yaml` 版本号，用 `git commit --amend --no-edit --no-verify` 并回本次提交。`pre-commit` 仅做 >500 行大改动提醒，不碰版本号。`.githooks/` 下**仅存在** `pre-commit` 与 `post-commit`，**无 `commit-msg` hook**。

| 文件 | 当前描述 | 实际机制 | 判定 |
|---|---|---|---|
| `.githooks/post-commit` | post-commit + amend（含防递归/幂等/逃生舱/cherry-pick/rebase/merge 跳过） | ✓ | **真相源，不改逻辑** |
| `.githooks/pre-commit` 第 2 行注释 | `版本号自动更新已移至 commit-msg hook` | post-commit | ✗ 冲突，改注释 |
| `scripts/bump-version.ps1` 第 12 行注释 | `日常自动递增由 git pre-commit 钩子负责` | post-commit | ✗ 冲突（且与 pre-commit 注释互相矛盾），改注释 |
| `AGENTS.md` 第 44/52/54/56 行 | `commit-msg hook`，描述 commit-msg 通过 `$1` 接收消息文件、`git add` 随本次提交写入 | post-commit + amend | ✗ 冲突，且缺 CLAUDE.md 已有的行为细节，统一对齐 |
| `CLAUDE.md` 第 44/52/54/56 行 | post-commit + amend，含「为什么不是 commit-msg」+ 5 点行为细节 | ✓ | 真相源镜像，不改版本描述 |
| hook/version 契约测试 | `Grep test/` | 14 文件命中均为业务 `version` 字样，无 hook 契约测试 | 需新增验证脚本 |

**冲突拓扑**：三份文档/脚本对"版本由谁 bump"给出三种互斥答案（commit-msg / pre-commit / post-commit），且 `pre-commit` 注释声称的 `commit-msg` hook 在 `.githooks/` 下根本不存在。唯一正确的是 `post-commit` 自身与 `CLAUDE.md`。统一方向：以 `post-commit` 实际行为为单一事实源，将 `AGENTS.md` / `pre-commit` 注释 / `bump-version.ps1` 注释对齐。

### 1.3 当前版本与基础门禁

| 项 | 结果 |
|---|---|
| 当前版本 | `version: 3.17.15+0` |
| `flutter analyze` | EXIT=0（Phase 1 基线） |
| CI 门禁 | Phase 1 已建立 `.github/workflows/ci.yml`（format/analyze/test/coverage），本 Phase 在其上新增 hook 契约验证 step |

## 二、关键实现决策（不改变 Phase 结论）

1. **不重复处理已消解项**。`.claude/settings.local.json` 已在 `c782d17` 移除跟踪且被 `.gitignore:55` `.claude/` 覆盖，本 Plan 仅在验收清单确认，不做变更。符合 Risks「精确确认目标，避免影响用户未提交内容」。
2. **异常诊断文件用 git pathspec 通配删除**。文件名含私用区字符 U+F03A，手打易错，统一用 `git rm -- '*gitfull_diff*'`（git pathspec glob 匹配，引号阻止 shell 展开）。该文件名是一次性 shell 路径解析错误产物，无合理通配模式可预防，**不新增**针对性 ignore 规则（避免过期规则噪声）；现有 `*.log` / `.claude/` / `/artifacts/` 已覆盖常规诊断产物。
3. **统一方向 = 向 post-commit 真相对齐，不改 hook 逻辑**。`post-commit` 实现健壮（防递归 `OMLL_BUMPING`、幂等对比第一 parent、cherry-pick/rebase/merge 跳过、amend 失败告警、逃生舱 `OMLL_SKIP_BUMP`），**不进入逻辑修改范围**。仅改文档与脚本注释的**陈述**，让三处错误描述（commit-msg / pre-commit）与 `post-commit` / `CLAUDE.md` 一致。`CLAUDE.md` 已是正确真相源镜像，不改其版本描述。
4. **AGENTS.md 行为细节向 CLAUDE.md 镜像**。`AGENTS.md` 缺「行为细节」段，补齐 CLAUDE.md 已有 5 点（读 `HEAD:pubspec.yaml` + amend、幂等、merge 跳过、逃生舱、`OMLL_BUMPING` 防递归）。cherry-pick/rebase 跳过细节留在 `post-commit` 源码注释（文档是协作指南非源码注释，行为细节已覆盖关键边界）。
5. **陈旧测试数字改为不易过期描述**。写死数字（1016 / 99 / 400+）随开发必然过期，改为「用例数随开发增长，详见各模块目录」式表述，符合 Refactor Scope「改为不易过期的项目描述、测试数字」。
6. **pubspec description 改为准确描述**。`"A new Flutter project."` 是 Flutter 模板占位符，改为与 README/CLAUDE.md 一致的项目一句话。改 description 不影响 `post-commit` 的 `sed 's/^version: .*/...'`（只匹配 `version:` 行）。
7. **新增 `scripts/verify-version-hook.sh` 契约脚本 + 接入 Phase 1 CI**。Verification Requirements 第四条要求「用隔离仓库或等效测试验证 fix/feat/breaking 类型版本行为，不污染当前工作树历史」。脚本在 `mktemp -d` 临时仓库跑 `post-commit`，验证 feat/minor、fix/patch、breaking/major、幂等、逃生舱。接入 ci.yml 是 Phase 2 Dependencies「版本机制与 CI 的最终关系应建立在已有门禁之上」的落地--File Scope 第三条「针对 hook/版本契约的测试或校验脚本」授权脚本，Dependencies 授权在 Phase 1 ci.yml 上新增 step。
8. **脚本 POSIX sh + 跨平台**。CI runner = ubuntu-latest（Phase 1 决策），本地 Git Bash 也能跑。仅用 `git` / `mktemp` / `cp` / `chmod` / `grep` / `awk`，无平台专属依赖。

## 三、文件修改清单

### 新增
- **`scripts/verify-version-hook.sh`**：隔离临时仓库验证 `post-commit` bump 契约。

### 修改
- **`AGENTS.md`**：第 44 行「commit-msg hook」→「post-commit hook」；第 52 行标题；第 54-56 行版本机制描述改为 post-commit + amend，补「为什么不是 commit-msg」与 5 点行为细节，与 CLAUDE.md 镜像。
- **`.githooks/pre-commit`**：第 2 行注释「版本号自动更新已移至 commit-msg hook」→「版本号自动更新由 post-commit hook 负责」。
- **`scripts/bump-version.ps1`**：第 12 行注释「由 git pre-commit 钩子（.githooks/pre-commit）负责」→「由 git post-commit 钩子（.githooks/post-commit）负责」。
- **`README.md`**：第 268 行「1016 个测试」、第 280 行「共 1016 个测试（99 个测试文件）」改为不易过期描述。
- **`AGENTS.md` / `CLAUDE.md`**：第 27 行「全量测试 400+ 用例」改为不易过期描述。
- **`pubspec.yaml`**：第 2 行 `description` 改为准确项目描述。
- **`.github/workflows/ci.yml`**：新增 `verify version hook` step（analyze 之后、test 之前，快速失败）。

### 删除
- **`E：Codeoh-my-llm.gitfull_diff.txt`**（git 跟踪的诊断产物，64KB CRLF 警告输出）。

### 不修改
- **`.githooks/post-commit`**：真相源，逻辑健壮，不进入修改范围。
- **`.gitignore`**：现有 `.claude/` / `*.log` / `/artifacts/` 已覆盖常规诊断产物；异常文件名无合理通配模式，不新增过期规则。
- **`CLAUDE.md` 版本描述**：已是正确真相源镜像，不改版本章节（仅第 27 行测试数字随 AGENTS.md 一并清理）。
- **`.githooks/commit-msg`**：不存在，不创建（Out Of Scope「不以个人偏好更换 Conventional Commits 语义」，且 post-commit 已是既定机制）。
- **Conventional Commits 前缀语义表**：type!/feat/其他 三类 bump 规则不变。
- **构建脚本 `build-windows-release.ps1` / `build-android-apk.ps1`**：仅从 `pubspec.yaml` 读版本号，不涉及 bump 机制描述，无需改。

## 四、`scripts/verify-version-hook.sh` 关键逻辑

```sh
#!/usr/bin/env bash
# verify-version-hook.sh: 在隔离临时仓库验证 post-commit 版本 bump 契约。
# 不污染当前工作树历史。CI（ubuntu）与本地 Git Bash 复用。
# 对应 Phase 2 Verification Requirements 第四条。
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/.githooks/post-commit"
[ -f "$HOOK" ] || { echo "post-commit hook 不存在: $HOOK" >&2; exit 1; }

# ── 1. 隔离临时仓库 ────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q
git config user.email "verify@local.test"
git config user.name "verify"
git config core.hooksPath .githooks
mkdir -p .githooks
cp "$HOOK" .githooks/post-commit
chmod +x .githooks/post-commit

assert_version() {
  local expect="$1" got
  got="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
  if [ "$got" != "$expect" ]; then
    echo "FAIL: 期望 $expect，实际 $got" >&2
    exit 1
  fi
}

# ── 2. 初始 pubspec（首提交 -> patch bump）──────────────────────
printf 'version: 1.0.0+0\n' > pubspec.yaml
git add pubspec.yaml
git commit -q -m "chore: init"          # 其他 -> patch+1
# 首提交无 parent，幂等检查跳过，直接 bump：1.0.0 -> 1.0.1
assert_version "1.0.1+0"

# ── 3. feat -> minor ───────────────────────────────────────────
git commit -q --allow-empty -m "feat: add feature x"
assert_version "1.1.0+0"

# ── 4. fix -> patch ─────────────────────────────────────────────
git commit -q --allow-empty -m "fix: patch something"
assert_version "1.1.1+0"

# ── 5. breaking -> major ────────────────────────────────────────
git commit -q --allow-empty -m "feat!: breaking change"
assert_version "2.0.0+0"

# ── 6. 幂等：amend 不改 message 不重复 bump ─────────────────────
git commit -q --amend --no-edit
assert_version "2.0.0+0"

# ── 7. 逃生舱：OMLL_SKIP_BUMP=1 跳过 bump ───────────────────────
OMLL_SKIP_BUMP=1 git commit -q --allow-empty -m "fix: should not bump"
assert_version "2.0.0+0"

echo "PASS: post-commit 版本 bump 契约验证通过（feat/fix/breaking/幂等/逃生舱）"
```

**幂等验证原理**：`git commit --amend --no-edit` 产生新 commit C'（同 message「feat!: breaking change」，parent 仍是 fix 提交 B，版本 1.1.1）。post-commit 计算 `compute_bumped("1.1.1", "feat!: breaking change")` = major → 2.0.0，与当前 pubspec `2.0.0` 相等，幂等检查跳过 bump，版本保持 2.0.0。

**逃生舱验证原理**：`OMLL_SKIP_BUMP=1` 使 post-commit 第 30 行 `[ -n "$OMLL_SKIP_BUMP" ] && exit 0` 直接退出，不 bump。版本保持 2.0.0（与 message「fix:」语义不一致是逃生舱的预期行为--用户主动跳过）。

## 五、ci.yml 新增 step

在 Phase 1 既有的 format → analyze → test → coverage 流水线中，于 analyze 之后、test 之前插入：

```yaml
      # 3) version hook 契约验证（Phase 2，不依赖 flutter，快速失败）
      - name: verify version hook
        run: bash scripts/verify-version-hook.sh
```

后续 step 编号顺延（原 test → 4，原 coverage → 5）。该 step 不依赖 `flutter pub get`，仅用 git，耗时 < 5s。

## 六、测试策略

### 本地验证（对应 Verification Requirements 第一、二、四条）
- 静态分析：`flutter analyze` → EXIT=0（本 Phase 不改 lib/，预期不变）。
- 全量测试：`flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log` → EXIT=0（本 Phase 不改 lib/test 业务代码，预期不变；删除的诊断 txt 与改的文档不影响测试）。
- hook 契约：`bash scripts/verify-version-hook.sh` → 期望 `PASS: post-commit 版本 bump 契约验证通过`，EXIT=0。
- 事实源统一校验：
  ```bash
  # 仓库内不应再有把 commit-msg / pre-commit 当作版本 bump 机制的陈述
  grep -rnE "由 .*commit-msg hook|由 git pre-commit 钩子.*负责|已移至 commit-msg" .githooks scripts AGENTS.md CLAUDE.md
  # 期望：仅 post-commit 注释中「为什么不是 commit-msg」这类正确说明命中（或无命中）
  ```
- pubspec description 不破坏 hook：改后 `grep '^version:' pubspec.yaml` 仍正常匹配 `version: 3.17.15+0`（hook 的 sed 只动 version 行）。
- 异常文件已删除：`git ls-files | grep gitfull_diff` → 无输出。
- ignore 覆盖确认：`git check-ignore -v .claude/settings.local.json` → `.gitignore:55:.claude/`。

### CI 验证（对应 Verification Requirements 第四条）
- push 到 master / PR 触发，ubuntu 上跑 format → analyze → **verify version hook** → test → coverage。
- hook 契约 step 失败即 fail-fast，避免版本机制回归静默通过。

## 七、实施顺序与独立提交节点

> 全部在 Bash 执行 `git commit`（CLAUDE.md/AGENTS.md 均要求，避免 PowerShell here-string）。版本 bump 由仓库 `post-commit` hook 按前缀自动处理（`chore`/`docs`/`test` → patch+1）。每个提交独立可 review、可回滚。

### Commit 1 - `chore: 移除误跟踪的 git 诊断产物`（TD-17）
- 删除：`git rm -- '*gitfull_diff*'`（git pathspec glob，引号阻止 shell 展开；文件名含 U+F03A 私用区字符，手打易错）。
- 验证：`git ls-files | grep gitfull_diff` 无输出；`git status` 仅该删除；`flutter analyze` EXIT=0。
- 不改 `.gitignore`（异常文件名无合理通配模式，现有规则已覆盖常规诊断产物）。
- 提交内容：仅删除该 64KB 文件。

### Commit 2 - `docs(version): 统一版本流程事实源至 post-commit`（TD-38）
- `AGENTS.md`：第 44 行 `commit-msg hook` → `post-commit hook`；第 52 行标题 `（commit-msg hook）` → `（post-commit hook）`；第 54-56 行整段替换为 CLAUDE.md 第 54-60 行的 post-commit + amend 描述 + 「为什么不是 commit-msg」+ 5 点行为细节（读 `HEAD:pubspec.yaml` + amend / 幂等 / merge 跳过 / 逃生舱 / `OMLL_BUMPING` 防递归）。
- `.githooks/pre-commit`：第 2 行 `版本号自动更新已移至 commit-msg hook` → `版本号自动更新由 post-commit hook 负责（pre-commit 仅做大改动提醒）`。
- `scripts/bump-version.ps1`：第 12 行 `由 git pre-commit 钩子（.githooks/pre-commit）负责` → `由 git post-commit 钩子（.githooks/post-commit）负责`。
- 验证：上方「事实源统一校验」grep 无机制性冲突残留；`post-commit` / `CLAUDE.md` 未改逻辑；`flutter analyze` EXIT=0。
- 提交内容：仅文档与注释陈述，零逻辑变更。

### Commit 3 - `docs: 清理陈旧 README 测试数字与 pubspec 默认描述`（TD-17）
- `README.md`：第 268 行 `运行全部测试（1016 个测试）` → `运行全部测试（用例数随开发增长，见各模块目录）`；第 280 行 `共 1016 个测试（99 个测试文件）` → `测试覆盖主要模块（用例数随开发增长，详见各模块目录）`。
- `AGENTS.md` / `CLAUDE.md`：第 27 行 `全量测试 400+ 用例` → `全量测试用例数随开发增长`。
- `pubspec.yaml`：第 2 行 `description: "A new Flutter project."` → `description: "本地 LLM 聊天客户端，Flutter 应用，Windows + Android 双端，兼容任意 OpenAI 接口。"`。
- 验证：纯文档/元数据；`grep '^version:' pubspec.yaml` 仍正常（hook sed 不受影响）；提交时 hook 会按 `docs:` 前缀 patch+1 bump version（3.17.15 → 3.17.16）并 amend 并回，属正常工作流。
- 提交内容：文档 + pubspec description（+ hook 自动 bump 的 version 行）。

### Commit 4 - `test(version): 新增 post-commit hook 契约验证脚本并接入 CI`（TD-38 可验证契约）
- 新增 `scripts/verify-version-hook.sh`（第四节逻辑）。
- `.github/workflows/ci.yml`：插入 `verify version hook` step（analyze 后、test 前）。
- 验证：本地 `bash scripts/verify-version-hook.sh` → `PASS`，EXIT=0；push 后观察 CI 全绿（含新 step）。
- 提交内容：新增脚本 + ci.yml 一个 step。
- **此提交后 push 触发 CI 运行**，确认 format/analyze/verify-version-hook/test/coverage 五步全绿。

> Commit 1/2/3 是清理与文档统一（低风险 housekeeping），Commit 4 是可验证契约的落地。若 CI 首次运行暴露脚本跨环境问题（如 `mktemp`/`awk` 行为差异），修复作为 Commit 4 的 amend 或新增 `fix(test):` 提交。

## 八、验证清单（对照 Verification Requirements）

- [ ] `flutter analyze` 必须通过 → 本 Phase 不改 lib/，本地已 EXIT=0；CI step 2 覆盖。
- [ ] 全量测试按重定向规范执行并得 EXIT=0 → 本 Phase 不改业务代码，本地重定向验证；CI step 4（test）覆盖。
- [ ] 验证被移除的本地/诊断文件已由 ignore 规则覆盖 → `.claude/` 由 `.gitignore:55` 覆盖（已确认）；异常 txt 文件删除后无需新规则（无合理通配模式，现有 `*.log` 等覆盖常规诊断产物）。
- [ ] 用隔离仓库或等效测试验证 fix/feat/breaking 类型版本行为与文档一致，不污染当前工作树历史 → `scripts/verify-version-hook.sh` 在 `mktemp -d` 临时仓库验证，CI step 3 持续验证。
- [ ] CI 配置本身完成一次成功运行验证 → Commit 4 push 后观察（plan 阶段无法本地完成 CI 运行）。

## 九、风险与缓解

| 风险 | 缓解 |
|---|---|
| 删除已跟踪文件误伤用户内容 | git status 已 clean；目标文件经 `git cat-file` 确认为 64KB git diff CRLF 警告输出，误提交于 F9 重构；用 `git rm` 精确删除，仅 pathspec `*gitfull_diff*` 命中单文件 |
| 文件名含私用区字符 U+F03A，手打错误 | 用 `git rm -- '*gitfull_diff*'` pathspec glob，引号阻止 shell 展开，避免手打特殊字符 |
| hook 注释/文档统一遗漏某处 | 提交后用 `grep -rnE` 扫描「commit-msg hook」「pre-commit 钩子.*负责」等冲突陈述，确认仅保留 post-comment 注释中「为什么不是 commit-msg」正确说明 |
| `verify-version-hook.sh` 在 ubuntu 与 Git Bash 行为差异 | 仅用 POSIX 工具（git/mktemp/cp/chmod/grep/awk），无平台专属依赖；`set -euo pipefail`；CI 失败即 fail-fast，本地可复现 |
| 改 pubspec description 影响 hook sed | hook 的 `sed 's/^version: .*/...'` 只匹配 `^version:` 行，description 行不受影响；提交后 `grep '^version:'` 验证 |
| 文档同时保留「当前机制」与「未来目标」形成歧义 | 本 Phase 只描述当前 post-commit 机制；正式 release 版本策略明确标注「由 Phase 16 处理」，不在本 Phase 提前实现 |
| 版本 bump 改变提交 hash | hook 行为不变（仅改文档/注释陈述），hash 变化来自正常的 patch+1 bump，属既定工作流；Commit 1/2 无 lib 改动，bump 正常 |

## 十、Out Of Scope 确认

- ❌ 不配置正式 Android 签名、secret、release provenance 或设备 smoke（Phase 16）。
- ❌ 不以个人偏好更换 Conventional Commits 语义（type!/feat/其他 三类 bump 规则不变，不创建 `commit-msg` hook）。
- ❌ 不修改 Review Report 的审查基线或结论。
- ❌ 不清理与报告未指出且与事实源无关的用户文件（仅删 TD-17 点名的诊断 txt；`.claude/` 已自然消解不重复处理）。
- ❌ 不改 `post-commit` hook 逻辑（真相源，仅改文档/注释陈述对齐）。
- ❌ 不改业务架构、生产功能、`lib/` 代码、业务测试。
- ❌ 不改 Flutter/Riverpod/sqlite3/http/go_router 选型。
- ❌ 不在本 Phase 实现正式 tag release 或 versionCode/provenance 收敛（Phase 16 依赖本 Phase 明确的本地版本流程后处理）。
