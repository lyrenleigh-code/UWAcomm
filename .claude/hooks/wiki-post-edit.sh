#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

python3 "$PROJECT_DIR/scripts/lint_wiki.py" --quick || {
  echo "Wiki lint 发现问题。请修复断链或补全 index 条目后再继续。" >&2
  exit 2
}
