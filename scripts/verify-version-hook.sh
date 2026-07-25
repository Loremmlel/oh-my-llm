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
git config core.autocrlf false  # 临时仓库无 .gitattributes，避免 CRLF 警告干扰契约输出
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
