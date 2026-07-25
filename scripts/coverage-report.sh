#!/usr/bin/env bash
# 聚焦 application/data 覆盖率，剔除 presentation（行为清单验证）与 domain（model getter 噪声）。
# 产出：lcov.filtered.info（application/data 聚焦）+ html/（可视化）+ diff-report.html（变更行）。
# 由 .github/workflows/ci.yml 在 flutter test --coverage 后调用。
set -euo pipefail

# 无 coverage 数据则跳过（如 test 失败未生成 lcov.info）
if [[ ! -f coverage/lcov.info ]]; then
  echo "coverage/lcov.info 不存在，跳过 coverage 报告"
  exit 0
fi

# 安装 lcov（genhtml / lcov --remove 依赖），CI ubuntu 上有 sudo
if ! command -v lcov >/dev/null 2>&1; then
  sudo apt-get update -qq >/dev/null 2>&1 || true
  sudo apt-get install -y lcov >/dev/null 2>&1 || true
fi

# 过滤：保留 application + data，剔除 presentation（行为清单）/ domain（model getter 噪声）
lcov --remove coverage/lcov.info \
  'lib/features/*/presentation/*' \
  'lib/features/*/domain/*' \
  -o coverage/lcov.filtered.info

genhtml coverage/lcov.filtered.info -o coverage/html

# 摘要输出（CI 日志可见，非单一总百分比）
echo "=== application/data 聚焦覆盖率 ==="
lcov --summary coverage/lcov.filtered.info 2>&1 | tee coverage/summary.txt

# 变更行报告（非阻塞，仅信息性；浅克隆下 origin/master 可能不可得，容错跳过）
pip install diff-cover --quiet 2>/dev/null || true
diff-cover coverage/lcov.info --compare-branch origin/master \
  --html-report coverage/diff-report.html 2>/dev/null || true

echo "=== coverage 产物清单 ==="
echo "  lcov.info          : 全量"
echo "  lcov.filtered.info : application/data 聚焦"
echo "  html/              : 可视化报告"
echo "  diff-report.html   : 变更行报告（若可得）"
